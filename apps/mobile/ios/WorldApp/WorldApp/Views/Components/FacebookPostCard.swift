import SwiftUI

struct FacebookPostCard: View {
    @Environment(AppState.self) private var appState

    let post: CountryPost
    var showsAuthorHeader: Bool = true
    var showsAuthorInJournal: Bool = false
    var mediaContext: MediaContext = .feed
    var commentsInitiallyExpanded: Bool = false
    var onLikeToggle: (() -> Void)?
    var onOpenPost: () -> Void
    var onOpenVideo: (() -> Void)? = nil
    var onPostDeleted: ((String) -> Void)?
    var onPostUpdated: ((CountryPost) -> Void)?

    @State private var commentsExpanded = false
    @State private var inlineComments: [PostComment] = []
    @State private var commentError: String?
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @State private var showReportConfirm = false
    @State private var actionBusy = false
    @State private var actionMessage: String?

    private var isOwnPost: Bool {
        guard let userID = appState.currentProfile?.userID else { return false }
        return post.authorID == userID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsAuthorHeader {
                authorHeader
            } else {
                journalHeader
            }

            if post.hasMedia {
                media
            }

            if !post.displayExcerpt.isEmpty {
                Text(post.displayExcerpt)
                    .font(.body)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineSpacing(4)
                    .lineLimit(post.hasMedia ? 4 : 8)
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, post.hasMedia ? 12 : 0)
                    .padding(.bottom, 4)
            }

            actions
            meta

