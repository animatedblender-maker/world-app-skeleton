import SwiftUI

/// Premium Search — Instagram / X style: Cancel, Recent + X, Top | People | Content.
struct SearchView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    private enum ResultScope: String, CaseIterable, Identifiable {
        case top = "Top"
        case people = "People"
        case content = "Content"
        var id: String { rawValue }
    }

    @State private var query = ""
    @State private var scope: ResultScope = .top
    @State private var profiles: [Profile] = []
    @State private var content: [CountryPost] = []
    @State private var isSearchingPeople = false
    @State private var isSearchingContent = false
    @State private var isLoadingMorePeople = false
    @State private var isLoadingMoreContent = false
    @State private var peopleHasMore = false
    @State private var contentHasMore = false
    @State private var peopleNextOffset = 0
    @State private var contentNextOffset = 0
    @State private var searchError: String?
    @State private var searchGeneration = 0
    @State private var recentQueries: [String] = SearchHistoryStore.recent(for: .main)

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool { isSearchingPeople || isSearchingContent }

    private var historySuggestions: [String] {
        SearchHistoryStore.suggestions(matching: normalizedQuery, surface: .main, limit: 8)
    }

    private var topPeople: [Profile] { Array(profiles.prefix(6)) }
    private var topContent: [CountryPost] { Array(content.prefix(24)) }

    var body: some View {
        VStack(spacing: 0) {
            searchChrome

            if normalizedQuery.isEmpty {
                idleBody
            } else {
                if !isSearching || !profiles.isEmpty || !content.isEmpty {
                    scopePicker
                }
                resultsBody
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            appState.searchPrefersCountries = false
            reloadRecent()
            fieldFocused = true
        }
        .onAppear {
            reloadRecent()
            appState.silencePlaybackForSearchBrowse()
        }
    }

    // MARK: - Chrome (field + Cancel)

    private var searchChrome: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkMuted)
                TextField("Search", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(Theme.ink)
                    .submitLabel(.search)
                    .focused($fieldFocused)
                    .onSubmit {
                        // Keyboard Search / Return — the only type-to-commit path.
                        commitSearchToHistory()
                        Task { await runSearch(immediate: true) }
                    }
                if !query.isEmpty {
                    Button {
                        clearQuery(keepFocus: true)
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
            .font(.body.weight(.regular))
            .foregroundStyle(Theme.ink)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
        .onChange(of: query) { _, _ in
            Task { await runSearch(immediate: false) }
        }
    }

    private var scopePicker: some View {
        HStack(spacing: 0) {
            ForEach(ResultScope.allCases) { item in
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

    // MARK: - Idle (Recent)

    private var idleBody: some View {
        Group {
            if recentQueries.isEmpty {
                VStack(spacing: 14) {
                    Spacer(minLength: 40)
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(Theme.inkMuted.opacity(0.55))
                    Text("Search Matterya")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("People, posts, Sparks, and videos")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                    Text("Recent appears after Search on the keyboard or opening a result.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 32)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Recent")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Button("Clear all") {
                                SearchHistoryStore.clear(surface: .main)
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
                applyHistoryQuery(item)
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
                SearchHistoryStore.remove(item, surface: .main)
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

    // MARK: - Results

    @ViewBuilder
    private var resultsBody: some View {
        if isSearching && profiles.isEmpty && content.isEmpty {
            VStack(spacing: 12) {
                if !historySuggestions.isEmpty {
                    suggestionsStrip
                }
                ProgressView()
                    .tint(Theme.ink)
                    .padding(.top, 24)
                Spacer()
            }
        } else if let searchError, profiles.isEmpty && content.isEmpty {
            ContentUnavailableView(
                "Search failed",
                systemImage: "exclamationmark.magnifyingglass",
                description: Text(searchError)
            )
        } else if profiles.isEmpty && content.isEmpty {
            VStack(spacing: 0) {
                if !historySuggestions.isEmpty {
                    suggestionsStrip
                }
                ContentUnavailableView(
                    "No results",
                    systemImage: "text.magnifyingglass",
                    description: Text("Try another name or keyword.")
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
                    if !topPeople.isEmpty {
                        Section {
                            ForEach(topPeople) { profile in
                                peopleRow(profile)
                            }
                            if profiles.count > topPeople.count {
                                Button {
                                    scope = .people
                                } label: {
                                    Text("See all people")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text("People")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.inkMuted)
                                .textCase(nil)
                        }
                    }
                    if !topContent.isEmpty {
                        Section {
                            ForEach(topContent) { post in
                                contentRow(post)
                            }
                            if contentHasMore || content.count > topContent.count {
                                Button {
                                    scope = .content
                                } label: {
                                    Text("See all content")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text("Content")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.inkMuted)
                                .textCase(nil)
                        }
                    }
                case .people:
                    Section {
                        ForEach(profiles) { profile in
                            peopleRow(profile)
                        }
                        if peopleHasMore {
                            loadMoreRow(title: "Load more people", busy: isLoadingMorePeople) {
                                Task { await loadMorePeople() }
                            }
                        }
                    } header: {
                        Text("\(profiles.count) people")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                            .textCase(nil)
                    }
                case .content:
                    Section {
                        ForEach(content) { post in
                            contentRow(post)
                        }
                        if contentHasMore {
                            loadMoreRow(title: "Load more content", busy: isLoadingMoreContent) {
                                Task { await loadMoreContent() }
                            }
                        }
                    } header: {
                        Text("\(content.count) posts")
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
            Theme.divider.frame(height: 0.5)
                .padding(.top, 4)
        }
        .background(Theme.surface)
    }

    // MARK: - Rows

    private func peopleRow(_ profile: Profile) -> some View {
        HStack(spacing: 12) {
            Button {
                commitSearchToHistory()
                appState.openPublicProfile(username: profile.username, userID: profile.userID)
            } label: {
                HStack(spacing: 12) {
                    AvatarView(url: profile.avatarURL, seed: profile.userID, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(profile.displayName ?? profile.username ?? "User")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            if profile.isVerified == true {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                        if let username = profile.username {
                            Text("@\(username)")
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                                .lineLimit(1)
                        } else if let country = profile.countryName {
                            Text(country)
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !profile.isDemoUser, profile.userID != appState.currentProfile?.userID {
                FollowButton(userID: profile.userID)
            }
        }
        .padding(.vertical, 4)
    }

    private func contentRow(_ post: CountryPost) -> some View {
        Button {
            commitSearchToHistory()
            appState.openSearchResult(post)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                contentThumbnail(post)

                VStack(alignment: .leading, spacing: 5) {
                    Text(post.authorDisplayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)

                    let excerpt = post.displayExcerpt
                    Text(excerpt.isEmpty ? (post.hasVideo ? "Video" : "Post") : excerpt)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        if post.hasVideo {
                            Label(
                                post.isReel || PlayPlatformBridge.isSparkFeedCard(post)
                                    ? MatteryaCopy.spark
                                    : "Video",
                                systemImage: "play.fill"
                            )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                            .labelStyle(.titleAndIcon)
                        } else if post.hasImage {
                            Text("Photo")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.inkMuted)
                        }
                        Text(RelativeTime.format(post.createdAt))
                            .font(.caption2)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func contentThumbnail(_ post: CountryPost) -> some View {
        let sparkLike = post.hasVideo && (post.isReel || PlayPlatformBridge.isSparkFeedCard(post))

        Group {
            if sparkLike {
                // True 9:16 Spark portrait — never the Hubs 16:9 card frame.
                Color.clear
                    .frame(width: 72, height: 128)
                    .overlay {
                        VideoThumbnailView(
                            post: post,
                            maxPixelSize: 420,
                            contentMode: .fill,
                            showsPlayIcon: true,
                            extractFrameIfNeeded: false,
                            placeholder: AnyView(
                                Theme.canvasDeep.overlay {
                                    Image(systemName: "play.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.85))
                                }
                            )
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.border.opacity(0.45), lineWidth: 0.5)
                    )
            } else if post.hasVideo {
                YouTubeVideoThumbnail(
                    post: post,
                    maxPixelSize: 360,
                    showsPlayIcon: true,
                    frameStyle: .card,
                    embedsFrame: false,
                    extractFrameIfNeeded: false,
                    showsHubBadge: false
                )
                .frame(width: 112, height: 63)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if let url = post.feedImageURL ?? post.resolvedImageURL {
                CachedAsyncImage(url: url, maxPixelSize: 160, contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Theme.canvasMuted
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: "text.alignleft")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func loadMoreRow(title: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                if busy {
                    ProgressView().controlSize(.small).tint(Theme.ink)
                } else {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    // MARK: - Actions

    private func applyHistoryQuery(_ item: String) {
        query = item
        scope = .top
        commitSearchToHistory(explicit: item)
        Task { await runSearch(immediate: true) }
    }

    private func clearQuery(keepFocus: Bool) {
        query = ""
        scope = .top
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
        fieldFocused = keepFocus
        appState.silencePlaybackForSearchBrowse()
    }

    private func reloadRecent() {
        recentQueries = SearchHistoryStore.recent(for: .main)
    }

    /// History commit — Return / result tap / Recent pick only. Never from debounce.
    private func commitSearchToHistory(explicit: String? = nil) {
        let trimmed = (explicit ?? normalizedQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        SearchHistoryStore.record(trimmed, surface: .main)
        reloadRecent()
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
            // Empty field → show Recent (idle). Refresh so commits from result taps appear.
            reloadRecent()
            return
        }

        if !immediate {
            // Live results only — never write Recent on this path (mid-word pause).
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            guard normalizedQuery == trimmed else { return }
        }

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
            profiles.append(contentsOf: loaded.filter { !existing.contains($0.userID) })
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
            content.append(contentsOf: loaded.filter { !existing.contains($0.id) })
            contentNextOffset = offset + MatteryaSearchEngine.contentPageSize
            contentHasMore = loaded.count >= MatteryaSearchEngine.contentPageSize
                && contentNextOffset < MatteryaSearchEngine.maxContentTotal
        } catch {
            guard searchGeneration == generation else { return }
            contentHasMore = false
        }
    }
}
