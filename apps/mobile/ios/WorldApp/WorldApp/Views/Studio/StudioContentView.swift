import SwiftUI

struct StudioContentView: View {
    @State private var range: StudioService.Range = .d28
    @State private var sort: StudioService.Sort = .views
    @State private var videos: [StudioService.VideoRow] = []
    @State private var nextCursor: String?
    @State private var loading = true
    @State private var loadingMore = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }

                if loading && videos.isEmpty {
                    ProgressView("Loading videos…")
                        .tint(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if !loading && videos.isEmpty && errorMessage == nil {
                    Text("No channel videos yet.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 24)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(videos) { video in
                            NavigationLink {
                                StudioVideoView(videoID: video.id)
                            } label: {
                                StudioVideoRowView(video: video, showsDate: true)
                                    .padding(14)
                                    .studioPanel()
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if video.id == videos.last?.id {
                                    Task { await loadMore() }
                                }
                            }
                        }
                        if loadingMore {
                            ProgressView()
                                .tint(Theme.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 16)
            .padding(.bottom, 28)
        }
        .task(id: "\(range.rawValue)-\(sort.rawValue)") { await reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Library")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .textCase(.uppercase)
                    Text("Content")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                Spacer(minLength: 8)
                StudioRangeChips(range: $range)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StudioService.Sort.allCases) { item in
                        Button {
                            sort = item
                        } label: {
                            Text(item.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(sort == item ? Theme.paper : Theme.inkSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(sort == item ? Theme.ink : Theme.matte)
                                )
                                .overlay {
                                    if sort != item {
                                        Capsule(style: .continuous)
                                            .stroke(Theme.border, lineWidth: 0.5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @MainActor
    private func reload() async {
        loading = true
        errorMessage = nil
        nextCursor = nil
        do {
            let page = try await StudioService.videos(range: range, sort: sort, limit: 30)
            videos = page.videos
            nextCursor = page.nextCursor
        } catch StudioService.StudioError.channelRequired {
            videos = []
            errorMessage = "Create a Hubs channel to manage Studio content."
        } catch {
            videos = []
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    @MainActor
    private func loadMore() async {
        guard let nextCursor, !loadingMore, !loading else { return }
        loadingMore = true
        do {
            let page = try await StudioService.videos(
                range: range,
                sort: sort,
                cursor: nextCursor,
                limit: 30
            )
            let existing = Set(videos.map(\.id))
            videos.append(contentsOf: page.videos.filter { !existing.contains($0.id) })
            self.nextCursor = page.nextCursor
        } catch {
            // Keep current page; silent fail on append.
        }
        loadingMore = false
    }
}
