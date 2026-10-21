import SwiftUI

struct AnonymousUsernameClaimView: View {
    @State private var store = AnonymousStore.shared
    @State private var showIrreversibleConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(MatteryaCopy.anonymousClaimTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ink)

                Text(MatteryaCopy.anonymousClaimBody)
                    .font(.body)
                    .foregroundStyle(Theme.inkSecondary)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Suggested username")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .textCase(.uppercase)

                    Text(store.suggestedUsername.isEmpty ? "…" : store.suggestedUsername)
                        .font(.system(size: 26, weight: .regular, design: .serif))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .stroke(Theme.border, lineWidth: 0.5)
                        )

                    Button {
                        Task { await store.regenerateUsername() }
                    } label: {
                        Text("Regenerate")
                            .elegantButton(outlined: true)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label(MatteryaCopy.anonymousClaimIrreversible, systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Text(MatteryaCopy.anonymousPrivacyBoundary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.matteDeep.opacity(0.65), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .stroke(Theme.border, lineWidth: 0.5)
                )

                Button {
                    showIrreversibleConfirm = true
                } label: {
                    Text(store.isClaimingUsername ? "Claiming…" : "Confirm username")
                        .elegantButton()
                        .opacity(store.isClaimingUsername || store.suggestedUsername.isEmpty ? 0.55 : 1)
                }
                .buttonStyle(.plain)
                .disabled(store.isClaimingUsername || store.suggestedUsername.isEmpty)

                Text(MatteryaCopy.anonymousClaimGeneratedOnly)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(Theme.pagePadding)
            .padding(.top, 24)
        }
        .task {
            if store.suggestedUsername.isEmpty {
                await store.regenerateUsername()
            }
        }
        .confirmationDialog(
            "Use \(store.suggestedUsername)?",
            isPresented: $showIrreversibleConfirm,
            titleVisibility: .visible
        ) {
            Button("Confirm — can’t change later") {
                Task { await store.claimUsername() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(MatteryaCopy.anonymousClaimIrreversible)
        }
    }
}
