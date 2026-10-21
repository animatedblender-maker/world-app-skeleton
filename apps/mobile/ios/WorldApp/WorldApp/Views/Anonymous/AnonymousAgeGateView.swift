import SwiftUI

struct AnonymousAgeGateView: View {
    enum Mode {
        case under18
        case attest
        case missingBirthdate
    }

    let mode: Mode
    @State private var store = AnonymousStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: modeIcon)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity)

                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(bodyCopy)
                    .font(.body)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                privacyCard

                if mode == .attest {
                    Button {
                        Task { await store.attest() }
                    } label: {
                        Text(store.isAttesting ? "Confirming…" : "I confirm I am 18 or older")
                            .elegantButton()
                            .opacity(store.isAttesting ? 0.6 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isAttesting)

                    Text(MatteryaCopy.anonymousAttestFinePrint)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                } else {
                    Text(MatteryaCopy.anonymousAgeGateHint)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            .padding(Theme.pagePadding)
            .padding(.top, 24)
        }
    }

    private var modeIcon: String {
        switch mode {
        case .under18, .missingBirthdate: "lock.shield"
        case .attest: "checkmark.shield"
        }
    }

    private var title: String {
        switch mode {
        case .under18: MatteryaCopy.anonymousUnder18Title
        case .missingBirthdate: MatteryaCopy.anonymousMissingBirthdateTitle
        case .attest: MatteryaCopy.anonymousAttestTitle
        }
    }

    private var bodyCopy: String {
        switch mode {
        case .under18: MatteryaCopy.anonymousUnder18Body
        case .missingBirthdate: MatteryaCopy.anonymousMissingBirthdateBody
        case .attest: MatteryaCopy.anonymousAttestBody
        }
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy boundary")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(MatteryaCopy.anonymousPrivacyBoundary)
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
}
