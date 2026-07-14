import PhotosUI
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
    var onOpenReel: (() -> Void)? = nil
    var onPostDeleted: ((String) -> Void)?
    var onPostUpdated: ((CountryPost) -> Void)?
    var expandsCommentsInline: Bool = false
    var viewingCountryISO: String? = nil

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

    private var opensAsSpark: Bool {
        if post.isReel || PlayPlatformBridge.isReelVideo(post) { return true }
        if post.hasVideo,
           FacebookMediaLayout.aspectRatio(for: post, context: mediaContext) == FacebookMediaLayout.reelAspect {
            return true
        }
        return false
    }

    private var postedFromLabel: String? {
        guard let viewing = viewingCountryISO?.uppercased(),
              let postISO = post.countryCode?.uppercased(),
              !postISO.isEmpty,
              postISO != viewing
        else { return nil }

        let country = post.countryName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCountry = (country?.isEmpty == false) ? country! : postISO
        if let city = post.cityName?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            return "Posted from \(city), \(resolvedCountry)"
        }
        return "Posted from \(resolvedCountry)"
    }

    @ViewBuilder
    private var postedFromBadge: some View {
        if let postedFromLabel {
            Label(postedFromLabel, systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .lineLimit(2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.accent.opacity(0.1), in: Capsule())
                .accessibilityLabel(postedFromLabel)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsAuthorHeader {
                authorHeader
            } else if showsPlayLinkInFeed || !usesYouTubeVideoFrame || !post.hasMedia {
                journalHeader
            }

            if let embed = post.sharedPost {
                SharedPostEmbedView(embed: embed)
            } else if post.sharedPostID != nil {
                SharedPostLoadingEmbed(postID: post.sharedPostID!)
            }

            if showsPlayLinkInFeed {
                PlayFeedLinkCard(post: post) {
                    openPlayVideo()
                }
            } else if post.hasMedia {
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
                    .contentShape(Rectangle())
                    .onTapGesture { openPrimaryDestination() }
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
        .clipShape(cardShape)
        .overlay(
            cardShape
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

                postTimestampRow

                postedFromBadge
            }

            Spacer(minLength: 8)
                .contentShape(Rectangle())
                .onTapGesture { openPrimaryDestination() }

            postOptionsMenu

            Button(action: openPrimaryDestination) {
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
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }

                postedFromBadge

                if showsPlayLinkInFeed {
                    Label(MatteryaCopy.publishedOnHubs, systemImage: "play.tv")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentBright)
                } else if let headline = post.displayHeadline {
                    Text(headline)
                        .postHeadlineStyle(lineLimit: 4)
                        .contentShape(Rectangle())
                        .onTapGesture { openPrimaryDestination() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Spacer(minLength: 8)
                .contentShape(Rectangle())
                .onTapGesture { openPrimaryDestination() }

            VStack(alignment: .trailing, spacing: 8) {
                postOptionsMenu
                postTimestampRow
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var postTimestampRow: some View {
        HStack(spacing: 6) {
            Text(RelativeTime.format(post.createdAt))
            if post.isEdited {
                Text("Edited")
                    .fontWeight(.semibold)
            }
            if isOwnPost, post.visibility != .public, post.visibility != .country {
                Image(systemName: post.visibility == .private ? "lock.fill" : "person.2.fill")
            }
        }
        .font(.caption2)
        .foregroundStyle(Theme.inkMuted)
    }

    private var postOptionsMenu: some View {
        Menu {
            if isOwnPost {
                Button("Edit") { showEditSheet = true }
                Button("Delete", role: .destructive) { showDeleteConfirm = true }
            }
            Button("Report", role: .destructive) { showReportConfirm = true }
            if !isOwnPost {
                Button("Block \(post.authorDisplayName)", role: .destructive) {
                    appState.blockUser(
                        post.authorID,
                        username: post.author?.username,
                        displayName: post.author?.displayName
                    )
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(actionBusy)
    }

    private var usesYouTubeVideoFrame: Bool {
        FacebookMediaLayout.usesYouTubeFrame(for: post, context: mediaContext)
    }

    private var showsPlayLinkInFeed: Bool {
        PlayPlatformBridge.showsPlayLinkInFeed(post, context: mediaContext)
    }

    private var cardShape: UnevenRoundedRectangle {
        if usesYouTubeVideoFrame, post.hasMedia, !showsPlayLinkInFeed {
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: Theme.cardRadius,
                bottomTrailingRadius: Theme.cardRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
        }
        return UnevenRoundedRectangle(
            topLeadingRadius: Theme.cardRadius,
            bottomLeadingRadius: Theme.cardRadius,
            bottomTrailingRadius: Theme.cardRadius,
            topTrailingRadius: Theme.cardRadius,
            style: .continuous
        )
    }

    @ViewBuilder
    private var media: some View {
        if let aspect = FacebookMediaLayout.aspectRatio(for: post, context: mediaContext) {
            Group {
                if usesYouTubeVideoFrame {
                    YouTubeVideoFrame(style: .feed) {
                        if let url = post.playableVideoURL {
                            InFrameVideoPlayer(
                                url: url,
                                posterURL: post.posterImageURL,
                                placement: nil,
                                countryCode: post.countryCode,
                                contentCountryCode: post.countryCode,
                                postID: post.id,
                                muted: true,
                                onViewed: { Task { await PostsService.shared.recordView(post) } }
                            )
                        } else {
                            feedVideoPoster
                        }
                    }
                } else if post.hasVideo, let url = post.playableVideoURL {
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
            .frame(maxHeight: usesYouTubeVideoFrame ? nil : FacebookMediaLayout.maxFeedMediaHeight)
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
            .overlay {
                if opensAsSpark {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Theme.iconFill.opacity(0.95))
                        .shadow(color: .black.opacity(0.25), radius: 6)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { openMedia() }
            .padding(.top, usesYouTubeVideoFrame || showsAuthorHeader || !post.displayExcerpt.isEmpty ? 0 : 8)
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
                if expandsCommentsInline {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        commentsExpanded.toggle()
                    }
                } else {
                    onOpenPost()
                }
            } label: {
                Image(systemName: commentsExpanded ? "bubble.right.fill" : "bubble.right")
                    .font(.system(size: 22))
                    .foregroundStyle(commentsExpanded ? Theme.ink : Theme.inkMuted)
            }
            .buttonStyle(.plain)

            Button {
                appState.presentShareSheet(for: post)
            } label: {
                Image(systemName: "arrowshape.turn.up.right")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    if let error = await appState.toggleSavePost(post) {
                        actionMessage = error
                    }
                }
            } label: {
                Image(systemName: appState.isPostSaved(post.id) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 21))
                    .foregroundStyle(appState.isPostSaved(post.id) ? Theme.ink : Theme.inkMuted)
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
                    if expandsCommentsInline {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            commentsExpanded = true
                        }
                    } else {
                        onOpenPost()
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
                    .postHeadlineStyle(lineLimit: 3)
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
        Group {
            if usesYouTubeVideoFrame {
                YouTubeVideoThumbnail(post: post, maxPixelSize: 900, frameStyle: .feed, embedsFrame: false)
            } else {
                VideoThumbnailView(
                    post: post,
                    maxPixelSize: 600,
                    contentMode: .fill,
                    showsPlayIcon: true,
                    playIconSize: 52,
                    placeholder: AnyView(mediaPlaceholder)
                )
            }
        }
    }

    private var reportReasons: [String] {
        ["Spam", "Harassment", "Misinformation", "Other"]
    }

    private func openPrimaryDestination() {
        if opensAsSpark {
            openReel()
        } else {
            onOpenPost()
        }
    }

    private func openMedia() {
        if opensAsSpark {
            openReel()
        } else if showsPlayLinkInFeed {
            openPlayVideo()
        } else if post.hasVideo, mediaContext == .feed, let onOpenVideo {
            onOpenVideo()
        } else {
            onOpenPost()
        }
    }

    private func openReel() {
        if let onOpenReel {
            onOpenReel()
        } else {
            appState.openReelsViewer(startingPost: post, seedPosts: [post])
        }
    }

    private func openPlayVideo() {
        if let onOpenVideo {
            onOpenVideo()
        } else {
            appState.openPost(post)
        }
    }

    private func openAuthorProfile() {
        appState.openPublicProfile(username: post.author?.username, userID: post.authorID)
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

private struct SharedPostLoadingEmbed: View {
    let postID: String

    @State private var embed: SharedPostPreview?

    var body: some View {
        Group {
            if let embed {
                SharedPostEmbedView(embed: embed)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading shared post…")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 8)
            }
        }
        .task(id: postID) {
            if let post = try? await PostsService.shared.getPostByID(postID) {
                embed = SharedPostPreview(
                    id: post.id,
                    title: post.title,
                    body: post.body,
                    mediaType: post.mediaType,
                    mediaURL: post.mediaURL,
                    thumbURL: post.thumbURL,
                    authorID: post.authorID,
                    author: post.author
                )
            }
        }
    }
}

private struct PostEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let post: CountryPost
    let onSaved: (CountryPost) -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var visibility: PostVisibility
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var previewImage: UIImage?
    @State private var removeExistingImage = false
    @State private var busy = false
    @State private var errorMessage: String?

    private var canEditImage: Bool {
        post.hasImage && !post.hasVideo && !post.isReel && !post.isStory
    }

    init(post: CountryPost, onSaved: @escaping (CountryPost) -> Void) {
        self.post = post
        self.onSaved = onSaved
        _title = State(initialValue: post.displayTitle ?? "")
        _bodyText = State(initialValue: post.displayBody)
        let initialVisibility = post.visibility == .country ? PostVisibility.public : post.visibility
        _visibility = State(initialValue: initialVisibility)
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
                Section("Privacy") {
                    PostVisibilityControl(visibility: $visibility)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }
                if canEditImage {
                    Section("Photo") {
                        editImageSection
                    }
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
            .onChange(of: selectedPhoto) { _, item in
                Task { await loadSelectedPhoto(item) }
            }
        }
    }

    @ViewBuilder
    private var editImageSection: some View {
        if let previewImage {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    clearReplacementImage()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
        } else if post.hasImage, !removeExistingImage, let url = post.feedImageURL {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Rectangle().fill(Theme.canvasMuted)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    removeExistingImage = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                        .padding(8)
                }
                .buttonStyle(.plain)
            }

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Replace photo", systemImage: "photo.on.rectangle.angled")
            }
        } else {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Add photo", systemImage: "photo.on.rectangle.angled")
            }

            if post.hasImage, removeExistingImage {
                Button("Restore original photo", role: .cancel) {
                    removeExistingImage = false
                }
            }
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else { return }
            guard let image = UIImage(data: raw) else { return }
            let jpeg = image.jpegData(compressionQuality: 0.88) ?? raw
            imageData = jpeg
            previewImage = UIImage(data: jpeg)
            removeExistingImage = false
            selectedPhoto = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            clearReplacementImage()
        }
    }

    private func clearReplacementImage() {
        imageData = nil
        previewImage = nil
        selectedPhoto = nil
    }

    private func save() async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            var mediaType: String?
            var mediaURL: String?
            var clearMedia = false

            if canEditImage {
                if let imageData {
                    let upload = try await MediaService.shared.uploadPostMedia(
                        data: imageData,
                        fileExtension: "jpg",
                        mimeType: "image/jpeg"
                    )
                    mediaType = "image"
                    mediaURL = upload.publicURL
                } else if removeExistingImage, post.hasImage {
                    clearMedia = true
                }
            }

            let updated = try await PostsService.shared.updatePost(
                post.id,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfWhitespace,
                body: preservedBody(from: bodyText),
                visibility: visibility,
                mediaType: mediaType,
                mediaURL: mediaURL,
                clearMedia: clearMedia
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