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
    private let maxSlots = 5

    private init() {}

    /// Warm CDN resolves for the whole list (cheap) and full-buffer players for a window.
    func prepare(posts: [CountryPost], around index: Int, ahead: Int = 3, behind: Int = 1) {
        guard !posts.isEmpty else { return }

        // 1) Resolve every Archive URL in the stack — free + snappy when swiping far.
        for post in posts {
            if let url = post.playableVideoURL, ArchiveVideoPlayback.isArchiveURL(url) {
                ArchiveVideoPlayback.warmResolve(url)
            }
        }
        ImageCache.shared.prefetchPostThumbnails(
            Array(posts[max(0, index)..<min(posts.count, index + ahead + 2)]),
            maxPixelSize: 480
        )

        // 2) Full AVPlayer buffer for neighbors (and current if not already on-screen).
        let lo = max(0, index - behind)
        let hi = min(posts.count, index + ahead + 1)
        guard lo < hi else { return }
        let window = Array(posts[lo..<hi])
        let keep = Set(window.map(\.id))

        for id in slots.keys where !keep.contains(id) {
            evict(id)
        }

        for post in window {
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

        let playURL = await ArchiveVideoPlayback.resolvedPlaybackURL(for: sourceURL)
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
        _ = try? await asset.load(.duration)
        if slots[postID] != nil || inUse.contains(postID) { return }

        let item = AVPlayerItem(asset: asset)
        // Buffer hard so the first swipe frame is already in memory.
        item.preferredForwardBufferDuration = 16
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
        item.preferredPeakBitRate = 0

        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .pause

        // Brief play → pause fills the forward buffer without leaving audio on.
        player.playImmediately(atRate: 1.0)
        try? await Task.sleep(nanoseconds: 220_000_000)
        player.pause()
        await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)

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

        MediaPlaybackCoordinator.shared.register(player)
        slots[postID] = Slot(postID: postID, player: player)
    }

    private func evict(_ postID: String) {
        guard let slot = slots.removeValue(forKey: postID) else { return }
        slot.player.pause()
        slot.player.replaceCurrentItem(with: nil)
        MediaPlaybackCoordinator.shared.unregister(slot.player)
    }
}
