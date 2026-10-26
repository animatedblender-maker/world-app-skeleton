import SwiftUI

/// Full Masquerade welcome letter shown once after claiming a name.
struct AnonymousWelcomeLetterView: View {
    @State private var store = AnonymousStore.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(MatteryaCopy.anonymousWelcomeLetterTitle)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.ink)

                    MatteryaMarkdown.text(
                        MatteryaCopy.anonymousWelcomeLetterBody,
                        baseFont: .body
                    )
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Text(MatteryaCopy.anonymousWildeQuote)
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.top, 8)

                    Text(MatteryaCopy.anonymousWildeAttribution)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }

            Button {
                store.completeWelcomeLetter()
            } label: {
                Text("Continue")
                    .elegantButton()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .background(Theme.canvas.opacity(0.96))
            .overlay(alignment: .top) {
                Theme.divider.frame(height: 0.5)
            }
        }
        .background(Theme.canvas)
    }
}
