import SwiftUI

struct CommentThreadItem: Identifiable {
    let comment: PostComment
    let depth: Int
    var id: String { comment.id }
}

enum CommentThreadBuilder {
    static func ordered(_ comments: [PostComment]) -> [CommentThreadItem] {
        var byParent: [String: [PostComment]] = [:]
        var roots: [PostComment] = []

        for comment in comments {
            if let parentID = comment.parentID, !parentID.isEmpty {
                byParent[parentID, default: []].append(comment)
            } else {
                roots.append(comment)
            }
        }

        func sortKey(_ comment: PostComment) -> String { comment.createdAt }
        roots.sort { sortKey($0) < sortKey($1) }
        for key in byParent.keys {
            byParent[key]?.sort { sortKey($0) < sortKey($1) }
        }

        var items: [CommentThreadItem] = []
        func appendTree(_ comment: PostComment, depth: Int) {
            items.append(CommentThreadItem(comment: comment, depth: depth))
            for child in byParent[comment.id] ?? [] {
                appendTree(child, depth: depth + 1)
            }
        }
        for root in roots {
            appendTree(root, depth: 0)
        }

        let included = Set(items.map(\.comment.id))
        let orphans = comments
            .filter { !included.contains($0.id) }
            .sorted { sortKey($0) < sortKey($1) }
        for orphan in orphans {
            let depth: Int
            if let parentID = orphan.parentID, !parentID.isEmpty,
               let parentDepth = items.first(where: { $0.comment.id == parentID })?.depth {
                depth = parentDepth + 1
            } else if orphan.parentID != nil {
                depth = 1
            } else {
                depth = 0
            }
            items.append(CommentThreadItem(comment: orphan, depth: depth))
        }

        return items
    }
}

struct PostCommentsView: View {
    @Environment(AppState.self) private var appState

    let postID: String
    @Binding var comments: [PostComment]
    var showsComposer: Bool = true
    var onError: ((String) -> Void)?

    @State private var commentDraft = ""
    @State private var replyTarget: ReplyTarget?
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var likingCommentIDs: Set<String> = []

    private struct ReplyTarget {
        let commentID: String
        let authorName: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoading {
                ProgressView()
                    .tint(Theme.facebookBlue)
                    .frame(maxWidth: .infinity)
            } else if threadedComments.isEmpty {
                Text("No comments yet. Be the first to comment.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
            } else {
                ForEach(threadedComments) { item in
                    FacebookCommentRow(
                        comment: item.comment,
                        depth: item.depth,
                        isLiking: likingCommentIDs.contains(item.comment.id),
                        onReply: { startReply(to: item.comment) },
                        onToggleLike: { Task { await toggleLike(item.comment) } }
                    )
                }
            }

            if showsComposer {
                composer
            }
        }
        .task(id: postID) {
            if comments.isEmpty {
                await loadComments()
            }
        }
    }

    private var threadedComments: [CommentThreadItem] {
        CommentThreadBuilder.ordered(comments)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let replyTarget {
                HStack(spacing: 6) {
                    Text("Replying to")
                        .foregroundStyle(Theme.inkMuted)
                    Text("@\(replyTarget.authorName)")
                        .foregroundStyle(Theme.facebookBlue)
                        .fontWeight(.semibold)
                    Button("Cancel") { self.replyTarget = nil }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                }
                .font(.caption)
            }

            HStack(alignment: .top, spacing: 8) {
                AvatarView(
                    url: appState.currentProfile?.avatarURL,
                    seed: appState.currentProfile?.userID ?? "me",
                    size: 32
                )

                TextField(
                    replyTarget == nil ? "Write a comment…" : "Write a reply…",
                    text: $commentDraft,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Theme.border, lineWidth: 0.5)
                )

                if !commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        Task { await submitComment() }
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.facebookBlue)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                }
            }
        }
        .padding(.leading, replyTarget == nil ? 0 : 36)
        .padding(.top, 4)
    }

    private func authorName(_ comment: PostComment) -> String {
        comment.author?.displayName
            ?? comment.author?.username
            ?? "Member"
    }

    private func startReply(to comment: PostComment) {
        replyTarget = ReplyTarget(
            commentID: comment.id,
            authorName: comment.author?.username ?? authorName(comment)
        )
    }

    private func loadComments() async {
        isLoading = true
        defer { isLoading = false }
        do {
            comments = try await PostsService.shared.listComments(postID)
        } catch {
            onError?(error.localizedDescription)
        }
    }

    private func submitComment() async {
        let body = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let comment = try await PostsService.shared.addComment(
                postID,
                body: body,
                parentID: replyTarget?.commentID
            )
            comments.append(comment)
            commentDraft = ""
            replyTarget = nil
        } catch {
            onError?(error.localizedDescription)
        }
    }

    private func toggleLike(_ comment: PostComment) async {
        guard !likingCommentIDs.contains(comment.id) else { return }
        likingCommentIDs.insert(comment.id)
        defer { likingCommentIDs.remove(comment.id) }

        do {
            let updated = comment.likedByMe
                ? try await PostsService.shared.unlikeComment(comment.id)
                : try await PostsService.shared.likeComment(comment.id)
            if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[index] = updated
            }
        } catch {
            onError?(error.localizedDescription)
        }
    }
}

private struct FacebookCommentRow: View {
    let comment: PostComment
    let depth: Int
    let isLiking: Bool
    let onReply: () -> Void
    let onToggleLike: () -> Void

    private var isReply: Bool { depth > 0 }
    private var avatarSize: CGFloat { isReply ? 26 : 32 }
    private var threadIndent: CGFloat { CGFloat(min(depth, 4)) * 36 }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isReply {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Theme.border)
                    .frame(width: 2)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }

            AvatarView(
                url: comment.author?.avatarURL,
                seed: comment.authorID,
                size: avatarSize
            )

            VStack(alignment: .leading, spacing: 4) {
                if isReply {
                    Text(authorName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(authorName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        if let body = cleanedBody {
                            Text(body)
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if isReply, let body = cleanedBody {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button(action: onToggleLike) {
                        Text(comment.likedByMe ? "Liked" : "Like")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(comment.likedByMe ? Theme.facebookBlue : Theme.inkMuted)
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
                                .foregroundStyle(Theme.facebookBlue)
                            Text("\(comment.likeCount)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
            }
        }
        .padding(.leading, threadIndent)
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