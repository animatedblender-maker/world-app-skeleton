import SwiftUI

enum CommentThreadLayout {
    static let indentPerLevel: CGFloat = 44
    /// Flat threads: top-level comments at 0, all replies at 1.
    static let maxDepth = 1

    static func indent(for depth: Int) -> CGFloat {
        CGFloat(min(max(depth, 0), maxDepth)) * indentPerLevel
    }
}

protocol CommentThreadNode: Identifiable where ID == String {
    var parentID: String? { get }
    var createdAt: String { get }
}

extension PostComment: CommentThreadNode {}
extension ExternalNewsComment: CommentThreadNode {}

struct CommentThreadItem<T: CommentThreadNode>: Identifiable {
    let comment: T
    let depth: Int
    var id: String { comment.id }
}

enum CommentThreadBuilder {
    private static func normalizedID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    /// Top-level comment that anchors a flat reply thread.
    static func threadRootID<T: CommentThreadNode>(for comment: T, in comments: [T]) -> String {
        let byID = Dictionary(
            comments.map { (normalizedID($0.id) ?? $0.id, $0) },
            uniquingKeysWith: { _, n in n }
        )
        var current = comment
        var visited = Set<String>()
        while let parentID = normalizedID(current.parentID),
              !visited.contains(parentID) {
            visited.insert(parentID)
            guard let parent = byID[parentID] else { break }
            current = parent
        }
        return current.id
    }

    static func ordered<T: CommentThreadNode>(_ comments: [T]) -> [CommentThreadItem<T>] {
        func sortKey(_ comment: T) -> String { comment.createdAt }
        func isRoot(_ comment: T) -> Bool { normalizedID(comment.parentID) == nil }
        func threadRootKey(for comment: T) -> String {
            let rootID = threadRootID(for: comment, in: comments)
            return normalizedID(rootID) ?? rootID
        }

        let roots = comments.filter(isRoot).sorted { sortKey($0) < sortKey($1) }
        let replies = comments.filter { !isRoot($0) }

        var items: [CommentThreadItem<T>] = []
        var included = Set<String>()

        for root in roots {
            let rootKey = normalizedID(root.id) ?? root.id
            items.append(CommentThreadItem(comment: root, depth: 0))
            included.insert(rootKey)

            let threadReplies = replies
                .filter { threadRootKey(for: $0) == rootKey }
                .sorted { sortKey($0) < sortKey($1) }
            for reply in threadReplies {
                let replyKey = normalizedID(reply.id) ?? reply.id
                items.append(CommentThreadItem(comment: reply, depth: 1))
                included.insert(replyKey)
            }
        }

        let orphans = comments
            .filter { !included.contains(normalizedID($0.id) ?? $0.id) }
            .sorted { sortKey($0) < sortKey($1) }
        for orphan in orphans {
            let key = normalizedID(orphan.id) ?? orphan.id
            let depth = isRoot(orphan) ? 0 : 1
            items.append(CommentThreadItem(comment: orphan, depth: depth))
            included.insert(key)
        }

        return items
    }
}

struct PostCommentsView: View {
    @Environment(AppState.self) private var appState

    let postID: String
    @Binding var comments: [PostComment]
    var showsComposer: Bool = true
    var maxVisibleComments: Int? = nil
    var totalCommentCount: Int? = nil
    var onViewAllComments: (() -> Void)? = nil
    var onError: ((String) -> Void)?
    /// Optional hook before navigating to a comment author (e.g. dismiss Sparks comments sheet).
    var onWillOpenProfile: (() -> Void)? = nil

    @State private var commentDraft = ""
    @State private var replyTarget: ReplyTarget?
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var likingCommentIDs: Set<String> = []
    @FocusState private var composerFocused: Bool

    private struct ReplyTarget {
        /// Thread anchor sent to the API (always the top-level comment).
        let threadRootID: String
        /// Row that shows the inline reply composer underneath.
        let anchorCommentID: String
        let authorName: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // New top-level comment only — replies render under the target row.
            if showsComposer, replyTarget == nil {
                composer(isReply: false)
            }

