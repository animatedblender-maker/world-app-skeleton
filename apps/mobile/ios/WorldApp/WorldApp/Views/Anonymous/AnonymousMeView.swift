import SwiftUI

struct AnonymousMeView: View {
    @Environment(AppState.self) private var appState
    @State private var store = AnonymousStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                profileCard
                section(title: "Spaces") {
                    let joined = store.spacesByFilter[.joined] ?? []
                    if joined.isEmpty {
                        Text(MatteryaCopy.anonymousNoJoinedSpacesBody)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkMuted)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Theme.border.opacity(0.85), lineWidth: 0.5)
                            )
                    } else {
                        ForEach(joined.prefix(12)) { space in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(space.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(Theme.ink)
                                    Text("a/\(space.slug)")
                                        .font(.caption)
                                        .foregroundStyle(Theme.inkMuted)
                                }
                                Spacer()
                                if space.isPaid {
                                    Text("Paid")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Theme.matteDeep, in: Capsule())
                                }
                            }
                            .matteryaSettingsCard()
                        }
                    }
                }

                section(title: "Safety") {
                    infoCard(
                        title: "Blocked profiles",
                        subtitle: store.blockedProfileIds.isEmpty
                            ? "No blocked Anonymous profiles"
                            : "\(store.blockedProfileIds.count) blocked"
                    )
                    infoCard(
                        title: "Username",
                        subtitle: "Immutable. Exceptional renames are handled by trust & safety only."
                    )
                }

                section(title: "Data") {
                    Button {
                        appState.showToast(MatteryaCopy.anonymousExportPlaceholder, style: .info)
                    } label: {
                        settingsLabel("Request data export")
                            .matteryaSettingsCard()
                    }
                    .buttonStyle(.plain)

                    Button {
                        appState.showToast(MatteryaCopy.anonymousDeletePlaceholder, style: .info)
                    } label: {
                        settingsLabel("Request Anonymous deletion", destructive: true)
                            .matteryaSettingsCard(destructive: true)
                    }
                    .buttonStyle(.plain)
                }

                Text(MatteryaCopy.anonymousPrivacyBoundary)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, 4)
            }
            .padding(Theme.pagePadding)
            .padding(.bottom, 28)
        }
        .task {
            await store.loadSpaces(filter: .joined)
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Anonymous identity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
                .textCase(.uppercase)

            Text(store.session.profile?.username ?? "—")
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)

            Text(MatteryaCopy.anonymousMeHint)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private func section(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
                .textCase(.uppercase)
            content()
        }
    }

    private func infoCard(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
        }
        .matteryaSettingsCard()
    }

    private func settingsLabel(_ title: String, destructive: Bool = false) -> some View {
        Text(title)
            .foregroundStyle(destructive ? Theme.danger : Theme.ink)
    }
}
