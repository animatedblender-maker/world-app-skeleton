import SwiftUI

enum LivingSection: String, CaseIterable, Identifiable {
    case videos, channels, following, trending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .videos: "Videos"
        case .channels: "Channels"
        case .following: "Following"
        case .trending: "Trending"
        }
    }
}

struct LivingView: View {
    @Environment(AppState.self) private var appState

    @State private var allVideos: [CountryPost] = []
    @State private var channels: [LivingChannel] = []
    @State private var selectedSection: LivingSection = .videos
    @State private var watchingPost: CountryPost?
    @State private var selectedChannel: LivingChannel?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var inlineComments: [PostComment] = []
    @State private var commentError: String?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    private var displayedVideos: [CountryPost] {
        switch selectedSection {
        case .videos:
            return ReelsRankingEngine.rank(
                allVideos,
                viewerCountry: appState.currentProfile?.countryCode,
                followingIDs: appState.followingIDs
            )
        case .channels:
            return []
        case .following:
            return allVideos
                .filter { appState.followingIDs.contains($0.authorID) }
                .sorted { $0.createdAt > $1.createdAt }
        case .trending:
            return allVideos.sorted {
                if $0.viewCount == $1.viewCount { return $0.createdAt > $1.createdAt }
                return $0.viewCount > $1.viewCount
            }
        }
    }

    private var relatedVideos: [CountryPost] {
        guard let watchingPost else { return [] }
        return displayedVideos.filter { $0.id != watchingPost.id }.prefix(6).map { $0 }
    }

