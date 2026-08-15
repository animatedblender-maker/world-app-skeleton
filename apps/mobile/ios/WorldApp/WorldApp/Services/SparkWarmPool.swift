import AVFoundation
import Foundation

/// Keeps **nearby Sparks / feed videos** fully buffered so play is instant on focus.
///
/// Cards **claim** a player when visible, and **park** it back (item intact) when they
/// scroll away — scrolling back reclaims the same buffered player instead of cold-start.
@MainActor
final class SparkWarmPool {
    static let shared = SparkWarmPool()

    private struct Slot {
        let postID: String
        let player: AVPlayer
        let parkedAt: Date
    }

    private var slots: [String: Slot] = [:]
    private var warming = Set<String>()
    /// Visible owners currently holding a claimed player — never re-warm these.
    private var inUse = Set<String>()
    /// Deep window: Sparks pager needs several neighbors fully buffered before swipe.
    private let maxSlots = 20
    private let forwardBufferSeconds: Double = 12

    private init() {}

    /// Warm CDN resolves for the whole list (cheap) and full-buffer players for a window.
    /// Call early (open + every page) so the next Spark is already at first-frame ready.
    func prepare(posts: [CountryPost], around index: Int, ahead: Int = 8, behind: Int = 2) {
        guard !posts.isEmpty else { return }

        let resolveLo = max(0, index - behind)
        let resolveHi = min(posts.count, index + ahead + 3)
        if resolveLo < resolveHi {
            if AppConfig.archiveContentEnabled {
                for post in posts[resolveLo..<resolveHi] {
                    if let url = post.playableVideoURL, ArchiveVideoPlayback.isArchiveURL(url) {
                        ArchiveVideoPlayback.warmResolve(url)
                    }
                }
            }
            ImageCache.shared.prefetchPostThumbnails(
                Array(posts[resolveLo..<resolveHi]),
                maxPixelSize: 360,
                aggressive: true
            )
        }

        let lo = max(0, index - behind)
        let hi = min(posts.count, index + ahead + 1)
        guard lo < hi else { return }
        let window = Array(posts[lo..<hi])
        let keep = Set(window.map(\.id)).union(inUse)

        for id in slots.keys where !keep.contains(id) {
            evict(id)
        }

        // Warm next first (highest swipe priority), then previous.
        let ordered = window.sorted { a, b in
            let ia = posts.firstIndex(where: { $0.id == a.id }) ?? 0
            let ib = posts.firstIndex(where: { $0.id == b.id }) ?? 0
            let da = abs(ia - index)
            let db = abs(ib - index)
            if da != db { return da < db }
            return ia > ib
        }
        for post in ordered {
            // Soft resolve: playableVideoURL first, then any non-image media path.
            // Over-strict playable-only filtering left previously-working sparks cold → unavailable.
            let url = post.playableVideoURL
                ?? MediaURLResolver.videoURL(for: post)
                ?? {
                    guard let raw = post.mediaURL, let u = MediaURLResolver.resolve(raw),
                          !MediaURLResolver.isImageURL(u) else { return nil }
                    return u
                }()
            guard let url else { continue }
            if inUse.contains(post.id) { continue }
            Task { await warm(postID: post.id, sourceURL: url) }
        }
    }

    /// Hand a fully buffered player to the visible card (removes it from the pool).
    /// Caller must treat the player as **paused at t≈0** (pool enforces that before parking).
    /// Returns nil if the parked item is missing or already failed (forces a clean cold start).
    ///
    /// Important: only mark `inUse` on a **successful** claim. Marking it when the slot
    /// is missing blocked re-warm forever → “Video unavailable” for clips that worked before.
    func claim(postID: String) -> AVPlayer? {
        guard let slot = slots.removeValue(forKey: postID) else { return nil }
        let player = slot.player
        // Never hand out a dead item — that became “Video unavailable” for good Sparks.
        if player.currentItem == nil
            || player.status == .failed
            || player.currentItem?.status == .failed {
            player.pause()
            player.replaceCurrentItem(with: nil)
            MediaPlaybackCoordinator.shared.unregister(player)
            return nil
        }
        inUse.insert(postID)
        // Stop any silent pool buffering; card takes exclusive control.
        player.pause()
        player.isMuted = true
        player.volume = 0
        player.rate = 0
        return player
    }