            if let actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.bottom, 8)
            }

            if commentsExpanded {
                Divider()
                    .padding(.top, 8)

                PostCommentsView(
                    postID: post.id,
                    comments: $inlineComments,
                    onError: { commentError = $0 }
                )
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 10)
                .padding(.bottom, 12)

                if let commentError {
                    Text(commentError)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                        .padding(.horizontal, Theme.pagePadding)
                        .padding(.bottom, 8)
                }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )

        .onAppear {
            if commentsInitiallyExpanded {
                commentsExpanded = true
            }
        }
        .sheet(isPresented: $showEditSheet) {
            PostEditSheet(post: post) { updated in
                onPostUpdated?(updated)
                actionMessage = "Post updated."
            }
        }
        .confirmationDialog("Delete this post?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await deletePost() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Report this post", isPresented: $showReportConfirm, titleVisibility: .visible) {
            ForEach(reportReasons, id: \.self) { reason in
                Button(reason, role: .destructive) {
                    Task { await reportPost(reason: reason) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var authorHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                openAuthorProfile()
            } label: {
                AvatarView(url: post.author?.avatarURL, seed: post.authorID, size: 36)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Button {
                    openAuthorProfile()
                } label: {
                    Text(post.authorDisplayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)

                Text(RelativeTime.format(post.createdAt))
                    .font(.caption2)
                    .foregroundStyle(Theme.inkMuted)
            }

            Spacer(minLength: 8)

            postOptionsMenu

            Button(action: onOpenPost) {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var journalHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            if showsAuthorInJournal {
                Button {
                    openAuthorProfile()
                } label: {
                    AvatarView(url: post.author?.avatarURL, seed: post.authorID, size: 36)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                if showsAuthorInJournal {
                    Button {
                        openAuthorProfile()
                    } label: {
                        Text(post.authorDisplayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                }

                Text(post.displayHeadline)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                postOptionsMenu
                Text(RelativeTime.format(post.createdAt))
                    .font(.caption2)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var postOptionsMenu: some View {
        Menu {
            if isOwnPost {
                Button("Edit") { showEditSheet = true }
                Button("Delete", role: .destructive) { showDeleteConfirm = true }
            }
            Button("Report", role: .destructive) { showReportConfirm = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(actionBusy)
    }

    @ViewBuilder
    private var media: some View {
        if let aspect = FacebookMediaLayout.aspectRatio(for: post, context: mediaContext) {
            Group {
                if post.hasVideo, let url = post.playableVideoURL {
                    InFrameVideoPlayer(
                        url: url,
                        posterURL: post.posterImageURL,
                        placement: post.isReel ? "reel" : nil,
                        countryCode: post.countryCode,
                        contentCountryCode: post.countryCode,
                        postID: post.id,
                        muted: true,
                        onViewed: { Task { await PostsService.shared.recordView(post) } }
                    )
                } else if post.hasVideo {
                    feedVideoPoster
                } else if let url = post.feedImageURL {
                    CachedAsyncImage(
                        url: url,
                        maxPixelSize: 900,
                        contentMode: .fill,
                        placeholder: AnyView(mediaPlaceholder)
                    )
                } else {
                    mediaPlaceholder
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(aspect, contentMode: .fit)
            .frame(maxHeight: FacebookMediaLayout.maxFeedMediaHeight)
            .clipped()
            .overlay(alignment: .bottom) {
                if !post.hasVideo {
                    LinearGradient(
                        colors: [.clear, Theme.ink.opacity(0.14)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 60)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { openMedia() }
            .padding(.top, showsAuthorHeader || !post.displayExcerpt.isEmpty ? 0 : 8)
        }
    }

    private var actions: some View {
        HStack(spacing: 18) {
            Button { onLikeToggle?() } label: {
                Image(systemName: post.likedByMe ? "heart.fill" : "heart")
                    .font(.system(size: 22))
                    .foregroundStyle(post.likedByMe ? Theme.like : Theme.ink)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    commentsExpanded.toggle()
                }
            } label: {
                Image(systemName: commentsExpanded ? "bubble.right.fill" : "bubble.right")
                    .font(.system(size: 22))
                    .foregroundStyle(commentsExpanded ? Theme.facebookBlue : Theme.ink)
            }
            .buttonStyle(.plain)

            Button(action: onOpenPost) {
                Image(systemName: "paperplane")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)

            Button {
                Task { await appState.toggleSavePost(post) }
            } label: {
                Image(systemName: appState.isPostSaved(post.id) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 21))
                    .foregroundStyle(appState.isPostSaved(post.id) ? Theme.facebookBlue : Theme.ink)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 6) {
            if post.likeCount > 0 {
                Text("\(post.likeCount) \(post.likeCount == 1 ? "like" : "likes")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }

            if post.commentCount > 0, !commentsExpanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        commentsExpanded = true
                    }
                } label: {
                    Text("\(post.commentCount) \(post.commentCount == 1 ? "comment" : "comments")")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)
                }
                .buttonStyle(.plain)
            }

            if showsAuthorHeader, let title = post.displayTitle {
                Text(title)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink)
            }


        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 14)
    }

    private var mediaPlaceholder: some View {
        Rectangle()
            .fill(Theme.canvasMuted)
            .overlay {
                Image(systemName: post.hasVideo ? "video" : "photo")
                    .foregroundStyle(Theme.inkMuted)
            }
    }

    private var feedVideoPoster: some View {
        ZStack {
            if let url = post.posterImageURL ?? post.feedImageURL {
                CachedAsyncImage(
                    url: url,
                    maxPixelSize: 600,
                    contentMode: .fill,
                    placeholder: AnyView(mediaPlaceholder)
                )
            } else {
                mediaPlaceholder
            }

            Image(systemName: "play.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        }
    }

    private var reportReasons: [String] {
        ["Spam", "Harassment", "Misinformation", "Other"]
    }

    private func openMedia() {
        if post.hasVideo, !post.isReel, mediaContext == .feed, let onOpenVideo {
            onOpenVideo()
        } else {
            onOpenPost()
        }
    }

    private func openAuthorProfile() {
        if let username = post.author?.username {
            appState.navigate(to: .publicProfile(username: username))
        }
    }

    private func deletePost() async {
        actionBusy = true
        defer { actionBusy = false }
        do {
            let deleted = try await PostsService.shared.deletePost(post.id)
            guard deleted else {
                actionMessage = "Could not delete post."
                return
            }
            onPostDeleted?(post.id)
            actionMessage = "Post deleted."
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func reportPost(reason: String) async {
        actionBusy = true
        defer { actionBusy = false }
        do {
            let reported = try await PostsService.shared.reportPost(post.id, reason: reason)
            actionMessage = reported ? "Post reported. Thank you." : "Could not report post."
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}

private struct PostEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let post: CountryPost
    let onSaved: (CountryPost) -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var busy = false
    @State private var errorMessage: String?

    init(post: CountryPost, onSaved: @escaping (CountryPost) -> Void) {
        self.post = post
        self.onSaved = onSaved
        _title = State(initialValue: post.displayTitle ?? "")
        _bodyText = State(initialValue: post.displayBody)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Optional title", text: $title)
                }
                Section("Body") {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 140)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle("Edit post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(busy)
                }
            }
        }
    }

    private func save() async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let updated = try await PostsService.shared.updatePost(
                post.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfWhitespace,
                body: preservedBody(from: bodyText)
            )
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func preservedBody(from edited: String) -> String {
        let trimmed = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        guard post.isStory else { return trimmed }

        let marker = post.body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0.hasPrefix("__story__|") })

        if let marker {
            return trimmed.isEmpty ? marker : "\(trimmed)\n\(marker)"
        }
        if let expires = PostStoryMarker.expiresAt(from: post.body) {
            return PostStoryMarker.buildBody(caption: trimmed, expiresAt: expires)
        }
        return trimmed
    }
}

private extension String {
    var nilIfWhitespace: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}