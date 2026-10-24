import SwiftUI

struct AnonymousSearchView: View {
    @State private var store = AnonymousStore.shared
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            searchField
            results
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // Spaces only — loading the full Masquerade feed here doubled network + decode cost.
            await store.loadSpaces(filter: .popular)
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
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !spaces.isEmpty {
                        Text("Spaces")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                            .textCase(.uppercase)
                            .padding(.horizontal, Theme.pagePadding)
                            .padding(.top, 8)
                            .padding(.bottom, 10)
                        ForEach(spaces.prefix(20)) { space in
                            Button { store.pushSpace(slug: space.slug) } label: {
                                AnonymousSpaceCard(space: space)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, Theme.pagePadding)
                            .padding(.bottom, 10)
                        }
                    }
                    if !posts.isEmpty {
                        Text("Posts")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                            .textCase(.uppercase)
                            .padding(.horizontal, Theme.pagePadding)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                        ForEach(posts.prefix(30)) { post in
                            AnonymousPostCard(
                                post: post,
                                style: .feed,
                                onOpenSpace: {
                                    if let slug = post.spaceSlug, !slug.isEmpty {
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
                                store.pushPost(post)
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Theme.canvas)
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
