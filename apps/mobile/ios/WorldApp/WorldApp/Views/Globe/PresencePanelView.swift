import SwiftUI

struct PresencePanelView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("MY PRESENCE")
                    .sectionLabel()
                Spacer()
                Button {
                    appState.globePanel = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.inkMuted)
                        .frame(width: 38, height: 38)
                        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 10) {
                presenceLine("STATUS", value: "ONLINE")
                presenceLine("COUNTRY", value: appState.currentProfile?.countryName ?? "—")
                presenceLine("CODE", value: appState.currentProfile?.countryCode?.uppercased() ?? "—")
                presenceLine("CITY", value: appState.currentProfile?.cityName ?? "—")
            }
            .padding(16)
            .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            if let stats = appState.globalStats {
                Text("\(stats.onlineUsers) online worldwide · \(stats.totalUsers) registered")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Theme.ink.opacity(0.10), radius: 30, y: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private func presenceLine(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .sectionLabel()
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
        }
    }
}