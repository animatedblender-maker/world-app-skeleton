import SwiftUI

/// Premium Hubs search — Cancel, Recent + X, Top | Creators | Videos. Separate history from main Search.
struct YouTubeSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    @Binding var query: String
    let videos: [CountryPost]
    let channels: [YouTubeChannel]
    let onSelectVideo: (CountryPost) -> Void
    let onSelectChannel: (YouTubeChannel) -> Void

    private enum Scope: String, CaseIterable, Identifiable {
        case top = "Top"
        case creators = "Creators"
        case videos = "Videos"
        var id: String { rawValue }
    }

    @State private var scope: Scope = .top
    @State private var remoteVideos: [CountryPost] = []
    @State private var remoteChannels: [YouTubeChannel] = []
    @State private var isSearchingRemote = false
    @State private var recentQueries: [String] = SearchHistoryStore.recent(for: .hubs)

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayVideos: [CountryPost] {
        videos.isEmpty ? remoteVideos : videos
    }

    private var displayChannels: [YouTubeChannel] {
        channels.isEmpty ? remoteChannels : channels
    }

    private var historySuggestions: [String] {
        SearchHistoryStore.suggestions(matching: normalizedQuery, surface: .hubs, limit: 8)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchChrome

            if normalizedQuery.isEmpty {
                idleBody
            } else {
                if !isSearchingRemote || !displayChannels.isEmpty || !displayVideos.isEmpty {
                    scopePicker
                }
                resultsBody
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .onAppear {
            reloadRecent()
            fieldFocused = true
        }
        .task(id: normalizedQuery) {
            await searchRemoteIfNeeded()
        }
    }

    private var searchChrome: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkMuted)
                TextField(MatteryaCopy.searchHubs, text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(Theme.ink)
                    .submitLabel(.search)
                    .focused($fieldFocused)
                    .onSubmit {
                        commitHistory()
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                        scope = .top
                        remoteVideos = []
                        remoteChannels = []
                        reloadRecent()
                        fieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.inkMuted.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.canvasMuted, in: Capsule(style: .continuous))

            Button("Cancel") {
                fieldFocused = false
                dismiss()
            }
            .font(.body)
            .foregroundStyle(Theme.ink)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
    }

    private var scopePicker: some View {
        HStack(spacing: 0) {
            ForEach(Scope.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { scope = item }
                } label: {
                    VStack(spacing: 8) {
                        Text(item.rawValue)
                            .font(.subheadline.weight(scope == item ? .semibold : .medium))
                            .foregroundStyle(scope == item ? Theme.ink : Theme.inkMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                        Rectangle()
                            .fill(scope == item ? Theme.ink : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
    }

    private var idleBody: some View {
        Group {
            if recentQueries.isEmpty {
                VStack(spacing: 14) {
                    Spacer(minLength: 40)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(Theme.inkMuted.opacity(0.55))
                    Text(MatteryaCopy.searchHubs)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(MatteryaCopy.searchHubsHint)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Recent")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Button("Clear all") {
                                SearchHistoryStore.clear(surface: .hubs)
                                reloadRecent()
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 8)

                        ForEach(recentQueries, id: \.self) { item in
                            recentRow(item)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func recentRow(_ item: String) -> some View {
        HStack(spacing: 14) {
            Button {
                query = item
                scope = .top
                commitHistory()
                Task { await searchRemoteIfNeeded() }
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Theme.canvasMuted)
                            .frame(width: 44, height: 44)
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.ink)
                    }
                    Text(item)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                SearchHistoryStore.remove(item, surface: .hubs)
                reloadRecent()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.inkMuted)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var resultsBody: some View {
        if isSearchingRemote && displayChannels.isEmpty && displayVideos.isEmpty {
            VStack {
                if !historySuggestions.isEmpty {
                    suggestionsStrip
                }
                ProgressView().tint(Theme.ink).padding(.top, 24)
                Spacer()
            }
        } else if displayChannels.isEmpty && displayVideos.isEmpty {
            VStack(spacing: 0) {
                if !historySuggestions.isEmpty {
                    suggestionsStrip
                }
                ContentUnavailableView(
                    "No results",
                    systemImage: "magnifyingglass",
                    description: Text("Try another search term.")
                )
            }
        } else {
            List {
                if !historySuggestions.isEmpty, normalizedQuery.count < 20, scope == .top {
                    Section {
                        ForEach(historySuggestions.prefix(4), id: \.self) { item in
                            recentRow(item)
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Theme.canvas)
                        }
                    } header: {
                        Text("Recent")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                            .textCase(nil)
                    }
                }

                switch scope {
                case .top:
                    if !displayChannels.isEmpty {
                        Section {
                            ForEach(Array(displayChannels.prefix(6))) { channel in
                                channelRow(channel)
                            }
                            if displayChannels.count > 6 {
                                Button { scope = .creators } label: {
                                    Text("See all creators")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text(MatteryaCopy.creators)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.inkMuted)
                                .textCase(nil)
                        }
                    }
                    if !displayVideos.isEmpty {
                        Section {
                            ForEach(Array(displayVideos.prefix(24))) { post in
                                videoRow(post)
                            }
                            if displayVideos.count > 24 {
                                Button { scope = .videos } label: {
                                    Text("See all videos")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text("Videos")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.inkMuted)
                                .textCase(nil)
                        }
                    }
                case .creators:
                    Section {
                        ForEach(displayChannels) { channel in
                            channelRow(channel)
                        }
                    } header: {
                        Text("\(displayChannels.count) creators")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                            .textCase(nil)
                    }
                case .videos:
                    Section {
                        ForEach(displayVideos) { post in
                            videoRow(post)
                        }
                    } header: {
                        Text("\(displayVideos.count) videos")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
        }
    }

    private var suggestionsStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            ForEach(historySuggestions.prefix(4), id: \.self) { item in
                recentRow(item)
            }
            Theme.divider.frame(height: 0.5).padding(.top, 4)
        }
        .background(Theme.surface)
    }

    private func channelRow(_ channel: YouTubeChannel) -> some View {
        Button {
            commitHistory()
            onSelectChannel(channel)
        } label: {
            HStack(spacing: 12) {
                AvatarView(url: channel.author?.avatarURL, seed: channel.authorID, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(channel.handle ?? "\(channel.videoCount) videos")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func videoRow(_ post: CountryPost) -> some View {
        Button {
            commitHistory()
            onSelectVideo(post)
        } label: {
            YouTubeVideoMetadataRow(post: post)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func reloadRecent() {
        recentQueries = SearchHistoryStore.recent(for: .hubs)
    }

    /// Only on Return / result tap / Recent pick — never on typing pause.
    private func commitHistory() {
        let trimmed = normalizedQuery
        guard trimmed.count >= 2 else { return }
        SearchHistoryStore.record(trimmed, surface: .hubs)
        reloadRecent()
    }

    private func searchRemoteIfNeeded() async {
        let trimmed = normalizedQuery
        guard trimmed.count >= 2, videos.isEmpty, channels.isEmpty else {
            remoteVideos = []
            remoteChannels = []
            isSearchingRemote = false
            return
        }

        isSearchingRemote = true
        defer { isSearchingRemote = false }

        let posts = (try? await PostsService.shared.searchPosts(trimmed, limit: 60)) ?? []
        let eligible = posts.filter { YouTubeCatalogService.shared.livingEligible($0) }
        remoteVideos = eligible.filter { !$0.isReel }
        remoteChannels = YouTubeCatalogService.shared.buildChannels(from: eligible)
    }
}
