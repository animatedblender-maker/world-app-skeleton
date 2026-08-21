import SwiftUI
import UIKit

private enum ReelsHaptics {
    /// Intentional like only — never fire on scroll/snap (Instagram-style silent paging).
    static func like() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
    }
}

/// Vertical Sparks feed — **UIKit paging** (TikTok / IG style), not SwiftUI ScrollView.
struct ReelsVerticalFeed: View {
    @Environment(AppState.self) private var appState
    @Binding var posts: [CountryPost]
    @Binding var activeIndex: Int

    var bottomInset: CGFloat = Theme.tabBarHeight + 12
    var showsOpenPostAction = true
    var showsProgressRail = true
    var viewerCountryCode: String? = nil
    var isScrollEnabled: Bool = true
    var onNearEnd: (() -> Void)? = nil
    var onNearStart: (() -> Void)? = nil
    var onOpenComments: ((String) -> Void)? = nil
    /// Swipe right to close the Sparks full-screen viewer.
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .top) {
            SparksUIKitPager(
                posts: $posts,
                activeIndex: $activeIndex,
                bottomInset: bottomInset,
                showsOpenPostAction: showsOpenPostAction,
                viewerCountryCode: viewerCountryCode,
                isScrollEnabled: isScrollEnabled,
                onNearEnd: onNearEnd,
                onNearStart: onNearStart,
                onOpenComments: onOpenComments,
                onLikeToggle: { post in Task { await toggleLike(post) } },
                onOpenPost: { post in openPost(post) },
                onDismiss: onDismiss
            )
            .ignoresSafeArea(.all)

            if showsProgressRail, posts.count > 1 {
                ReelsProgressRail(
                    posts: posts,
                    activeIndex: activeIndex,
                    viewerCountryCode: viewerCountryCode
                )
                .padding(.top, 54)
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea(.all)
        .onAppear {
            // Don’t silenceAll / pauseAll here — feed already soft-handed off; wiping
            // the warm buffer made open feel like a cold start.
            if posts.indices.contains(activeIndex) {
                recordView(at: activeIndex)
                SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
            }
        }
        .onDisappear {
            MediaPlaybackCoordinator.shared.stopAllPlayback()
            SparkWarmPool.shared.drain()
        }
        .onChange(of: activeIndex) { _, idx in
            recordView(at: idx)
            SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: idx)
            // Request next catalog bulk well before the user reaches the tail.
            if idx >= posts.count - 16 {
                onNearEnd?()
            }
        }
    }

    private func openPost(_ post: CountryPost) {
        appState.reelsViewerContext = nil
        appState.openPostInFeed(postID: post.id)
    }

    private func recordView(at index: Int) {
        guard posts.indices.contains(index) else { return }
        let post = posts[index]
        SparkDiscoveryEngine.markWatched(post)
        Task { await PostsService.shared.recordView(post) }
    }

    private func toggleLike(_ post: CountryPost) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        // Always use the *current* array state — UIKit cells capture a stale `post`
        // at configure time, so `post.likedByMe` can never flip to unlike.
        let current = posts[index]
        let wasLiked = current.likedByMe
        let nextLiked = !wasLiked
        let nextCount = nextLiked
            ? current.likeCount + 1
            : max(0, current.likeCount - 1)

        // Optimistic UI so the heart flips immediately (including unlike).
        // Prefer withEngagement so we keep every media/author field intact.
        let optimistic = current.withEngagement(
            likedByMe: nextLiked,
            likeCount: nextCount,
            commentCount: current.commentCount
        )
        posts[index] = optimistic

        // unlikePost / likePost are local-first and do not throw on network failure.
        if wasLiked {
            try? await PostsService.shared.unlikePost(
                current.id,
                baseLikeCount: current.likeCount
            )
        } else {
            try? await PostsService.shared.likePost(
                current.id,
                baseLikeCount: current.likeCount
            )
        }
        EngagementTracker.shared.enqueueLike(post: current, liked: nextLiked)
    }
}

private struct ReelsProgressRail: View {
    let posts: [CountryPost]
    let activeIndex: Int
    let viewerCountryCode: String?

    var body: some View {
        let window = min(posts.count, 12)
        HStack(spacing: 3) {
            ForEach(0..<window, id: \.self) { index in
                let isActive = index == activeIndex % 12
                Capsule()
                    .fill(segmentColor(isActive: isActive))
                    .frame(height: 2.5)
                    .frame(maxWidth: isActive ? 18 : 8)
                    .animation(.easeOut(duration: 0.18), value: activeIndex)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }

    private func segmentColor(isActive: Bool) -> Color {
        if isActive {
            return Theme.reelsAccent
        }
        return Color.white.opacity(0.28)
    }
}

/// Slim amber trail on glass dock — readable without a heavy bar.
private struct SparksTimelineBar: View {
    let currentSeconds: Double
    let durationSeconds: Double
    @Binding var isScrubbing: Bool
    let onSeek: (Double) -> Void

    @State private var dragFraction: Double = 0

    private var fraction: Double {
        guard durationSeconds.isFinite, durationSeconds > 0.35 else { return 0 }
        if isScrubbing { return min(1, max(0, dragFraction)) }
        guard currentSeconds.isFinite else { return 0 }
        return min(1, max(0, currentSeconds / durationSeconds))
    }

    private var timeLabel: String {
        guard durationSeconds > 0.35 else { return "" }
        let t = isScrubbing ? dragFraction * durationSeconds : currentSeconds
        return "\(formatClock(t)) · \(formatClock(durationSeconds))"
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if isScrubbing, durationSeconds > 0.35 {
                Text(timeLabel)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.paper.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity)
            }

            GeometryReader { geo in
                let trackH: CGFloat = isScrubbing ? 3.5 : 1.5
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.paper.opacity(0.18))
                        .frame(height: trackH)
                    Capsule()
                        .fill(Theme.accentBright.opacity(0.95))
                        .frame(width: max(trackH, geo.size.width * fraction), height: trackH)
                        // Smooth advance between ~10 Hz player ticks (no jumpy rail).
                        .animation(isScrubbing ? nil : .linear(duration: 0.1), value: fraction)
                    if isScrubbing {
                        Circle()
                            .fill(Theme.paper)
                            .overlay(Circle().stroke(Theme.accentBright, lineWidth: 1.2))
                            .frame(width: 11, height: 11)
                            .offset(x: max(0, geo.size.width * fraction - 5.5))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                // simultaneous so vertical page swipes always win over scrub.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 14, coordinateSpace: .local)
                        .onChanged { value in
                            let w = max(geo.size.width, 1)
                            let dx = abs(value.translation.width)
                            let dy = abs(value.translation.height)
                            if !isScrubbing {
                                // Strictly horizontal only — never compete with Sparks paging.
                                if dy > 8, dy >= dx { return }
                                if dx < 12 { return }
                            }
                            isScrubbing = true
                            dragFraction = min(1, max(0, value.location.x / w))
                        }
                        .onEnded { value in
                            defer {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    isScrubbing = false
                                }
                            }
                            guard isScrubbing else { return }
                            let w = max(geo.size.width, 1)
                            let f = min(1, max(0, value.location.x / w))
                            dragFraction = f
                            if durationSeconds > 0.35 {
                                onSeek(f * durationSeconds)
                            }
                        }
                )
            }
            .frame(height: 18)
        }
        .animation(.easeOut(duration: 0.12), value: isScrubbing)
        .accessibilityLabel("Spark timeline")
        .accessibilityValue(timeLabel)
    }

    private func formatClock(_ seconds: Double) -> String {
        let s = max(0, SafeNumeric.int(seconds, max: 359_999))
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}

struct ReelsPagerCard: View {
    @Environment(AppState.self) private var appState

