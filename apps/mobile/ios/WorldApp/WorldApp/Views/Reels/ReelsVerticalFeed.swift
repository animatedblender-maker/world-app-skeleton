import SwiftUI
import UIKit

private enum ReelsHaptics {
    /// Intentional like only — never fire on scroll/snap (Instagram-style silent paging).
    static func like() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
    }
}

struct ReelsVerticalFeed: View {
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

    @State private var scrollPosition: Int?
    @State private var isNormalizingLoop = false

    private var usesInfiniteLoop: Bool { posts.count > 1 }

    private var loopedPosts: [CountryPost] {
        guard usesInfiniteLoop else { return posts }
        return posts + posts + posts
    }

    private func realIndex(from loopIndex: Int) -> Int {
        guard usesInfiniteLoop else { return loopIndex }
        let count = posts.count
        return ((loopIndex % count) + count) % count
    }

    private func loopIndex(for realIndex: Int) -> Int {
        guard usesInfiniteLoop else { return realIndex }
        return posts.count + realIndex
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(loopedPosts.enumerated()), id: \.offset) { index, post in
                            // CRITICAL: only the *visible loop page* is active.
                            // Do NOT use realIndex — the infinite triple-copy would mark
                            // three cards active at once and stack audio.
                            ReelsPagerCard(
                                post: post,
                                isActive: (scrollPosition ?? loopIndex(for: activeIndex)) == index,
                                bottomInset: bottomInset,
                                showsOpenPostAction: showsOpenPostAction,
                                viewerCountryCode: viewerCountryCode,
                                onLikeToggle: { Task { await toggleLike(post) } },
                                onOpenPost: { openPost(post) },
                                onOpenComments: { onOpenComments?(post.id) }
                            )
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollBounceBehavior(.basedOnSize)
                .scrollDisabled(!isScrollEnabled)
                .scrollPosition(id: $scrollPosition)
                // Instant page identity — no springy settle animation between Sparks.
                .animation(nil, value: scrollPosition)
                .onChange(of: scrollPosition) { _, newValue in
                    guard let newValue, !isNormalizingLoop else { return }
                    let resolved = realIndex(from: newValue)
                    guard resolved != activeIndex else {
                        // Loop wrap only — don't silence the same clip that's still active.
                        normalizeLoopPosition(newValue)
                        return
                    }
                    // Hard-silence every player (prev page + warm pool) before the next card solos.
                    MediaPlaybackCoordinator.shared.silenceForSparkPageChange()
                    activeIndex = resolved
                    // Simple vertical paging — no world-hop / passport chrome.
                    recordView(at: resolved)
                    prefetchIfNeeded(at: resolved)
                    warmNeighbors(at: resolved)
                    normalizeLoopPosition(newValue)
                }
                .onChange(of: activeIndex) { _, newValue in
                    let target = loopIndex(for: newValue)
                    if scrollPosition != target {
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) { scrollPosition = target }
                    }
                    prefetchIfNeeded(at: newValue)
                    warmNeighbors(at: newValue)
                }
                .onChange(of: posts.count) { _, _ in
                    syncLoopScrollPosition()
                    warmNeighbors(at: activeIndex)
                }
                .onAppear {
                    if scrollPosition == nil {
                        scrollPosition = loopIndex(for: activeIndex)
                    }
                    // Kill feed / hubs audio only — keep warm pool so the first swipe is ready.
                    MediaPlaybackCoordinator.shared.pauseAll()
                    recordView(at: activeIndex)
                    prefetchIfNeeded(at: activeIndex)
                    warmNeighbors(at: activeIndex)
                }
                .onDisappear {
                    MediaPlaybackCoordinator.shared.stopAllPlayback()
                    SparkWarmPool.shared.drain()
                }

