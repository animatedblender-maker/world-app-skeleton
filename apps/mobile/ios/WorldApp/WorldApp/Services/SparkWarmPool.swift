import AVFoundation
import Foundation

/// Keeps **nearby Sparks / feed videos** fully buffered so play is instant on focus.
///
/// Cards **claim** a player when visible, and **park** it back (item intact) when they
/// scroll away — scrolling back reclaims the same buffered player instead of cold-start.
///
/// Player bulk policy (memory-aware, IG-class):
/// - **Feed:** deep preroll only 2–4 ahead (device tier) — never 8–32 AVPlayers
/// - **Sparks:** slightly wider window; still capped on low-RAM devices
/// - Light-load outer ring so claim rarely cold-starts mid-scroll
/// - Catalog/queue growth is separate — this only buffers AVPlayers
@MainActor
final class SparkWarmPool {
    static let shared = SparkWarmPool()

    /// Device RAM budget — caps concurrent AVPlayers so low devices never thrash.
    enum MediaBudget {
        static var physicalGB: Double {
            Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        }
        /// ~3GB class (older phones)
        static var isConstrained: Bool { physicalGB < 3.6 }
        static var isMid: Bool { physicalGB < 5.6 }

        /// Full first-frame preroll depth (feed home).
        static var deepPrerollFeed: Int { isConstrained ? 1 : (isMid ? 2 : 2) }
        /// Sparks vertical player can afford a slightly deeper head.
        static var deepPrerollSparks: Int { isConstrained ? 2 : (isMid ? 3 : 4) }
        /// Parked player slots (claimed not counted).
        static var maxSlots: Int { isConstrained ? 6 : (isMid ? 10 : 14) }
        /// How far ahead to keep *any* player item mounted (light or deep).
        static var playerAheadFeed: Int { isConstrained ? 2 : (isMid ? 3 : 4) }
        static var playerAheadSparks: Int { isConstrained ? 4 : (isMid ? 7 : 10) }
        static var playerBehind: Int { isConstrained ? 1 : 2 }
        static var forwardBufferDeep: Double { isConstrained ? 8 : (isMid ? 12 : 14) }
        static var forwardBufferLight: Double { isConstrained ? 4 : 6 }
    }

    /// Default Sparks player window (adaptive).
    static var playerAhead: Int { MediaBudget.playerAheadSparks }
    static var playerBehind: Int { MediaBudget.playerBehind }
    /// Full preroll (first-frame ready) for this many neighbors ahead of focus.
    static var deepPrerollAhead: Int { MediaBudget.deepPrerollSparks }
    /// Feed-specific deep preroll (stricter than Sparks).
    static var deepPrerollFeed: Int { MediaBudget.deepPrerollFeed }

    private struct Slot {
        let postID: String
        let player: AVPlayer
        let parkedAt: Date
    }

    private var slots: [String: Slot] = [:]
    private var warming = Set<String>()
    /// Visible owners currently holding a claimed player — never re-warm these.
    private var inUse = Set<String>()
    private var maxSlots: Int { MediaBudget.maxSlots }
    private var forwardBufferSeconds: Double { MediaBudget.forwardBufferDeep }

    private init() {}

    /// Convenience for Sparks player — adaptive bulk ahead/behind.
    func preparePlayerWindow(posts: [CountryPost], around index: Int) {
        prepare(
            posts: posts,
            around: index,
            ahead: MediaBudget.playerAheadSparks,
            behind: MediaBudget.playerBehind,
            deepPrerollLimit: MediaBudget.deepPrerollSparks
        )
    }

    /// Home feed / profile: **tight** window — deep preroll 2–4 only.
    func prepareFeedWindow(posts: [CountryPost], around index: Int) {
        prepare(
            posts: posts,
            around: index,
            ahead: MediaBudget.playerAheadFeed,
            behind: MediaBudget.playerBehind,
            deepPrerollLimit: MediaBudget.deepPrerollFeed
        )
    }

