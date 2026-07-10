import SwiftUI

enum PostCardStyle {
    case feed
    case embedded
}

struct PostCardView: View {
    let post: CountryPost
    var style: PostCardStyle = .embedded
    var onLikeToggle: (() -> Void)?
    var onOpenPost: (() -> Void)?

    @State private var commentsExpanded = false
    @State private var inlineComments: [PostComment] = []
    @State private var commentError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            media
            actions
            meta

            if commentsExpanded {
                PostCommentsView(
                    postID: post.id,
                    comments: $inlineComments,
                    onError: { commentError = $0 }
                )
                .padding(.horizontal, Theme.pagePadding)
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
        .padding(.bottom, style == .feed ? 0 : 12)
        .background(style == .feed ? Theme.surface : Theme.canvasMuted)
        .feedDivider()
    }

    private var header: some View {
        HStack(spacing: 10) {
            AvatarView(url: post.author?.avatarURL, seed: post.authorID, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(post.author?.username ?? post.author?.displayName ?? "user")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let country = post.countryName {
                    Text(country)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            Spacer()
            Button {} label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var media: some View {
        if let url = post.feedImageURL {
            Button { onOpenPost?() } label: {
                CachedAsyncImage(
                    url: url,
                    maxPixelSize: style == .feed ? 900 : 600,
                    contentMode: .fill,
                    placeholder: AnyView(mediaPlaceholder)
                )
                .frame(maxWidth: .infinity)
                .frame(height: style == .feed ? 390 : 280)
                .clipped()
            }
            .buttonStyle(.plain)
        } else if !post.body.isEmpty {
            Button { onOpenPost?() } label: {
                Text(post.body)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }

    private var actions: some View {
        HStack(spacing: 16) {
            Button { onLikeToggle?() } label: {
                Image(systemName: post.likedByMe ? "heart.fill" : "heart")
                    .font(.system(size: 24))
                    .foregroundStyle(post.likedByMe ? Theme.like : Theme.ink)
            }
            .buttonStyle(.plain)

            Button {
                commentsExpanded.toggle()
            } label: {
                Image(systemName: commentsExpanded ? "bubble.right.fill" : "bubble.right")
                    .font(.system(size: 24))
                    .foregroundStyle(commentsExpanded ? Theme.facebookBlue : Theme.ink)
            }
            .buttonStyle(.plain)

            Image(systemName: "paperplane")
                .font(.system(size: 24))
                .foregroundStyle(Theme.ink)

            Spacer()

            Image(systemName: "bookmark")
                .font(.system(size: 22))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 6) {
            if post.likeCount > 0 {
                Text("\(post.likeCount) likes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }

            if post.commentCount > 0 {
                Button {
                    commentsExpanded.toggle()
                } label: {
                    Text("\(post.commentCount) \(post.commentCount == 1 ? "comment" : "comments")")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)
                }
                .buttonStyle(.plain)
            }

            if let title = post.title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }

            if !post.body.isEmpty, post.mediaURL != nil || post.thumbURL != nil {
                Text(post.body)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(3)
            }

            Text(RelativeTime.format(post.createdAt))
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
                .textCase(.uppercase)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 14)
    }

    private var mediaPlaceholder: some View {
        Rectangle()
            .fill(Theme.canvasMuted)
            .frame(height: style == .feed ? 320 : 220)
            .overlay {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(Theme.inkMuted)
            }
    }
}

struct AvatarView: View {
    let url: String?
    let seed: String
    let size: CGFloat

    var body: some View {
        Group {
            if let url = MediaService.normalizedAvatarURL(url), let imageURL = URL(string: url) {
                CachedAsyncImage(
                    url: imageURL,
                    maxPixelSize: max(96, size * 2),
                    contentMode: .fill,
                    placeholder: AnyView(fallback)
                )
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        ZStack {
            Circle().fill(Theme.canvasMuted)
            Text(initials)
                .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var initials: String {
        let cleaned = seed.replacingOccurrences(of: "user_", with: "")
        return String(cleaned.prefix(1)).uppercased()
    }
}