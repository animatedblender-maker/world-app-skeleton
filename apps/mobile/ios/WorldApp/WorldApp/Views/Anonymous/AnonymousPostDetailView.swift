import SwiftUI

struct AnonymousPostDetailView: View {
    let post: AnonymousPost
    @Environment(AppState.self) private var appState
    private var store: AnonymousStore { AnonymousStore.shared }
    @State private var comments: [AnonymousComment] = []
    @State private var isLoading = true
    @State private var commentsError: String?
    @State private var replyBody = ""
    @State private var replyParentId: String?
    @State private var showReport = false
    @State private var localPost: AnonymousPost
    @FocusState private var composerFocused: Bool

    init(post: AnonymousPost) {
        self.post = post
        _localPost = State(initialValue: post)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AnonymousPostCard(
                    post: localPost,
                    style: .thread,
                    onOpenSpace: {
                        if let slug = localPost.spaceSlug, !slug.isEmpty {
                            store.pushSpace(slug: slug)
                        }
                    },
                    onToggleLike: {
                        Task {
                            let next = (localPost.myVote ?? 0) > 0 ? 0 : 1
                            if let updated = await store.vote(post: localPost, value: next) {
                                localPost = updated
                            }
                        }
                    }
                )

                HStack {
                    Button { showReport = true } label: {
                        Text("Report")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.danger)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button {
                        Task {
                            let ok = await store.block(profileId: localPost.authorProfileId)
                            if ok {
                                appState.showToast("Blocked @\(localPost.authorUsername)", style: .info)
                            } else if let msg = store.consumeError() {
                                appState.showToast(msg, style: .error)
                            } else {
                                appState.showToast("Couldn’t block this author.", style: .error)
                            }
                        }
                    } label: {
                        Text("Block author")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.vertical, 12)

                HStack(alignment: .firstTextBaseline) {
                    Text("Comments")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    if let count = localPost.commentCount, count > 0 {
                        Text("\(count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 10)

                if isLoading {
                    ProgressView().tint(Theme.ink)
                        .padding(.horizontal, Theme.pagePadding)
                } else if let commentsError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(commentsError)
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkMuted)
                        Button("Try again") {
                            Task { await loadComments() }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    }
                    .padding(.horizontal, Theme.pagePadding)
                } else if comments.isEmpty {
                    Text(MatteryaCopy.anonymousNoComments)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.horizontal, Theme.pagePadding)
                        .padding(.bottom, 8)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(flattenedComments, id: \.rowId) { row in
                            AnonymousCommentRowView(
                                comment: row.comment,
                                depth: row.depth,
                                isPostAuthor: row.comment.authorProfileId == localPost.authorProfileId,
                                onToggleLike: {
                                    Task {
                                        let next = (row.comment.myVote ?? 0) > 0 ? 0 : 1
                                        if let updated = await store.voteComment(row.comment, value: next) {
                                            replaceComment(updated)
                                        }
                                    }
                                }
                            ) {
                                replyParentId = row.comment.id
                                composerFocused = true
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .background(Theme.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composerBar
        }
        .scrollDismissesKeyboard(.interactively)
        // Back lives on MasqueradePushChrome — system nav bars stay hidden inside MainTabView.
        .toolbar(.hidden, for: .navigationBar)
        .tint(Theme.ink)
        .task {
            await refreshPostMedia()
            await loadComments()
        }
        .confirmationDialog("Report post", isPresented: $showReport, titleVisibility: .visible) {
            Button("Harassment", role: .destructive) { Task { await report("harassment") } }
            Button("Spam", role: .destructive) { Task { await report("spam") } }
            Button("Doxxing / identity", role: .destructive) { Task { await report("doxxing") } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var flattenedComments: [(rowId: String, comment: AnonymousComment, depth: Int)] {
        var out: [(rowId: String, comment: AnonymousComment, depth: Int)] = []
        func walk(_ items: [AnonymousComment], depth: Int, prefix: String) {
            for (index, item) in items.enumerated() {
                let rowId = "\(prefix)\(item.id)#\(depth)-\(index)"
                out.append((rowId, item, depth))
                if let replies = item.replies, !replies.isEmpty {
                    walk(replies, depth: depth + 1, prefix: rowId + "/")
                }
            }
        }
        walk(comments, depth: 0, prefix: "")
        return out
    }

    private var composerBar: some View {
        VStack(spacing: 8) {
            if replyParentId != nil {
                HStack {
                    Text("Replying…")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                    Spacer()
                    Button("Cancel") {
                        replyParentId = nil
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, Theme.pagePadding)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Add a comment", text: $replyBody, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .padding(10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.controlRadius)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )
                Button {
                    Task { await submitComment() }
                } label: {
                    Text("Post")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.surface)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                        .opacity(canSubmit ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        // Tab bar is hidden on this screen — sit flush; home indicator comes from safeAreaInset.
        .background(Theme.surface.opacity(0.98))
        .overlay(alignment: .top) { Theme.divider.frame(height: 0.5) }
    }

    private var canSubmit: Bool {
        !replyBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Fresh signed media_url — feed cache can hold an expired Amz signature.
    private func refreshPostMedia() async {
        do {
            var fresh = try await AnonymousService.getPost(id: localPost.id)
            // Never clobber a painted URL with a decode/empty miss (feed cards
            // share rememberPost — blanking here blanked the list on back).
            if (fresh.mediaURL == nil || fresh.mediaURL?.isEmpty == true),
               let keep = localPost.mediaURL, !keep.isEmpty {
                fresh.mediaURL = keep
            }
            if (fresh.thumbURL == nil || fresh.thumbURL?.isEmpty == true),
               let keep = localPost.thumbURL, !keep.isEmpty {
                fresh.thumbURL = keep
            }
            if fresh.mediaType == nil, let keep = localPost.mediaType {
                fresh.mediaType = keep
            }
            localPost = fresh
            store.rememberPost(fresh)
        } catch {
            // Keep painted card media — playback may still work from feed URL.
        }
    }

    private func loadComments() async {
        isLoading = true
        commentsError = nil
        defer { isLoading = false }
        do {
            let page = try await AnonymousService.listComments(postId: localPost.id)
            comments = page.items
            if localPost.commentCount == nil || (localPost.commentCount ?? 0) < page.items.count {
                localPost.commentCount = page.items.count
            }
        } catch let err as AnonymousError {
            comments = []
            commentsError = err.errorDescription ?? "Couldn’t load comments."
        } catch {
            comments = []
            commentsError = error.localizedDescription
        }
    }

    private func submitComment() async {
        let body = replyBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        do {
            let created = try await AnonymousService.createComment(
                postId: localPost.id,
                input: AnonymousCreateCommentInput(body: body, parentCommentId: replyParentId)
            )
            comments.append(created)
            replyBody = ""
            replyParentId = nil
            composerFocused = false
            localPost.commentCount = (localPost.commentCount ?? 0) + 1
        } catch let err as AnonymousError {
            appState.showToast(err.errorDescription ?? "Couldn’t post comment", style: .error)
        } catch {
            appState.showToast(error.localizedDescription, style: .error)
        }
    }

    private func report(_ reason: String) async {
        await store.report(targetType: "post", targetId: localPost.id, reason: reason)
        appState.showToast("Report submitted.", style: .info)
    }

    private func replaceComment(_ updated: AnonymousComment) {
        func walk(_ items: inout [AnonymousComment]) -> Bool {
            for i in items.indices {
                if items[i].id == updated.id {
                    items[i] = updated
                    return true
                }
                if var replies = items[i].replies, walk(&replies) {
                    items[i].replies = replies
                    return true
                }
            }
            return false
        }
        _ = walk(&comments)
    }
}

private struct AnonymousCommentRowView: View {
    let comment: AnonymousComment
    let depth: Int
    /// Matterya term for the post writer (never Reddit “OP”).
    var isPostAuthor: Bool = false
    var onToggleLike: (() -> Void)? = nil
    var onReply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("@\(comment.authorUsername)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if isPostAuthor {
                    Text("Author")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.matteDeep, in: Capsule())
                        .accessibilityLabel("Post author")
                }
                Spacer()
                Text(RelativeTime.format(comment.createdAt))
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
            Text(comment.body)
                .font(.body)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Button {
                    onToggleLike?()
                } label: {
                    let liked = (comment.myVote ?? 0) > 0
                    Label(
                        "\((comment.score ?? 0))",
                        systemImage: liked ? "heart.fill" : "heart"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(liked ? Theme.danger : Theme.inkMuted)
                }
                .buttonStyle(.plain)
                .disabled(onToggleLike == nil)
                .accessibilityLabel((comment.myVote ?? 0) > 0 ? "Unlike" : "Like")

                Button(action: onReply) {
                    Text("Reply")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 14)
        .padding(.leading, CGFloat(min(depth, 4)) * 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
    }
}
