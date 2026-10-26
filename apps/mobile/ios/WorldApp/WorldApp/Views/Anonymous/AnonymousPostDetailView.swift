import SwiftUI

struct AnonymousPostDetailView: View {
    let post: AnonymousPost
    @Environment(AppState.self) private var appState
    private var store: AnonymousStore { AnonymousStore.shared }
    @State private var comments: [AnonymousComment]
    /// True after first fetch finishes — empty copy only then; never a spinner.
    @State private var hasCompletedInitialLoad = false
    @State private var commentsError: String?
    @State private var replyBody = ""
    @State private var replyParentId: String?
    @State private var localPost: AnonymousPost
    @FocusState private var composerFocused: Bool

    init(post: AnonymousPost) {
        self.post = post
        _localPost = State(initialValue: post)
        // Seed from warm cache so the thread paints on first frame.
        _comments = State(initialValue: AnonymousCommentsWarmCache.shared.cached(post.id) ?? [])
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

                commentsSectionHeader

                if let commentsError {
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
                    if hasCompletedInitialLoad {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(MatteryaCopy.anonymousNoComments)
                                .font(.system(size: 17, weight: .regular, design: .serif))
                                .foregroundStyle(Theme.ink)
                            Text("Say the thing everyone else is thinking.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.inkMuted)
                        }
                        .padding(.horizontal, Theme.pagePadding)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { composerFocused = true }
                    }
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
        .onAppear {
            if comments.isEmpty, let warm = AnonymousCommentsWarmCache.shared.cached(localPost.id) {
                comments = warm
                hasCompletedInitialLoad = true
            }
            AnonymousCommentsWarmCache.shared.warm(localPost.id)
        }
        .task {
            // Comments first — never block the thread on media re-sign.
            async let commentsTask: Void = loadComments()
            async let mediaTask: Void = refreshPostMedia()
            _ = await (commentsTask, mediaTask)
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

    private var commentsSectionHeader: some View {
        let count = max(localPost.commentCount ?? 0, flattenedComments.count)
        return HStack(spacing: 8) {
            Text(count == 0 ? "Comments" : "Comments · \(count)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .overlay(alignment: .top) {
            Theme.divider.frame(height: 0.5)
        }
    }

    private var replyTargetUsername: String? {
        guard let replyParentId else { return nil }
        func find(_ items: [AnonymousComment]) -> String? {
            for item in items {
                if item.id == replyParentId { return item.authorUsername }
                if let nested = item.replies, let hit = find(nested) { return hit }
            }
            return nil
        }
        return find(comments)
    }

    private var composerBar: some View {
        VStack(spacing: 8) {
            if replyParentId != nil {
                HStack {
                    Text(replyTargetUsername.map { "Replying to @\($0)" } ?? "Replying…")
                        .font(.caption.weight(.semibold))
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
                TextField(
                    replyParentId == nil ? "Join the thread…" : "Write your reply…",
                    text: $replyBody,
                    axis: .vertical
                )
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .padding(10)
                    .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
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
        commentsError = nil
        // Paint warm/disk cache immediately so the thread never sits empty.
        if comments.isEmpty, let warm = AnonymousCommentsWarmCache.shared.cached(localPost.id) {
            comments = warm
            hasCompletedInitialLoad = true
        }

        let loaded = await AnonymousCommentsWarmCache.shared.load(localPost.id)
        if !loaded.isEmpty {
            comments = loaded
            if localPost.commentCount == nil || (localPost.commentCount ?? 0) < countComments(loaded) {
                localPost.commentCount = countComments(loaded)
            }
            hasCompletedInitialLoad = true
            return
        }

        // Cache miss / empty warm — one direct fetch (API no longer signs media first).
        do {
            let page = try await AnonymousService.listComments(postId: localPost.id)
            comments = page.items
            if !page.items.isEmpty {
                AnonymousCommentsWarmCache.shared.store(localPost.id, comments: page.items)
            }
            let n = countComments(page.items)
            if localPost.commentCount == nil || (localPost.commentCount ?? 0) < n {
                localPost.commentCount = n
            }
        } catch let err as AnonymousError {
            if comments.isEmpty {
                commentsError = err.errorDescription ?? "Couldn’t load comments."
            }
        } catch {
            if comments.isEmpty {
                commentsError = error.localizedDescription
            }
        }
        hasCompletedInitialLoad = true
    }

    private func countComments(_ items: [AnonymousComment]) -> Int {
        var n = 0
        func walk(_ list: [AnonymousComment]) {
            for item in list {
                n += 1
                if let replies = item.replies, !replies.isEmpty { walk(replies) }
            }
        }
        walk(items)
        return n
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
            AnonymousCommentsWarmCache.shared.store(localPost.id, comments: comments)
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
        if walk(&comments) {
            AnonymousCommentsWarmCache.shared.store(localPost.id, comments: comments)
        }
    }
}

private struct AnonymousCommentRowView: View {
    let comment: AnonymousComment
    let depth: Int
    /// Matterya term for the post writer (never Reddit “OP”).
    var isPostAuthor: Bool = false
    var onToggleLike: (() -> Void)? = nil
    var onReply: () -> Void

    private var isOfficialMatterya: Bool {
        comment.authorUsername
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "matterya"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Thread rails — Reddit nesting, Matterya paper.
            if depth > 0 {
                HStack(spacing: 0) {
                    ForEach(0..<min(depth, 5), id: \.self) { _ in
                        Rectangle()
                            .fill(Theme.ink.opacity(0.10))
                            .frame(width: 2)
                            .padding(.trailing, 10)
                    }
                }
                .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if isOfficialMatterya {
                        AvatarView(url: nil, seed: "matterya", size: 18)
                        Text("Matterya")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        MatteryaVerifiedBadge(size: 11)
                    } else {
                        Button {
                            AnonymousStore.shared.pushProfile(username: comment.authorUsername)
                        } label: {
                            Text("@\(comment.authorUsername)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.inkMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open @\(comment.authorUsername)")
                    }
                    if isPostAuthor {
                        Text("Author")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.matteDeep, in: Capsule())
                            .accessibilityLabel("Post author")
                    }
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(Theme.inkMuted)
                    Text(RelativeTime.format(comment.createdAt))
                        .font(.caption2)
                        .foregroundStyle(Theme.inkMuted)
                    Spacer(minLength: 0)
                }

                MatteryaRichText(
                    text: comment.displayBody,
                    font: .body,
                    color: Theme.ink
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 14) {
                    Button {
                        onToggleLike?()
                    } label: {
                        let liked = (comment.myVote ?? 0) > 0
                        HStack(spacing: 4) {
                            Image(systemName: liked ? "heart.fill" : "heart")
                                .font(.system(size: 12, weight: .semibold))
                            Text("\((comment.score ?? 0))")
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(liked ? Theme.danger : Theme.inkMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            (liked ? Theme.danger.opacity(0.10) : Color.clear),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(onToggleLike == nil)
                    .accessibilityLabel((comment.myVote ?? 0) > 0 ? "Unlike" : "Like")

                    Button(action: onReply) {
                        Text("Reply")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
    }
}
