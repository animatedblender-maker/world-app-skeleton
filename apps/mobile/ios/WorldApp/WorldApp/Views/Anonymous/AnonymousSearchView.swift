import SwiftUI

/// Premium Masquerade search — Recent + X, Top | People | Spaces | Posts.
/// History is separate from main Search / Hubs. Never records while typing.
struct AnonymousSearchView: View {
    @State private var store = AnonymousStore.shared
    @Binding var query: String
    /// When false, the header owns the text field (persistent search under chrome).
    var showsSearchField: Bool = true

    private enum Scope: String, CaseIterable, Identifiable {
        case top = "Top"
        case people = "People"
        case spaces = "Spaces"
        case posts = "Posts"
        var id: String { rawValue }
    }

    @State private var scope: Scope = .top
    @State private var results = AnonymousSearchResults()
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var lastSubmitted = ""
    @State private var searchGeneration = 0
    @State private var recentQueries: [String] = SearchHistoryStore.recent(for: .masquerade)

    init(query: Binding<String> = .constant(""), showsSearchField: Bool = true) {
        _query = query
        self.showsSearchField = showsSearchField
    }

    private var queryDebounceKey: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasResults: Bool {
        !results.people.isEmpty || !results.spaces.isEmpty || !results.posts.isEmpty
    }