    /// Mark a post as on-screen even when cold-starting (no pool hit).
    func markInUse(postID: String) {
        inUse.insert(postID)
    }

    func release(postID: String) {
        inUse.remove(postID)
    }

    /// Return a still-buffered player so scrolling back is instant (keeps `currentItem`).
    /// Always rewound to **exact t=0** before the next claim (no mid-clip first frame).
    func park(postID: String, player: AVPlayer) {
        inUse.remove(postID)
        player.pause()
        player.isMuted = true
        player.volume = 0
        player.rate = 0

        guard player.currentItem != nil,
              player.status != .failed,
              player.currentItem?.status != .failed
        else {
            player.replaceCurrentItem(with: nil)
            MediaPlaybackCoordinator.shared.unregister(player)
            return
        }

        // Already have a fresher buffer for this id — drop the incoming one.
        if let existing = slots[postID], existing.player !== player {
            player.replaceCurrentItem(with: nil)
            MediaPlaybackCoordinator.shared.unregister(player)
            return
        }

        while slots.count >= maxSlots {
            // Evict oldest parked first (not the one we're parking).
            let victim = slots
                .filter { $0.key != postID }
                .min(by: { $0.value.parkedAt < $1.value.parkedAt })?
                .key
            if let victim {
                evict(victim)
            } else {
                break
            }
        }

        MediaPlaybackCoordinator.shared.register(player)
        slots[postID] = Slot(postID: postID, player: player, parkedAt: Date())
        // Snap to exact 0 + decode first frame while parked (never free-play into the clip).
        Task { await silentBufferFill(postID: postID, player: player) }
    }

    /// True when this exact player is still sitting in the pool (not claimed).
    func isParked(postID: String, player: AVPlayer) -> Bool {
        slots[postID]?.player === player
    }

    func drain() {
        for id in Array(slots.keys) {
            evict(id)
        }
        warming.removeAll()
        inUse.removeAll()
    }

    /// Hard-silence every buffered player (page change / open). Keeps items for instant claim.
    func silenceAllBuffered() {
        for slot in slots.values {
            slot.player.pause()
            slot.player.isMuted = true
            slot.player.volume = 0
        }
    }

    /// Warm a single post by id+url (feed card mount).
    func warmSingle(postID: String, url: URL) {
        guard slots[postID] == nil, !inUse.contains(postID) else { return }
        Task { await warm(postID: postID, sourceURL: url) }
    }

    /// True when a parked (or in-use) player is ready at t≈0 for seamless first paint.
    func isReadyAtStart(postID: String) -> Bool {
        if inUse.contains(postID) { return true }
        guard let slot = slots[postID] else { return false }
        if slot.player.status == .failed || slot.player.currentItem?.status == .failed {
            return false
        }
        let itemOK = slot.player.currentItem?.status == .readyToPlay
            || slot.player.status == .readyToPlay
        return itemOK && Self.isAtStart(slot.player)
    }

