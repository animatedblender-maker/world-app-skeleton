import SwiftUI

struct StoriesStripView: View {
    @Environment(AppState.self) private var appState

    private var sortedGroups: [StoryGroup] {
        appState.storyGroups
            .filter { $0.authorID != appState.currentProfile?.userID }
            .sorted { lhs, rhs in
                if lhs.hasUnviewed != rhs.hasUnviewed {
                    return lhs.hasUnviewed && !rhs.hasUnviewed
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            .prefix(12)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "globe.americas.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.oceanWash.opacity(0.95))
                Text("Globe moments")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            .padding(.horizontal, Theme.pagePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    yourStoryButton

                    ForEach(sortedGroups) { group in
                        Button {
                            appState.openStoryViewer(group: group)
                        } label: {
                            storyBubble(group: group)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 8)
        .background {
            LinearGradient(
                colors: [Theme.oceanWash.opacity(0.08), Theme.canvas.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var yourStoryButton: some View {
        Button {
            Task { await appState.openStoryComposerOrViewer() }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    let mine = appState.storyGroups.first {
                        $0.authorID == appState.currentProfile?.userID
                    }
                    storyPassportBubble(
                        previewURL: mine?.stories.last?.resolvedImageURL,
                        avatarSeed: appState.currentProfile?.userID ?? "me",
                        avatarURL: appState.currentProfile?.avatarURL,
                        countryCode: appState.currentProfile?.countryCode,
                        highlighted: !(mine?.stories.isEmpty ?? true)
                    )

                    HandDrawnPlusIcon(size: 14, color: Theme.accentBright)
                        .padding(5)
                        .background(Theme.surface, in: Circle())
                        .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                        .offset(x: 2, y: 2)
                }

                Text("Add moment")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(1)
            }
            .frame(width: 76)
        }
        .buttonStyle(.plain)
    }

    private func storyBubble(group: StoryGroup) -> some View {
        VStack(spacing: 6) {
            storyPassportBubble(
                previewURL: group.stories.last?.resolvedImageURL,
                avatarSeed: group.authorID,
                avatarURL: group.author?.avatarURL,
                countryCode: group.author?.countryCode,
                highlighted: group.hasUnviewed
            )

            VStack(spacing: 2) {
                Text(group.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)

                if let code = group.author?.countryCode?.uppercased(), !code.isEmpty {
                    Text(code)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(group.hasUnviewed ? Theme.accent : Theme.inkMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().stroke(Theme.border.opacity(0.7), lineWidth: 0.5))
                }
            }
            .frame(width: 76)
        }
    }

    private func storyPassportBubble(
        previewURL: URL?,
        avatarSeed: String,
        avatarURL: String?,
        countryCode: String?,
        highlighted: Bool
    ) -> some View {
        ZStack {
            if highlighted {
                StoryOrbitRing(size: 68)
            }

            HandDrawnGlobeStoryRing(size: 62, highlighted: highlighted)

            ZStack {
                if let previewURL {
                    CachedAsyncImage(
                        url: previewURL,
                        maxPixelSize: 120,
                        contentMode: .fill
                    )
                } else {
                    Theme.canvasMuted
                }

                LinearGradient(
                    colors: [.clear, Theme.ink.opacity(0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: 50, height: 50)
            .clipShape(Circle())

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    AvatarView(url: avatarURL, seed: avatarSeed, size: 20)
                        .overlay(Circle().stroke(Theme.surface, lineWidth: 1.5))
                        .offset(x: 4, y: 4)
                }
            }
            .frame(width: 54, height: 54)
        }
        .frame(width: 68, height: 68)
    }
}

private struct StoryOrbitRing: View {
    let size: CGFloat
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.oceanWash)
                    .frame(width: 5, height: 5)
                    .offset(y: -(size / 2) + 2)
                    .rotationEffect(.degrees(rotation + Double(index) * 120))
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}