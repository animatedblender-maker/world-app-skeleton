import SwiftUI

struct AnonymousFeedView: View {
    @State private var store = AnonymousStore.shared

    var body: some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            // Paint cache instantly, then soft-refresh so ranked tops rotate (ledger).
            .task {
                if store.feed.isEmpty {
                    await store.loadFeed()
                } else {
                    await store.softRefreshFeedIfStale()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.feedLoading && store.feed.isEmpty {
            AnonymousLoadingSkeleton()
        } else if store.feed.isEmpty {
            let wakeHint = (store.lastError ?? "").localizedCaseInsensitiveContains("time")
                || (store.lastError ?? "").localizedCaseInsensitiveContains("timed out")
                || (store.lastError ?? "").localizedCaseInsensitiveContains("network")
            AnonymousEmptyState(
                title: wakeHint
                    ? MatteryaCopy.anonymousFeedWakeTitle
                    : MatteryaCopy.anonymousFeedEmptyTitle,
                message: wakeHint
                    ? MatteryaCopy.anonymousFeedWakeBody
                    : MatteryaCopy.anonymousFeedEmptyBody,
                systemImage: wakeHint ? "icloud.and.arrow.down" : "text.bubble"
            )
            .refreshable { await store.refreshFeed() }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(store.feed.enumerated()), id: \.element.id) { index, post in
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
                        .onAppear {
                            // Prefetch first page of comments so opening the thread never spins.
                            AnonymousCommentsWarmCache.shared.warm(post.id)
                            // Session suppress — next refresh/load-more skips already-seen cards.
                            store.markFeedPostSeen(post.id)
                            // Endless For you — prefetch when ~8 cards from the end.
                            if index >= store.feed.count - 8 {
                                Task { await store.loadMoreFeed() }
                            }
                        }
                    }
                    if store.feedLoadingMore {
                        ProgressView()
                            .tint(Theme.inkMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
                .padding(.bottom, 8)
            }
            .background(Theme.canvas)
            .refreshable { await store.refreshFeed() }
        }
    }
}
