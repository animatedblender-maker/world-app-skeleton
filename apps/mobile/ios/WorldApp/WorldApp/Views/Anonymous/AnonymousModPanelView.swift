import SwiftUI

struct AnonymousModPanelView: View {
    let spaceTitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(spaceTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.ink)

                    Text(MatteryaCopy.anonymousModPlaceholderBody)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)

                    VStack(spacing: 10) {
                        placeholderRow("Report queue", "Incoming member reports")
                        placeholderRow("Removed content", "Soft-deleted posts and comments")
                        placeholderRow("Member sanctions", "Timeouts and bans")
                        placeholderRow("Rules & logs", "Versioned rules and audit trail")
                    }
                }
                .padding(Theme.pagePadding)
            }
            .screenBackground()
            .navigationTitle("Mod tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.ink)
                }
            }
        }
    }

    private func placeholderRow(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
            Text("Coming soon")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.inkMuted)
                .padding(.top, 2)
        }
        .matteryaSettingsCard()
    }
}
