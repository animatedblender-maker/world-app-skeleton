import SwiftUI

struct CreateMenuOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack(alignment: .bottom) {
            if appState.showCreateMenu {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                CreateMenuPanel()
                    .padding(.bottom, Theme.tabBarHeight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.24), value: appState.showCreateMenu)
        .allowsHitTesting(appState.showCreateMenu)
        .zIndex(180)
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.24)) {
            appState.showCreateMenu = false
        }
    }
}

private struct CreateMenuPanel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create")
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Text("Share something with your country")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }

                Spacer()

                Button { close() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .frame(width: 32, height: 32)
                        .background(Theme.canvasMuted, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Theme.divider.frame(height: 0.5)

            VStack(spacing: 10) {
                createOption(
                    title: "Post",
                    subtitle: "Share an update with your country",
                    icon: "square.and.pencil",
                    tint: Theme.accentBright
                ) {
                    Task { await appState.presentCreateSheet(.post) }
                }

                createOption(
                    title: "Video",
                    subtitle: "Share to feed and Living",
                    icon: "play.tv",
                    tint: Theme.accent
                ) {
                    Task { await appState.presentCreateSheet(.video) }
                }

                createOption(
                    title: "Reel",
                    subtitle: "Publish a short vertical video",
                    icon: "play.rectangle.fill",
                    tint: Theme.facebookBlue
                ) {
                    Task { await appState.presentCreateSheet(.reel) }
                }

                createOption(
                    title: "Story",
                    subtitle: "24-hour photo or video moment",
                    icon: "circle.dashed",
                    tint: Color(red: 0.85, green: 0.32, blue: 0.55)
                ) {
                    Task { await appState.presentCreateSheet(.story) }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 16)
        }
        .background(
            Theme.surface
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
        .shadow(color: Theme.ink.opacity(0.14), radius: 24, y: -4)
        .padding(.horizontal, 10)
    }

    private func createOption(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.24)) {
            appState.showCreateMenu = false
        }
    }
}