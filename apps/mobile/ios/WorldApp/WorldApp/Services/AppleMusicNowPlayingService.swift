import Foundation
import MusicKit

struct AppleMusicPlaybackSnapshot: Sendable {
    let contentId: String?
    let title: String
    let subtitle: String
    let momentLabel: String?
    let progressMs: Int
    let durationMs: Int
    let isPlaying: Bool
}

enum AppleMusicServiceError: LocalizedError {
    case notAuthorized
    case subscriptionRequired
    case nothingPlaying
    case songUnavailable

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            "Allow Matterya to access Apple Music in Settings to share what you're listening to."
        case .subscriptionRequired:
            "An active Apple Music subscription is required to read playback from the Music app."
        case .nothingPlaying:
            "Nothing is playing in Apple Music right now. Start a song in Music, then come back."
        case .songUnavailable:
            "That song isn't available in your Apple Music catalog."
        }
    }
}

@MainActor
final class AppleMusicNowPlayingService {
    static let shared = AppleMusicNowPlayingService()

    private var syncTask: Task<Void, Never>?
    private var lastUploadedSecond: Int?
    private var onUpdated: (() async -> Void)?
    private(set) var localSnapshot: AppleMusicPlaybackSnapshot?

    private init() {}

    func requestAuthorization() async throws {
        let status = await MusicAuthorization.request()
        switch status {
        case .authorized:
            return
        case .denied, .restricted, .notDetermined:
            throw AppleMusicServiceError.notAuthorized
        @unknown default:
            throw AppleMusicServiceError.notAuthorized
        }
    }

    func readCurrentPlayback() async throws -> AppleMusicPlaybackSnapshot {
        try await requestAuthorization()

        let subscription = try await MusicSubscription.current
        if !subscription.canPlayCatalogContent {
            throw AppleMusicServiceError.subscriptionRequired
        }

        let player = SystemMusicPlayer.shared
        guard let entry = player.queue.currentEntry else {
            throw AppleMusicServiceError.nothingPlaying
        }

        let playbackTime = max(0, player.playbackTime)
        let isPlaying = player.state.playbackStatus == .playing

        let snapshot: AppleMusicPlaybackSnapshot
        switch entry.item {
        case .song(let song):
            let duration = max(song.duration ?? 0, playbackTime + 1)
            snapshot = AppleMusicPlaybackSnapshot(
                contentId: song.id.rawValue,
                title: song.title,
                subtitle: song.artistName,
                momentLabel: song.albumTitle,
                progressMs: Int(playbackTime * 1000),
                durationMs: Int(duration * 1000),
                isPlaying: isPlaying
            )

        case .musicVideo(let video):
            let duration = max(video.duration ?? 0, playbackTime + 1)
            snapshot = AppleMusicPlaybackSnapshot(
                contentId: video.id.rawValue,
                title: video.title,
                subtitle: video.artistName,
                momentLabel: "Music Video",
                progressMs: Int(playbackTime * 1000),
                durationMs: Int(duration * 1000),
                isPlaying: isPlaying
            )

        default:
            let title = entry.title
            guard !title.isEmpty else { throw AppleMusicServiceError.nothingPlaying }
            snapshot = AppleMusicPlaybackSnapshot(
                contentId: nil,
                title: title,
                subtitle: entry.subtitle ?? "Apple Music",
                momentLabel: nil,
                progressMs: Int(playbackTime * 1000),
                durationMs: max(Int(playbackTime * 1000) + 60_000, 180_000),
                isPlaying: isPlaying
            )
        }

        localSnapshot = snapshot
        return snapshot
    }

    func syncNowPlayingToHub(sharingEnabled: Bool, force: Bool = false) async throws -> YourNowPlaying? {
        let snapshot = try await readCurrentPlayback()
        let currentSecond = snapshot.progressMs / 1000

        if !force, !snapshot.isPlaying, lastUploadedSecond == currentSecond {
            return nil
        }
        if !force, snapshot.isPlaying, lastUploadedSecond == currentSecond {
            return nil
        }

        let saved = try await StreamingHubService.shared.updateNowPlaying(
            platform: .appleMusic,
            title: snapshot.title,
            subtitle: snapshot.subtitle,
            momentLabel: snapshot.momentLabel,
            progressMs: snapshot.progressMs,
            durationMs: snapshot.durationMs,
            isSharing: sharingEnabled && snapshot.isPlaying,
            contentId: snapshot.contentId
        )
        lastUploadedSecond = currentSecond
        return saved
    }

    func joinSession(contentId: String, progressMs: Int) async throws {
        try await requestAuthorization()

        let subscription = try await MusicSubscription.current
        if !subscription.canPlayCatalogContent {
            throw AppleMusicServiceError.subscriptionRequired
        }

        let itemID = MusicItemID(contentId)
        var request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: itemID)
        let response = try await request.response()
        guard let song = response.items.first else {
            throw AppleMusicServiceError.songUnavailable
        }

        let player = ApplicationMusicPlayer.shared
        player.queue = ApplicationMusicPlayer.Queue(for: [song], startingAt: song)
        try await player.play()
        player.playbackTime = TimeInterval(progressMs) / 1000

        _ = try await StreamingHubService.shared.linkPlatform(.appleMusic)
        _ = try await syncNowPlayingToHub(sharingEnabled: true, force: true)
    }

    func startAutoSync(sharingEnabled: Bool, onUpdated: @escaping () async -> Void) {
        stopAutoSync()
        guard sharingEnabled else { return }

        self.onUpdated = onUpdated
        syncTask = Task { [weak self] in
            guard let self else { return }
            await self.runSyncLoop(sharingEnabled: sharingEnabled)
        }
    }

    func stopAutoSync() {
        syncTask?.cancel()
        syncTask = nil
        onUpdated = nil
        lastUploadedSecond = nil
    }

    func liveStateForDisplay(fallback: YourNowPlaying) -> LivePlaybackState {
        let player = SystemMusicPlayer.shared
        guard player.queue.currentEntry != nil, let local = localSnapshot else {
            return fallback.liveState
        }

        let playbackTime = max(0, player.playbackTime)
        let isPlaying = player.state.playbackStatus == .playing
        return LivePlaybackState(
            contentId: local.contentId,
            title: local.title,
            subtitle: local.subtitle,
            momentLabel: local.momentLabel,
            progressMs: Int(playbackTime * 1000),
            durationMs: local.durationMs,
            updatedAt: Date(),
            isPlaying: isPlaying,
            platform: .appleMusic
        )
    }

    private func runSyncLoop(sharingEnabled: Bool) async {
        while !Task.isCancelled {
            do {
                let snapshot = try await readCurrentPlayback()
                let interval: Duration = snapshot.isPlaying ? .seconds(2) : .seconds(6)
                if try await syncNowPlayingToHub(sharingEnabled: sharingEnabled) != nil {
                    await onUpdated?()
                } else {
                    await onUpdated?()
                }
                try await Task.sleep(for: interval)
            } catch {
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }
}