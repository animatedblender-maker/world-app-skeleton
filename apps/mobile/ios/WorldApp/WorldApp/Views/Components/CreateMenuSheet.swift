import SwiftUI

struct CreateMenuOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack(alignment: .bottom) {
            if appState.showCreateMenu {
                Theme.ink.opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                CreateMenuPanel()
                    .padding(.bottom, Theme.tabBarHeight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: appState.showCreateMenu)
        .allowsHitTesting(appState.showCreateMenu)
        .zIndex(500)
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.22)) {
            appState.showCreateMenu = false
        }
    }
}

private struct CreateMenuPanel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Theme.border)
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 12)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Create")
                        .font(.system(size: 24, weight: .regular, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Text("Share with your country")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                Button { close() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            Theme.divider.frame(height: 0.5)

            VStack(spacing: 0) {
                createRow(
                    title: "Post",
                    subtitle: "Share an update",
                    icon: "square.and.pencil"
                ) {
                    Task { await appState.presentCreateSheet(.post) }
                }

                createRow(
                    title: "Video",
                    subtitle: MatteryaCopy.longFormOnHubs,
                    icon: "film"
                ) {
                    Task { await appState.presentCreateSheet(.video) }
                }

                createRow(
                    title: MatteryaCopy.spark,
                    subtitle: MatteryaCopy.sparksOnHubs,
                    icon: "sparkles"
                ) {
                    Task { await appState.presentCreateSheet(.reel) }
                }

                createRow(
                    title: "Moment",
                    subtitle: "Disappears in 24 hours",
                    icon: "circle.dashed"
                ) {
                    Task { await appState.presentCreateSheet(.story) }
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                topTrailingRadius: 18,
                style: .continuous
            )
        )
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: 18,
                topTrailingRadius: 18,
                style: .continuous
            )
            .stroke(Theme.border, lineWidth: 0.5)
        )
        .shadow(color: Theme.ink.opacity(0.08), radius: 18, y: -4)
    }

    private func createRow(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 24)
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.22)) {
            appState.showCreateMenu = false
        }
    }
}