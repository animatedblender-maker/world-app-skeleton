import SwiftUI

enum PostCardStyle {
    case feed
    case embedded
}

struct PostCardView: View {
    @Environment(AppState.self) private var appState

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
            VStack(alignment: .leading, spacing: 2) {
                Text(post.authorDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                if let location = post.authorLocationLabel {
                    HStack(spacing: 4) {
                        if let flag = post.authorLocationFlag {
                            Text(flag).font(.caption2)
                        }
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            Menu {
                Button {
                    appState.presentShareSheet(for: post)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button {
                    appState.openPost(post)
                } label: {
                    Label("Open post", systemImage: "doc.text")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(Theme.ink)
            }
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
                    .foregroundStyle(commentsExpanded ? Theme.ink : Theme.inkMuted)
            }
            .buttonStyle(.plain)

            Button {
                appState.presentShareSheet(for: post)
            } label: {
                Image(systemName: "paperplane")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                Task {
                    if let error = await appState.toggleSavePost(
                        post,
                        reelPresentation: AppState.belongsInSavedSparks(post)
                    ) {
                        commentError = error
                    }
                }
            } label: {
                Image(systemName: appState.isPostSaved(post.id) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 22))
                    .foregroundStyle(appState.isPostSaved(post.id) ? Theme.ink : Theme.inkMuted)
            }
            .buttonStyle(.plain)
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

/// Elegant hand-drawn picture frame — soft irregular rounded rect + thin double border.
/// Reads like a paper photo frame (travel scrapbook), not a stock circle avatar.
struct HandDrawnPictureFrame: Shape {
    var seed: String = "matterya"

    func path(in rect: CGRect) -> Path {
        let inset = min(rect.width, rect.height) * 0.04
        let r = rect.insetBy(dx: inset, dy: inset)
        // Gentle seed-based wobble so frames feel drawn, not stamped.
        let wobble = seedWobble(seed)
        let corners: [CGPoint] = [
            CGPoint(x: r.minX + wobble[0], y: r.minY + wobble[1]),
            CGPoint(x: r.maxX + wobble[2], y: r.minY + wobble[3]),
            CGPoint(x: r.maxX + wobble[4], y: r.maxY + wobble[5]),
            CGPoint(x: r.minX + wobble[6], y: r.maxY + wobble[7]),
        ]
        let radius = min(r.width, r.height) * 0.16
        var path = Path()
        for i in 0..<4 {
            let curr = corners[i]
            let next = corners[(i + 1) % 4]
            let prev = corners[(i + 3) % 4]
            let toPrev = CGVector(dx: prev.x - curr.x, dy: prev.y - curr.y)
            let toNext = CGVector(dx: next.x - curr.x, dy: next.y - curr.y)
            let lenPrev = max(0.001, hypot(toPrev.dx, toPrev.dy))
            let lenNext = max(0.001, hypot(toNext.dx, toNext.dy))
            let start = CGPoint(
                x: curr.x + toPrev.dx / lenPrev * radius,
                y: curr.y + toPrev.dy / lenPrev * radius
            )
            let end = CGPoint(
                x: curr.x + toNext.dx / lenNext * radius,
                y: curr.y + toNext.dy / lenNext * radius
            )
            if i == 0 { path.move(to: start) } else { path.addLine(to: start) }
            path.addQuadCurve(to: end, control: curr)
        }
        path.closeSubpath()
        return path
    }

    private func seedWobble(_ seed: String) -> [CGFloat] {
        var h: UInt64 = 2166136261
        for b in seed.utf8 {
            h ^= UInt64(b)
            h = h &* 16777619
        }
        var values: [CGFloat] = []
        var x = h
        for _ in 0..<8 {
            x = x &* 6364136223846793005 &+ 1
            let unit = CGFloat(x % 1000) / 1000.0 // 0...1
            values.append((unit - 0.5) * 1.8) // ±0.9 pt-ish at default sizes
        }
        return values
    }
}

enum MatteryaAvatarStyle {
    static func frameAccent(for seed: String) -> Color {
        var hash: UInt64 = 0
        for u in seed.utf8 { hash = hash &* 31 &+ UInt64(u) }
        let hues: [Color] = [
            Theme.ink.opacity(0.55),
            Theme.accent.opacity(0.75),
            Color(red: 0.45, green: 0.38, blue: 0.32),
            Color(red: 0.32, green: 0.42, blue: 0.40),
        ]
        return hues[Int(hash % UInt64(hues.count))]
    }
}

struct AvatarView: View {
    let url: String?
    let seed: String
    let size: CGFloat

    private var frameShape: HandDrawnPictureFrame {
        HandDrawnPictureFrame(seed: seed)
    }

    var body: some View {
        ZStack {
            // Outer mat / paper edge
            frameShape
                .fill(Theme.paper)
                .shadow(color: Theme.ink.opacity(0.10), radius: size * 0.05, y: size * 0.03)

            // Photo well
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
            .frame(width: size * 0.78, height: size * 0.78)
            .clipShape(HandDrawnPictureFrame(seed: seed + "-inner"))

            // Hand-drawn double line frame
            frameShape
                .stroke(MatteryaAvatarStyle.frameAccent(for: seed), lineWidth: max(1.2, size * 0.055))
            HandDrawnPictureFrame(seed: seed + "-rim")
                .stroke(MatteryaAvatarStyle.frameAccent(for: seed).opacity(0.45), lineWidth: max(0.7, size * 0.028))
                .padding(size * 0.055)
        }
        .frame(width: size, height: size)
    }

    private var fallback: some View {
        ZStack {
            HandDrawnPictureFrame(seed: seed + "-fill")
                .fill(Theme.canvasMuted)
            Text(initials)
                .font(.system(size: size * 0.30, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private var initials: String {
        let cleaned = seed.replacingOccurrences(of: "user_", with: "")
        return String(cleaned.prefix(1)).uppercased()
    }
}

struct ExpandableProfileAvatar: View {
    let url: String?
    let seed: String
    let size: CGFloat
    var displayName: String? = nil

    @State private var showPreview = false

    private var hasRemoteImage: Bool {
        guard let normalized = MediaService.normalizedAvatarURL(url),
              URL(string: normalized) != nil
        else { return false }
        return true
    }

    var body: some View {
        Button {
            showPreview = true
        } label: {
            AvatarView(url: url, seed: seed, size: size)
        }
        .buttonStyle(.plain)
        .disabled(!hasRemoteImage)
        .accessibilityLabel(displayName.map { "View \($0)'s profile photo" } ?? "View profile photo")
        .fullScreenCover(isPresented: $showPreview) {
            AvatarPreviewScreen(url: url, seed: seed, displayName: displayName)
        }
    }
}

private struct AvatarPreviewScreen: View {
    @Environment(\.dismiss) private var dismiss

    let url: String?
    let seed: String
    var displayName: String? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)

                Spacer()

                if let imageURL = normalizedURL {
                    CachedAsyncImage(
                        url: imageURL,
                        maxPixelSize: 1200,
                        contentMode: .fill,
                        placeholder: AnyView(
                            ProgressView()
                                .tint(.white)
                        )
                    )
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 360)
                    .padding(.horizontal, 24)
                    .clipShape(HandDrawnPictureFrame(seed: seed))
                    .overlay {
                        HandDrawnPictureFrame(seed: seed)
                            .stroke(Color.white.opacity(0.28), lineWidth: 1.5)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                } else {
                    AvatarView(url: url, seed: seed, size: 200)
                }

                if let displayName, !displayName.isEmpty {
                    Text(displayName)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.top, 20)
                }

                Spacer()
            }
        }
    }

    private var normalizedURL: URL? {
        guard let raw = MediaService.normalizedAvatarURL(url),
              let url = URL(string: raw)
        else { return nil }
        return url
    }
}