            // Show spinner while demo threads / GraphQL load — avoids a false "no comments" flash.
            if isLoading && threadedComments.isEmpty {
                ProgressView()
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else if threadedComments.isEmpty {
                Text("No comments yet. Be the first to comment.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
            } else {
                ForEach(visibleThreadedComments) { item in
                    FacebookCommentRow(
                        comment: item.comment,
                        depth: item.depth,
                        isLiking: likingCommentIDs.contains(item.comment.id),
                        onReply: { startReply(to: item.comment, depth: item.depth) },
                        onToggleLike: { Task { await toggleLike(item.comment) } },
                        onOpenProfile: { openCommentAuthor(item.comment) }
                    )

                    // Reply composer sits directly under the comment being answered.
                    if showsComposer,
                       let replyTarget,
                       replyTarget.anchorCommentID == item.comment.id {
                        composer(isReply: true)
                            .padding(.leading, CommentThreadLayout.indent(for: 1))
                            .padding(.bottom, 4)
                    }
                }

                if let maxVisibleComments,
                   threadedComments.count > maxVisibleComments {
                    Button {
                        // Stay on the card — parent loads more inline (never navigates away).
                        onViewAllComments?()
                    } label: {
                        let total = totalCommentCount ?? threadedComments.count
                        let remaining = max(0, total - maxVisibleComments)
                        Text(
                            remaining > 0
                                ? "Load more comments (\(remaining) more)"
                                : "Load more comments"
                        )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
        // Always Matterya paper ink — Sparks full-screen uses .dark and made TextField white-on-white.
        .environment(\.colorScheme, .light)
        .dismissKeyboardOnTap()
        .task(id: postID) {
            // Paint warm cache immediately so Chat / feed expand never flash empty.
            if comments.isEmpty, let warm = CommentsWarmCache.shared.cached(postID) {
                comments = warm
            }
            await loadComments()
        }
    }

    private var threadedComments: [CommentThreadItem<PostComment>] {
        CommentThreadBuilder.ordered(comments)
    }

    private var visibleThreadedComments: [CommentThreadItem<PostComment>] {
        guard let maxVisibleComments else { return threadedComments }
        return Array(threadedComments.prefix(maxVisibleComments))
    }

    /// Flat field — no white bubble box; ink text always readable.
    @ViewBuilder
    private func composer(isReply: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if isReply, let replyTarget {
                HStack(spacing: 6) {
                    Text("Replying to")
                        .foregroundStyle(Theme.inkMuted)
                    Text("@\(replyTarget.authorName)")
                        .foregroundStyle(Theme.accent)
                        .fontWeight(.semibold)
                    Button("Cancel") {
                        self.replyTarget = nil
                        commentDraft = ""
                        composerFocused = false
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                }
                .font(.caption)
            }

            HStack(alignment: .bottom, spacing: 8) {
                AvatarView(
                    url: appState.currentProfile?.avatarURL,
                    seed: appState.currentProfile?.userID ?? "me",
                    size: isReply ? 26 : 32
                )

                TextField(
                    isReply ? "Write a reply…" : "Write a comment…",
                    text: $commentDraft,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .tint(Theme.accent)
                .focused($composerFocused)
                .submitLabel(.done)
                .onSubmit {
                    composerFocused = false
                    Keyboard.dismiss()
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Theme.border.opacity(0.85))
                        .frame(height: 0.5)
                }

                if !commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        Task { await submitComment() }
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                }
            }
        }
        .padding(.top, 4)
    }

    private func authorName(_ comment: PostComment) -> String {
        comment.author?.displayName
            ?? comment.author?.username
            ?? "Member"
    }

    private func openCommentAuthor(_ comment: PostComment) {
        let userID = comment.authorID.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = comment.author?.username
        guard !userID.isEmpty || !(username ?? "").isEmpty else { return }
        onWillOpenProfile?()
        appState.openPublicProfile(username: username, userID: userID)
    }

    private func startReply(to comment: PostComment, depth: Int) {
        replyTarget = ReplyTarget(
            threadRootID: CommentThreadBuilder.threadRootID(for: comment, in: comments),
            anchorCommentID: comment.id,
            authorName: comment.author?.username ?? authorName(comment)
        )
        commentDraft = ""
        DispatchQueue.main.async {
            composerFocused = true
        }
    }

    private func loadComments() async {
        // Prefer warm cache first so the sheet / Hubs watch opens already filled.
        if comments.isEmpty, let warm = CommentsWarmCache.shared.cached(postID) {
            comments = warm
        }
        let showSpinner = comments.isEmpty
        if showSpinner { isLoading = true }
        defer { isLoading = false }

        do {
            // Progressive load — first page only on the critical path (was 2000 × 2 GraphQL calls).
            let loaded = await CommentsWarmCache.shared.loadProgressive(postID)
            if !loaded.isEmpty || comments.isEmpty {
                comments = loaded
            }
            if loaded.isEmpty {
                let fresh = try await PostsService.shared.listComments(
                    postID,
                    limit: PostsService.commentsFirstPageLimit,
                    resolveOrigin: true
                )
                comments = fresh
                // Never persist empty — that blocked retries after thin-feed origin miss.
                if !fresh.isEmpty {
                    CommentsWarmCache.shared.store(postID, comments: fresh)
                }
            }
            // Top up fuller thread without spinner; only replace if we got more rows.
            let capturedCount = comments.count
            Task { @MainActor in
                let more = (try? await PostsService.shared.listComments(
                    postID,
                    limit: PostsService.commentsBackgroundLimit,
                    resolveOrigin: true
                )) ?? []
                guard more.count > capturedCount else { return }
                comments = more
                CommentsWarmCache.shared.store(postID, comments: more)
            }
        } catch {
            // Seed / offline fallback — surface real errors when local is also empty.
            if comments.isEmpty {
                comments = HubEngagementStore.shared.listComments(
                    postID,
                    limit: PostsService.commentsFirstPageLimit
                )
            }
            if comments.isEmpty {
                onError?(error.localizedDescription)
            }
        }
    }

    private func submitComment() async {
        let body = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let parentID = replyTarget?.threadRootID
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let created = try await PostsService.shared.addComment(
                postID,
                body: body,
                parentID: parentID
            )
            // Prefer local append over re-downloading the whole thread after every send.
            var refreshed = comments
            if !refreshed.contains(where: { $0.id == created.id }) {
                refreshed.append(created)
            }
            if let parentID, !parentID.isEmpty {
                refreshed = refreshed.map { comment in
                    guard comment.id == created.id, comment.parentID == nil else { return comment }
                    return comment.withParentID(parentID)
                }
            }
            comments = refreshed
            CommentsWarmCache.shared.store(postID, comments: refreshed)
            commentDraft = ""
            replyTarget = nil
            composerFocused = false
            Keyboard.dismiss()
        } catch {
            // Never red-toast: always keep the comment on-device.
            let profile = ContentCache.shared.cachedProfile()
            let author = profile.map {
                PostAuthor(
                    userID: $0.userID,
                    displayName: $0.displayName ?? $0.username ?? "You",
                    username: $0.username,
                    avatarURL: $0.avatarURL,
                    countryName: $0.countryName,
                    countryCode: $0.countryCode,
                    lastReadAt: nil
                )
            }
            let created = HubEngagementStore.shared.addComment(
                postID: postID,
                body: body,
                parentID: parentID,
                author: author
            )
            comments.append(created)
            CommentsWarmCache.shared.store(postID, comments: comments)
            commentDraft = ""
            replyTarget = nil
            composerFocused = false
            Keyboard.dismiss()
        }
    }

    private func toggleLike(_ comment: PostComment) async {
        guard !likingCommentIDs.contains(comment.id) else { return }
        likingCommentIDs.insert(comment.id)
        defer { likingCommentIDs.remove(comment.id) }

        // Optimistic UI first — hub comments never need the network.
        if let index = comments.firstIndex(where: { $0.id == comment.id }) {
            let c = comments[index]
            let liked = !c.likedByMe
            comments[index] = PostComment(
                id: c.id,
                postID: c.postID,
                parentID: c.parentID,
                authorID: c.authorID,
                body: c.body,
                likeCount: liked ? c.likeCount + 1 : max(0, c.likeCount - 1),
                likedByMe: liked,
                createdAt: c.createdAt,
                updatedAt: c.updatedAt,
                author: c.author
            )
        }

        do {
            let updated = comment.likedByMe
                ? try await PostsService.shared.unlikeComment(comment.id)
                : try await PostsService.shared.likeComment(comment.id)
            if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[index] = updated
            }
        } catch {
            // Keep optimistic state — never surface GraphQL "Unexpected error".
        }
    }
}

struct FacebookCommentRow: View {
    let comment: PostComment
    let depth: Int
    let isLiking: Bool
    let onReply: () -> Void
    let onToggleLike: () -> Void
    var onOpenProfile: (() -> Void)? = nil

