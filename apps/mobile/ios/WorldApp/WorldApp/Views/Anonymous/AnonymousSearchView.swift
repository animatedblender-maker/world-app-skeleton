import SwiftUI

struct AnonymousSearchView: View {
    @State private var store = AnonymousStore.shared
    @State private var query = ""
    @State private var selectedPost: AnonymousPost?
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                searchField
                results
            }
            .navigationDestination(for: String.self) { slug in
                AnonymousSpaceDetailView(slug: slug)
            }
            .navigationDestination(item: $selectedPost) { post in
                AnonymousPostDetailView(post: post)
            }
        }
        .task {
            await store.loadSpaces(filter: .popular)
            await store.loadFeed()
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.inkMuted)
            TextField("Search spaces and posts", text: $query)
                .foregroundStyle(Theme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.inkMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius)
                .stroke(Theme.border, lineWidth: 0.5)
        )
        .padding(Theme.pagePadding)
    }

    @ViewBuilder
    private var results: some View {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let spaces = allSpaces.filter { space in
            guard !q.isEmpty else { return false }
            return space.title.lowercased().contains(q)
                || space.slug.lowercased().contains(q)
                || (space.description?.lowercased().contains(q) ?? false)
        }
        let posts = store.feed.filter { post in
            guard !q.isEmpty else { return false }
            return post.body.lowercased().contains(q)
                || (post.title?.lowercased().contains(q) ?? false)
                || post.authorUsername.lowercased().contains(q)
        }

        if q.isEmpty {
            AnonymousEmptyState(
                title: MatteryaCopy.anonymousSearchTitle,
                message: MatteryaCopy.anonymousSearchHint,
                systemImage: "magnifyingglass"
            )
        } else if spaces.isEmpty && posts.isEmpty {
            AnonymousEmptyState(
                title: MatteryaCopy.anonymousSearchEmptyTitle,
                message: MatteryaCopy.anonymousSearchEmptyBody,
                systemImage: "magnifyingglass"
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !spaces.isEmpty {
                        Text("Spaces")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                            .textCase(.uppercase)
                        ForEach(spaces.prefix(20)) { space in
                            Button { path.append(space.slug) } label: {
                                AnonymousSpaceCard(space: space)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !posts.isEmpty {
                        Text("Posts")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                            .textCase(.uppercase)
                        ForEach(posts.prefix(30)) { post in
                            Button { selectedPost = post } label: {
                                AnonymousPostCard(post: post)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 24)
            }
        }
    }

    private var allSpaces: [AnonymousSpace] {
        var seen = Set<String>()
        var out: [AnonymousSpace] = []
        for filter in AnonymousSpaceFilter.allCases {
            for space in store.spacesByFilter[filter] ?? [] where seen.insert(space.id).inserted {
                out.append(space)
            }
        }
        return out
    }
}