    private var historySuggestions: [String] {
        SearchHistoryStore.suggestions(matching: queryDebounceKey, surface: .masquerade, limit: 8)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsSearchField {
                searchField
            }

            if queryDebounceKey.isEmpty {
                idleBody
            } else {
                if !isSearching || hasResults {
                    scopePicker
                }
                resultsBody
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(Theme.canvas)
        .onAppear { reloadRecent() }
        .task(id: queryDebounceKey) {
            await runSearchDebounced()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.inkMuted)
            TextField("Search people, spaces, posts", text: $query)
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { commitHistory() }
            if !query.isEmpty {
                Button {
                    clearQuery()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.inkMuted)
                }
                .buttonStyle(.plain)
            }
            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.inkMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.canvasMuted, in: Capsule(style: .continuous))
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 8)
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
                            .padding(.top, 10)
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
                AnonymousEmptyState(
                    title: MatteryaCopy.anonymousSearchTitle,
                    message: MatteryaCopy.anonymousSearchHint,
                    systemImage: "magnifyingglass"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Recent")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Button("Clear all") {
                                SearchHistoryStore.clear(surface: .masquerade)
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
                SearchHistoryStore.remove(item, surface: .masquerade)
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
        let q = queryDebounceKey

        if isSearching && !hasResults {
            VStack {
                if !historySuggestions.isEmpty {
                    suggestionsStrip
                }
                ProgressView()
                    .tint(Theme.ink)
                    .padding(.top, 24)
                Spacer()
            }
        } else if let searchError, !hasResults {
            VStack(spacing: 0) {
                if !historySuggestions.isEmpty { suggestionsStrip }
                AnonymousEmptyState(
                    title: MatteryaCopy.anonymousSearchEmptyTitle,
                    message: searchError,
                    systemImage: "magnifyingglass"
                )
            }
        } else if !hasResults {
            VStack(spacing: 0) {
                if !historySuggestions.isEmpty { suggestionsStrip }
                AnonymousEmptyState(
                    title: MatteryaCopy.anonymousSearchEmptyTitle,
                    message: MatteryaCopy.anonymousSearchEmptyBody,
                    systemImage: "magnifyingglass"
                )
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !historySuggestions.isEmpty, q.count < 20, scope == .top {
                        sectionHeader("Recent")
                        ForEach(historySuggestions.prefix(4), id: \.self) { item in
                            recentRow(item)
                        }
                    }

                    switch scope {
                    case .top:
                        if !results.people.isEmpty {
                            sectionHeader("People")
                            ForEach(Array(results.people.prefix(6))) { person in
                                peopleButton(person)
                            }
                            if results.people.count > 6 {
                                seeAllButton("See all people") { scope = .people }
                            }
                        }
                        if !results.spaces.isEmpty {
                            sectionHeader("Spaces")
                            ForEach(Array(results.spaces.prefix(6))) { space in
                                spaceButton(space)
                            }
                            if results.spaces.count > 6 {
                                seeAllButton("See all spaces") { scope = .spaces }
                            }
                        }
                        if !results.posts.isEmpty {
                            sectionHeader("Posts")
                            ForEach(Array(results.posts.prefix(12))) { post in
                                postCard(post)
                            }
                            if results.posts.count > 12 {
                                seeAllButton("See all posts") { scope = .posts }
                            }
                        }
                    case .people:
                        sectionHeader("\(results.people.count) people")
                        ForEach(results.people) { person in
                            peopleButton(person)
                        }
                    case .spaces:
                        sectionHeader("\(results.spaces.count) spaces")
                        ForEach(results.spaces) { space in
                            spaceButton(space)
                        }
                    case .posts:
                        sectionHeader("\(results.posts.count) posts")
                        ForEach(results.posts) { post in
                            postCard(post)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.inkMuted)
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }

    private func seeAllButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func peopleButton(_ person: AnonymousProfile) -> some View {
        Button {
            commitHistory()
            store.pushProfile(username: person.username)
        } label: {
            peopleRow(person)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 10)
    }

    private func spaceButton(_ space: AnonymousSpace) -> some View {
        Button {
            commitHistory()
            store.pushSpace(slug: space.slug)
        } label: {
            AnonymousSpaceCard(space: space)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 10)
    }

    private func postCard(_ post: AnonymousPost) -> some View {
        AnonymousPostCard(
            post: post,
            style: .feed,
            onOpenSpace: {
                if let slug = post.spaceSlug, !slug.isEmpty {
                    commitHistory()
                    store.pushSpace(slug: slug)
                }
            },
            onToggleLike: {
                Task {
                    let next = (post.myVote ?? 0) > 0 ? 0 : 1
                    await store.vote(post: post, value: next)
                }
            }
        ) {
            commitHistory()
            store.pushPost(post)
        }
        .onAppear { AnonymousCommentsWarmCache.shared.warm(post.id) }
    }

    private func peopleRow(_ person: AnonymousProfile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(person.username)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Masquerade identity")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border.opacity(0.85), lineWidth: 0.5)
        )
    }

    private func clearQuery() {
        query = ""
        scope = .top
        results = AnonymousSearchResults()
        searchError = nil
        lastSubmitted = ""
        searchGeneration += 1
        isSearching = false
        reloadRecent()
    }

    private func reloadRecent() {
        recentQueries = SearchHistoryStore.recent(for: .masquerade)
    }

    /// Only on Return / result tap / Recent pick — never on typing pause.
    private func commitHistory() {
        let q = queryDebounceKey
        guard q.count >= 2 else { return }
        SearchHistoryStore.record(q, surface: .masquerade)
        reloadRecent()
    }

    @MainActor
    private func runSearchDebounced() async {
        let q = queryDebounceKey
        if q.isEmpty {
            results = AnonymousSearchResults()
            searchError = nil
            lastSubmitted = ""
            isSearching = false
            return
        }
        try? await Task.sleep(nanoseconds: 120_000_000)
        guard !Task.isCancelled else { return }
        guard queryDebounceKey == q else { return }
        if q == lastSubmitted, hasResults {
            return
        }

        let generation = searchGeneration + 1
        searchGeneration = generation
        isSearching = true
        searchError = nil
        do {
            let remote = try await AnonymousService.search(query: q, limit: 40)
            guard searchGeneration == generation, queryDebounceKey == q else { return }
            results = remote
            lastSubmitted = q
            for post in remote.posts {
                store.rememberPost(post)
            }
            // Do not record here — typing must not create Recent rows.
        } catch {
            guard searchGeneration == generation, queryDebounceKey == q else { return }
            searchError = (error as? AnonymousError)?.errorDescription ?? error.localizedDescription
            if !hasResults {
                results = AnonymousSearchResults()
            }
        }
        if searchGeneration == generation {
            isSearching = false
        }
    }
}
