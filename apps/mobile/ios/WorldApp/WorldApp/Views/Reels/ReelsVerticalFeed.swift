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
                onOpenPost: { post in openPost(post) }
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
            MediaPlaybackCoordinator.shared.silenceForSparkPageChange()
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
        SparkDiscoveryEngine.markWatched(post.id)
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
        let s = max(0, Int(seconds.rounded(.down)))
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
    /// Start as fill (most Sparks are vertical + covers notch); may drop to fit for wide clips.
    @State private var useFill = true

    /// Single restart token — active + parent generation in the same render (no double play).
    private var restartFromBeginningToken: UInt {
        isActive ? max(1, focusGeneration) : 0
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
        useFill = SparksStageLayout.shouldFillWithoutCrop(
            videoSize: size,
            stageSize: SparksStageLayout.physicalScreenSize
        )
        gravityLocked = true
    }

    var body: some View {
        ZStack {
            // Film fills the page; chrome floats on top (YouTube Shorts / TikTok).
            filmStage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    pendingSingleTap?.cancel()
                    keepPlayingThroughUIAction()
                    triggerLike(fromButton: false)
                }
                .onTapGesture(count: 1) {
                    handleSingleTapPause()
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        // Film + chrome draw under the Dynamic Island; top chrome is overlaid separately.
        .ignoresSafeArea(.all)
        .overlay(alignment: .bottom) {
            sparkDock
                .padding(.horizontal, 12)
                .padding(.bottom, max(10, bottomInset - 4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.62), value: showLikeBurst)
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
            videoNaturalSize = .zero
            gravityLocked = false
            useFill = true
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

    /// Full-stage under the notch. Portrait fills; wide clips fit when fill would crop hard.
    private var filmStage: some View {
        ZStack {
            Color.black

            if let poster = post.posterImageURL {
                CachedAsyncImage(
                    url: poster,
                    maxPixelSize: 900,
                    contentMode: useFill ? .fill : .fit,
                    placeholder: AnyView(Color.black)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .allowsHitTesting(false)
            }

            if let url = sparkPlayURL {
                Group {
                    if ArchiveVideoPlayback.isArchiveURL(url) || post.isHubSeedVideo {
                        ArchiveVideoPlayerView(
                            url: url,
                            posterURL: post.posterImageURL,
                            isActive: isActive,
                            muted: false,
                            startTime: 0,
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
                            posterURL: post.posterImageURL,
                            placement: "reel",
                            countryCode: post.countryCode,
                            contentCountryCode: post.countryCode,
                            postID: post.id,
                            isActive: isActive,
                            loops: true,
                            muted: false,
                            showsControls: false,
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

            // Horizontal action ribbon — compact glass chips.
            // Never pause the Spark for Like / Chat / Keep / Send.
            HStack(spacing: 5) {
                sparkAction(
                    icon: post.likedByMe ? "heart.fill" : "heart",
                    label: post.likeCount > 0 ? "\(post.likeCount)" : "Like",
                    accent: post.likedByMe ? Theme.like : Theme.paper,
                    scale: likeButtonScale
                ) {
                    keepPlayingThroughUIAction()
                    triggerLike(fromButton: true)
                }
                sparkAction(
                    icon: "bubble.right",
                    label: post.commentCount > 0 ? "\(post.commentCount)" : "Chat",
                    accent: Theme.paper
                ) {
                    keepPlayingThroughUIAction()
                    // Warm thread *before* the sheet paints so comments are already there.
                    CommentsWarmCache.shared.warm(post.id)
                    onOpenComments()
                    reassertPlayback()
                }
                sparkAction(
                    icon: appState.isPostSaved(post.id) ? "bookmark.fill" : "bookmark",
                    label: "Keep",
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
                    // Overlay share — do not pause or dismiss the Spark.
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
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 10)
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
        .shadow(color: Theme.ink.opacity(0.18), radius: 14, y: 6)
    }

    private func sparkAction(
        icon: String,
        label: String,
        accent: Color,
        scale: CGFloat = 1,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .scaleEffect(scale)
                Text(label)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Theme.paper.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(Theme.paper.opacity(0.14), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    /// Update Sparks timeline from AVPlayer ticks.
    /// Safe to call from a preloaded (inactive) time-observer closure — @State storage is shared.
    private func applyTimelineProgress(current: Double, duration: Double) {
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
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                showLikeBurst = true
                likeButtonScale = 1.22
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.easeOut(duration: 0.2)) {
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
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
        // Fade dimmer + drop sheet together — no residual black veil on the Spark.
        withAnimation(.easeOut(duration: 0.2)) {
            dragOffset = max(dragOffset, UIScreen.main.bounds.height * 0.55)
            dimOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onClose()
        }
    }
}

/// Top chrome: close (X) top-leading + “SPARKS” centered — same row, just under the notch.
/// Sized to chrome only (not full-screen) so vertical paging is free on the rest of the stage.
private struct SparksTopChrome: View {
    let onClose: () -> Void
    private let word = MatteryaCopy.sparks.uppercased()

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
            }
        }
        .frame(height: 44)
        .padding(.horizontal, Theme.pagePadding - 4)
        .padding(.top, Self.notchInset + 2)
        .frame(maxWidth: .infinity)
        // Height = notch + bar only — never expand to full screen (that blocked first swipe).
        .allowsHitTesting(true)
        .ignoresSafeArea(edges: .top)
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

    /// How many unplayed pages we always try to keep ahead of the focused Spark.
    private static let minQueueAhead = 28
    /// Catalog bulk size per load-more (R2 library is large — fetch in chunks).
    private static let bulkBatchSize = 80

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
                    }
                )
            }

            SparksTopChrome(onClose: { dismiss() })
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
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: appState.sharePostSheet?.id)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: commentsPostID)
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
            // 1) Warm the head *before* catalog churn so the first swipes aren't cold.
            SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
            if posts.indices.contains(activeIndex) {
                CommentsWarmCache.shared.warm(posts[activeIndex].id)
            }
            let headIDs = Array(posts.dropFirst(activeIndex).prefix(SparkWarmPool.deepPrerollAhead).map(\.id))
            await SparkWarmPool.shared.awaitReady(postIDs: headIDs, timeout: 1.8)

            // 2) Grow the queue without remounting the live head (append-only).
            seedFromWarmCatalogIfNeeded()
            SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
            await SparkWarmPool.shared.awaitReady(
                postIDs: Array(posts.dropFirst(activeIndex).prefix(6).map(\.id)),
                timeout: 1.2
            )

            // 3) Deep catalog — append unseen only (full replace remounted first pages → glitch).
            await expandFeed()
            SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)

            // 4) Top up until we have a full bulk ahead — scroll must never wait on network.
            await ensureBulkQueueAhead(target: Self.minQueueAhead)
            SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
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

    /// Keep at least `target` unplayed Sparks after the focused index.
    private func ensureBulkQueueAhead(target: Int = Self.minQueueAhead) async {
        var guardPasses = 0
        while guardPasses < 4 {
            guardPasses += 1
            let remaining = max(0, posts.count - activeIndex - 1)
            guard remaining < target else { return }
            let before = posts.count
            await loadMoreReels()
            if posts.count <= before { return }
            SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
        }
    }

    /// Instant neighbors from memory — **unviewed discovery order**, append only.
    private func seedFromWarmCatalogIfNeeded() {
        guard posts.count < Self.minQueueAhead else { return }
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

        // Full discovery session: unviewed first + random library samples.
        let fresh = await PostsService.shared.beginFreshSparksSession(preferStart: rankingAnchor)

        // Re-read live id after await (swipe during load).
        let keepID = posts.indices.contains(activeIndex)
            ? posts[activeIndex].id
            : liveID
        let liveIndex = posts.firstIndex(where: { $0.id == keepID }) ?? activeIndex

        // Keep only what the user already swiped + current clip (no jump).
        // Replace **upcoming** with the discovery queue — previously we only *appended*
        // after a sticky seed, so the algorithm never drove the next swipes.
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
            .filter { !SparkDiscoveryEngine.isViewed($0.id) }.count
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
            !seen.contains($0.id) && !SparkDiscoveryEngine.isViewed($0.id)
        }
        for p in feed where seen.insert(p.id).inserted {
            if !preserveID.isEmpty {
                guard ReelsRankingEngine.isSparkEligible(p) || p.id == preserveID else { continue }
            } else {
                guard ReelsRankingEngine.isSparkEligible(p) || p.hasVideo || p.playableVideoURL != nil
                else { continue }
            }
            // Skip already-viewed while we still have unviewed candidates in this batch.
            if hasUnviewedIncoming, SparkDiscoveryEngine.isViewed(p.id), p.id != preserveID {
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
        let bulk = Self.bulkBatchSize

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
            hasMorePages = remaining.count > batch.count || !discover.isEmpty
            SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
            return
        }

        // Second remote bulk if catalog was empty of unviewed.
        let more = await PostsService.shared.fetchDiscoverSparks(
            limit: min(120, bulk + 20),
            excluding: Array(existingIDs) + SparkDiscoveryEngine.viewedIDList(limit: 600)
        )
        if !more.isEmpty {
            applyExpandedFeed(SparkDiscoveryEngine.rankForDiscovery(more, excluding: existingIDs))
            hasMorePages = true
            SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
            return
        }

        let fromCatalog = ReelsRankingEngine.nextBatch(
            from: catalog,
            excluding: existingIDs,
            limit: bulk,
            viewerCountry: appState.currentProfile?.countryCode,
            followingIDs: appState.followingIDs,
            tail: tail,
            // Only after unviewed catalog + discoverSparks are empty.
            allowRecycle: recyclePass > 2
        )
        if !fromCatalog.isEmpty {
            applyExpandedFeed(ReelsRankingEngine.sessionFreshOrder(fromCatalog))
            hasMorePages = true
            SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
            return
        }

        let page = await PostsService.shared.loadReelsFeedPage(
            excludingIDs: existingIDs,
            cursor: feedCursor,
            batchSize: bulk / 2,
            fetchLimit: 120,
            viewerCountry: appState.currentProfile?.countryCode,
            followingIDs: appState.followingIDs,
            tail: tail,
            allowRecycle: recyclePass > 0
        )

        if !page.posts.isEmpty {
            applyExpandedFeed(ReelsRankingEngine.sessionFreshOrder(page.posts))
            feedCursor = page.nextCursor ?? feedCursor
            hasMorePages = page.hasMore
            SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
            return
        }

        if hasMorePages, let feedCursor, feedCursor != page.nextCursor {
            let retry = await PostsService.shared.loadReelsFeedPage(
                excludingIDs: Set(posts.map(\.id)),
                cursor: page.nextCursor ?? feedCursor,
                batchSize: bulk / 2,
                fetchLimit: 120,
                viewerCountry: appState.currentProfile?.countryCode,
                followingIDs: appState.followingIDs,
                tail: tail,
                allowRecycle: false
            )
            if !retry.posts.isEmpty {
                applyExpandedFeed(retry.posts)
                SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
            }
            self.feedCursor = retry.nextCursor
            hasMorePages = retry.hasMore
            if !retry.posts.isEmpty { return }
        }

        guard recyclePass < 6 else { return }
        recyclePass += 1
        // Last resort: reshuffle discovery + allow recycle of watched (not current list).
        PostsService.shared.invalidateSparksDiscoveryCatalog()
        let reshuffled = await PostsService.shared.loadSparksDiscoveryCatalog(forceRefresh: true, deep: true)
        let recycled = ReelsRankingEngine.nextBatch(
            from: reshuffled,
            excluding: Set(posts.map(\.id)),
            limit: bulk,
            viewerCountry: appState.currentProfile?.countryCode,
            followingIDs: appState.followingIDs,
            tail: tail,
            allowRecycle: true
        )
        if !recycled.isEmpty {
            applyExpandedFeed(recycled)
            SparkWarmPool.shared.preparePlayerWindow(posts: posts, around: activeIndex)
        }
        hasMorePages = true
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