    var body: some View {
        ZStack {
            if let watchingPost {
                watchScreen(for: watchingPost)
            } else if let selectedChannel {
                channelScreen(for: selectedChannel)
            } else {
                browseScreen
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await loadVideos()
        }
        .task {
            await loadVideos()
            await consumePendingVideoIfNeeded()
        }
        .onChange(of: appState.pendingLivingVideoID) { _, newID in
            guard let newID else { return }
            Task { await openVideo(id: newID) }
        }
    }

    private var browseScreen: some View {
        VStack(spacing: 0) {
            livingHeader

            if isLoading && allVideos.isEmpty {
                ProgressView("Loading videos…")
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, allVideos.isEmpty {
                ContentUnavailableView(
                    "Videos unavailable",
                    systemImage: "play.tv",
                    description: Text(errorMessage)
                )
            } else if allVideos.isEmpty {
                ContentUnavailableView(
                    "No videos yet",
                    systemImage: "play.tv",
                    description: Text("Share a video in the feed and it will show up here.")
                )
            } else {
                sectionPicker
                if selectedSection == .channels {
                    channelsBrowse
                } else {
                    videoGrid
                }
            }
        }
    }

    private var livingHeader: some View {
        HStack(spacing: 0) {
            MenuToolbarButton()
                .frame(width: 44, height: 44)

            Spacer()

            VStack(spacing: 2) {
                Text("Living")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.ink)
                Text("Watch & discover")
                    .font(.caption2)
                    .foregroundStyle(Theme.inkMuted)
            }

            Spacer()

            Button {
                appState.navigate(to: .search)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LivingSection.allCases) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSection = section
                        }
                    } label: {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedSection == section ? Theme.surface : Theme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selectedSection == section ? Theme.ink : Theme.canvasMuted)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 10)
        }
    }

    private var videoGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(displayedVideos) { post in
                    LivingVideoCard(post: post) {
                        Task { await openVideo(post: post) }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 20)
        }
    }

    private var channelsBrowse: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Creators with channels publish here. Anyone can still share videos in the feed without a channel.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, Theme.pagePadding)

                if channels.isEmpty {
                    ContentUnavailableView(
                        "No channels yet",
                        systemImage: "person.crop.rectangle",
                        description: Text("Enable a Living channel in Edit Profile to appear here.")
                    )
                    .padding(.top, 24)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(channels) { channel in
                            LivingChannelCard(channel: channel) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedChannel = channel
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func channelScreen(for channel: LivingChannel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedChannel = nil
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Channels")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 10)

                HStack(spacing: 12) {
                    AvatarView(url: channel.author?.avatarURL, seed: channel.authorID, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.title)
                            .font(.system(size: 24, weight: .regular, design: .serif))
                            .foregroundStyle(Theme.ink)
                        Text(channel.author?.displayName ?? channel.author?.username ?? "Creator")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkMuted)
                        Text("\(channel.videoCount) videos")
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                .padding(.horizontal, Theme.pagePadding)

                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(channel.videos) { post in
                        LivingVideoCard(post: post) {
                            Task { await openVideo(post: post) }
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
            .padding(.bottom, 24)
        }
    }

    private func watchScreen(for post: CountryPost) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                watchTopBar

                if let url = post.playableVideoURL {
                    VideoPlayerView(
                        url: url,
                        posterURL: post.posterImageURL,
                        placement: "living",
                        countryCode: post.countryCode,
                        contentCountryCode: post.countryCode,
                        postID: post.id,
                        isActive: true,
                        loops: false,
                        muted: false,
                        showsControls: true,
                        onViewed: { Task { await PostsService.shared.recordView(post) } }
                    )
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                } else {
                    LivingVideoThumbnail(post: post, height: 220)
                }

                watchMeta(for: post)
                watchActions(for: post)

                if post.commentCount > 0 || !inlineComments.isEmpty {
                    Divider()
                        .padding(.top, 8)

                    PostCommentsView(
                        postID: post.id,
                        comments: $inlineComments,
                        onError: { commentError = $0 }
                    )
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, 12)
                }

                if let commentError {
                    Text(commentError)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                        .padding(.horizontal, Theme.pagePadding)
                        .padding(.top, 8)
                }

                if !relatedVideos.isEmpty {
                    relatedSection
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var watchTopBar: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    watchingPost = nil
                    inlineComments = []
                    commentError = nil
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Living")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 10)
    }

    private func watchMeta(for post: CountryPost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(post.displayHeadline)
                .font(.system(size: 20, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    openAuthorProfile(for: post)
                } label: {
                    AvatarView(url: post.author?.avatarURL, seed: post.authorID, size: 36)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    Button {
                        openAuthorProfile(for: post)
                    } label: {
                        Text(post.authorDisplayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 6) {
                        if post.viewCount > 0 {
                            Text("\(post.viewCount.formatted()) views")
                        }
                        Text("·")
                        Text(RelativeTime.format(post.createdAt))

                    }
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func watchActions(for post: CountryPost) -> some View {
        HStack(spacing: 22) {
            Button {
                Task { await toggleLike(post) }
            } label: {
                Image(systemName: post.likedByMe ? "heart.fill" : "heart")
                    .font(.system(size: 22))
                    .foregroundStyle(post.likedByMe ? Theme.like : Theme.ink)
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

            Button {
                appState.navigate(to: .post(post.id))
            } label: {
                Image(systemName: "bubble.right")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 6)

        if !post.displayExcerpt.isEmpty {
            Text(post.displayExcerpt)
                .font(.body)
                .foregroundStyle(Theme.inkSecondary)
                .lineSpacing(4)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 8)
        }
    }

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Up next")
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 20)

            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(relatedVideos) { post in
                    LivingVideoCard(post: post) {
                        Task { await openVideo(post: post) }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
        }
    }

    private func loadVideos() async {
        if allVideos.isEmpty {
            isLoading = true
        }
        errorMessage = nil
        defer { isLoading = false }

        let videos = await PostsService.shared.loadLivingVideos()
        allVideos = videos.filter { $0.playableVideoURL != nil }
        if allVideos.isEmpty, !videos.isEmpty {
            errorMessage = "Videos were found but their media links could not be opened."
        }
        channels = await loadChannels(from: allVideos)
    }

    private func loadChannels(from videos: [CountryPost]) async -> [LivingChannel] {
        let grouped = Dictionary(grouping: videos.filter { !$0.isReel }) { $0.authorID }
        var built: [LivingChannel] = []

        for (authorID, authorVideos) in grouped {
            guard let profile = try? await ProfileService.shared.profileByID(authorID),
                  let title = LivingChannelMarker.parse(from: profile.bio) else { continue }
            let sorted = authorVideos.sorted { $0.createdAt > $1.createdAt }
            built.append(
                LivingChannel(
                    id: authorID,
                    authorID: authorID,
                    title: title,
                    author: sorted.first?.author,
                    videos: sorted
                )
            )
        }

        return built.sorted {
            if $0.videoCount == $1.videoCount {
                return ($0.latestVideo?.createdAt ?? "") > ($1.latestVideo?.createdAt ?? "")
            }
            return $0.videoCount > $1.videoCount
        }
    }

    private func consumePendingVideoIfNeeded() async {
        guard let id = appState.pendingLivingVideoID else { return }
        await openVideo(id: id)
    }

    private func openVideo(id: String) async {
        appState.clearPendingLivingVideo()

        if let cached = allVideos.first(where: { $0.id == id }) {
            await presentVideo(cached)
            return
        }

        if allVideos.isEmpty {
            await loadVideos()
            if let cached = allVideos.first(where: { $0.id == id }) {
                await presentVideo(cached)
                return
            }
        }

        do {
            if let fetched = try await PostsService.shared.getPostByID(id), fetched.hasVideo {
                if !allVideos.contains(where: { $0.id == fetched.id }) {
                    allVideos.insert(fetched, at: 0)
                }
                await presentVideo(fetched)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openVideo(post: CountryPost) async {
        appState.clearPendingLivingVideo()
        await presentVideo(post)
    }

    @MainActor
    private func presentVideo(_ post: CountryPost) async {
        inlineComments = []
        commentError = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            watchingPost = post
        }
    }

    private func toggleLike(_ post: CountryPost) async {
        guard var current = watchingPost, current.id == post.id else { return }
        do {
            if current.likedByMe {
                try await PostsService.shared.unlikePost(current.id)
                current = copyPost(current, likedByMe: false, likeCount: max(0, current.likeCount - 1))
            } else {
                try await PostsService.shared.likePost(current.id)
                current = copyPost(current, likedByMe: true, likeCount: current.likeCount + 1)
            }
            watchingPost = current
            if let index = allVideos.firstIndex(where: { $0.id == current.id }) {
                allVideos[index] = current
            }
        } catch {
            commentError = error.localizedDescription
        }
    }

    private func openAuthorProfile(for post: CountryPost) {
        if let username = post.author?.username {
            appState.navigate(to: .publicProfile(username: username))
        }
    }
}

private struct LivingChannelCard: View {
    let channel: LivingChannel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    if let post = channel.latestVideo {
                        LivingVideoThumbnail(post: post, height: 104)
                    } else {
                        Rectangle()
                            .fill(Theme.canvasMuted)
                            .frame(height: 104)
                    }

                    HStack(spacing: 8) {
                        AvatarView(url: channel.author?.avatarURL, seed: channel.authorID, size: 28)
                        Text(channel.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(8)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(8)
                }

                Text(channel.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)

                Text("\(channel.videoCount) videos")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct LivingVideoCard: View {
    let post: CountryPost
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                LivingVideoThumbnail(post: post, height: 104)

                Text(post.displayHeadline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Text(post.authorDisplayName)
                    if post.viewCount > 0 {
                        Text("·")
                        Text("\(post.viewCount.formatted()) views")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
                .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct LivingVideoThumbnail: View {
    let post: CountryPost
    var height: CGFloat = 104

    var body: some View {
        ZStack {
            if let url = post.posterImageURL ?? post.feedImageURL {
                CachedAsyncImage(
                    url: url,
                    maxPixelSize: 480,
                    contentMode: .fill,
                    placeholder: AnyView(thumbnailPlaceholder)
                )
            } else {
                thumbnailPlaceholder
            }

            Image(systemName: "play.circle.fill")
                .font(.system(size: height > 150 ? 52 : 36))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Theme.canvasMuted)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(Theme.canvasMuted)
            .overlay {
                Image(systemName: "video")
                    .foregroundStyle(Theme.inkMuted)
            }
    }
}

private func copyPost(
    _ post: CountryPost,
    likedByMe: Bool,
    likeCount: Int
) -> CountryPost {
    CountryPost(
        id: post.id,
        title: post.title,
        body: post.body,
        mediaType: post.mediaType,
        mediaURL: post.mediaURL,
        thumbURL: post.thumbURL,
        mediaCaption: post.mediaCaption,
        sharedPostID: post.sharedPostID,
        visibility: post.visibility,
        likeCount: likeCount,
        commentCount: post.commentCount,
        viewCount: post.viewCount,
        likedByMe: likedByMe,
        savedByMe: post.savedByMe,
        createdAt: post.createdAt,
        updatedAt: post.updatedAt,
        authorID: post.authorID,
        countryName: post.countryName,
        countryCode: post.countryCode,
        cityName: post.cityName,
        author: post.author,
        linkURL: post.linkURL,
        linkTitle: post.linkTitle,
        externalRefType: post.externalRefType,
        externalRefID: post.externalRefID
    )
}