import SwiftUI

struct AnonymousFeedView: View {
    @State private var store = AnonymousStore.shared
    @Bindable private var photoZoomGate = FeedPhotoZoomGate.shared

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
                // Prefetch comments for the first screen only — keep feed light.
                AnonymousCommentsWarmCache.shared.warmMany(store.feed.prefix(6).map(\.id))
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
                    // Avoid Array(enumerated()) every body pass — that copied the feed on scroll.
                    ForEach(store.feed) { post in
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
                            // Prefetch comments only for head / near-tail (not every row).
                            if let index = store.feed.firstIndex(where: { $0.id == post.id }) {
                                if index < 6 || index >= store.feed.count - 3 {
                                    AnonymousCommentsWarmCache.shared.warm(post.id)
                                }
                                // Rare silent append — only at the very end (first page is fat).
                                if store.feedHasMore,
                                   store.feed.count < AnonymousService.feedSoftCap,
                                   index >= store.feed.count - 2 {
                                    Task { await store.loadMoreFeed() }
                                }
                            }
                            // Session suppress — next refresh/load-more skips already-seen cards.
                            store.markFeedPostSeen(post.id)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollDisabled(photoZoomGate.isZooming)
            .background(Theme.canvas)
            .refreshable { await store.refreshFeed() }
        }
    }
}