    /// Block until the first few Sparks are warm at t=0 (or timeout).
    /// Cuts the cold-start blink on the first swipes after open.
    func awaitReady(postIDs: [String], timeout: TimeInterval = 1.8) async {
        guard !postIDs.isEmpty else { return }
        let deadline = Date().addingTimeInterval(timeout)
        for id in postIDs {
            while Date() < deadline {
                if isReadyAtStart(postID: id) { break }
                if inUse.contains(id) { break }
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
        }
    }

    // MARK: - Private

    private func warm(postID: String, sourceURL: URL) async {
        if slots[postID] != nil || inUse.contains(postID) { return }
        guard !warming.contains(postID) else { return }
        warming.insert(postID)
        defer { warming.remove(postID) }

        // Warm with the URL we already have — do NOT await GraphQL per neighbor
        // (that froze feed/Sparks loading and caused ghost audio from stalled players).
        // Expiry re-resolve only if the presign is actually dead/near-dead.
        let configuration = await MediaURLResolver.playbackConfiguration(
            for: sourceURL,
            postID: MediaURLResolver.isPresignExpiredOrNearExpiry(sourceURL) ? postID : nil
        )
        let playURL = configuration.url
        if slots[postID] != nil || inUse.contains(postID) { return }

        // AVPlayerItem loads playable/duration itself — avoid deprecated loadValuesAsynchronously.
        let item: AVPlayerItem
        if let headers = configuration.headers, !headers.isEmpty,
           !ArchiveVideoPlayback.isArchiveURL(playURL) {
            let asset = AVURLAsset(
                url: playURL,
                options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
            )
            item = AVPlayerItem(asset: asset)
        } else {
            let asset = AVURLAsset(
                url: playURL,
                options: [
                    AVURLAssetAllowsCellularAccessKey: true,
                    AVURLAssetAllowsExpensiveNetworkAccessKey: true,
                    AVURLAssetAllowsConstrainedNetworkAccessKey: true,
                ]
            )
            item = AVPlayerItem(asset: asset)
        }

        if slots[postID] != nil || inUse.contains(postID) {
            return
        }
        // Deep buffer so first frame + audio are ready before the user lands on the card.
        item.preferredForwardBufferDuration = forwardBufferSeconds
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        item.preferredPeakBitRate = 0

        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.volume = 0
        player.automaticallyWaitsToMinimizeStalling = false
        // .none so DidPlayToEndTime still fires after claim (feed Sparks can loop).
        player.actionAtItemEnd = .none
        player.pause()

        if slots[postID] != nil || inUse.contains(postID) {
            player.replaceCurrentItem(with: nil)
            return
        }

        while slots.count >= maxSlots {
            let victim = slots
                .filter { $0.key != postID }
                .min(by: { $0.value.parkedAt < $1.value.parkedAt })?
                .key
            if let victim {
                evict(victim)
            } else {
                break
            }
        }

        MediaPlaybackCoordinator.shared.register(player)
        slots[postID] = Slot(postID: postID, player: player, parkedAt: Date())
        Task { await silentBufferFill(postID: postID, player: player) }
    }

    /// Decode first frame + fill forward buffer **without advancing playhead**.
    /// Previous path free-played ~0.7s then seeked back → every swipe showed mid-clip then jumped to 0.
    private func silentBufferFill(postID: String, player: AVPlayer) async {
        for _ in 0..<80 {
            guard isParked(postID: postID, player: player) else { return }
            if player.currentItem == nil {
                evict(postID)
                return
            }
            if player.status == .failed || player.currentItem?.status == .failed {
                // Drop dead warm slots so claim never surfaces “Video unavailable”.
                evict(postID)
                return
            }
            if player.status == .readyToPlay || player.currentItem?.status == .readyToPlay {
                player.isMuted = true
                player.volume = 0
                player.rate = 0
                // Exact start — infinite tolerance was landing on distant keyframes.
                _ = await player.seek(
                    to: .zero,
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
                guard isParked(postID: postID, player: player) else { return }

                // Preroll buffers from t=0 without leaving the start (unlike play()+sleep).
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    player.preroll(atRate: 1.0) { _ in
                        cont.resume()
                    }
                }
                guard isParked(postID: postID, player: player) else { return }
                if player.status == .failed || player.currentItem?.status == .failed {
                    evict(postID)
                    return
                }

                player.pause()
                player.rate = 0
                player.isMuted = true
                player.volume = 0
                // Hard lock head at exact 0 after preroll (preroll can nudge slightly).
                _ = await player.seek(
                    to: .zero,
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
                player.pause()
                player.rate = 0
                return
            }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
    }

    /// True when playhead is already at the start (no seek needed on claim).
    static func isAtStart(_ player: AVPlayer, epsilon: Double = 0.05) -> Bool {
        let t = player.currentTime().seconds
        return t.isFinite && t >= 0 && t < epsilon
    }

    private func evict(_ postID: String) {
        guard let slot = slots.removeValue(forKey: postID) else { return }
        slot.player.pause()
        slot.player.isMuted = true
        slot.player.volume = 0
        slot.player.replaceCurrentItem(with: nil)
        MediaPlaybackCoordinator.shared.unregister(slot.player)
    }
}
