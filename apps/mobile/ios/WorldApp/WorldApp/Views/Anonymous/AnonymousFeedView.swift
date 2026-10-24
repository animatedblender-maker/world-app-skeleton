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
                    }
                }
                .padding(.bottom, 8)
            }
            .background(Theme.canvas)
            .refreshable { await store.refreshFeed() }
        }
    }
}