    let post: CountryPost
    let isActive: Bool
    /// Parent focus generation while active (0 when inactive). Drives a single t=0 restart.
    var focusGeneration: UInt = 0
    var bottomInset: CGFloat = Theme.tabBarHeight + 12
    var showsOpenPostAction = true
    var viewerCountryCode: String? = nil
    var onLikeToggle: () -> Void
    var onOpenPost: () -> Void
    var onOpenComments: () -> Void = {}

    private var isHomeCountry: Bool {
        MatteryaCountryBridge.isHomeCountry(post: post, viewerCountryCode: viewerCountryCode)
    }

    @State private var saveFeedback: String?
    @State private var isPaused = false
    /// Center play glyph — fades in on pause, then fades out and disappears (video stays frozen).
    @State private var showPauseGlyph = false
    @State private var pauseGlyphTask: Task<Void, Never>?
    @State private var showLikeBurst = false
    @State private var likeButtonScale: CGFloat = 1
    @State private var pendingSingleTap: DispatchWorkItem?
    /// Sparks timeline (YouTube Shorts–style bottom scrubber).
    @State private var progressSeconds: Double = 0
    @State private var durationSeconds: Double = 0
    @State private var seekToSeconds: Double? = nil
    @State private var isScrubbingTimeline = false
    /// Natural size → portrait fills; landscape only fills when crop is small.
    @State private var videoNaturalSize: CGSize = .zero
    /// Locked after first real size so gravity does not thrash mid-play.
    @State private var gravityLocked = false
    /// Optimistic gravity before `onVideoSize`. Default **fit** so landscape ShortForm never
    /// mounts zoom-cropped (clips the bottom dock). `onAppear` / size callback may switch to fill
    /// for true vertical TikTok packs.
    @State private var useFill: Bool = false

    /// Prefer fit until measured when the pack is likely landscape (ShortForm / wide DAR).
    private var prefersFillUntilMeasured: Bool {
        let blobs = [post.mediaURL, post.thumbURL, post.primaryMediaURL, post.linkURL]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        // YouTube ShortForm on R2 is frequently 16:9 / 4:3 — never optimistic-fill those.
        if blobs.contains("shortform/") { return false }
        if blobs.contains("/longform/") { return false }
        return true
    }

    /// Sparks vertical player: always start at 0 on focus (instant TikTok-style sessions).
    /// Feed→Sparks handoff still continues mid-clip via SparkWarmPool continue flag + claim.
    private var restartFromBeginningToken: UInt {
        // If feed exported a live buffer for this id, do not force t=0 (seamless open).
        if SparkWarmPool.shared.shouldContinueFromCurrentTime(postID: post.id) {
            return 0
        }
        return isActive ? max(1, focusGeneration) : 0
    }

    /// Only used for feed→Sparks continue; normal Sparks swipe uses restart token → 0.
    private var resumeStartTime: Double {
        if SparkWarmPool.shared.shouldContinueFromCurrentTime(postID: post.id) {
            let t = YouTubeCatalogService.shared.playbackPosition(for: post.id)
            return t > 0.2 ? t : 0
        }
        return 0
    }

    /// Best-effort play URL — primary resolver plus raw media/thumb fallbacks.
    private var sparkPlayURL: URL? {
        if let url = post.playableVideoURL { return url }
        if let raw = post.mediaURL, let url = MediaURLResolver.resolve(raw),
           !MediaURLResolver.isImageURL(url) {
            return url
        }
        if let raw = post.primaryMediaURL, let url = MediaURLResolver.resolve(raw),
           !MediaURLResolver.isImageURL(url) {
            return url
        }
        if let raw = post.thumbURL, let url = MediaURLResolver.resolve(raw),
           MediaURLResolver.isVideoURL(url) {
            return url
        }
        return nil
    }

    private func noteVideoSize(_ size: CGSize) {
        guard size.width > 2, size.height > 2 else { return }
        if gravityLocked { return }
        videoNaturalSize = size
        // Always re-evaluate from real pixels — never keep an optimistic zoom.
        useFill = SparksStageLayout.shouldFillWithoutCrop(
            videoSize: size,
            stageSize: SparksStageLayout.physicalScreenSize
        )
        gravityLocked = true
    }

    private func resetGravityForCurrentPost() {
        videoNaturalSize = .zero
        gravityLocked = false
        useFill = prefersFillUntilMeasured
    }

