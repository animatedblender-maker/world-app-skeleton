import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var appState

    @State private var query = ""
    @State private var profiles: [Profile] = []
    @State private var content: [CountryPost] = []
    @State private var isSearchingPeople = false
    @State private var isSearchingContent = false
    @State private var isLoadingMorePeople = false
    @State private var isLoadingMoreContent = false
    @State private var peopleHasMore = false
    @State private var contentHasMore = false
    /// Next server offset (page-size steps — not result.count, which drifts when rows filter out).
    @State private var peopleNextOffset = 0
    @State private var contentNextOffset = 0
    @State private var searchError: String?
    @State private var searchGeneration = 0
    /// Local mirror of SearchHistoryStore so SwiftUI always repaints (List-in-VStack + Observable were flaky).
    @State private var recentQueries: [String] = SearchHistoryStore.shared.recent

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { isSearchingPeople || isSearchingContent }

    private var historySuggestions: [String] {
        let q = normalizedQuery.lowercased()
        guard !q.isEmpty else { return Array(recentQueries.prefix(8)) }
        return recentQueries
            .filter {
                let n = $0.lowercased()
                return n.contains(q) || n.hasPrefix(q)
            }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            if normalizedQuery.isEmpty {
                if recentQueries.isEmpty {
                    emptyPrompt
                } else {
                    recentPanel(title: "Recent", queries: recentQueries, showsClearAll: true)
                }
            } else if isSearching && profiles.isEmpty && content.isEmpty {
                if !historySuggestions.isEmpty {
                    recentPanel(title: "Recent", queries: historySuggestions, showsClearAll: false)
                        .frame(maxHeight: 220)
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
            reloadRecent()
        }
        .onAppear {
            reloadRecent()
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
                    recordHistory(normalizedQuery)
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
            description: Text("Find people and posts, Sparks, and videos. Recent searches will show up here.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// ScrollView (not List-in-VStack) so Recent actually gets height under the field.
    private func recentPanel(title: String, queries: [String], showsClearAll: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                Spacer()
                if showsClearAll, !recentQueries.isEmpty {
                    Button("Clear") {
                        SearchHistoryStore.shared.clear()
                        reloadRecent()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 4)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
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
                                SearchHistoryStore.shared.remove(item)
                                reloadRecent()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.inkMuted)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(item) from search history")
                        }
                        .padding(.horizontal, Theme.pagePadding)
                        .padding(.vertical, 12)
                        .background(Theme.surface)
                        Divider()
                            .padding(.leading, Theme.pagePadding + 34)
                    }
                }
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, Theme.pagePadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
    }

    private var resultsList: some View {
        Group {
            if let searchError, profiles.isEmpty && content.isEmpty {
                ContentUnavailableView("Search failed", systemImage: "magnifyingglass", description: Text(searchError))
            } else if profiles.isEmpty && content.isEmpty && !isSearching {
                VStack(spacing: 0) {
                    if !historySuggestions.isEmpty {
                        recentPanel(title: "Recent", queries: historySuggestions, showsClearAll: false)
                            .frame(maxHeight: 240)
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
                                        SearchHistoryStore.shared.remove(item)
                                        reloadRecent()
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
                        Section("People · \(profiles.count)") {
                            ForEach(profiles) { profile in
                                HStack {
                                    profileRow(profile)
                                    Spacer()
                                    if !profile.isDemoUser, profile.userID != appState.currentProfile?.userID {
                                        FollowButton(userID: profile.userID)
                                    }
                                }
                            }
                            if peopleHasMore {
                                loadMoreRow(
                                    title: "Load more people",
                                    busy: isLoadingMorePeople
                                ) {
                                    Task { await loadMorePeople() }
                                }
                            }
                        }
                    }

                    if !content.isEmpty {
                        Section("Content · \(content.count)") {
                            ForEach(content) { post in
                                contentRow(post)
                            }
                            if contentHasMore {
                                loadMoreRow(
                                    title: "Load more content",
                                    busy: isLoadingMoreContent
                                ) {
                                    Task { await loadMoreContent() }
                                }
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
            recordHistory(normalizedQuery)
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
                recordHistory(normalizedQuery)
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
        recordHistory(item)
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
        isLoadingMorePeople = false
        isLoadingMoreContent = false
        peopleHasMore = false
        contentHasMore = false
        peopleNextOffset = 0
        contentNextOffset = 0
        reloadRecent()
        appState.silencePlaybackForSearchBrowse()
    }

    private func reloadRecent() {
        recentQueries = SearchHistoryStore.shared.recent
    }

    private func recordHistory(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        SearchHistoryStore.shared.record(trimmed)
        reloadRecent()
    }

    private func loadMoreRow(title: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.ink)
                } else {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func runSearch(immediate: Bool) async {
        let trimmed = normalizedQuery
        guard !trimmed.isEmpty else {
            profiles = []
            content = []
            searchError = nil
            isSearchingPeople = false
            isSearchingContent = false
            peopleHasMore = false
            contentHasMore = false
            peopleNextOffset = 0
            contentNextOffset = 0
            return
        }

        if !immediate {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            guard normalizedQuery == trimmed else { return }
        }

        // Record as soon as a real search starts (do not wait for network).
        recordHistory(trimmed)

        let generation = searchGeneration + 1
        searchGeneration = generation
        searchError = nil
        isSearchingPeople = true
        isSearchingContent = true
        isLoadingMorePeople = false
        isLoadingMoreContent = false
        peopleHasMore = false
        contentHasMore = false
        peopleNextOffset = 0
        contentNextOffset = 0

        async let peopleTask: Void = {
            do {
                let loaded = try await ProfileService.shared.searchProfiles(
                    trimmed,
                    limit: MatteryaSearchEngine.peoplePageSize,
                    offset: 0
                )
                guard searchGeneration == generation else { return }
                profiles = loaded
                peopleNextOffset = MatteryaSearchEngine.peoplePageSize
                peopleHasMore = loaded.count >= MatteryaSearchEngine.peoplePageSize
                    && peopleNextOffset < MatteryaSearchEngine.maxPeopleTotal
            } catch {
                guard searchGeneration == generation else { return }
                if profiles.isEmpty && content.isEmpty {
                    searchError = error.localizedDescription
                }
                profiles = []
                peopleHasMore = false
            }
            if searchGeneration == generation {
                isSearchingPeople = false
            }
        }()

        async let contentTask: Void = {
            do {
                let loaded = try await PostsService.shared.searchPosts(
                    trimmed,
                    limit: MatteryaSearchEngine.contentPageSize,
                    offset: 0
                )
                guard searchGeneration == generation else { return }
                content = loaded
                contentNextOffset = MatteryaSearchEngine.contentPageSize
                contentHasMore = loaded.count >= MatteryaSearchEngine.contentPageSize
                    && contentNextOffset < MatteryaSearchEngine.maxContentTotal
            } catch {
                guard searchGeneration == generation else { return }
                content = []
                contentHasMore = false
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

    private func loadMorePeople() async {
        let trimmed = normalizedQuery
        guard !trimmed.isEmpty, peopleHasMore, !isLoadingMorePeople else { return }
        guard peopleNextOffset < MatteryaSearchEngine.maxPeopleTotal else {
            peopleHasMore = false
            return
        }
        let generation = searchGeneration
        let offset = peopleNextOffset
        isLoadingMorePeople = true
        defer { if searchGeneration == generation { isLoadingMorePeople = false } }
        do {
            let loaded = try await ProfileService.shared.searchProfiles(
                trimmed,
                limit: MatteryaSearchEngine.peoplePageSize,
                offset: offset
            )
            guard searchGeneration == generation else { return }
            let existing = Set(profiles.map(\.userID))
            let appended = loaded.filter { !existing.contains($0.userID) }
            profiles.append(contentsOf: appended)
            peopleNextOffset = offset + MatteryaSearchEngine.peoplePageSize
            peopleHasMore = loaded.count >= MatteryaSearchEngine.peoplePageSize
                && peopleNextOffset < MatteryaSearchEngine.maxPeopleTotal
        } catch {
            guard searchGeneration == generation else { return }
            peopleHasMore = false
        }
    }

    private func loadMoreContent() async {
        let trimmed = normalizedQuery
        guard !trimmed.isEmpty, contentHasMore, !isLoadingMoreContent else { return }
        guard contentNextOffset < MatteryaSearchEngine.maxContentTotal else {
            contentHasMore = false
            return
        }
        let generation = searchGeneration
        let offset = contentNextOffset
        isLoadingMoreContent = true
        defer { if searchGeneration == generation { isLoadingMoreContent = false } }
        do {
            let loaded = try await PostsService.shared.searchPosts(
                trimmed,
                limit: MatteryaSearchEngine.contentPageSize,
                offset: offset
            )
            guard searchGeneration == generation else { return }
            let existing = Set(content.map(\.id))
            let appended = loaded.filter { !existing.contains($0.id) }
            content.append(contentsOf: appended)
            contentNextOffset = offset + MatteryaSearchEngine.contentPageSize
            contentHasMore = loaded.count >= MatteryaSearchEngine.contentPageSize
                && contentNextOffset < MatteryaSearchEngine.maxContentTotal
        } catch {
            guard searchGeneration == generation else { return }
            contentHasMore = false
        }
    }
}