    private var isReply: Bool { depth > 0 }
    private var avatarSize: CGFloat { isReply ? 26 : 32 }
    private var threadIndent: CGFloat { CommentThreadLayout.indent(for: depth) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if threadIndent > 0 {
                HStack(spacing: 0) {
                    if isReply {
                        threadGuide
                            .padding(.trailing, 6)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: threadIndent, alignment: .trailing)
            }

            HStack(alignment: .top, spacing: 8) {
                Button(action: { onOpenProfile?() }) {
                    AvatarView(
                        url: comment.author?.avatarURL,
                        seed: comment.authorID,
                        size: avatarSize
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(authorName)'s profile")

                VStack(alignment: .leading, spacing: 4) {
                    Button(action: { onOpenProfile?() }) {
                        Text(authorName)
                            .font(isReply ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(authorName)'s profile")

                    if let body = cleanedBody {
                        Text(body)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 12) {
                        Button(action: onToggleLike) {
                            Text(comment.likedByMe ? "Liked" : "Like")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(comment.likedByMe ? Theme.ink : Theme.inkMuted)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLiking)

                        Button(action: onReply) {
                            Text("Reply")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.inkMuted)
                        }
                        .buttonStyle(.plain)

                        Text(RelativeTime.format(comment.createdAt))
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)

                        if comment.likeCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "hand.thumbsup.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.ink)
                                Text("\(comment.likeCount)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var threadGuide: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(Theme.accent.opacity(0.45))
            .frame(width: 2)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }

    private var cleanedBody: String? {
        ContentSanitizer.clean(comment.body)
    }

    private var authorName: String {
        ContentSanitizer.displayName(
            displayName: comment.author?.displayName,
            username: comment.author?.username
        )
    }
}

struct NewsCommentsSection: View {
    @Environment(AppState.self) private var appState

    let newsItemID: String
    @Binding var comments: [ExternalNewsComment]
    var onError: ((String) -> Void)?

    @State private var commentDraft = ""
    @State private var replyTarget: NewsReplyTarget?
    @State private var isSubmitting = false

    private struct NewsReplyTarget {
        let threadRootID: String
        let authorName: String
    }

    private var threadedComments: [CommentThreadItem<ExternalNewsComment>] {
        CommentThreadBuilder.ordered(comments)
    }

    private var composerIndent: CGFloat {
        guard replyTarget != nil else { return 0 }
        return CommentThreadLayout.indent(for: 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comments")
                .font(.headline)
                .foregroundStyle(Theme.ink)

            composer

            if threadedComments.isEmpty {
                Text("No comments yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
            } else {
                ForEach(threadedComments) { item in
                    NewsCommentRow(
                        comment: item.comment,
                        depth: item.depth,
                        onReply: { startReply(to: item.comment, depth: item.depth) }
                    )
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let replyTarget {
                HStack(spacing: 6) {
                    Text("Replying to")
                        .foregroundStyle(Theme.inkMuted)
                    Text("@\(replyTarget.authorName)")
                        .foregroundStyle(Theme.accent)
                        .fontWeight(.semibold)
                    Button("Cancel") { self.replyTarget = nil }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                }
                .font(.caption)
            }

            HStack(spacing: 8) {
                TextField(
                    replyTarget == nil ? "Add comment…" : "Write a reply…",
                    text: $commentDraft,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .stroke(Theme.border, lineWidth: 0.5)
                )

                Button("Send") {
                    Task { await addComment() }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accentBright)
                .disabled(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
        .padding(.leading, composerIndent)
    }

    private func startReply(to comment: ExternalNewsComment, depth: Int) {
        replyTarget = NewsReplyTarget(
            threadRootID: CommentThreadBuilder.threadRootID(for: comment, in: comments),
            authorName: comment.author?.username ?? comment.author?.displayName ?? "Member"
        )
    }

    private func addComment() async {
        let body = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            _ = try await NewsService.shared.addComment(
                newsItemID,
                body: body,
                parentID: replyTarget?.threadRootID
            )
            comments = try await NewsService.shared.comments(newsItemID)
            commentDraft = ""
            replyTarget = nil
        } catch {
            onError?(error.localizedDescription)
        }
    }
}

private struct NewsCommentRow: View {
    let comment: ExternalNewsComment
    let depth: Int
    let onReply: () -> Void

    private var isReply: Bool { depth > 0 }
    private var threadIndent: CGFloat { CommentThreadLayout.indent(for: depth) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if threadIndent > 0 {
                HStack(spacing: 0) {
                    if isReply {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Theme.accent.opacity(0.45))
                            .frame(width: 2)
                            .padding(.top, 4)
                            .padding(.trailing, 6)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: threadIndent, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(comment.author?.displayName ?? comment.author?.username ?? "Member")
                    .font(isReply ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(comment.body)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Reply", action: onReply)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .buttonStyle(.plain)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
    }
}

struct PostCommentsPageView: View {
    @Environment(\.dismiss) private var dismiss

    let postID: String
    /// When true (Sparks sheet), dismiss comments before opening a profile.
    var dismissesOnProfileOpen: Bool = true

    @State private var comments: [PostComment]
    @State private var errorMessage: String?

    init(postID: String, dismissesOnProfileOpen: Bool = true) {
        self.postID = postID
        self.dismissesOnProfileOpen = dismissesOnProfileOpen
        // Seed from warm cache so first paint already has the thread.
        _comments = State(initialValue: CommentsWarmCache.shared.cached(postID) ?? [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PostCommentsView(
                    postID: postID,
                    comments: $comments,
                    onError: { errorMessage = $0 },
                    onWillOpenProfile: dismissesOnProfileOpen ? { dismiss() } : nil
                )

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
            }
            .padding(Theme.pagePadding)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle("Comments")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .onAppear { CommentsWarmCache.shared.warm(postID) }
    }
}

/// Full-screen comments sheet for Sparks / Reels viewer.
struct ReelsCommentsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let postID: String
    @State private var comments: [PostComment] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PostCommentsView(
                        postID: postID,
                        comments: $comments,
                        showsComposer: true,
                        onError: { errorMessage = $0 },
                        onWillOpenProfile: { dismiss() }
                    )

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                    }
                }
                .padding(Theme.pagePadding)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(Theme.canvas, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Compact comments panel for Sparks — keeps the video partially visible behind a detented sheet.
/// No Close button — drag indicator / swipe-down dismisses.
struct SparksCommentsSheet: View {
    let postID: String
    @Environment(\.dismiss) private var dismiss

    @State private var comments: [PostComment] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PostCommentsView(
                        postID: postID,
                        comments: $comments,
                        onError: { errorMessage = $0 },
                        onWillOpenProfile: { dismiss() }
                    )

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnTap()
            .background(Theme.canvas)
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            if comments.isEmpty, let warm = CommentsWarmCache.shared.cached(postID) {
                comments = warm
            }
            CommentsWarmCache.shared.warm(postID)
        }
    }
}