import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var appState

    @State private var query = ""
    @State private var profiles: [Profile] = []
    @State private var content: [CountryPost] = []
    @State private var isSearchingPeople = false
    @State private var isSearchingContent = false
    @State private var searchError: String?
    @State private var searchGeneration = 0
    @State private var history = SearchHistoryStore.shared

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { isSearchingPeople || isSearchingContent }

    private var historySuggestions: [String] {
        history.suggestions(matching: normalizedQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            if normalizedQuery.isEmpty {
                if history.recent.isEmpty {
                    emptyPrompt
                } else {
                    historyList(title: "Recent", queries: history.recent, showsClearAll: true)
                }
            } else if isSearching && profiles.isEmpty && content.isEmpty {
                if !historySuggestions.isEmpty {
                    historyList(title: "Recent", queries: historySuggestions, showsClearAll: false)
                }
                ProgressView().tint(Theme.ink).padding()
                Spacer()
            } else {
                resultsList
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Search")
                    .font(.headline.weight(.semibold))
            }
        }
        .task {
            appState.searchPrefersCountries = false
        }
        .onAppear {
            // Returning to Search after a result open — quiet orphan Sparks / paused Hubs mini.
            appState.silencePlaybackForSearchBrowse()
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.inkMuted)
            TextField("Search people and content…", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Theme.ink)
                .submitLabel(.search)
                .onSubmit {
                    recordHistoryIfNeeded()
                    Task { await runSearch(immediate: true) }
                }
            if !query.isEmpty {
                Button {
                    clearQuery()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.inkMuted)
                }
                .accessibilityLabel("Clear search")
            }
            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.inkMuted)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
        .shadow(color: Theme.ink.opacity(0.04), radius: 12, y: 4)
        .padding(Theme.pagePadding)
        .onChange(of: query) { _, _ in
            Task { await runSearch(immediate: false) }
        }
    }

    private var emptyPrompt: some View {
        ContentUnavailableView(
            "Search Matterya",
            systemImage: "magnifyingglass",
            description: Text("Find people and posts, Sparks, and videos.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func historyList(title: String, queries: [String], showsClearAll: Bool) -> some View {
        List {
            Section {
                ForEach(queries, id: \.self) { item in
                    HStack(spacing: 12) {
                        Button {
                            applyHistoryQuery(item)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.inkMuted)
                                    .frame(width: 22)
                                Text(item)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            history.remove(item)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.inkMuted)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(item) from search history")
                    }
                }
            } header: {
                HStack {
                    Text(title)
                    Spacer()
                    if showsClearAll, !history.recent.isEmpty {
                        Button("Clear") {
                            history.clear()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
    }

    private var resultsList: some View {
        Group {
            if let searchError, profiles.isEmpty && content.isEmpty {
                ContentUnavailableView("Search failed", systemImage: "magnifyingglass", description: Text(searchError))
            } else if profiles.isEmpty && content.isEmpty && !isSearching {
                VStack(spacing: 0) {
                    if !historySuggestions.isEmpty {
                        historyList(title: "Recent", queries: historySuggestions, showsClearAll: false)
                            .frame(maxHeight: 220)
                    }
                    ContentUnavailableView(
                        "No results",
                        systemImage: "text.magnifyingglass",
                        description: Text("Try another person or keyword.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                List {
                    if !historySuggestions.isEmpty, normalizedQuery.count < 24 {
                        Section("Recent") {
                            ForEach(historySuggestions.prefix(5), id: \.self) { item in
                                HStack(spacing: 12) {
                                    Button {
                                        applyHistoryQuery(item)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "clock.arrow.circlepath")
                                                .font(.subheadline)
                                                .foregroundStyle(Theme.inkMuted)
                                                .frame(width: 22)
                                            Text(item)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(Theme.ink)
                                                .lineLimit(1)
                                            Spacer(minLength: 0)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        history.remove(item)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Theme.inkMuted)
                                            .frame(width: 28, height: 28)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove \(item) from search history")
                                }
                            }
                        }
                    }

                    if !profiles.isEmpty {
                        Section("People") {
                            ForEach(profiles) { profile in
                                HStack {
                                    profileRow(profile)
                                    Spacer()
                                    if !profile.isDemoUser, profile.userID != appState.currentProfile?.userID {
                                        FollowButton(userID: profile.userID)
                                    }
                                }
                            }
                        }
                    }

                    if !content.isEmpty {
                        Section("Content") {
                            ForEach(content) { post in
                                contentRow(post)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Theme.canvas)
            }
        }
    }

    private func contentRow(_ post: CountryPost) -> some View {
        Button {
            recordHistoryIfNeeded()
            appState.openSearchResult(post)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                contentThumbnail(post)

                VStack(alignment: .leading, spacing: 6) {
                    Text(post.authorDisplayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.ink)

                    let excerpt = post.displayExcerpt
                    if !excerpt.isEmpty {
                        Text(excerpt)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        if let country = post.countryName ?? post.countryCode?.uppercased() {
                            Text(country)
                                .font(.caption2)
                                .foregroundStyle(Theme.inkMuted)
                        }
                        Text(RelativeTime.format(post.createdAt))
                            .font(.caption2)
                            .foregroundStyle(Theme.inkMuted)
                        if post.hasVideo {
                            Text(post.isReel || PlayPlatformBridge.isSparkFeedCard(post) ? MatteryaCopy.spark : "Video")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.inkMuted)
                        } else if post.hasImage {
                            Text("Photo")
                                .font(.caption2)
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func contentThumbnail(_ post: CountryPost) -> some View {
        if post.hasVideo {
            let sparkLike = post.isReel || PlayPlatformBridge.isSparkFeedCard(post)
            let w: CGFloat = sparkLike ? 72 : 128
            let h: CGFloat = sparkLike ? 128 : 72
            YouTubeVideoThumbnail(
                post: post,
                maxPixelSize: 360,
                showsPlayIcon: false,
                frameStyle: .card,
                extractFrameIfNeeded: false,
                showsHubBadge: false
            )
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if let url = post.feedImageURL ?? post.resolvedImageURL {
            CachedAsyncImage(url: url, maxPixelSize: 160, contentMode: .fill)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.canvasMuted)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "text.alignleft")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                }
        }
    }

    private func profileRow(_ profile: Profile) -> some View {
        HStack(spacing: 12) {
            Button {
                recordHistoryIfNeeded()
                appState.openPublicProfile(username: profile.username, userID: profile.userID)
            } label: {
                HStack(spacing: 12) {
                    AvatarView(url: profile.avatarURL, seed: profile.userID, size: 40)
                    VStack(alignment: .leading) {
                        Text(profile.displayName ?? profile.username ?? "User")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        if let username = profile.username {
                            Text("@\(username)")
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                        } else if let country = profile.countryName {
                            Text(country)
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                appState.openPlayChannel(
                    authorID: profile.userID,
                    username: profile.username
                )
            } label: {
                Image(systemName: "globe.americas")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentBright)
                    .frame(width: 32, height: 32)
                    .background(Theme.accentSoft, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(MatteryaCopy.matteryaHubs) channel")
        }
    }

    private func applyHistoryQuery(_ item: String) {
        query = item
        recordHistoryIfNeeded()
        Task { await runSearch(immediate: true) }
    }

    private func clearQuery() {
        query = ""
        profiles = []
        content = []
        searchError = nil
        searchGeneration += 1
        isSearchingPeople = false
        isSearchingContent = false
        appState.silencePlaybackForSearchBrowse()
    }

    private func recordHistoryIfNeeded() {
        let trimmed = normalizedQuery
        guard !trimmed.isEmpty else { return }
        history.record(trimmed)
    }

    private func runSearch(immediate: Bool) async {
        let trimmed = normalizedQuery
        guard !trimmed.isEmpty else {
            profiles = []
            content = []
            searchError = nil
            isSearchingPeople = false
            isSearchingContent = false
            return
        }

        if !immediate {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            guard normalizedQuery == trimmed else { return }
        } else {
            history.record(trimmed)
        }

        let generation = searchGeneration + 1
        searchGeneration = generation
        searchError = nil
        isSearchingPeople = true
        isSearchingContent = true

        // Progressive: paint People as soon as they arrive; Content follows.
        async let peopleTask: Void = {
            do {
                let loaded = try await ProfileService.shared.searchProfiles(
                    trimmed,
                    limit: MatteryaSearchEngine.peopleLimit
                )
                guard searchGeneration == generation else { return }
                profiles = loaded
            } catch {
                guard searchGeneration == generation else { return }
                if profiles.isEmpty && content.isEmpty {
                    searchError = error.localizedDescription
                }
                profiles = []
            }
            if searchGeneration == generation {
                isSearchingPeople = false
            }
        }()

        async let contentTask: Void = {
            do {
                let loaded = try await PostsService.shared.searchPosts(
                    trimmed,
                    limit: MatteryaSearchEngine.contentLimit
                )
                guard searchGeneration == generation else { return }
                content = loaded
            } catch {
                guard searchGeneration == generation else { return }
                content = []
                if profiles.isEmpty {
                    searchError = searchError ?? error.localizedDescription
                }
            }
            if searchGeneration == generation {
                isSearchingContent = false
            }
        }()

        _ = await (peopleTask, contentTask)
    }
}
