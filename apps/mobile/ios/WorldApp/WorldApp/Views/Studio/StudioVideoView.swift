import SwiftUI

struct StudioVideoView: View {
    let videoID: String

    @State private var range: StudioService.Range = .d28
    @State private var analytics: StudioService.VideoAnalytics?
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }

                if loading && analytics == nil {
                    ProgressView("Loading analytics…")
                        .tint(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }

                if let analytics {
                    header(analytics)
                    funnelGrid(analytics.funnel)
                    sourcesPanel(analytics.sources)
                    retentionPanel(analytics.retention)
                    if !analytics.daily.isEmpty {
                        dailyChart(analytics.daily)
                    }
                    if !analytics.note.isEmpty {
                        Text(analytics.note)
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
        .screenBackground()
        .navigationTitle("Video")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .tint(Theme.ink)
        .task(id: range) { await load() }
    }

    private func header(_ analytics: StudioService.VideoAnalytics) -> some View {
        HStack(alignment: .top, spacing: 12) {
            thumb(analytics.video.thumbUrl)
            VStack(alignment: .leading, spacing: 6) {
                Text("Video analytics")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .textCase(.uppercase)
                Text(videoTitle(analytics.video))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Published \(StudioService.formatDate(analytics.video.createdAt))")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                StudioRangeChips(range: $range)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
    }

    private func funnelGrid(_ funnel: StudioService.Funnel) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10
        ) {
            StudioKPICard(label: "Impressions", value: StudioService.formatCount(funnel.impressions))
            StudioKPICard(label: "CTR", value: StudioService.formatCtr(funnel.ctr))
            StudioKPICard(label: "Views", value: StudioService.formatCount(funnel.views))
            StudioKPICard(label: "Watch time", value: StudioService.formatWatch(funnel.watchMs))
            StudioKPICard(label: "Completes", value: StudioService.formatCount(funnel.completes))
            StudioKPICard(label: "Skips", value: StudioService.formatCount(funnel.skips))
        }
    }

    private func sourcesPanel(_ sources: [StudioService.SourceRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Traffic sources")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            if sources.isEmpty {
                Text("No source breakdown yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
            } else {
                ForEach(sources) { row in
                    HStack {
                        Text(row.source)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(StudioService.formatCount(row.views))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
            }
        }
        .padding(16)
        .studioPanel()
    }

    private func retentionPanel(_ retention: [StudioService.RetentionBucket]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Retention")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            if retention.isEmpty {
                Text("No progress events yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
            } else {
                ForEach(retention) { bucket in
                    HStack(spacing: 10) {
                        Text("\(bucket.bucket)%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                            .frame(width: 36, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.matteDeep)
                                Capsule()
                                    .fill(Theme.ink.opacity(0.8))
                                    .frame(width: max(4, geo.size.width * min(1, max(0, bucket.reached))))
                            }
                        }
                        .frame(height: 8)
                        Text("\(Int((bucket.reached * 100).rounded()))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
        .padding(16)
        .studioPanel()
    }

    private func dailyChart(_ daily: [StudioService.DailyPoint]) -> some View {
        let maxViews = max(daily.map(\.views).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Daily views")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(daily.enumerated()), id: \.offset) { _, day in
                    let height = max(4, CGFloat(day.views) / CGFloat(maxViews) * 88)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.ink.opacity(0.78))
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
            }
            .frame(height: 96, alignment: .bottom)
        }
        .padding(16)
        .studioPanel()
    }

    @ViewBuilder
    private func thumb(_ urlString: String?) -> some View {
        let placeholder = RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.matteDeep)
            .frame(width: 72, height: 96)
        if let urlString, let url = URL(string: urlString) {
            CachedAsyncImage(
                url: url,
                maxPixelSize: 240,
                contentMode: .fill,
                placeholder: AnyView(placeholder)
            )
            .frame(width: 72, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            placeholder
        }
    }

    private func videoTitle(_ video: StudioService.VideoRow) -> String {
        if let title = video.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return "Untitled video"
    }

    @MainActor
    private func load() async {
        loading = true
        errorMessage = nil
        do {
            analytics = try await StudioService.videoAnalytics(id: videoID, range: range)
        } catch {
            analytics = nil
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}
