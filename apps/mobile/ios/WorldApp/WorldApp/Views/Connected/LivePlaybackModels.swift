import Foundation

struct LivePlaybackState: Equatable {
    let contentId: String?
    let title: String
    let subtitle: String
    let momentLabel: String?
    let progressMs: Int
    let durationMs: Int
    let updatedAt: Date
    let isPlaying: Bool
    let platform: StreamingPlatform

    var progress: Double {
        guard durationMs > 0 else { return 0 }
        return min(1, max(0, Double(liveProgressMs) / Double(durationMs)))
    }

    var progressLabel: String {
        StreamingHubRoomKey.formatTimestamp(liveProgressMs)
    }

    var liveProgressMs: Int {
        guard isPlaying else { return progressMs }
        let elapsed = Int(Date().timeIntervalSince(updatedAt) * 1000)
        return min(progressMs + max(0, elapsed), durationMs)
    }

    var canJoinSession: Bool {
        platform == .appleMusic && contentId != nil && !contentId!.isEmpty
    }
}

extension YourNowPlaying {
    var liveState: LivePlaybackState {
        LivePlaybackState(
            contentId: contentId,
            title: title,
            subtitle: subtitle,
            momentLabel: momentLabel,
            progressMs: progressMs,
            durationMs: durationMs,
            updatedAt: updatedAt,
            isPlaying: isSharing,
            platform: platform
        )
    }
}

extension FriendActivity {
    var liveState: LivePlaybackState {
        LivePlaybackState(
            contentId: contentId,
            title: title,
            subtitle: subtitle,
            momentLabel: nil,
            progressMs: progressMs,
            durationMs: durationMs,
            updatedAt: updatedAt,
            isPlaying: isLive,
            platform: platform
        )
    }
}