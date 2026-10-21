import SwiftUI

struct AnonymousPostDetailView: View {
    let post: AnonymousPost
    @Environment(AppState.self) private var appState
    @State private var store = AnonymousStore.shared
    @State private var comments: [AnonymousComment] = []
    @State private var isLoading = true
    @State private var replyBody = ""
    @State private var replyParentId: String?
    @State private var showReport = false
    @State private var localPost: AnonymousPost

    init(post: AnonymousPost) {
        self.post = post
        _localPost = State(initialValue: post)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AnonymousPostCard(post: localPost) {
                    Task { await vote(1) }
                } onDownvote: {
                    Task { await vote(-1) }
                }

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
                            await store.block(profileId: localPost.authorProfileId)
                            appState.showToast("Blocked @\(localPost.authorUsername)", style: .info)
                        }
                    } label: {
                        Text("Block author")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .buttonStyle(.plain)
                }

                Text("Comments")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)

                if isLoading {
                    ProgressView().tint(Theme.ink)
                } else if comments.isEmpty {
                    Text(MatteryaCopy.anonymousNoComments)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)
                } else {
                    ForEach(flattenedComments, id: \.id) { row in
                        AnonymousCommentRowView(comment: row.comment, depth: row.depth) {
                            replyParentId = row.comment.id
                        }
                    }
                }
            }
            .padding(Theme.pagePadding)
        }
        .safeAreaInset(edge: .bottom) {
            composerBar
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadComments() }
        .confirmationDialog("Report post", isPresented: $showReport, titleVisibility: .visible) {
            Button("Harassment", role: .destructive) { Task { await report("harassment") } }
            Button("Spam", role: .destructive) { Task { await report("spam") } }
            Button("Doxxing / identity", role: .destructive) { Task { await report("doxxing") } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var flattenedComments: [(id: String, comment: AnonymousComment, depth: Int)] {
        var out: [(id: String, comment: AnonymousComment, depth: Int)] = []
        func walk(_ items: [AnonymousComment], depth: Int) {
            for item in items {
                out.append((item.id, item, depth))
                if let replies = item.replies, !replies.isEmpty {
                    walk(replies, depth: depth + 1)
                }
            }
        }
        walk(comments, depth: 0)
        return out
    }

    private var composerBar: some View {
        VStack(spacing: 8) {
            if let replyParentId {
                HStack {
                    Text("Replying…")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                    Spacer()
                    Button("Cancel") { self.replyParentId = nil }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, Theme.pagePadding)
            }
            HStack(spacing: 10) {
                TextField("Add a comment", text: $replyBody, axis: .vertical)
                    .lineLimit(1...4)
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
                        .opacity(replyBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }
                .buttonStyle(.plain)
                .disabled(replyBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 10)
        }
        .padding(.top, 8)
        .background(Theme.canvas.opacity(0.96))
        .overlay(alignment: .top) { Theme.divider.frame(height: 0.5) }
    }

    private func loadComments() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await AnonymousService.listComments(postId: localPost.id)
            comments = page.items
        } catch {
            comments = []
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
            localPost.commentCount = (localPost.commentCount ?? 0) + 1
        } catch let err as AnonymousError {
            appState.showToast(err.errorDescription ?? "Couldn’t post comment", style: .error)
        } catch {
            appState.showToast(error.localizedDescription, style: .error)
        }
    }

    private func vote(_ value: Int) async {
        let next = localPost.myVote == value ? 0 : value
        await store.vote(post: localPost, value: next)
        localPost.myVote = next
        localPost.score = (localPost.score ?? 0) + next - (post.myVote ?? 0)
    }

    private func report(_ reason: String) async {
        await store.report(targetType: "post", targetId: localPost.id, reason: reason)
        appState.showToast("Report submitted.", style: .info)
    }
}

private struct AnonymousCommentRowView: View {
    let comment: AnonymousComment
    let depth: Int
    var onReply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("@\(comment.authorUsername)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(comment.createdAt.prefix(10))
                    .font(.caption2)
                    .foregroundStyle(Theme.inkMuted)
            }
            Text(comment.body)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
            Button(action: onReply) {
                Text("Reply")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .padding(.leading, CGFloat(min(depth, 4)) * 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.border.opacity(0.8), lineWidth: 0.5)
        )
    }
}
