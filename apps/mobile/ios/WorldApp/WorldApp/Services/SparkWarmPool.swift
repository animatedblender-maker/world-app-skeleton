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
    /// Deep window: feed scroll + Sparks pager both need instant neighbors.
    private let maxSlots = 14
    private let forwardBufferSeconds: Double = 8

    private init() {}

    /// Warm CDN resolves for the whole list (cheap) and full-buffer players for a window.
    func prepare(posts: [CountryPost], around index: Int, ahead: Int = 5, behind: Int = 2) {
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
            guard let url = post.playableVideoURL else { continue }
            if inUse.contains(post.id) { continue }
            Task { await warm(postID: post.id, sourceURL: url) }
        }
    }

    /// Hand a fully buffered player to the visible card (removes it from the pool).
    func claim(postID: String) -> AVPlayer? {
        inUse.insert(postID)
        guard let slot = slots.removeValue(forKey: postID) else { return nil }
        let player = slot.player
        // Stop any silent pool buffering; card takes exclusive control.
        player.pause()
        player.isMuted = true
        player.volume = 0
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
    func park(postID: String, player: AVPlayer) {
        inUse.remove(postID)
        player.pause()
        player.isMuted = true
        player.volume = 0
        // Park at t≈0 so the next claim can play without a mid-clip seek (black flash).
        // Match VideoPlayer / Archive near-zero window (0.35s) so swipe never re-seeks.
        let t = player.currentTime().seconds
        if !(t.isFinite && t >= 0 && t < 0.35) {
            player.seek(
                to: .zero,
                toleranceBefore: .positiveInfinity,
                toleranceAfter: .positiveInfinity
            )
        }

        guard player.currentItem != nil, player.status != .failed else {
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
        // Quietly top up the buffer while parked.
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

    // MARK: - Private

    private func warm(postID: String, sourceURL: URL) async {
        if slots[postID] != nil || inUse.contains(postID) { return }
        guard !warming.contains(postID) else { return }
        warming.insert(postID)
        defer { warming.remove(postID) }

        let playURL: URL
        if ArchiveVideoPlayback.isArchiveURL(sourceURL) {
            playURL = await ArchiveVideoPlayback.resolvedPlaybackURL(for: sourceURL)
        } else {
            playURL = sourceURL
        }
        if slots[postID] != nil || inUse.contains(postID) { return }

        let asset = AVURLAsset(
            url: playURL,
            options: [
                AVURLAssetAllowsCellularAccessKey: true,
                AVURLAssetAllowsExpensiveNetworkAccessKey: true,
                AVURLAssetAllowsConstrainedNetworkAccessKey: true,
            ]
        )
        asset.loadValuesAsynchronously(forKeys: ["playable", "duration"]) {}

        if slots[postID] != nil || inUse.contains(postID) { return }

        let item = AVPlayerItem(asset: asset)
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

    /// Muted play for a short window so AVPlayer actually fills the forward buffer while parked.
    /// Aborts if the player was claimed mid-fill (must not pause a live Spark).
    private func silentBufferFill(postID: String, player: AVPlayer) async {
        for _ in 0..<50 {
            guard isParked(postID: postID, player: player) else { return }
            if player.currentItem == nil { return }
            if player.status == .readyToPlay {
                player.isMuted = true
                player.volume = 0
                player.play()
                try? await Task.sleep(nanoseconds: 450_000_000)
                // Only pause if still parked — claim may have taken ownership.
                guard isParked(postID: postID, player: player) else { return }
                player.pause()
                player.isMuted = true
                player.volume = 0
                return
            }
            if player.status == .failed { return }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
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
