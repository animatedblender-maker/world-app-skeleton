import SwiftUI

struct AnonymousFeedView: View {
    @State private var store = AnonymousStore.shared
    @State private var selectedPost: AnonymousPost?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sortBar
                content
            }
            .navigationDestination(item: $selectedPost) { post in
                AnonymousPostDetailView(post: post)
            }
        }
        .task { await store.loadFeed() }
    }

    private var sortBar: some View {
        HStack(spacing: 8) {
            ForEach(AnonymousFeedSort.allCases) { sort in
                Button {
                    store.feedSort = sort
                    Task { await store.refreshFeed() }
                } label: {
                    Text(sort.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(store.feedSort == sort ? Theme.surface : Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(store.feedSort == sort ? Theme.ink : Theme.matteDeep))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if store.feedLoading && store.feed.isEmpty {
            AnonymousLoadingSkeleton()
        } else if store.feed.isEmpty {
            AnonymousEmptyState(
                title: MatteryaCopy.anonymousFeedEmptyTitle,
                message: MatteryaCopy.anonymousFeedEmptyBody,
                systemImage: "text.bubble"
            )
            .refreshable { await store.refreshFeed() }
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.feed) { post in
                        Button {
                            selectedPost = post
                        } label: {
                            AnonymousPostCard(post: post) {
                                Task { await store.vote(post: post, value: post.myVote == 1 ? 0 : 1) }
                            } onDownvote: {
                                Task { await store.vote(post: post, value: post.myVote == -1 ? 0 : -1) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.pagePadding)
            }
            .refreshable { await store.refreshFeed() }
        }
    }
}