                if showsProgressRail, posts.count > 1 {
                    ReelsProgressRail(
                        posts: posts,
                        activeIndex: activeIndex,
                        viewerCountryCode: viewerCountryCode
                    )
                    .safeAreaPadding(.top, 6)
                    .padding(.horizontal, 16)
                }
            }
        }
        .ignoresSafeArea()
    }

    @Environment(AppState.self) private var appState

    private func openPost(_ post: CountryPost) {
        appState.reelsViewerContext = nil
        appState.openPostInFeed(postID: post.id)
    }

    private func normalizeLoopPosition(_ position: Int) {
        guard usesInfiniteLoop else { return }
        let span = posts.count
        let adjusted: Int?
        if position < span {
            adjusted = position + span
        } else if position >= span * 2 {
            adjusted = position - span
        } else {
            adjusted = nil
        }
        guard let adjusted, scrollPosition != adjusted else { return }
        isNormalizingLoop = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollPosition = adjusted
        }
        Task { @MainActor in
            isNormalizingLoop = false
        }
    }

    private func syncLoopScrollPosition() {
        guard usesInfiniteLoop else {
            scrollPosition = activeIndex
            return
        }
        let target = loopIndex(for: activeIndex)
        guard scrollPosition != target else { return }
        isNormalizingLoop = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollPosition = target
        }
        Task { @MainActor in
            isNormalizingLoop = false
        }
    }

    private func prefetchIfNeeded(at index: Int) {
        if index >= max(0, posts.count - 5) {
            onNearEnd?()
        }
        if index <= 2 {
            onNearStart?()
        }
    }

    /// Buffer next/prev Sparks before the finger lifts (Instagram-depth warm window).
    private func warmNeighbors(at index: Int) {
        SparkWarmPool.shared.prepare(posts: posts, around: index, ahead: 4, behind: 1)
    }

    private func recordView(at index: Int) {
        guard posts.indices.contains(index) else { return }
        let post = posts[index]
        ReelsRankingEngine.markWatched(post.id)
        Task { await PostsService.shared.recordView(post) }
    }

    private func toggleLike(_ post: CountryPost) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        do {
            if post.likedByMe {
                try await PostsService.shared.unlikePost(post.id)
                posts[index] = copyPost(post, likedByMe: false, likeCount: max(0, post.likeCount - 1))
            } else {
                try await PostsService.shared.likePost(post.id)
                posts[index] = copyPost(post, likedByMe: true, likeCount: post.likeCount + 1)
            }
        } catch {
            // Keep the scroll loop smooth.
        }
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

/// Matterya Sparks progress — warm ink trail inside the paper dock (not a Shorts bar).
private struct SparksTimelineBar: View {
    let currentSeconds: Double
    let durationSeconds: Double
    @Binding var isScrubbing: Bool
    let onSeek: (Double) -> Void

    @State private var dragFraction: Double = 0

    private var fraction: Double {
        guard durationSeconds > 0.35 else { return 0 }
        if isScrubbing { return min(1, max(0, dragFraction)) }
        return min(1, max(0, currentSeconds / durationSeconds))
    }

    private var timeLabel: String {
        guard durationSeconds > 0.35 else { return "" }
        let t = isScrubbing ? dragFraction * durationSeconds : currentSeconds
        return "\(formatClock(t)) · \(formatClock(durationSeconds))"
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if isScrubbing, durationSeconds > 0.35 {
                Text(timeLabel)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.ink.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity)
            }