    /// Warm CDN resolves for a band (cheap) and buffer players for a tight window.
    /// Call early (open + every page) so the next clip is first-frame ready.
    func prepare(
        posts: [CountryPost],
        around index: Int,
        ahead: Int = 6,
        behind: Int = 2,
        deepPrerollLimit: Int? = nil
    ) {
        guard !posts.isEmpty else { return }
        let deepLimit = deepPrerollLimit ?? MediaBudget.deepPrerollSparks

        // Resolve + thumbs for a *slightly wider* band than full AV buffers (cheap).
        let resolveLo = max(0, index - behind)
        let resolveHi = min(posts.count, index + max(ahead, deepLimit) + 3)
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
                aggressive: !MediaBudget.isConstrained
            )
        }

        let lo = max(0, index - behind)
        let hi = min(posts.count, index + ahead + 1)
        guard lo < hi else { return }
        let window = Array(posts[lo..<hi])
        // Never evict the deep-preroll head — only drop far tails.
        let protectHi = min(posts.count, index + max(ahead, deepLimit) + 1)
        let protectLo = max(0, index - behind)
        var keep = Set(window.map(\.id)).union(inUse)
        if protectLo < protectHi {
            for p in posts[protectLo..<protectHi] {
                keep.insert(p.id)
            }
        }

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
            let url = post.playableVideoURL
                ?? MediaURLResolver.videoURL(for: post)
                ?? {
                    guard let raw = post.mediaURL, let u = MediaURLResolver.resolve(raw),
                          !MediaURLResolver.isImageURL(u) else { return nil }
                    return u
                }()
            guard let url else { continue }
            if inUse.contains(post.id) { continue }
            let postIndex = posts.firstIndex(where: { $0.id == post.id }) ?? index
            let distanceAhead = postIndex - index
            // Deep only for the next N ahead (not behind) — behind was doubling CPU cost.
            let deep = distanceAhead >= 0 && distanceAhead <= deepLimit
            Task { await warm(postID: post.id, sourceURL: url, deepPreroll: deep) }
        }
    }

    /// Parked player still in the pool (not claimed) — used so pauseAll can spare it.
    func parkedPlayer(for postID: String) -> AVPlayer? {
        slots[postID]?.player
    }

    /// Move a parked warm slot from one id → another (feed share id → Sparks origin id).
    /// Lets feed→Sparks open claim the same decoded player without a cold start.
    func rekey(from oldID: String, to newID: String) {
        let old = oldID.trimmingCharacters(in: .whitespacesAndNewlines)
        let neu = newID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !old.isEmpty, !neu.isEmpty, old != neu else { return }
        if slots[neu] != nil {
            // Prefer keeping the destination; drop the old duplicate.
            if let discarded = slots.removeValue(forKey: old) {
                discarded.player.pause()
                discarded.player.replaceCurrentItem(with: nil)
                MediaPlaybackCoordinator.shared.unregister(discarded.player)
            }
            if inUse.remove(old) != nil { inUse.insert(neu) }
            return
        }
        guard let slot = slots.removeValue(forKey: old) else {
            if inUse.remove(old) != nil { inUse.insert(neu) }
            return
        }
        slots[neu] = Slot(postID: neu, player: slot.player, parkedAt: slot.parkedAt)
        if inUse.remove(old) != nil { inUse.insert(neu) }
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
            continuingIDs.remove(postID)
            return nil
        }
        inUse.insert(postID)
        // Soft pause for handoff; keep playhead (continue) or t≈0 (normal park).
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
        parkInternal(postID: postID, player: player, continueFromCurrentTime: false)
    }

    /// Park without seeking to 0 — feed→Sparks/Hubs open continues mid-clip.
    func parkContinuing(postID: String, player: AVPlayer) {
        parkInternal(postID: postID, player: player, continueFromCurrentTime: true)
    }

    private func parkInternal(postID: String, player: AVPlayer, continueFromCurrentTime: Bool) {
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
        if continueFromCurrentTime {
            continuingIDs.insert(postID)
        } else {
            continuingIDs.remove(postID)
            // Snap to exact 0 + decode first frame while parked (never free-play into the clip).
            Task { await silentBufferFill(postID: postID, player: player) }
        }
    }

    /// IDs parked for mid-clip continue (do not seek to 0 on next claim).
    private var continuingIDs: Set<String> = []

    /// True when the next claim should resume mid-playhead (feed → full player).
    func shouldContinueFromCurrentTime(postID: String) -> Bool {
        continuingIDs.contains(postID)
    }

    func clearContinueFlag(postID: String) {
        continuingIDs.remove(postID)
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
    /// Default **light** — deep preroll is reserved for the focus window (memory).
    func warmSingle(postID: String, url: URL, deep: Bool = false) {
        guard slots[postID] == nil, !inUse.contains(postID) else { return }
        Task { await warm(postID: postID, sourceURL: url, deepPreroll: deep) }
    }

    /// True while a warm Task is still building a parked player for this id.
    func isWarming(postID: String) -> Bool {
        warming.contains(postID)
    }

    /// True if parked or actively warming (claim may succeed shortly).
    func hasWarmOrInflight(postID: String) -> Bool {
        slots[postID] != nil || warming.contains(postID)
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

    private func warm(postID: String, sourceURL: URL, deepPreroll: Bool) async {
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
        // Outer bulk ring uses a slightly smaller forward buffer to save memory/bandwidth.
        item.preferredForwardBufferDuration = deepPreroll
            ? MediaBudget.forwardBufferDeep
            : MediaBudget.forwardBufferLight
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
        if deepPreroll {
            Task { await silentBufferFill(postID: postID, player: player) }
        } else {
            // Light path: get readyToPlay + park at t=0 without full preroll cost.
            Task { await lightReady(postID: postID, player: player) }
        }
    }

    /// Outer bulk ring — asset loads + seek 0, no full preroll (saves CPU for deep neighbors).
    private func lightReady(postID: String, player: AVPlayer) async {
        for _ in 0..<50 {
            guard isParked(postID: postID, player: player) else { return }
            if player.currentItem == nil || player.status == .failed
                || player.currentItem?.status == .failed {
                evict(postID)
                return
            }
            if player.status == .readyToPlay || player.currentItem?.status == .readyToPlay {
                player.isMuted = true
                player.volume = 0
                player.rate = 0
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
