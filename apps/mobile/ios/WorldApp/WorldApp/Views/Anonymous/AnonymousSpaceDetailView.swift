import SwiftUI

struct AnonymousSpaceDetailView: View {
    let slug: String
    @Environment(AppState.self) private var appState
    @State private var store = AnonymousStore.shared
    @State private var showComposer = false
    @State private var showModPanel = false
    @State private var showReport = false
    @State private var selectedPost: AnonymousPost?

    var body: some View {
        Group {
            if let space = store.currentSpace, space.slug == slug {
                spaceBody(space)
            } else if store.spacePostsLoading {
                ProgressView()
                    .tint(Theme.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                AnonymousEmptyState(
                    title: MatteryaCopy.anonymousSpaceMissing,
                    message: MatteryaCopy.anonymousSpaceMissingBody,
                    systemImage: "questionmark.folder"
                )
            }
        }
        .navigationTitle(store.currentSpace?.title ?? slug)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.openSpace(slug: slug)
        }
        .sheet(isPresented: $showComposer) {
            if let space = store.currentSpace {
                AnonymousComposerView(spaceId: space.id, spaceTitle: space.title)
                    .environment(appState)
            }
        }
        .sheet(isPresented: $showModPanel) {
            AnonymousModPanelView(spaceTitle: store.currentSpace?.title ?? slug)
        }
        .confirmationDialog("Report Space", isPresented: $showReport, titleVisibility: .visible) {
            Button("Harassment", role: .destructive) { Task { await report("harassment") } }
            Button("Spam", role: .destructive) { Task { await report("spam") } }
            Button("Illegal or harmful", role: .destructive) { Task { await report("illegal") } }
            Button("Cancel", role: .cancel) {}
        }
        .navigationDestination(item: $selectedPost) { post in
            AnonymousPostDetailView(post: post)
        }
    }

    @ViewBuilder
    private func spaceBody(_ space: AnonymousSpace) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(space)
                rules(space)
                actions(space)
                postsSection
            }
            .padding(Theme.pagePadding)
        }
        .refreshable { await store.openSpace(slug: slug) }
    }

    private func header(_ space: AnonymousSpace) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("a/\(space.slug)")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                Spacer()
                if space.isPaid {
                    Text("Paid")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.matteDeep, in: Capsule())
                }
            }
            if let description = space.description, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundStyle(Theme.inkSecondary)
            }
            HStack(spacing: 12) {
                if let count = space.memberCount {
                    Text("\(count.formatted()) members")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                if let owner = space.ownerUsername {
                    Text("Owner @\(owner)")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func rules(_ space: AnonymousSpace) -> some View {
        if let rules = space.rules, !rules.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Rules")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                ForEach(Array(rules.enumerated()), id: \.offset) { idx, rule in
                    Text("\(idx + 1). \(rule)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
        }
    }

    private func actions(_ space: AnonymousSpace) -> some View {
        VStack(spacing: 10) {
            if space.isPaid {
                Text(MatteryaCopy.anonymousPaidJoinDisabled)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Join — coming soon")
                    .elegantButton()
                    .opacity(0.45)
            } else if space.isJoined == true {
                HStack(spacing: 10) {
                    Button { showComposer = true } label: {
                        Text("New post").elegantButton()
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await store.leaveCurrentSpace() }
                    } label: {
                        Text("Leave").elegantButton(outlined: true)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    Task { await store.joinCurrentSpace() }
                } label: {
                    Text("Join Space").elegantButton()
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                if space.isOwner == true || space.isModerator == true {
                    Button { showModPanel = true } label: {
                        Text("Mod tools")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.matteDeep, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    }
                    .buttonStyle(.plain)
                }
                Button { showReport = true } label: {
                    Text("Report")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.controlRadius)
                                .stroke(Theme.border, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var postsSection: some View {
        Text("Posts")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)

        if store.spacePosts.isEmpty {
            Text(MatteryaCopy.anonymousSpaceEmptyPosts)
                .font(.subheadline)
                .foregroundStyle(Theme.inkMuted)
                .padding(.vertical, 12)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(store.spacePosts) { post in
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
        }
    }

    private func report(_ reason: String) async {
        guard let id = store.currentSpace?.id else { return }
        await store.report(targetType: "space", targetId: id, reason: reason)
        appState.showToast("Report submitted.", style: .info)
    }
}

struct AnonymousPostCard: View {
    let post: AnonymousPost
    var onUpvote: () -> Void = {}
    var onDownvote: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("@\(post.authorUsername)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let space = post.spaceTitle ?? post.spaceSlug {
                    Text("in \(space)")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .lineLimit(1)
                }
                Spacer()
                Text(post.createdAt.prefix(10))
                    .font(.caption2)
                    .foregroundStyle(Theme.inkMuted)
            }

            if let title = post.title, !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
            }

            Text(post.body)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(6)
                .multilineTextAlignment(.leading)

            HStack(spacing: 16) {
                Button(action: onUpvote) {
                    Label("\(post.score ?? 0)", systemImage: post.myVote == 1 ? "arrow.up.circle.fill" : "arrow.up.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)

                Button(action: onDownvote) {
                    Image(systemName: post.myVote == -1 ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                }
                .buttonStyle(.plain)

                Label("\(post.commentCount ?? 0)", systemImage: "bubble.left")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }
}
