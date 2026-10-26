import SwiftUI

/// Masquerade anonymous profile — handle + their public posts.
struct AnonymousPublicProfileView: View {
    let username: String
    @Environment(AppState.self) private var appState
    private var store: AnonymousStore { AnonymousStore.shared }

    @State private var profile: AnonymousProfile?
    @State private var postCount: Int?
    @State private var spaceCount: Int?
    @State private var posts: [AnonymousPost] = []
    @State private var nextCursor: String?
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var loadFailed = false
    @State private var errorMessage: String?

    private var handle: String {
        username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    var body: some View {
        Group {
            if isLoading && profile == nil {
                ProgressView()
                    .tint(Theme.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loadFailed, profile == nil {
                AnonymousEmptyState(
                    title: "Profile unavailable",
                    message: errorMessage ?? "This Masquerade identity couldn’t be opened.",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    actionTitle: "Back"
                ) {
                    store.popNavigation()
                }
            } else if let profile {
                profileScroll(profile)
            } else {
                AnonymousEmptyState(
                    title: "Profile unavailable",
                    message: "This Masquerade identity couldn’t be opened.",
                    systemImage: "person.crop.circle",
                    actionTitle: "Back"
                ) {
                    store.popNavigation()
                }
            }
        }
        .background(Theme.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: handle) {
            await loadProfile()
        }
    }

    @ViewBuilder
    private func profileScroll(_ profile: AnonymousProfile) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                headerCard(profile)
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                if posts.isEmpty && !isLoading {
                    Text("No public posts yet")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.pagePadding)
                        .padding(.bottom, 24)
                } else {
                    Text("Posts")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .textCase(.uppercase)
                        .padding(.horizontal, Theme.pagePadding)
                        .padding(.bottom, 8)

                    ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
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
                                    if let updated = await store.vote(post: post, value: next) {
                                        if let i = posts.firstIndex(where: { $0.id == updated.id }) {
                                            posts[i] = updated
                                        }
                                    }
                                }
                            }
                        ) {
                            store.pushPost(post)
                        }
                        .onAppear {
                            AnonymousCommentsWarmCache.shared.warm(post.id)
                            if index >= posts.count - 4 {
                                Task { await loadMorePosts() }
                            }
                        }
                    }

                    if isLoadingMore {
                        ProgressView()
                            .tint(Theme.inkMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { await loadProfile(force: true) }
    }

    private func headerCard(_ profile: AnonymousProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Masquerade")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
                .textCase(.uppercase)

            Text("@\(profile.username)")
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)

            HStack(spacing: 16) {
                if let postCount {
                    Text("\(postCount.formatted()) posts")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
                if let spaceCount, spaceCount > 0 {
                    Text("\(spaceCount.formatted()) spaces")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            Text(MatteryaCopy.anonymousMeHint)
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    @MainActor
    private func loadProfile(force: Bool = false) async {
        guard !handle.isEmpty else {
            loadFailed = true
            errorMessage = "Missing username."
            isLoading = false
            return
        }
        if force {
            posts = []
            nextCursor = nil
        }
        isLoading = true
        loadFailed = false
        errorMessage = nil
        do {
            let payload = try await AnonymousService.publicProfile(username: handle)
            profile = payload.profile
            postCount = payload.postCount
            spaceCount = payload.spaceCount
            let page = try await AnonymousService.authorPosts(username: handle, limit: 24)
            posts = page.items
            nextCursor = page.nextCursor
            for post in page.items {
                store.rememberPost(post)
            }
        } catch {
            loadFailed = true
            errorMessage = (error as? AnonymousError)?.errorDescription ?? error.localizedDescription
            if profile == nil {
                appState.showToast(errorMessage ?? "Couldn’t load profile", style: .error)
            }
        }
        isLoading = false
    }

    @MainActor
    private func loadMorePosts() async {
        guard let cursor = nextCursor, !cursor.isEmpty, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await AnonymousService.authorPosts(username: handle, cursor: cursor, limit: 24)
            var seen = Set(posts.map(\.id))
            for post in page.items where seen.insert(post.id).inserted {
                posts.append(post)
                store.rememberPost(post)
            }
            nextCursor = page.nextCursor
        } catch {
            // Soft-fail load-more — keep what we have.
        }
    }
}