    var body: some View {
        // Dock is a ZStack sibling (not under a parent `.clipped()`), so fullscreen
        // fill Sparks never slice the frosted card’s L/R rounded corners.
        ZStack(alignment: .bottom) {
            filmStage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    pendingSingleTap?.cancel()
                    keepPlayingThroughUIAction()
                    triggerLike(fromButton: false)
                }
                .onTapGesture(count: 1) {
                    handleSingleTapPause()
                }

            sparkDock
                .padding(.horizontal, 16)
                .padding(.bottom, max(10, bottomInset - 4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Film + chrome draw under the Dynamic Island; top chrome is overlaid separately.
        .ignoresSafeArea(.all)
        .animation(MatteryaMotion.like, value: showLikeBurst)
        .onChange(of: isActive) { _, active in
            if !active {
                isPaused = false
                hidePauseGlyph(animated: false)
                pendingSingleTap?.cancel()
                seekToSeconds = nil
                isScrubbingTimeline = false
            } else {
                // Focus start is owned by focusGeneration — only reset local UI state here.
                isPaused = false
                hidePauseGlyph(animated: false)
                progressSeconds = 0
                seekToSeconds = nil
                isScrubbingTimeline = false
                if let url = sparkPlayURL {
                    SparkWarmPool.shared.warmSingle(postID: post.id, url: url)
                }
            }
        }
        .onAppear {
            // ShortForm must not mount already zoom-cropped (landscape packs).
            if !gravityLocked {
                useFill = prefersFillUntilMeasured
            }
            if let url = sparkPlayURL {
                SparkWarmPool.shared.warmSingle(postID: post.id, url: url)
            }
        }
        .onChange(of: post.id) { _, _ in
            progressSeconds = 0
            durationSeconds = 0
            seekToSeconds = nil
            isScrubbingTimeline = false
            isPaused = false
            hidePauseGlyph(animated: false)
            resetGravityForCurrentPost()
            if let url = sparkPlayURL {
                SparkWarmPool.shared.warmSingle(postID: post.id, url: url)
            }
        }
        .onDisappear {
            pendingSingleTap?.cancel()
            isPaused = false
            hidePauseGlyph(animated: false)
        }
        // Share / comments overlay may briefly interrupt AVPlayer — re-solo when they open.
        .onReceive(NotificationCenter.default.publisher(for: .matteryaResumePlaybackAfterInterrupt)) { _ in
            guard isActive else { return }
            isPaused = false
        }
    }

    /// Prefer server Frame 0, then nested shared origin, then raw posterImageURL.
    private var sparkPosterURL: URL? {
        MediaURLResolver.posterURL(for: post)
            ?? post.sharedPost.flatMap { MediaURLResolver.posterURL(for: $0.asCountryPost) }
            ?? post.posterImageURL
    }

    /// Full-stage under the notch. Portrait fills; wide clips fit when fill would crop hard.
    private var filmStage: some View {
        ZStack {
            Color.black

            // Prefer existing thumb; otherwise pack-path Frame 0 (API). Never AV-extract
            // on every neighbor — that downloaded full videos and froze the pager.
            if let poster = sparkPosterURL {
                CachedAsyncImage(
                    url: poster,
                    maxPixelSize: 900,
                    contentMode: useFill ? .fill : .fit,
                    placeholder: AnyView(Color.black)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .allowsHitTesting(false)
            } else if let url = sparkPlayURL {
                FrameZeroFallbackPoster(
                    postID: post.id,
                    videoURL: url,
                    fillsFrame: useFill,
                    allowClientExtract: isActive
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }

            if let url = sparkPlayURL {
                Group {
                    if ArchiveVideoPlayback.isArchiveURL(url) || post.isHubSeedVideo {
                        ArchiveVideoPlayerView(
                            url: url,
                            posterURL: sparkPosterURL,
                            isActive: isActive,
                            muted: false,
                            startTime: resumeStartTime,
                            loops: true,
                            fillsFrame: useFill,
                            postID: post.id,
                            interactive: false,
                            onReady: { Task { await PostsService.shared.recordView(post) } },
                            onProgress: { current, duration in
                                applyTimelineProgress(current: current, duration: duration)
                            },
                            onVideoSize: { noteVideoSize($0) },
                            seekToSeconds: seekToSeconds,
                            onSeekConsumed: { seekToSeconds = nil },
                            restartFromBeginningToken: restartFromBeginningToken,
                            isPausedByUser: isPaused
                        )
                    } else {
                        VideoPlayerView(
                            url: url,
                            posterURL: sparkPosterURL,
                            placement: "reel",
                            countryCode: post.countryCode,
                            contentCountryCode: post.countryCode,
                            postID: post.id,
                            isActive: isActive,
                            loops: true,
                            muted: false,
                            showsControls: false,
                            startTime: resumeStartTime > 0 ? resumeStartTime : nil,
                            fillsFrame: useFill,
                            preloadsWhenInactive: true,
                            onViewed: { Task { await PostsService.shared.recordView(post) } },
                            onProgress: { current, duration in
                                applyTimelineProgress(current: current, duration: duration)
                            },
                            onVideoSize: { noteVideoSize($0) },
                            seekToSeconds: seekToSeconds,
                            onSeekConsumed: { seekToSeconds = nil },
                            restartFromBeginningToken: restartFromBeginningToken,
                            isPausedByUser: isPaused
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .animation(nil, value: useFill)
                .allowsHitTesting(false)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Theme.paper.opacity(0.45))
                    Text("Spark unavailable")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Theme.paper.opacity(0.55))
                    Text("Swipe for the next one")
                        .font(.caption)
                        .foregroundStyle(Theme.paper.opacity(0.4))
                }
                .allowsHitTesting(false)
            }

            // Light vignette only — video stays immersive; dock floats over film.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Theme.ink.opacity(0.22), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 64)
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [.clear, Theme.ink.opacity(0.18), Theme.ink.opacity(0.42)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Soft off-white gold play — fades in, holds briefly, fades out & disappears.
            // No glow. Video stays frozen underneath while paused.
            Image(systemName: "play.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(
                    Color(red: 0.96, green: 0.93, blue: 0.86).opacity(0.72)
                )
                .offset(x: 3) // optical center for play triangle
                .opacity(showPauseGlyph ? 1 : 0)
                .scaleEffect(showPauseGlyph ? 1 : 0.92)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.22), value: showPauseGlyph)

            if showLikeBurst {
                Image(systemName: "heart.fill")
                    .font(.system(size: 88, weight: .bold))
                    .foregroundStyle(Theme.like)
                    .shadow(color: Theme.ink.opacity(0.25), radius: 12)
                    .scaleEffect(showLikeBurst ? 1 : 0.55)
                    .opacity(showLikeBurst ? 0.95 : 0)
                    .allowsHitTesting(false)
            }

            if let message = saveFeedback {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.paper.opacity(0.94), in: Capsule())
                    .shadow(color: Theme.ink.opacity(0.15), radius: 8, y: 3)
                    .padding(.top, 56)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Frosted paper dock — same Matterya card, translucent so film stays immersive.
    private var sparkDock: some View {
        VStack(alignment: .leading, spacing: 8) {
            authorRow

            if let text = post.sparkDisplayCaption, !text.isEmpty {
                Text(text)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Theme.paper.opacity(0.94))
                    .shadow(color: Theme.ink.opacity(0.45), radius: 6, y: 1)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Timeline sits *above* Like / Chat / Keep / Send (not under the actions).
            if isActive {
                SparksTimelineBar(
                    currentSeconds: progressSeconds,
                    durationSeconds: durationSeconds,
                    isScrubbing: $isScrubbingTimeline,
                    onSeek: { seconds in
                        progressSeconds = seconds
                        seekToSeconds = seconds
                    }
                )
            }

            // Action ribbon — must never overflow the card (overflow was slicing L/R capsules).
            sparkActionsRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .background {
            // Warm paper wash — Matterya, not pure iOS glass.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.paper.opacity(0.14))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.paper.opacity(0.22), lineWidth: 0.5)
        )
        .shadow(color: Theme.ink.opacity(0.22), radius: 6, y: 5)
    }

    /// Like / Chat / Keep / Send — equal flexible chips; compact counts so capsules aren’t sliced.
    private var sparkActionsRow: some View {
        HStack(spacing: 4) {
            sparkAction(
                icon: post.likedByMe ? "heart.fill" : "heart",
                label: post.likeCount > 0 ? Self.compactCount(post.likeCount) : "Like",
                accent: post.likedByMe ? Theme.like : Theme.paper,
                scale: likeButtonScale
            ) {
                keepPlayingThroughUIAction()
                triggerLike(fromButton: true)
            }
            sparkAction(
                icon: "bubble.right",
                label: post.commentCount > 0 ? Self.compactCount(post.commentCount) : "Chat",
                accent: Theme.paper
            ) {
                keepPlayingThroughUIAction()
                CommentsWarmCache.shared.warm(post.id)
                onOpenComments()
                reassertPlayback()
            }
            sparkAction(
                icon: appState.isPostSaved(post.id) ? "bookmark.fill" : "bookmark",
                label: appState.isPostSaved(post.id) ? "Kept" : "Keep",
                accent: appState.isPostSaved(post.id) ? Theme.accentBright : Theme.paper
            ) {
                keepPlayingThroughUIAction()
                Task { await toggleSave() }
            }
            sparkAction(
                icon: "arrowshape.turn.up.right",
                label: "Send",
                accent: Theme.paper
            ) {
                keepPlayingThroughUIAction()
                appState.presentShareSheet(for: post)
                reassertPlayback()
            }
            if showsOpenPostAction {
                sparkAction(icon: "arrow.up.right", label: "Open", accent: Theme.paper) {
                    keepPlayingThroughUIAction()
                    onOpenPost()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sparkAction(
        icon: String,
        label: String,
        accent: Color,
        scale: CGFloat = 1,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .scaleEffect(scale)
                Text(label)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .allowsTightening(true)
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 5)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Theme.paper.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(Theme.paper.opacity(0.14), lineWidth: 0.5))
            // Clip label/icon to the capsule — never bleed past the chip edge.
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .layoutPriority(0)
    }

    /// 12487 → "12.5K" so four/five chips fit without side-slicing.
    private static func compactCount(_ n: Int) -> String {
        let v = abs(n)
        switch v {
        case 1_000_000...:
            let m = Double(v) / 1_000_000
            return m >= 10 ? String(format: "%.0fM", m) : String(format: "%.1fM", m)
        case 1_000...:
            let k = Double(v) / 1_000
            return k >= 10 ? String(format: "%.0fK", k) : String(format: "%.1fK", k)
        default:
            return "\(v)"
        }
    }

    /// Update Sparks timeline from AVPlayer ticks.
    /// Safe to call from a preloaded (inactive) time-observer closure — @State storage is shared.
    private func applyTimelineProgress(current: Double, duration: Double) {
        // Persist playhead so swipe away/back + feed handoff can continue mid-clip.
        if current >= 0.2 {
            YouTubeCatalogService.shared.notePlaybackPosition(
                current,
                for: post.id,
                duration: duration > 0 ? duration : nil
            )
        }
        guard !isScrubbingTimeline else { return }
        let cur = current.isFinite ? max(0, current) : 0
        progressSeconds = cur
        if duration.isFinite, duration > 0.25 {
            durationSeconds = duration
        }
    }

    /// Single-tap pause with a short delay so double-tap like can cancel it.
    /// Only invoked from film-stage taps — never from dock buttons.
    private func handleSingleTapPause() {
        pendingSingleTap?.cancel()
        let work = DispatchWorkItem {
            togglePause()
        }
        pendingSingleTap = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    private func togglePause() {
        isPaused.toggle()
        if isPaused {
            flashPauseGlyph()
        } else {
            hidePauseGlyph(animated: true)
        }
    }

    /// Fade play glyph in, hold a beat, then fade out and disappear (pause state remains).
    private func flashPauseGlyph() {
        pauseGlyphTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            showPauseGlyph = true
        }
        pauseGlyphTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                showPauseGlyph = false
            }
        }
    }

    private func hidePauseGlyph(animated: Bool) {
        pauseGlyphTask?.cancel()
        pauseGlyphTask = nil
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                showPauseGlyph = false
            }
        } else {
            showPauseGlyph = false
        }
    }

    /// Cancel any pending film single-tap pause and force the Spark to keep playing.
    private func keepPlayingThroughUIAction() {
        pendingSingleTap?.cancel()
        pendingSingleTap = nil
        isPaused = false
        hidePauseGlyph(animated: true)
    }

    /// Kick solo audio again after overlays / sheets that may have interrupted AVPlayer.
    private func reassertPlayback() {
        guard isActive else { return }
        isPaused = false
        hidePauseGlyph(animated: false)
        // Slight delay so sheet/overlay presentation settles first.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
        }
    }

    private func triggerLike(fromButton: Bool) {
        // Always keep audio rolling through like (button or double-tap).
        keepPlayingThroughUIAction()
        // Heart button always toggles (like *and* unlike). Double-tap only likes
        // (Instagram-style) so a second double-tap does not strip the like.
        if fromButton {
            onLikeToggle()
        } else if !post.likedByMe {
            onLikeToggle()
        }
        ReelsHaptics.like()
        // Burst only when liking, not when unliking.
        let willLike = fromButton ? !post.likedByMe : !post.likedByMe
        if willLike || !fromButton {
            withAnimation(MatteryaMotion.like) {
                showLikeBurst = true
                likeButtonScale = 1.18
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(MatteryaMotion.micro) {
                    showLikeBurst = false
                    likeButtonScale = 1
                }
            }
        }
        reassertPlayback()
    }

    private var authorRow: some View {
        HStack(spacing: 8) {
            Button {
                appState.openPublicProfile(username: post.author?.username, userID: post.authorID)
            } label: {
                HStack(spacing: 8) {
                    AvatarView(url: post.author?.avatarURL, seed: post.authorID, size: 34)
                        .overlay(Circle().stroke(Theme.paper.opacity(0.35), lineWidth: 0.5))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(post.author?.displayName ?? "Member")
                            .font(.system(.subheadline, design: .serif).weight(.semibold))
                            .foregroundStyle(Theme.paper)
                            .shadow(color: Theme.ink.opacity(0.4), radius: 4, y: 1)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if let handle = post.author?.username, !handle.isEmpty {
                                Text("@\(handle)")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Theme.paper.opacity(0.7))
                                    .lineLimit(1)
                            }
                            if post.countryCode != nil || post.countryName != nil {
                                Text("·")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.paper.opacity(0.4))
                                Text(post.countryName ?? post.countryCode?.uppercased() ?? "")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Theme.paper.opacity(0.65))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            if post.authorID != appState.currentProfile?.userID, !post.authorID.isEmpty {
                FollowButton(userID: post.authorID, compact: true, onDark: true)
            }
        }
    }

    private func toggleSave() async {
        let willSave = !appState.isPostSaved(post.id)
        if let error = await appState.toggleSavePost(post, reelPresentation: true) {
            withAnimation(.easeInOut(duration: 0.2)) {
                saveFeedback = error
            }
            try? await Task.sleep(for: .seconds(2.5))
            if saveFeedback == error {
                withAnimation(.easeInOut(duration: 0.2)) {
                    saveFeedback = nil
                }
            }
            return
        }
        // Confirm Keep landed in Saved Sparks (profile → Saved Sparks).
        let message = willSave ? "Saved to \(MatteryaCopy.savedSparks)" : "Removed from saved"
        withAnimation(.easeInOut(duration: 0.2)) {
            saveFeedback = message
        }
        try? await Task.sleep(for: .seconds(1.6))
        if saveFeedback == message {
            withAnimation(.easeInOut(duration: 0.2)) {
                saveFeedback = nil
            }
        }
    }
}

private struct ReelsCommentTarget: Identifiable {
    let id: String
}

/// Bottom share card over the live Sparks player — video keeps playing underneath.
private struct SparksShareOverlay: View {
    @Environment(AppState.self) private var appState
    let post: CountryPost
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .allowsHitTesting(true)

            SharePostSheet(
                post: post,
                onClose: onClose,
                keepsSparksPlaying: true
            )
            .withAppState(appState)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 18,
                    style: .continuous
                )
            )
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 18,
                    style: .continuous
                )
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.35), radius: 20, y: -4)
            )
            .frame(maxHeight: UIScreen.main.bounds.height * 0.52)
            .padding(.bottom, 0)
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            // Only the current solo Spark may keep audio under the share sheet.
            MediaPlaybackCoordinator.shared.enforceSoloAudioOnly()
            NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
        }
    }
}

