import AVFoundation
import Foundation

/// Keeps the **current + next few Sparks** buffering before the user swipes.
///
/// LazyVStack only mounts nearby pages; this pool warms AVPlayers off-screen so
/// the next three (and previous one) are already resolved + buffered when claimed.
@MainActor
final class SparkWarmPool {
    static let shared = SparkWarmPool()

    private struct Slot {
        let postID: String
        let player: AVPlayer
    }

    private var slots: [String: Slot] = [:]
    private var warming = Set<String>()
    /// Visible Sparks currently owning a claimed player — never re-warm these.
    private var inUse = Set<String>()
    /// Deeper window so Instagram-speed swipes still hit a buffered player.
    private let maxSlots = 7

    private init() {}

    /// Warm CDN resolves for the whole list (cheap) and full-buffer players for a window.
    func prepare(posts: [CountryPost], around index: Int, ahead: Int = 4, behind: Int = 1) {
        guard !posts.isEmpty else { return }

        // 1) Resolve Archive URLs in the near window only when Archive content is enabled.
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

        // 2) Full AVPlayer buffer for neighbors (and current if not already on-screen).
        let lo = max(0, index - behind)
        let hi = min(posts.count, index + ahead + 1)
        guard lo < hi else { return }
        let window = Array(posts[lo..<hi])
        let keep = Set(window.map(\.id))

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
            return ia > ib // prefer ahead over behind on ties
        }
        for post in ordered {
            guard let url = post.playableVideoURL else { continue }
            // Don't build a second buffer for the spark already playing.
            if inUse.contains(post.id) { continue }
            Task { await warm(postID: post.id, sourceURL: url) }
        }
    }

    /// Hand a fully buffered player to the visible card (removes it from the pool).
    func claim(postID: String) -> AVPlayer? {
        inUse.insert(postID)
        guard let slot = slots.removeValue(forKey: postID) else { return nil }
        return slot.player
    }

    /// Mark a post as on-screen even when cold-starting (no pool hit).
    func markInUse(postID: String) {
        inUse.insert(postID)
    }

    func release(postID: String) {
        inUse.remove(postID)
    }

    func drain() {
        for id in Array(slots.keys) {
            evict(id)
        }
        warming.removeAll()
        inUse.removeAll()
    }

    // MARK: - Private

    private func warm(postID: String, sourceURL: URL) async {
        if slots[postID] != nil || inUse.contains(postID) { return }
        guard !warming.contains(postID) else { return }
        warming.insert(postID)
        defer { warming.remove(postID) }

        // Resolve Archive CDN only when needed — R2 / signed URLs play as-is.
        let playURL: URL
        if ArchiveVideoPlayback.isArchiveURL(sourceURL) {
            playURL = await ArchiveVideoPlayback.resolvedPlaybackURL(for: sourceURL)
        } else {
            playURL = sourceURL
        }
        // Race: visible card may have claimed / created its own player already.
        if slots[postID] != nil || inUse.contains(postID) { return }

        let asset = AVURLAsset(
            url: playURL,
            options: [
                AVURLAssetAllowsCellularAccessKey: true,
                AVURLAssetAllowsExpensiveNetworkAccessKey: true,
                AVURLAssetAllowsConstrainedNetworkAccessKey: true,
            ]
        )
        // Do NOT await duration — that blocked warm and made swipes feel cold.
        // Kick a light preread so bytes start flowing without waiting for metadata.
        asset.loadValuesAsynchronously(forKeys: ["playable", "duration"]) {}

        if slots[postID] != nil || inUse.contains(postID) { return }

        let item = AVPlayerItem(asset: asset)
        // Tiny buffer = first frame ASAP on feed Sparks.
        item.preferredForwardBufferDuration = 2
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        item.preferredPeakBitRate = 0

        let player = AVPlayer(playerItem: item)
        // Always silent — never play briefly (that leaked audio into Sparks scroll).
        player.isMuted = true
        player.volume = 0
        player.automaticallyWaitsToMinimizeStalling = false
        player.actionAtItemEnd = .pause
        // Prefetch only — do not call play / playImmediately (causes stacked audio).
        player.pause()
        // NEVER call player.preroll before AVPlayerStatusReadyToPlay — that throws
        // NSInvalidArgumentException and kills the app (looked like a freeze in Xcode).
        // Creating the item is enough for the network buffer to start filling.

        if slots[postID] != nil || inUse.contains(postID) {
            player.replaceCurrentItem(with: nil)
            return
        }

        while slots.count >= maxSlots {
            if let victim = slots.keys.first(where: { $0 != postID }) {
                evict(victim)
            } else {
                break
            }
        }

        // Registered so page-change silence can mute if something goes wrong; volume stays 0.
        MediaPlaybackCoordinator.shared.register(player)
        slots[postID] = Slot(postID: postID, player: player)

        // Optional safe buffer nudge once ready (never crashes if never ready).
        Task { @MainActor in
            await Self.safeSilentPreroll(player)
        }
    }

    /// Wait until player is ready, then silent preroll. No-ops if it never becomes ready.
    private static func safeSilentPreroll(_ player: AVPlayer) async {
        for _ in 0..<40 {
            if player.status == .readyToPlay {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    player.preroll(atRate: 1.0) { _ in
                        cont.resume()
                    }
                }
                player.pause()
                player.isMuted = true
                player.volume = 0
                return
            }
            if player.status == .failed { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Warm a single post by id+url (feed card mount - double check).
    func warmSingle(postID: String, url: URL) {
        guard slots[postID] == nil, !inUse.contains(postID) else { return }
        Task { await warm(postID: postID, sourceURL: url) }
    }

    private func evict(_ postID: String) {
        guard let slot = slots.removeValue(forKey: postID) else { return }
        slot.player.pause()
        slot.player.replaceCurrentItem(with: nil)
        
    }
}