            GeometryReader { geo in
                let trackH: CGFloat = isScrubbing ? 4 : 2
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.ink.opacity(0.10))
                        .frame(height: trackH)
                    Capsule()
                        .fill(Theme.accentBright)
                        .frame(width: max(trackH, geo.size.width * fraction), height: trackH)
                    if isScrubbing {
                        Circle()
                            .fill(Theme.paper)
                            .overlay(Circle().stroke(Theme.accentBright, lineWidth: 1.5))
                            .frame(width: 14, height: 14)
                            .shadow(color: Theme.ink.opacity(0.18), radius: 3, y: 1)
                            .offset(x: max(0, geo.size.width * fraction - 7))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            let w = max(geo.size.width, 1)
                            if !isScrubbing {
                                let dx = abs(value.translation.width)
                                let dy = abs(value.translation.height)
                                if dy > 12, dy > dx * 1.15 { return }
                            }
                            isScrubbing = true
                            dragFraction = min(1, max(0, value.location.x / w))
                        }
                        .onEnded { value in
                            let w = max(geo.size.width, 1)
                            let f = min(1, max(0, value.location.x / w))
                            dragFraction = f
                            if durationSeconds > 0.35 {
                                onSeek(f * durationSeconds)
                            }
                            withAnimation(.easeOut(duration: 0.15)) {
                                isScrubbing = false
                            }
                        }
                )
            }
            .frame(height: 22)
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
    @State private var showLikeBurst = false
    @State private var likeButtonScale: CGFloat = 1
    @State private var lastTapTime: Date = .distantPast
    @State private var pendingSingleTap: DispatchWorkItem?
    /// Sparks timeline (YouTube Shorts–style bottom scrubber).
    @State private var progressSeconds: Double = 0
    @State private var durationSeconds: Double = 0
    @State private var seekToSeconds: Double? = nil
    @State private var isScrubbingTimeline = false

    var body: some View {
        ZStack {
            // Film stage
            Theme.ink.ignoresSafeArea()

            if let url = post.playableVideoURL {
                Group {
                    if ArchiveVideoPlayback.isArchiveURL(url) || post.isHubSeedVideo {
                        ArchiveVideoPlayerView(
                            url: url,
                            posterURL: post.posterImageURL,
                            isActive: isActive && !isPaused,
                            muted: false,
                            startTime: 0,
                            loops: true,
                            fillsFrame: true,
                            postID: post.id,
                            onReady: { Task { await PostsService.shared.recordView(post) } },
                            onProgress: { current, duration in
                                guard isActive, !isScrubbingTimeline else { return }
                                progressSeconds = current
                                if duration > 0.25 { durationSeconds = duration }
                            },
                            seekToSeconds: seekToSeconds,
                            onSeekConsumed: { seekToSeconds = nil }
                        )
                    } else {
                        VideoPlayerView(
                            url: url,
                            posterURL: post.posterImageURL,
                            placement: "reel",
                            countryCode: post.countryCode,
                            contentCountryCode: post.countryCode,
                            postID: post.id,
                            isActive: isActive && !isPaused,
                            loops: true,
                            muted: false,
                            showsControls: false,
                            fillsFrame: true,
                            onViewed: { Task { await PostsService.shared.recordView(post) } },
                            onProgress: { current, duration in
                                guard isActive, !isScrubbingTimeline else { return }
                                progressSeconds = current
                                if duration > 0.25 { durationSeconds = duration }
                            },
                            seekToSeconds: seekToSeconds,
                            onSeekConsumed: { seekToSeconds = nil }
                        )
                    }
                }
                .ignoresSafeArea()
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Theme.paper.opacity(0.45))
                    Text("Spark unavailable")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Theme.paper.opacity(0.55))
                }
            }

            // Soft vignette — journal light, not IG black fade.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Theme.ink.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 88)
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [.clear, Theme.ink.opacity(0.55), Theme.ink.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 280)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { handleTap() }

            // Center pause — paper seal (not a big white play glyph).
            if isPaused {
                ZStack {
                    Circle()
                        .fill(Theme.paper.opacity(0.94))
                        .frame(width: 72, height: 72)
                        .shadow(color: Theme.ink.opacity(0.28), radius: 16, y: 6)
                    Image(systemName: "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.accentBright)
                        .offset(x: 2)
                }
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }

            if showLikeBurst {
                Image(systemName: "heart.fill")
                    .font(.system(size: 96, weight: .bold))
                    .foregroundStyle(Theme.like)
                    .shadow(color: Theme.ink.opacity(0.25), radius: 12)
                    .scaleEffect(showLikeBurst ? 1 : 0.55)
                    .opacity(showLikeBurst ? 0.95 : 0)
                    .allowsHitTesting(false)
            }

            // ── Matterya Spark dock (unique layout: paper card + horizontal actions) ──
            VStack(spacing: 0) {
                // Top mark — brand whisper, not a TikTok header.
                HStack {
                    Spacer(minLength: 0)
                    Text(MatteryaCopy.sparks.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(2.4)
                        .foregroundStyle(Theme.paper.opacity(0.72))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.ink.opacity(0.28), in: Capsule())
                        .overlay(Capsule().stroke(Theme.paper.opacity(0.12), lineWidth: 0.5))
                    Spacer(minLength: 0)
                }
                .padding(.top, 10)
                .allowsHitTesting(false)

                Spacer(minLength: 0)

                sparkDock
                    .padding(.horizontal, 14)
                    .padding(.bottom, max(12, bottomInset))
            }
            .zIndex(10)

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
        .animation(.easeOut(duration: 0.16), value: isPaused)
        .animation(.spring(response: 0.34, dampingFraction: 0.62), value: showLikeBurst)
        .onChange(of: isActive) { _, active in
            if !active {
                isPaused = false
                pendingSingleTap?.cancel()
                progressSeconds = 0
                durationSeconds = 0
                seekToSeconds = nil
                isScrubbingTimeline = false
            }
        }
        .onChange(of: post.id) { _, _ in
            progressSeconds = 0
            durationSeconds = 0
            seekToSeconds = nil
            isScrubbingTimeline = false
        }
        .onDisappear {
            pendingSingleTap?.cancel()
            isPaused = false
        }
    }

    /// Bottom paper “journal card” — creator, caption, ribbon actions, ink progress.
    private var sparkDock: some View {
        VStack(alignment: .leading, spacing: 12) {
            authorRow

            if let text = post.sparkDisplayCaption, !text.isEmpty {
                Text(text)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Theme.ink.opacity(0.92))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if post.countryCode != nil || post.countryName != nil {
                    ReelsCountryChip(post: post, isHomeCountry: isHomeCountry) {
                        if let country = MatteryaCountryBridge.country(from: post) {
                            appState.openCountryReels(country)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            // Horizontal action ribbon — not a vertical Shorts rail.
            HStack(spacing: 6) {
                sparkAction(
                    icon: post.likedByMe ? "heart.fill" : "heart",
                    label: post.likeCount > 0 ? "\(post.likeCount)" : "Like",
                    accent: post.likedByMe ? Theme.like : Theme.ink,
                    scale: likeButtonScale
                ) {
                    triggerLike(fromButton: true)
                }
                sparkAction(
                    icon: "bubble.right",
                    label: post.commentCount > 0 ? "\(post.commentCount)" : "Chat",
                    accent: Theme.ink
                ) {
                    onOpenComments()
                }
                sparkAction(
                    icon: appState.isPostSaved(post.id) ? "bookmark.fill" : "bookmark",
                    label: "Keep",
                    accent: appState.isPostSaved(post.id) ? Theme.accentBright : Theme.ink
                ) {
                    Task { await toggleSave() }
                }
                sparkAction(
                    icon: "arrowshape.turn.up.right",
                    label: "Send",
                    accent: Theme.ink
                ) {
                    appState.presentShareSheet(for: post)
                }
                if showsOpenPostAction {
                    sparkAction(icon: "arrow.up.right", label: "Open", accent: Theme.ink, action: onOpenPost)
                }
            }

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
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.paper.opacity(0.94))
                .shadow(color: Theme.ink.opacity(0.22), radius: 20, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.border.opacity(0.65), lineWidth: 0.5)
        )
    }

    private func sparkAction(
        icon: String,
        label: String,
        accent: Color,
        scale: CGFloat = 1,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .scaleEffect(scale)
                Text(label)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Theme.canvasMuted.opacity(0.9), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func handleTap() {
        let now = Date()
        if now.timeIntervalSince(lastTapTime) < 0.3 {
            pendingSingleTap?.cancel()
            lastTapTime = .distantPast
            triggerLike(fromButton: false)
            return
        }

        lastTapTime = now
        pendingSingleTap?.cancel()
        let work = DispatchWorkItem {
            togglePause()
        }
        pendingSingleTap = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func togglePause() {
        withAnimation(.easeOut(duration: 0.12)) {
            isPaused.toggle()
        }
    }

    private func triggerLike(fromButton: Bool) {
        if fromButton || !post.likedByMe {
            onLikeToggle()
        }
        ReelsHaptics.like()
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

    private var authorRow: some View {
        HStack(spacing: 10) {
            Button {
                appState.openPublicProfile(username: post.author?.username, userID: post.authorID)
            } label: {
                HStack(spacing: 10) {
                    AvatarView(url: post.author?.avatarURL, seed: post.authorID, size: 40)
                        .overlay(Circle().stroke(Theme.border, lineWidth: 0.5))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(post.author?.displayName ?? "Member")
                            .font(.system(.subheadline, design: .serif).weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        if let handle = post.author?.username, !handle.isEmpty {
                            Text("@\(handle)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Theme.inkMuted)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 6)

            if post.authorID != appState.currentProfile?.userID, !post.authorID.isEmpty {
                FollowButton(userID: post.authorID, compact: true, onDark: false)
            }
        }
    }

    private func toggleSave() async {
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
        }
    }
}

private struct ReelsCommentTarget: Identifiable {
    let id: String
}

struct ReelsScrollViewer: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let context: ReelsViewerContext

    @State private var posts: [CountryPost]
    @State private var activeIndex = 0
    @State private var isExpandingFeed = false
    @State private var feedCursor: String?
    @State private var hasMorePages = true
    @State private var recyclePass = 0
    @State private var commentsPostID: String?

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
            .sheet(item: Binding(
                get: { commentsPostID.map(ReelsCommentTarget.init(id:)) },
                set: { commentsPostID = $0?.id }
            )) { target in
                NavigationStack {
                    PostCommentsPageView(postID: target.id)
                }
                .withAppState(appState)
            }
    }

    private var reelsContent: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if posts.isEmpty {
                ContentUnavailableView(
                    "No \(MatteryaCopy.sparks.lowercased())",
                    systemImage: "video.slash",
                    description: Text("This \(MatteryaCopy.spark.lowercased()) is no longer available.")
                )
            } else {
                // Simple vertical page scroll — no world-hop / passport / globe chrome.
                ReelsVerticalFeed(
                    posts: $posts,
                    activeIndex: $activeIndex,
                    bottomInset: 28,
                    showsOpenPostAction: false,
                    showsProgressRail: false,
                    viewerCountryCode: appState.currentProfile?.countryCode,
                    isScrollEnabled: true,
                    onNearEnd: { Task { await loadMoreReels() } },
                    onNearStart: { Task { await loadEarlierReels() } },
                    onOpenComments: { commentsPostID = $0 }
                )
            }

            // Close only — vertical swipe changes Sparks.
            ReelsChromeButton(systemName: "xmark", accessibilityLabel: "Close \(MatteryaCopy.sparks.lowercased())") {
                dismiss()
            }
            .safeAreaPadding(.top, 6)
            .padding(.leading, Theme.pagePadding)
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(item: Binding(
            get: { appState.sharePostSheet },
            set: { appState.sharePostSheet = $0 }
        )) { post in
            SharePostSheet(post: post)
                .withAppState(appState)
        }
        .task {
            ReelsRankingEngine.resetSession()
            SparkWarmPool.shared.prepare(posts: posts, around: activeIndex, ahead: 4, behind: 0)
            await expandFeed()
            SparkWarmPool.shared.prepare(posts: posts, around: activeIndex, ahead: 4, behind: 1)
        }
    }

    private func expandFeed() async {
        guard !isExpandingFeed else { return }
        isExpandingFeed = true
        defer { isExpandingFeed = false }

        feedCursor = nil
        hasMorePages = true
        recyclePass = 0

        // Keep the already-visible starting clip first so open stays snappy.
        var feed: [CountryPost] = posts
        var excluding = Set(feed.map(\.id))
        if !feed.contains(where: { $0.id == context.startingPostID }) {
            feed.insert(context.startingPost, at: 0)
            excluding.insert(context.startingPostID)
        }

        // Seed neighbors from open context (already ranked R2-first when possible).
        let seedReels = context.seedPosts.filter(ReelsRankingEngine.isSparkEligible)
        for reel in seedReels where excluding.insert(reel.id).inserted {
            feed.append(reel)
        }

        // 1) Network / R2 Sparks — light first page so open stays snappy; more loads on swipe.
        var cursor: String? = nil
        var attempts = 0
        while feed.count < 28, attempts < 3 {
            attempts += 1
            let page = await PostsService.shared.loadReelsFeedPage(
                excludingIDs: excluding,
                cursor: cursor,
                batchSize: 16,
                fetchLimit: 48,
                viewerCountry: appState.currentProfile?.countryCode,
                followingIDs: appState.followingIDs,
                tail: feed,
                allowRecycle: false
            )
            var added = 0
            for post in page.posts where excluding.insert(post.id).inserted {
                feed.append(post)
                added += 1
            }
            cursor = page.nextCursor
            feedCursor = page.nextCursor
            hasMorePages = page.hasMore
            if page.posts.isEmpty || added == 0 { break }
        }

        // 2) Archive last — only when AppConfig.archiveContentEnabled (else seed returns []).
        let r2Count = feed.filter(\.isR2HostedMedia).count
        if AppConfig.archiveContentEnabled, feed.count < 24 || r2Count < 12 {
            let shuffleSeed = UInt64.random(in: 1...UInt64.max)
                ^ UInt64(Date().timeIntervalSince1970 * 1_000)
            let archiveSparks = await HubVideoSeedService.shared.sparkSeedVideos(
                limit: 40,
                shuffleSeed: shuffleSeed
            )
            for post in archiveSparks where excluding.insert(post.id).inserted {
                guard ReelsRankingEngine.isSparkEligible(post) else { continue }
                feed.append(post)
                if feed.count >= 80 { break }
            }
        }

        if feed.count < 10 {
            let topUp = await PostsService.shared.loadReelsFeedPage(
                excludingIDs: Set(feed.map(\.id)),
                cursor: feedCursor,
                batchSize: 16,
                fetchLimit: 80,
                viewerCountry: appState.currentProfile?.countryCode,
                followingIDs: appState.followingIDs,
                tail: feed,
                allowRecycle: true
            )
            for post in topUp.posts where !feed.contains(where: { $0.id == post.id }) {
                feed.append(post)
            }
            feedCursor = topUp.nextCursor ?? feedCursor
            hasMorePages = topUp.hasMore
        }

        // Always reshuffle after start clip — no recommender yet, order must feel new every open.
        let previousID = posts.indices.contains(activeIndex) ? posts[activeIndex].id : context.startingPostID
        let start = feed.first(where: { $0.id == previousID }) ?? feed.first
        let rest = feed.filter { $0.id != start?.id }
        let ordered = (start.map { [$0] } ?? []) + ReelsRankingEngine.sessionFreshOrder(rest)
        posts = ordered
        activeIndex = posts.firstIndex(where: { $0.id == previousID }) ?? 0
        SparkWarmPool.shared.prepare(posts: posts, around: activeIndex, ahead: 4, behind: 1)
    }

    private func loadMoreReels() async {
        guard !isExpandingFeed else { return }
        isExpandingFeed = true
        defer { isExpandingFeed = false }

        let existingIDs = Set(posts.map(\.id))
        let tail = Array(posts.suffix(6))

        let page = await PostsService.shared.loadReelsFeedPage(
            excludingIDs: existingIDs,
            cursor: feedCursor,
            batchSize: 14,
            fetchLimit: 56,
            viewerCountry: appState.currentProfile?.countryCode,
            followingIDs: appState.followingIDs,
            tail: tail,
            allowRecycle: recyclePass > 0
        )

        if !page.posts.isEmpty {
            var batch: [CountryPost] = []
            for post in page.posts where !existingIDs.contains(post.id) {
                batch.append(post)
            }
            posts.append(contentsOf: ReelsRankingEngine.sessionFreshOrder(batch))
            feedCursor = page.nextCursor ?? feedCursor
            hasMorePages = page.hasMore
            return
        }

        if hasMorePages, let feedCursor, feedCursor != page.nextCursor {
            let retry = await PostsService.shared.loadReelsFeedPage(
                excludingIDs: Set(posts.map(\.id)),
                cursor: page.nextCursor ?? feedCursor,
                batchSize: 14,
                fetchLimit: 56,
                viewerCountry: appState.currentProfile?.countryCode,
                followingIDs: appState.followingIDs,
                tail: tail,
                allowRecycle: false
            )
            for post in retry.posts where !posts.contains(where: { $0.id == post.id }) {
                posts.append(post)
            }
            self.feedCursor = retry.nextCursor
            hasMorePages = retry.hasMore
            if !retry.posts.isEmpty { return }
        }

        guard recyclePass < 4 else { return }
        recyclePass += 1
        let recycled = await PostsService.shared.loadReelsFeedPage(
            excludingIDs: Set(posts.map(\.id)),
            cursor: nil,
            batchSize: 16,
            fetchLimit: 80,
            viewerCountry: appState.currentProfile?.countryCode,
            followingIDs: appState.followingIDs,
            tail: tail,
            allowRecycle: true
        )
        for post in recycled.posts where !posts.contains(where: { $0.id == post.id }) {
            posts.append(post)
        }
        feedCursor = recycled.nextCursor
        hasMorePages = true
    }

    private func loadEarlierReels() async {
        guard !isExpandingFeed, let first = posts.first else { return }
        isExpandingFeed = true
        defer { isExpandingFeed = false }

        let prepend = await PostsService.shared.loadReelsNewerBatch(
            than: first.createdAt,
            excludingIDs: Set(posts.map(\.id)),
            batchSize: 8,
            viewerCountry: appState.currentProfile?.countryCode,
            followingIDs: appState.followingIDs,
            head: Array(posts.prefix(4))
        )
        if !prepend.isEmpty {
            posts.insert(contentsOf: prepend, at: 0)
            activeIndex += prepend.count
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
            posts.insert(contentsOf: recycled.posts, at: 0)
            activeIndex += recycled.posts.count
        }
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