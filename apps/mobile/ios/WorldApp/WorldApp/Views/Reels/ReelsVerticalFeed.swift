import SwiftUI
import UIKit

private enum ReelsHaptics {
    static func snap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.85)
    }

    static func like() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 1)
    }

    static func pause() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
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
    var onCountryVisit: ((String?) -> Void)? = nil
    var onWorldHop: ((ReelsWorldHopMoment) -> Void)? = nil
    var onOpenComments: ((String) -> Void)? = nil

    @State private var scrollPosition: Int?
    @State private var lastCountryCode: String?
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
                            ReelsPagerCard(
                                post: post,
                                isActive: activeIndex == realIndex(from: index),
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
                .scrollDisabled(!isScrollEnabled)
                .scrollPosition(id: $scrollPosition)
                .onChange(of: scrollPosition) { _, newValue in
                    guard let newValue, !isNormalizingLoop else { return }
                    let resolved = realIndex(from: newValue)
                    guard resolved != activeIndex else {
                        normalizeLoopPosition(newValue)
                        return
                    }
                    let previousCode = posts.indices.contains(activeIndex)
                        ? posts[activeIndex].countryCode?.uppercased()
                        : lastCountryCode
                    activeIndex = resolved
                    ReelsHaptics.snap()
                    recordView(at: resolved)
                    prefetchIfNeeded(at: resolved)
                    announceCountryChange(at: resolved, previousCode: previousCode)
                    normalizeLoopPosition(newValue)
                }
                .onChange(of: activeIndex) { _, newValue in
                    let target = loopIndex(for: newValue)
                    if scrollPosition != target {
                        scrollPosition = target
                    }
                    prefetchIfNeeded(at: newValue)
                }
                .onChange(of: posts.count) { _, _ in
                    syncLoopScrollPosition()
                }
                .onAppear {
                    if scrollPosition == nil {
                        scrollPosition = loopIndex(for: activeIndex)
                    }
                    recordView(at: activeIndex)
                    prefetchIfNeeded(at: activeIndex)
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

    private func recordView(at index: Int) {
        guard posts.indices.contains(index) else { return }
        let post = posts[index]
        ReelsRankingEngine.markWatched(post.id)
        Task { await PostsService.shared.recordView(post) }
        onCountryVisit?(post.countryCode?.uppercased())
        lastCountryCode = post.countryCode?.uppercased()
    }

    private func announceCountryChange(at index: Int, previousCode: String?) {
        guard posts.indices.contains(index) else { return }
        let post = posts[index]
        let currentCode = post.countryCode?.uppercased()
        guard let currentCode, !currentCode.isEmpty, currentCode != previousCode else { return }

        let moment = ReelsWorldHopMoment(
            countryCode: currentCode,
            countryName: post.countryName ?? currentCode,
            cityName: post.cityName,
            isHomeCountry: MatteryaCountryBridge.isHomeCountry(post: post, viewerCountryCode: viewerCountryCode)
        )
        ReelsTwistHaptics.worldHop()
        onWorldHop?(moment)
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

    var body: some View {
        ZStack {
            if let url = post.playableVideoURL {
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
                    onViewed: { Task { await PostsService.shared.recordView(post) } }
                )
            } else {
                Color.black
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.5))
                    Text("Video unavailable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { handleTap() }

            if isPaused {
                Image(systemName: "play.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(Theme.iconFill)
                    .shadow(color: .black.opacity(0.35), radius: 10)
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
            }

            if showLikeBurst {
                Image(systemName: "heart.fill")
                    .font(.system(size: 108, weight: .bold))
                    .foregroundStyle(Theme.like)
                    .shadow(color: .black.opacity(0.25), radius: 12)
                    .scaleEffect(showLikeBurst ? 1 : 0.55)
                    .opacity(showLikeBurst ? 0.95 : 0)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.75)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: 220)
                .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                Spacer()
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    authorRow
                    if let text = post.displayCaption ?? post.displayHeadline {
                        Text(text)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(4)
                    }
                    if post.countryCode != nil || post.countryName != nil {
                        ReelsCountryChip(post: post, isHomeCountry: isHomeCountry) {
                            if let country = MatteryaCountryBridge.country(from: post) {
                                appState.openCountryReels(country)
                            }
                        }
                    }
                }
                .padding(.leading, 20)
                .padding(.bottom, bottomInset)

                Spacer()

                VStack(spacing: 22) {
                    actionButton(
                        icon: post.likedByMe ? "heart.fill" : "heart",
                        label: "\(post.likeCount)",
                        tint: post.likedByMe ? Theme.like : .white,
                        scale: likeButtonScale
                    ) {
                        triggerLike(fromButton: true)
                    }

                    actionButton(
                        icon: "bubble.right",
                        label: "\(post.commentCount)",
                        tint: .white
                    ) {
                        onOpenComments()
                    }

                    actionButton(
                        icon: appState.isPostSaved(post.id) ? "bookmark.fill" : "bookmark",
                        label: "Save",
                        tint: appState.isPostSaved(post.id) ? Theme.iconFill : .white
                    ) {
                        Task { await toggleSave() }
                    }

                    actionButton(
                        icon: "arrowshape.turn.up.right",
                        label: "Share",
                        tint: .white
                    ) {
                        appState.presentShareSheet(for: post)
                    }

                    if showsOpenPostAction {
                        actionButton(
                            icon: "arrow.up.right",
                            label: "Open",
                            tint: .white,
                            action: onOpenPost
                        )
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, bottomInset)
            }
            }
        }
        .animation(.easeOut(duration: 0.16), value: isPaused)
        .animation(.spring(response: 0.34, dampingFraction: 0.62), value: showLikeBurst)
        .onChange(of: isActive) { _, active in
            if !active {
                isPaused = false
                pendingSingleTap?.cancel()
            }
        }
        .overlay(alignment: .topTrailing) {
            if let message = saveFeedback {
                Text(message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background((saveFeedback != nil ? Theme.danger : Color.black).opacity(0.55), in: Capsule())
                    .padding(.top, 56)
                    .padding(.trailing, 72)
                    .transition(.opacity)
            }
        }

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
        withAnimation(.easeOut(duration: 0.16)) {
            isPaused.toggle()
        }
        ReelsHaptics.pause()
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
        Button {
            appState.openPublicProfile(username: post.author?.username, userID: post.authorID)
        } label: {
            HStack(spacing: 10) {
                AvatarView(url: post.author?.avatarURL, seed: post.authorID, size: 36)
                Text(post.author?.displayName ?? "Member")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
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

    private func actionButton(
        icon: String,
        label: String,
        tint: Color,
        scale: CGFloat = 1,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(tint)
                    .scaleEffect(scale)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .buttonStyle(.plain)
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
    @State private var passport = ReelsPassport()
    @State private var worldHopMoment: ReelsWorldHopMoment?
    @AppStorage("matterya.reels_swipe_hint_seen") private var swipeHintSeen = false
    @State private var showSwipeHint = false
    @State private var dismissDragOffset: CGFloat = 0
    @State private var isPullingToDismiss = false
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
                ReelsCommentsSheet(postID: target.id)
                    .withAppState(appState)
            }
    }

    private var reelsContent: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            Group {
                if posts.isEmpty {
                    ContentUnavailableView(
                        "No \(MatteryaCopy.sparks.lowercased())",
                        systemImage: "video.slash",
                        description: Text("This \(MatteryaCopy.spark.lowercased()) is no longer available.")
                    )
                } else {
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
                        onCountryVisit: { code in
                            passport.visit(code)
                        },
                        onWorldHop: { moment in
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                worldHopMoment = moment
                            }
                            Task {
                                try? await Task.sleep(for: .seconds(1.8))
                                withAnimation(.easeOut(duration: 0.28)) {
                                    if worldHopMoment == moment {
                                        worldHopMoment = nil
                                    }
                                }
                            }
                        },
                        onOpenComments: { commentsPostID = $0 }
                    )
                }

                if showSwipeHint {
                    ReelsSwipeHint()
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                VStack(spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        ReelsChromeButton(systemName: "xmark", accessibilityLabel: "Close \(MatteryaCopy.sparks.lowercased())") {
                            dismiss()
                        }

                        Spacer(minLength: 8)

                        ReelsIslandStrip(
                            post: activePost,
                            passport: passport
                        )

                        Spacer(minLength: 8)

                        ReelsChromeButton(systemName: "globe", accessibilityLabel: "Globe shuffle") {
                            globeShuffle()
                        }
                    }

                    if let worldHopMoment {
                        ReelsWorldHopBanner(moment: worldHopMoment)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if isPullingToDismiss, dismissDragOffset > 28 {
                        Label("Release to close", systemImage: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.88))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.ink.opacity(0.5), in: Capsule())
                            .transition(.opacity)
                    }

                    Spacer()
                }
                .safeAreaPadding(.top, 6)
                .padding(.horizontal, Theme.pagePadding)
            }
            .matteryaPullDownDismissTransform(offset: dismissDragOffset)
            .matteryaPullDownToDismiss(
                offset: $dismissDragOffset,
                isDragging: $isPullingToDismiss,
                onDismiss: { dismiss() }
            )
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
            await expandFeed()
        }
        .onAppear {
            if !swipeHintSeen {
                showSwipeHint = true
                swipeHintSeen = true
                Task {
                    try? await Task.sleep(for: .seconds(2.4))
                    withAnimation(.easeOut(duration: 0.35)) {
                        showSwipeHint = false
                    }
                }
            }
        }
    }

    private func expandFeed() async {
        guard !isExpandingFeed else { return }
        isExpandingFeed = true
        defer { isExpandingFeed = false }

        feedCursor = nil
        hasMorePages = true
        recyclePass = 0

        var feed: [CountryPost] = []
        var excluding = Set<String>()
        var cursor: String? = nil
        var attempts = 0

        while feed.count < 24, attempts < 4 {
            attempts += 1
            let page = await PostsService.shared.loadReelsFeedPage(
                excludingIDs: excluding,
                cursor: cursor,
                batchSize: 16,
                fetchLimit: 56,
                viewerCountry: appState.currentProfile?.countryCode,
                followingIDs: appState.followingIDs,
                tail: feed,
                allowRecycle: false
            )
            for post in page.posts where !excluding.contains(post.id) {
                feed.append(post)
                excluding.insert(post.id)
            }
            cursor = page.nextCursor
            feedCursor = page.nextCursor
            hasMorePages = page.hasMore
            if page.posts.isEmpty { break }
        }

        let seedReels = context.seedPosts.filter(ReelsRankingEngine.isSparkEligible)
        if !feed.contains(where: { $0.id == context.startingPostID }) {
            feed.insert(context.startingPost, at: 0)
        }
        for reel in seedReels.reversed() where !feed.contains(where: { $0.id == reel.id }) {
            if let anchor = feed.firstIndex(where: { $0.id == context.startingPostID }) {
                feed.insert(reel, at: anchor + 1)
            } else {
                feed.insert(reel, at: 0)
            }
        }

        if feed.count < 8 {
            let topUp = await PostsService.shared.loadReelsFeedPage(
                excludingIDs: Set(feed.map(\.id)),
                cursor: feedCursor,
                batchSize: 12,
                fetchLimit: 64,
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

        let previousID = posts.indices.contains(activeIndex) ? posts[activeIndex].id : context.startingPostID
        posts = feed
        activeIndex = feed.firstIndex(where: { $0.id == previousID }) ?? 0
    }

    private var activePost: CountryPost? {
        guard posts.indices.contains(activeIndex) else { return posts.first }
        return posts[activeIndex]
    }

    private func globeShuffle() {
        guard !posts.isEmpty else { return }
        let currentCode = posts.indices.contains(activeIndex)
            ? posts[activeIndex].countryCode?.uppercased()
            : nil

        let abroad = posts.enumerated().filter { index, post in
            guard index != activeIndex else { return false }
            let code = post.countryCode?.uppercased()
            guard let code, !code.isEmpty else { return false }
            return code != currentCode
        }

        if let pick = abroad.randomElement() {
            ReelsTwistHaptics.globeShuffle()
            activeIndex = pick.offset
            return
        }

        if posts.count > 1 {
            let alternatives = posts.indices.filter { $0 != activeIndex }
            if let index = alternatives.randomElement() {
                ReelsTwistHaptics.globeShuffle()
                activeIndex = index
                return
            }
        }

        appState.showToast("Keep scrolling — more countries ahead.", style: .info)
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
            for post in page.posts where !existingIDs.contains(post.id) {
                posts.append(post)
            }
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

private struct ReelsSwipeHint: View {
    var body: some View {
        VStack {
            Spacer()
                VStack(spacing: 8) {
                HStack(spacing: 14) {
                    Image(systemName: "chevron.down")
                    Image(systemName: "chevron.up")
                }
                .font(.title3.weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
                Text("Swipe up or down · drag down hard to close")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.black.opacity(0.42), in: Capsule())
            .safeAreaPadding(.bottom, 24)
            .padding(.bottom, 96)
        }
        .allowsHitTesting(false)
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