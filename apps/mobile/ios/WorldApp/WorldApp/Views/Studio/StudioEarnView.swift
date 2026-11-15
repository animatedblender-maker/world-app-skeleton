import SwiftUI

struct StudioEarnView: View {
    @Environment(AppState.self) private var appState

    @State private var range: StudioService.Range = .d28
    @State private var earn: StudioService.Earn?
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }

                if loading && earn == nil {
                    ProgressView("Loading Earn…")
                        .tint(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }

                if let earn {
                    statusCard(earn)
                    estimateGrid(earn)
                    if !earn.estimateDisclaimer.isEmpty {
                        Text(earn.estimateDisclaimer)
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    checklistPanel(earn.checklist)
                    promotionPanel(earn)
                    adsPanel(earn)
                    if !earn.note.isEmpty {
                        Text(earn.note)
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 16)
            .padding(.bottom, 28)
        }
        .task(id: range) { await load() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Monetization")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .textCase(.uppercase)
                Text("Earn")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 8)
            StudioRangeChips(range: $range)
        }
    }

    private func statusCard(_ earn: StudioService.Earn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(earn.payoutsLive ? "Live" : "Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
                .textCase(.uppercase)
            Text(earn.statusLabel)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(earn.statusDetail)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .studioPanel()
    }

    private func estimateGrid(_ earn: StudioService.Earn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(earn.estimateLabel)
                    .font(.caption)
                    .foregroundStyle(Theme.paper.opacity(0.72))
                Text(StudioService.formatMoneyUsd(earn.estimatedRevenueUsd))
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Theme.paper)
                Text("Stub RPM \(StudioService.formatMoneyUsd(earn.rpmUsd)) · \(earn.estimateBasis)")
                    .font(.caption)
                    .foregroundStyle(Theme.paper.opacity(0.72))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.ink)
            )

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                StudioKPICard(label: "Views", value: StudioService.formatCount(earn.views))
                StudioKPICard(label: "Impressions", value: StudioService.formatCount(earn.impressions))
                StudioKPICard(label: "Watch hours", value: String(format: "%.2f", earn.watchHours))
                StudioKPICard(label: "Videos", value: StudioService.formatCount(earn.videos))
            }
        }
    }

    private func checklistPanel(_ items: [StudioService.EarnChecklistItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Eligibility checklist")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 12) {
                    Text(item.met ? "✓" : "○")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(item.met ? Theme.paper : Theme.inkMuted)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle().fill(item.met ? Theme.ink : Theme.matteDeep)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .studioPanel()
    }

    private func promotionPanel(_ earn: StudioService.Earn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Paid promotion")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(earn.promotionNote)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if earn.promotionCount > 0 {
                Text("\(earn.promotionCount) disclosed in your library")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .studioPanel()
    }

    private func adsPanel(_ earn: StudioService.Earn) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(earn.adsLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(earn.adsDetail)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                appState.navigate(to: .ads)
            } label: {
                Text("Open Ads")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.paper)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.ink, in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .studioPanel()
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            earn = try await StudioService.earn(range: range)
        } catch StudioService.StudioError.channelRequired {
            earn = nil
            errorMessage = "Create a Hubs channel to open Earn."
        } catch {
            earn = nil
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}
