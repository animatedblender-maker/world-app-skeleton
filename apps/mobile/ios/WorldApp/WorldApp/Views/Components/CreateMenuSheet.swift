import SwiftUI

struct CreateMenuSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.border)
                .frame(width: 42, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 18)

            Text("Create")
                .font(.system(.title2, design: .serif))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 20)

            VStack(spacing: 12) {
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

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.hidden)
    }

    private func createOption(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

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

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(16)
            .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}