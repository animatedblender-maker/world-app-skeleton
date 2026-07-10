import SwiftUI

struct LivePlaybackCard: View {
    let resolveState: () -> LivePlaybackState
    var showsJoinButton = false
    var onJoin: (() async -> Void)?

    @State private var isJoining = false

    init(
        resolveState: @escaping () -> LivePlaybackState,
        showsJoinButton: Bool = false,
        onJoin: (() async -> Void)? = nil
    ) {
        self.resolveState = resolveState
        self.showsJoinButton = showsJoinButton
        self.onJoin = onJoin
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            cardContent(liveState: resolveState())
        }
    }

    private func cardContent(liveState: LivePlaybackState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.accentSoft)
                        .frame(width: 44, height: 44)

                    Image(systemName: liveState.platform.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(liveState.title)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)

                    Text(liveState.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if liveState.isPlaying {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Theme.success)
                            .frame(width: 6, height: 6)
                        Text("Live")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.success)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.success.opacity(0.12), in: Capsule())
                }
            }

            if let moment = liveState.momentLabel {
                Text(moment)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(2)
            }

            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.divider)
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: geo.size.width * liveState.progress)
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(liveState.progressLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.inkMuted)
                    Spacer()
                    Text("\(Int(liveState.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            if showsJoinButton, liveState.canJoinSession {
                Button {
                    Task {
                        isJoining = true
                        await onJoin?()
                        isJoining = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                        Text(isJoining ? "Joining…" : "Join session")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                }
                .buttonStyle(.plain)
                .disabled(isJoining)
            }
        }
        .padding(14)
        .hubCard()
    }
}

struct FriendLiveSessionCard: View {
    let friend: FriendActivity
    var onJoin: () async -> Void

    @State private var isJoining = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let state = friend.liveState

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarView(url: friend.avatarURL, seed: friend.avatarSeed, size: 36)

                        if friend.isLive {
                            Circle()
                                .fill(Theme.success)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
                                .offset(x: 2, y: 2)
                        }
                    }

                    Text(friend.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: friend.platform.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accent)
                        Text(friend.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }

                    Text(friend.subtitle.isEmpty ? state.progressLabel : friend.subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                        .lineLimit(1)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.divider)
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: geo.size.width * state.progress)
                    }
                }
                .frame(height: 3)

                HStack {
                    Text(state.progressLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.inkMuted)
                    Spacer()
                    if state.isPlaying {
                        Text("Live")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.success)
                    }
                }

                if state.canJoinSession {
                    Button {
                        Task {
                            isJoining = true
                            await onJoin()
                            isJoining = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.circle.fill")
                            Text(isJoining ? "Joining…" : "Join session")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    }
                    .buttonStyle(.plain)
                    .disabled(isJoining)
                }
            }
            .frame(width: 168)
            .padding(12)
            .hubCard()
        }
    }
}

private extension View {
    func hubCard() -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
    }
}