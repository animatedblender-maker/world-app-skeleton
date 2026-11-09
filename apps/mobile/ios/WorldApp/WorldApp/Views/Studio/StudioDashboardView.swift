import SwiftUI

struct StudioDashboardView: View {
    @State private var range: StudioService.Range = .d28
    @State private var dashboard: StudioService.Dashboard?
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

                if loading && dashboard == nil {
                    ProgressView("Loading metrics…")
                        .tint(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }

                if let dashboard {
                    kpiGrid(dashboard.kpis)
                    if !dashboard.daily.isEmpty {
                        dailyChart(dashboard.daily, range: dashboard.range)
                    }
                    topVideos(dashboard.topVideos)
                    if !dashboard.note.isEmpty {
                        Text(dashboard.note)
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
                Text("Overview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .textCase(.uppercase)
                Text("Dashboard")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 8)
            StudioRangeChips(range: $range)
        }
    }

    private func kpiGrid(_ kpis: StudioService.KPIs) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10
        ) {
            StudioKPICard(label: "Views", value: StudioService.formatCount(kpis.views))
            StudioKPICard(label: "Watch time", value: StudioService.formatWatch(kpis.watchMs))
            StudioKPICard(label: "CTR", value: StudioService.formatCtr(kpis.ctr))
            StudioKPICard(label: "Impressions", value: StudioService.formatCount(kpis.impressions))
            StudioKPICard(
                label: "Avg view",
                value: kpis.avgViewDurationMs.map(StudioService.formatWatch) ?? "—"
            )
            StudioKPICard(label: "Subscribers", value: StudioService.formatCount(kpis.subscribers))
        }
    }

    private func dailyChart(_ daily: [StudioService.DailyPoint], range: StudioService.Range) -> some View {
        let maxViews = max(daily.map(\.views).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Views · \(range.label)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(daily.enumerated()), id: \.offset) { _, day in
                    let height = max(4, CGFloat(day.views) / CGFloat(maxViews) * 88)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.ink.opacity(0.78))
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .accessibilityLabel("\(day.day): \(day.views) views")
                }
            }
            .frame(height: 96, alignment: .bottom)
        }
        .padding(16)
        .studioPanel()
    }

    private func topVideos(_ videos: [StudioService.VideoRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top videos")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)

            if videos.isEmpty {
                Text("No video activity in this range yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
            } else {
                ForEach(videos) { video in
                    NavigationLink {
                        StudioVideoView(videoID: video.id)
                    } label: {
                        StudioVideoRowView(video: video)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .studioPanel()
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            dashboard = try await StudioService.dashboard(range: range)
        } catch StudioService.StudioError.channelRequired {
            errorMessage = "Create a Hubs channel to see Studio metrics."
            dashboard = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}