/// Bottom comments card over the live Sparks player — video keeps playing (no .sheet).
/// Dismiss: tap outside (dimmer) or drag the grabber down — **no Close button**.
/// Dimmer + sheet shadow fade with drag/dismiss so nothing black stains the film.
private struct SparksCommentsOverlay: View {
    @Environment(AppState.self) private var appState
    let postID: String
    let onClose: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isDismissing = false
    /// Full-screen dim strength; always fades to 0 on dismiss (never leaves a black veil).
    @State private var dimOpacity: Double = 0.32

    private var sheetShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 18,
            style: .continuous
        )
    }

    var body: some View {
        GeometryReader { geo in
            let maxSheetH = max(geo.size.height * 0.62, 280)
            // Fade dimmer as the user pulls the sheet down (1:1 with finger).
            let dragProgress = min(1, max(0, dragOffset / max(maxSheetH * 0.55, 120)))
            let liveDim = isDismissing ? dimOpacity : dimOpacity * (1 - dragProgress * 0.92)
            // Hide upward sheet shadow while dragging / dismissing — that was the black stain.
            let shadowOpacity = (isDismissing || dragOffset > 6) ? 0.0 : 0.18

            ZStack(alignment: .bottom) {
                // Full-screen dimmer — opacity-driven so dismiss never leaves a black rectangle.
                Color.black
                    .opacity(liveDim)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }
                    .allowsHitTesting(!isDismissing)
                    .accessibilityLabel("Dismiss comments")
                    .accessibilityAddTraits(.isButton)

                VStack(spacing: 0) {
                    // Grab handle — drag down to close without fighting the comments list.
                    VStack(spacing: 0) {
                        Capsule()
                            .fill(Theme.inkMuted.opacity(0.45))
                            .frame(width: 44, height: 5)
                            .padding(.top, 10)
                            .padding(.bottom, 10)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .gesture(dismissDragGesture)
                    .accessibilityLabel("Drag down to close comments")

                    NavigationStack {
                        // Don't Environment.dismiss the Sparks full-screen cover when opening a profile.
                        // No Close/Done toolbar — dimmer + grabber only (Instagram-style).
                        PostCommentsPageView(postID: postID, dismissesOnProfileOpen: false)
                            .toolbar(.hidden, for: .navigationBar)
                    }
                    .withAppState(appState)
                }
                .frame(maxWidth: .infinity)
                .frame(height: maxSheetH, alignment: .top)
                .background(Theme.surface)
                .clipShape(sheetShape)
                // Clip shadow to the sheet bounds so it can't paint over the video after dismiss.
                .compositingGroup()
                .shadow(color: .black.opacity(shadowOpacity), radius: 12, y: -2)
                .offset(y: max(0, dragOffset))
                .opacity(isDismissing ? max(0, 1 - dragProgress) : 1)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .ignoresSafeArea()
        .onAppear {
            // Prefetch already running from Chat tap; keep warm in case of cold path.
            CommentsWarmCache.shared.warm(postID)
            // Kill ghost audio from off-screen Sparks (UICollectionView cells can stay “active”).
            MediaPlaybackCoordinator.shared.enforceSoloAudioOnly()
            // Resume only the solo player (handlers ignore non-solo).
            NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                MediaPlaybackCoordinator.shared.enforceSoloAudioOnly()
                NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
            }
        }
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                guard !isDismissing else { return }
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                guard !isDismissing else { return }
                let dy = value.translation.height
                let predicted = value.predictedEndTranslation.height
                if dy > 90 || predicted > 180 {
                    dismiss()
                } else {
                    withAnimation(MatteryaMotion.sheet) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        // Fade dimmer + drop sheet together — no residual black veil on the Spark.
        withAnimation(MatteryaMotion.sheet) {
            dragOffset = max(dragOffset, UIScreen.main.bounds.height * 0.55)
            dimOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onClose()
        }
    }
}

/// Top chrome: close (X) top-leading · “SPARKS” centered · ⋯ menu top-trailing (like feed cards).
/// Sized to chrome only (not full-screen) so vertical paging is free on the rest of the stage.
private struct SparksTopChrome: View {
    @Environment(AppState.self) private var appState

    let post: CountryPost?
    let onClose: () -> Void
    var onNotInterested: (() -> Void)? = nil
    var onHide: (() -> Void)? = nil

    @State private var showReportConfirm = false
    @State private var actionBusy = false

    private let word = MatteryaCopy.sparks.uppercased()
    private let reportReasons = ["Spam", "Harassment", "Misinformation", "Other"]

    private var isOwnPost: Bool {
        guard let post, let me = appState.currentProfile?.userID else { return false }
        return post.authorID == me
    }

    var body: some View {
        ZStack {
            Text(word)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(4.5)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Theme.paper.opacity(0.95),
                            Theme.accentBright.opacity(0.88),
                            Theme.paper.opacity(0.95),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: .black.opacity(0.55), radius: 6, y: 1)
                .allowsHitTesting(false)
                .accessibilityLabel(MatteryaCopy.sparks)

            HStack {
                ReelsChromeButton(
                    systemName: "xmark",
                    accessibilityLabel: "Close \(MatteryaCopy.sparks.lowercased())",
                    action: onClose
                )
                .offset(y: -2)

                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                // Top-right ⋯ — same family of actions as feed cards.
                Menu {
                    if let post, !isOwnPost {
                        Button {
                            onNotInterested?()
                        } label: {
                            Label("Not interested", systemImage: "hand.thumbsdown")
                        }
                        Button {
                            onHide?()
                        } label: {
                            Label("Hide \(MatteryaCopy.spark.lowercased())", systemImage: "eye.slash")
                        }
                        Button {
                            appState.blockUser(
                                post.authorID,
                                username: post.author?.username,
                                displayName: post.author?.displayName
                            )
                            appState.showToast("Blocked \(post.authorDisplayName).", style: .info)
                            onNotInterested?()
                        } label: {
                            Label("Block \(post.authorDisplayName)", systemImage: "person.slash")
                        }
                    }
                    if post != nil {
                        Button("Report", role: .destructive) {
                            showReportConfirm = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(post == nil || actionBusy)
                .accessibilityLabel("More options")
                .offset(y: -2)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, Theme.pagePadding - 4)
        .padding(.top, Self.notchInset + 2)
        .frame(maxWidth: .infinity)
        // Height = notch + bar only — never expand to full screen (that blocked first swipe).
        .allowsHitTesting(true)
        .ignoresSafeArea(edges: .top)
        .confirmationDialog(
            "Report this \(MatteryaCopy.spark.lowercased())",
            isPresented: $showReportConfirm,
            titleVisibility: .visible
        ) {
            ForEach(reportReasons, id: \.self) { reason in
                Button(reason, role: .destructive) {
                    Task { await reportCurrent(reason: reason) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func reportCurrent(reason: String) async {
        guard let post else { return }
        actionBusy = true
        defer { actionBusy = false }
        do {
            let ok = try await PostsService.shared.reportPost(post.id, reason: reason)
            await MainActor.run {
                appState.showToast(
                    ok ? "Reported. Thank you." : "Could not report.",
                    style: ok ? .info : .error
                )
            }
            if ok {
                // Also skip past this clip after report.
                await MainActor.run { onNotInterested?() }
            }
        } catch {
            await MainActor.run {
                appState.showToast(error.localizedDescription, style: .error)
            }
        }
    }

    private static var notchInset: CGFloat {
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }),
           let top = scene.windows.first(where: \.isKeyWindow)?.safeAreaInsets.top,
           top > 20 {
            return top
        }
        return UIScreen.main.bounds.height >= 900 ? 54 : 50
    }
}

/// Nonisolated queue budgets (default args cannot reference MainActor-isolated statics).
private enum SparksQueueBudget {
    static let minQueueAhead = 28
    static let bulkBatchSize = 80
}


struct ReelsScrollViewer: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let context: ReelsViewerContext

    @State private var posts: [CountryPost]
    @State private var activeIndex = 0
    @State private var isExpandingFeed = false
    /// If near-end fires while a bulk load is in flight, run another bulk immediately after.
    @State private var loadMoreQueued = false
    @State private var feedCursor: String?
    @State private var hasMorePages = true
    @State private var recyclePass = 0
    @State private var commentsPostID: String?

    // Budget constants live on SparksQueueBudget (nonisolated) so default args compile under Swift 6.

    init(context: ReelsViewerContext) {
        self.context = context
        var seed = context.seedPosts
        if !seed.contains(where: { $0.id == context.startingPost.id }) {
            seed.insert(context.startingPost, at: 0)
        }
        if seed.isEmpty {
            seed = [context.startingPost]
        }
        _posts = State(initialValue: seed)
        _activeIndex = State(initialValue: max(0, seed.firstIndex(where: { $0.id == context.startingPost.id }) ?? 0))
    }

    var body: some View {
        reelsContent
    }

    private var reelsContent: some View {
        ZStack(alignment: .topLeading) {
            Color.black

            if posts.isEmpty {
                ContentUnavailableView(
                    "No \(MatteryaCopy.sparks.lowercased())",
                    systemImage: "video.slash",
                    description: Text("This \(MatteryaCopy.spark.lowercased()) is no longer available.")
                )
            } else {
                // Full physical screen from frame 0 — never reflows under safe area.
                ReelsVerticalFeed(
                    posts: $posts,
                    activeIndex: $activeIndex,
                    bottomInset: 28,
                    showsOpenPostAction: false,
                    showsProgressRail: false,
                    viewerCountryCode: appState.currentProfile?.countryCode,
                    isScrollEnabled: commentsPostID == nil && appState.sharePostSheet == nil,
                    onNearEnd: { requestLoadMore() },
                    onNearStart: { Task { await loadEarlierReels() } },
                    onOpenComments: { id in
                        CommentsWarmCache.shared.warm(id)
                        commentsPostID = id
                    },
                    onDismiss: { dismiss() }
                )
            }

            SparksTopChrome(
                post: posts.indices.contains(activeIndex) ? posts[activeIndex] : nil,
                onClose: { dismiss() },
                onNotInterested: { skipCurrentSpark(kind: .notInterested) },
                onHide: { skipCurrentSpark(kind: .hide) }
            )
            .zIndex(40)

            if let commentsID = commentsPostID {
                SparksCommentsOverlay(postID: commentsID) {
                    commentsPostID = nil
                    MediaPlaybackCoordinator.shared.enforceSoloAudioOnly()
                    NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
                }
                .zIndex(75)
                // Removal is pure opacity — move+opacity left a black dimmer stain over the film.
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    )
                )
                .onAppear { CommentsWarmCache.shared.warm(commentsID) }
            }

            if let sharePost = appState.sharePostSheet {
                SparksShareOverlay(post: sharePost) {
                    appState.sharePostSheet = nil
                    MediaPlaybackCoordinator.shared.enforceSoloAudioOnly()
                    NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
                }
                .zIndex(80)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea(.all))
        .ignoresSafeArea(.all)
        .animation(MatteryaMotion.sheet, value: appState.sharePostSheet?.id)
        .animation(MatteryaMotion.sheet, value: commentsPostID)
        .toolbar(.hidden, for: .navigationBar)
        // Status bar hidden so film can paint under the Dynamic Island.
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onChange(of: activeIndex) { _, idx in
            // Idle-warm comments for the focused Spark so Chat is instant.
            guard posts.indices.contains(idx) else { return }
            CommentsWarmCache.shared.warm(posts[idx].id)
            // Keep a bulk of unplayed Sparks ahead of the finger at all times.
            Task { await ensureBulkQueueAhead() }
        }
        .task {
            // Open must paint immediately — never await warm/network on the critical path.
            PerformanceTelemetry.markIfAbsent("sparks_open_start")
            SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
            if posts.indices.contains(activeIndex) {
                CommentsWarmCache.shared.warm(posts[activeIndex].id)
            }
            PerformanceTelemetry.milestone(
                "reel_swipe_first_frame",
                surface: "sparks",
                from: "sparks_open_start",
                meta: ["path": "open_instant", "queue": "\(posts.count)"]
            )

            // Everything else off the open path.
            Task { @MainActor in
                seedFromWarmCatalogIfNeeded()
                await ensureBulkQueueAhead(target: max(24, SparksQueueBudget.minQueueAhead))
                SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
                await expandFeed()
                await ensureBulkQueueAhead(target: SparksQueueBudget.minQueueAhead)
                SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
                if posts.count < SparksQueueBudget.minQueueAhead {
                    await loadMoreReels()
                    await ensureBulkQueueAhead(target: SparksQueueBudget.minQueueAhead)
                }
            }
        }
        .onDisappear {
            // Closing Sparks: kill every non-hub player (safety net).
            MediaPlaybackCoordinator.shared.silenceAllOffScreenAudio()
            SparkWarmPool.shared.silenceAllBuffered()
        }
    }

    /// Fire-and-forget catalog bulk; queues a second pass if one is already in flight.
    private func requestLoadMore() {
        if isExpandingFeed {
            loadMoreQueued = true
            return
        }
        Task { await loadMoreReels() }
    }

    private enum SparkSkipKind {
        case notInterested
        case hide
    }

    /// ⋯ menu: hide / not interested / after report — remove clip and advance (or close).
    private func skipCurrentSpark(kind: SparkSkipKind) {
        guard posts.indices.contains(activeIndex) else { return }
        let post = posts[activeIndex]
        switch kind {
        case .notInterested:
            FeedFeedbackStore.shared.notInterested(post: post)
            EngagementTracker.shared.enqueueRecommendationEvent(
                type: "not_interested",
                contentId: post.id,
                authorId: post.authorID,
                surface: RecommendationSurface.sparks.rawValue,
                meta: ["place": "sparks_menu"]
            )
            appState.showToast("We'll show less like this.", style: .info)
        case .hide:
            FeedFeedbackStore.shared.hide(post: post)
            EngagementTracker.shared.enqueueRecommendationEvent(
                type: "hide",
                contentId: post.id,
                authorId: post.authorID,
                surface: RecommendationSurface.sparks.rawValue,
                meta: ["place": "sparks_menu"]
            )
            appState.showToast("Hidden from \(MatteryaCopy.sparks.lowercased()).", style: .info)
        }
        SparkDiscoveryEngine.markWatched(post)

        var next = posts
        next.removeAll { $0.id == post.id }
        if next.isEmpty {
            dismiss()
            return
        }
        let newIndex = min(activeIndex, next.count - 1)
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            posts = next
            activeIndex = newIndex
        }
        SparkWarmPool.shared.preparePlayerWindow(posts: next, around: newIndex)
        Task { await ensureBulkQueueAhead() }
    }

    /// Keep at least `target` unplayed Sparks after the focused index.
    private func ensureBulkQueueAhead(target: Int = SparksQueueBudget.minQueueAhead) async {
        var guardPasses = 0
        while guardPasses < 5 {
            guardPasses += 1
            let remaining = max(0, posts.count - activeIndex - 1)
            guard remaining < target else { return }
            let before = posts.count
            let beforeIndex = activeIndex
            await loadMoreReels()
            let afterRemaining = max(0, posts.count - activeIndex - 1)
            if afterRemaining > remaining || posts.count > before {
                SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
                continue
            }
            // Network/catalog empty of new IDs — force endless rotation once.
            if beforeIndex == activeIndex, posts.count >= 8 {
                rotateQueueForEndless()
                SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
            }
            return
        }
    }

    /// Instant neighbors from memory — **unviewed discovery order**, append only.
    private func seedFromWarmCatalogIfNeeded() {
        guard posts.count < SparksQueueBudget.minQueueAhead else { return }
        var seen = Set(posts.map(\.id))
        var toAppend: [CountryPost] = []
        let warm = SparkDiscoveryEngine.rankForDiscovery(
            PostsService.shared.sparksCatalogSnapshot()
                .filter { ReelsRankingEngine.isSparkEligible($0) }
        )
        for post in warm {
            guard seen.insert(post.id).inserted else { continue }
            let hasPath = MediaURLResolver.videoURL(for: post) != nil
                || !(post.mediaURL ?? "").isEmpty
                || post.hasVideo
            guard hasPath else { continue }
            toAppend.append(post)
            if posts.count + toAppend.count >= 96 { break }
        }
        guard !toAppend.isEmpty else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            posts.append(contentsOf: toAppend)
        }
        hasMorePages = true
        SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
    }

    private func expandFeed() async {
        guard !isExpandingFeed else {
            loadMoreQueued = true
            return
        }
        isExpandingFeed = true
        defer {
            isExpandingFeed = false
            if loadMoreQueued {
                loadMoreQueued = false
                Task { await loadMoreReels() }
            }
        }

        feedCursor = nil
        hasMorePages = true
        recyclePass = 0

        // Live clip under the finger (user may have swiped during network).
        let liveID = posts.indices.contains(activeIndex)
            ? posts[activeIndex].id
            : context.startingPostID
        let rankingAnchor = ReelsRankingEngine.resolvePlayerStart(
            posts.first(where: { $0.id == liveID }) ?? context.startingPost
        )
        let liveIndexBefore = posts.firstIndex(where: { $0.id == liveID }) ?? activeIndex
        let aheadBefore = max(0, posts.count - liveIndexBefore - 1)

        // Full discovery session: unviewed first + random library samples.
        var fresh = await PostsService.shared.beginFreshSparksSession(preferStart: rankingAnchor)
        // Server rank (scale path) — soft reorder; never blocks first paint (already open).
        if fresh.count >= 6 {
            let ranked = await RecommendationClient.rankPosts(
                fresh,
                surface: .sparks,
                sessionId: context.id.uuidString,
                followingIDs: Set<String>(),
                limit: min(fresh.count, 100)
            )
            if ranked.count >= 2 {
                fresh = ranked
            }
        }

        // Re-read live id after await (swipe during load).
        let keepID = posts.indices.contains(activeIndex)
            ? posts[activeIndex].id
            : liveID
        let liveIndex = posts.firstIndex(where: { $0.id == keepID }) ?? activeIndex

        // Large instant seed already under the finger — **append only**.
        // Full replace remounted early pages → open “hallucinations” / flicker.
        if aheadBefore >= 12, posts.count >= 16 {
            applyExpandedFeed(fresh, preserveID: keepID)
            hasMorePages = true
            SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
            #if DEBUG
            print("[Sparks] expand soft-append size=\(posts.count) live=\(keepID.prefix(8))")
            #endif
            return
        }

        // Thin seed: keep history + replace upcoming with discovery queue.
        let history = Array(posts.prefix(max(0, liveIndex + 1)))
        var seen = Set(history.map(\.id))
        var upcoming: [CountryPost] = []
        for post in fresh {
            guard seen.insert(post.id).inserted else { continue }
            guard ReelsRankingEngine.isSparkEligible(post) || post.id == keepID else { continue }
            let hasPath = MediaURLResolver.videoURL(for: post) != nil
                || !(post.mediaURL ?? "").isEmpty
                || post.hasVideo
            guard hasPath else { continue }
            upcoming.append(post)
        }

        if !upcoming.isEmpty || history.count != posts.count {
            let queue = history + upcoming
            if queue.count >= 2 {
                replacePlayerQueue(queue, preserveID: keepID)
            } else if !upcoming.isEmpty {
                applyExpandedFeed(upcoming)
            }
        } else if posts.count < 4, rankingAnchor.playableVideoURL != nil || rankingAnchor.hasVideo {
            var tiny = [rankingAnchor]
            for p in fresh where p.id != rankingAnchor.id {
                tiny.append(p)
                if tiny.count >= 40 { break }
            }
            replacePlayerQueue(tiny, preserveID: keepID)
        }

        hasMorePages = posts.count > 12 || !upcoming.isEmpty
        SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
        #if DEBUG
        let unviewedAhead = posts.dropFirst(activeIndex + 1)
            .filter { !SparkDiscoveryEngine.isViewed($0) }.count
        print("[Sparks] player queue size=\(posts.count) live=\(keepID.prefix(8)) unviewedAhead=\(unviewedAhead)")
        #endif
    }

    /// Replace the swipe queue without animation (keeps current page under the finger).
    /// Never falls back to index 0 when preserve is missing — that was the “jump to entry” bug.
    private func replacePlayerQueue(_ feed: [CountryPost], preserveID: String) {
        guard !feed.isEmpty else { return }
        // Prefer the clip the user is watching *now* over a stale preserveID.
        let liveID = posts.indices.contains(activeIndex) ? posts[activeIndex].id : preserveID
        let targetID = feed.contains(where: { $0.id == liveID }) ? liveID
            : (feed.contains(where: { $0.id == preserveID }) ? preserveID : feed[0].id)
        let newIndex = feed.firstIndex(where: { $0.id == targetID }) ?? 0
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            posts = feed
            activeIndex = newIndex
        }
    }

    /// Append only — **never** mutates `activeIndex` (append cannot change the focused clip).
    private func applyExpandedFeed(_ feed: [CountryPost], preserveID: String = "") {
        var seen = Set(posts.map(\.id))
        var appended: [CountryPost] = []
        let hasUnviewedIncoming = feed.contains {
            !seen.contains($0.id) && !SparkDiscoveryEngine.isViewed($0)
        }
        for p in feed where seen.insert(p.id).inserted {
            if !preserveID.isEmpty {
                guard ReelsRankingEngine.isSparkEligible(p) || p.id == preserveID else { continue }
            } else {
                guard ReelsRankingEngine.isSparkEligible(p) || p.hasVideo || p.playableVideoURL != nil
                else { continue }
            }
            // Skip already-viewed while we still have unviewed candidates in this batch.
            if hasUnviewedIncoming, SparkDiscoveryEngine.isViewed(p), p.id != preserveID {
                continue
            }
            appended.append(p)
        }
        guard !appended.isEmpty else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            posts.append(contentsOf: appended)
            // Do NOT reassign activeIndex — even to the same id's index. Stale preserveIDs
            // from network start were snapping the user back to the entry spark.
        }
    }

    private func loadMoreReels() async {
        if isExpandingFeed {
            loadMoreQueued = true
            return
        }
        isExpandingFeed = true
        defer {
            isExpandingFeed = false
            if loadMoreQueued {
                loadMoreQueued = false
                Task { await loadMoreReels() }
            }
        }

        let existingIDs = Set(posts.map(\.id))
        let tail = Array(posts.suffix(8))
        let bulk = SparksQueueBudget.bulkBatchSize

        // Parallel bulk sources — catalog + random library sample at once.
        async let catalogTask = PostsService.shared.loadSparksDiscoveryCatalog(
            forceRefresh: false,
            deep: true
        )
        async let discoverTask = PostsService.shared.fetchDiscoverSparks(
            limit: min(120, bulk + 20),
            excluding: Array(existingIDs) + SparkDiscoveryEngine.viewedIDList(limit: 500)
        )
        let catalog = await catalogTask
        let discover = await discoverTask

        // Prefer unviewed catalog + random DB sample — never re-queue watched Sparks first.
        let remaining = SparkDiscoveryEngine.rankForDiscovery(
            (catalog + discover).filter {
                !existingIDs.contains($0.id) && ReelsRankingEngine.isSparkEligible($0)
            }
        )
        if !remaining.isEmpty {
            let batch = Array(remaining.prefix(bulk))
            applyExpandedFeed(batch)
            hasMorePages = true
            SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
            return
        }

        // Second remote bulk if catalog was empty of unviewed — don't over-exclude viewed.
        let more = await PostsService.shared.fetchDiscoverSparks(
            limit: min(120, bulk + 20),
            excluding: Array(existingIDs.prefix(400))
        )
        if !more.isEmpty {
            let before = posts.count
            applyExpandedFeed(SparkDiscoveryEngine.rankForDiscovery(more, excluding: existingIDs))
            if posts.count > before {
                hasMorePages = true
                SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
                return
            }
        }

        // New IDs not already in the player queue (may include viewed for endless).
        let fromCatalog = ReelsRankingEngine.nextBatch(
            from: catalog,
            excluding: existingIDs,
            limit: bulk,
            viewerCountry: appState.currentProfile?.countryCode,
            followingIDs: appState.followingIDs,
            tail: tail,
            allowRecycle: true
        )
        if !fromCatalog.isEmpty {
            let before = posts.count
            applyExpandedFeed(ReelsRankingEngine.sessionFreshOrder(fromCatalog))
            if posts.count > before {
                hasMorePages = true
                SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
                return
            }
        }

        // Fast endless path: library already absorbed into the queue — rotate, don't stall on network.
        if posts.count >= 12 {
            recyclePass += 1
            let recentOnly = Set(posts.suffix(20).map(\.id))
            let pool: [CountryPost]
            if catalog.isEmpty {
                pool = await PostsService.shared.loadSparksDiscoveryCatalog(
                    forceRefresh: recyclePass % 3 == 1,
                    deep: true
                )
            } else {
                pool = catalog
            }
            let recycled = ReelsRankingEngine.nextBatch(
                from: pool,
                excluding: recentOnly,
                limit: bulk,
                viewerCountry: appState.currentProfile?.countryCode,
                followingIDs: appState.followingIDs,
                tail: tail,
                allowRecycle: true
            )
            if !recycled.isEmpty {
                rotateInRecycled(recycled)
            } else {
                rotateQueueForEndless()
            }
            SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
            hasMorePages = true
            return
        }

        // Thin /v1/sparks first (light pages) — GraphQL catalog only if empty.
        if let thin = await SurfacePageClient.fetchSparks(limit: min(bulk, 24), cursor: feedCursor),
           !thin.items.isEmpty {
            let fresh = thin.items.filter { !existingIDs.contains($0.id) }
            if !fresh.isEmpty {
                applyExpandedFeed(ReelsRankingEngine.sessionFreshOrder(fresh))
                feedCursor = thin.nextCursor ?? feedCursor
                hasMorePages = thin.nextCursor != nil || !fresh.isEmpty
                SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
                return
            }
        }

        let page = await PostsService.shared.loadReelsFeedPage(
            excludingIDs: existingIDs,
            cursor: feedCursor,
            batchSize: bulk / 2,
            fetchLimit: 80,
            viewerCountry: appState.currentProfile?.countryCode,
            followingIDs: appState.followingIDs,
            tail: tail,
            allowRecycle: true
        )

        if !page.posts.isEmpty {
            applyExpandedFeed(ReelsRankingEngine.sessionFreshOrder(page.posts))
            feedCursor = page.nextCursor ?? feedCursor
            hasMorePages = true
            SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
            return
        }

        recyclePass += 1
        rotateQueueForEndless()
        hasMorePages = true
    }

    /// Re-queue clips that are already in the player list by moving them after the live page.
    /// `applyExpandedFeed` cannot append duplicate IDs — without this, endless scroll dies
    /// once the session has absorbed the library.
    private func rotateInRecycled(_ batch: [CountryPost]) {
        guard !batch.isEmpty, !posts.isEmpty else { return }
        let liveID = posts.indices.contains(activeIndex) ? posts[activeIndex].id : posts[0].id
        let liveIndex = posts.firstIndex(where: { $0.id == liveID }) ?? activeIndex
        let live = posts[liveIndex]
        let recycleIDs = Set(batch.map(\.id))
        // Pull recycle targets out of history so they can reappear after live (no dup IDs).
        var history = Array(posts.prefix(liveIndex)).filter { !recycleIDs.contains($0.id) }
        history.append(live)
        var seen = Set(history.map(\.id))
        var upcoming: [CountryPost] = []
        for p in posts.dropFirst(liveIndex + 1) where !recycleIDs.contains(p.id) && seen.insert(p.id).inserted {
            upcoming.append(p)
        }
        for p in batch where p.id != liveID && seen.insert(p.id).inserted {
            upcoming.append(p)
        }
        // If still thin, pull from far-behind history (not recent 8).
        if upcoming.count < 12, liveIndex > 10 {
            let far = Array(posts.prefix(max(0, liveIndex - 8)))
            for p in far.shuffled() where p.id != liveID && seen.insert(p.id).inserted {
                upcoming.append(p)
                if upcoming.count >= SparksQueueBudget.bulkBatchSize { break }
            }
        }
        guard upcoming.count >= 4 else {
            rotateQueueForEndless()
            return
        }
        replacePlayerQueue(history + upcoming, preserveID: liveID)
    }

    /// Always-on endless: move far-behind pages to the tail (TikTok-style loop).
    private func rotateQueueForEndless() {
        guard posts.count >= 8 else { return }
        let liveID = posts.indices.contains(activeIndex) ? posts[activeIndex].id : posts[0].id
        let liveIndex = posts.firstIndex(where: { $0.id == liveID }) ?? activeIndex
        let keepBehind = 3
        let dropCount = max(0, liveIndex - keepBehind)
        if dropCount >= 4 {
            let moved = Array(posts.prefix(dropCount)).shuffled()
            let keep = Array(posts.dropFirst(dropCount))
            replacePlayerQueue(keep + moved, preserveID: liveID)
            return
        }
        // Not enough history — reshuffle everything after live + prepend shuffled catalog tail.
        let history = Array(posts.prefix(liveIndex + 1))
        var rest = Array(posts.dropFirst(liveIndex + 1))
        if rest.count < 6 {
            rest.append(contentsOf: history.dropLast().shuffled().prefix(20))
        }
        rest.shuffle()
        // Dedupe preserving order.
        var seen = Set(history.map(\.id))
        var upcoming: [CountryPost] = []
        for p in rest where seen.insert(p.id).inserted {
            upcoming.append(p)
        }
        guard !upcoming.isEmpty else { return }
        replacePlayerQueue(history + upcoming, preserveID: liveID)
    }

    private func loadEarlierReels() async {
        guard !isExpandingFeed, let first = posts.first else { return }
        isExpandingFeed = true
        defer { isExpandingFeed = false }

        // Capture the live clip *before* network so a mid-flight swipe still maps correctly.
        let liveID = posts.indices.contains(activeIndex) ? posts[activeIndex].id : first.id

        let prepend = await PostsService.shared.loadReelsNewerBatch(
            than: first.createdAt,
            excludingIDs: Set(posts.map(\.id)),
            batchSize: 8,
            viewerCountry: appState.currentProfile?.countryCode,
            followingIDs: appState.followingIDs,
            head: Array(posts.prefix(4))
        )
        if !prepend.isEmpty {
            prependKeepingFocus(prepend, liveID: liveID)
            return
        }

        // No newer sparks yet — recycle from the tail so scrolling backward stays endless.
        let recycled = await PostsService.shared.loadReelsFeedPage(
            excludingIDs: Set(posts.map(\.id)),
            cursor: nil,
            batchSize: 10,
            fetchLimit: 64,
            viewerCountry: appState.currentProfile?.countryCode,
            followingIDs: appState.followingIDs,
            tail: Array(posts.prefix(4)),
            allowRecycle: true
        )
        if !recycled.posts.isEmpty {
            prependKeepingFocus(recycled.posts, liveID: liveID)
        }
    }

    /// Prepend + retarget `activeIndex` to the same post id in one transaction.
    /// Split updates (posts then index) briefly pointed activeIndex at the wrong clip
    /// and the pager scrolled to the entry spark.
    private func prependKeepingFocus(_ batch: [CountryPost], liveID: String) {
        guard !batch.isEmpty else { return }
        // Re-read live id in case the user swiped during the network call.
        let focusID = posts.indices.contains(activeIndex) ? posts[activeIndex].id : liveID
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            posts.insert(contentsOf: batch, at: 0)
            if let idx = posts.firstIndex(where: { $0.id == focusID }) {
                activeIndex = idx
            } else {
                // Should not happen (focus was already in the list) — clamp, never force 0.
                activeIndex = min(activeIndex + batch.count, max(0, posts.count - 1))
            }
        }
        SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
    }
}

private func copyPost(_ post: CountryPost, likedByMe: Bool, likeCount: Int) -> CountryPost {
    CountryPost(
        id: post.id, title: post.title, body: post.body,
        mediaType: post.mediaType, mediaURL: post.mediaURL, thumbURL: post.thumbURL,
        mediaCaption: post.mediaCaption, sharedPostID: post.sharedPostID,
        visibility: post.visibility, likeCount: likeCount, commentCount: post.commentCount,
        viewCount: post.viewCount, likedByMe: likedByMe, savedByMe: post.savedByMe,
        createdAt: post.createdAt, updatedAt: post.updatedAt,
        authorID: post.authorID, countryName: post.countryName,
        countryCode: post.countryCode, cityName: post.cityName, author: post.author
    )
}