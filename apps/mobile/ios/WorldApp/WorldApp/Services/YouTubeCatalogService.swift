import Foundation

enum YouTubeMainTab: String, CaseIterable, Identifiable {
    case home, subscriptions, library

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: "Home"
        case .subscriptions: "Subscriptions"
        case .library: "Library"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .subscriptions: "rectangle.stack.fill"
        case .library: "books.vertical"
        }
    }
}

/// Hubs home chips — aligned with seed `hub_slug` / HubCategoryClassifier (not YouTube clones).
enum YouTubeHomeFilter: String, CaseIterable, Identifiable {
    case all
    case social, travel, nature, music, food, sports
    case tech, fitness, film, culture, daily
    case trending, recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "For you"
        case .social: "Social"
        case .travel: "Travel"
        case .nature: "Nature"
        case .music: "Music"
        case .food: "Food"
        case .sports: "Sports"
        case .tech: "Tech"
        case .fitness: "Fitness"
        case .film: "Film"
        case .culture: "Culture"
        case .daily: "Daily"
        case .trending: "Trending"
        case .recent: "Latest"
        }
    }

    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .social: "person.2"
        case .travel: "airplane"
        case .nature: "leaf"
        case .music: "music.note"
        case .food: "fork.knife"
        case .sports: "sportscourt"
        case .tech: "desktopcomputer"
        case .fitness: "figure.run"
        case .film: "film"
        case .culture: "theatermasks"
        case .daily: "sun.max"
        case .trending: "flame"
        case .recent: "clock"
        }
    }

    /// Seed / category slug for shelf filtering (nil for algorithmic chips).
    var hubSlug: String? {
        switch self {
        case .all, .trending, .recent: return nil
        default: return rawValue
        }
    }

    /// Chips shown under Hubs home (ordered like TF shelves).
    static var hubCategories: [YouTubeHomeFilter] {
        [
            .social, .travel, .nature, .music, .food, .sports,
            .tech, .fitness, .film, .culture, .daily,
            .trending, .recent,
        ]
    }
}

enum YouTubeLibrarySection: String, CaseIterable, Identifiable {
    case history, reels, watchLater, liked, uploads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: "History"
        case .reels: MatteryaCopy.sparks
        case .watchLater: "Saved videos"
        case .liked: "Liked videos"
        case .uploads: "Your videos"
        }
    }

    var icon: String {
        switch self {
        case .history: "clock"
        case .reels: "sparkles"
        case .watchLater: "clock.badge.checkmark"
        case .liked: "hand.thumbsup"
        case .uploads: "film"
        }
    }
}

struct YouTubeChannel: Identifiable, Hashable {
    let id: String
    let authorID: String
    let title: String
    let handle: String?
    let author: PostAuthor?
    let videos: [CountryPost]
    let reels: [CountryPost]
    let hasCustomChannelName: Bool

    var videoCount: Int { videos.count }
    var reelCount: Int { reels.count }
    var latestVideo: CountryPost? { videos.first }
    var totalViews: Int { videos.reduce(0) { $0 + $1.viewCount } }
}

@MainActor
final class YouTubeCatalogService {
    static let shared = YouTubeCatalogService()

    /// Device-wide legacy keys (pre-user-scoping). Never write these for new accounts.
    private let legacyGlobalHistoryKey = "matterya.play.watch_history_v1"
    private let legacyHistoryKey = "youtube.watch_history_v1"
    private let legacyGlobalPositionsKey = "matterya.play.playback_positions_v1"

    private var activeUserID: String?
    private var playbackPositions: [String: Double] = [:]
    private var livePlaybackPositions: [String: Double] = [:]
    private var lastDiskPersistAt: [String: Date] = [:]

    private init() {
        // Bind to current session if already signed in (app relaunch).
        bindToUser(AuthService.shared.currentUser?.id)
    }

    /// Call on login / logout so Continue watching never leaks between accounts.
    func bindToUser(_ userID: String?) {
        let normalized = userID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (normalized?.isEmpty == false) ? normalized : nil
        guard next != activeUserID else { return }
        activeUserID = next
        lastDiskPersistAt = [:]
        livePlaybackPositions = [:]
        playbackPositions = [:]
        if let uid = next {
            let key = positionsKey(for: uid)
            if let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] {
                playbackPositions = stored
                livePlaybackPositions = stored
            }
            // One-time migrate device-wide history into this user only if their
            // personal history is empty (avoids wiping on upgrade).
            migrateLegacyHistoryIfNeeded(for: uid)
        }
    }

    private func historyKey(for userID: String) -> String {
        "matterya.play.watch_history_v1.\(userID)"
    }

    private func positionsKey(for userID: String) -> String {
        "matterya.play.playback_positions_v1.\(userID)"
    }

    private func migrateLegacyHistoryIfNeeded(for userID: String) {
        let personalKey = historyKey(for: userID)
        let existing = UserDefaults.standard.stringArray(forKey: personalKey) ?? []
        guard existing.isEmpty else { return }
        // Do NOT migrate legacy global history into brand-new accounts — that
        // was the bug (new users saw prior device watch history).
        // Legacy keys stay only for users who already had personal keys empty
        // after a prior app version; we intentionally leave them unused.
        _ = personalKey
    }

    func livingEligible(_ post: CountryPost) -> Bool {
        post.hasVideo && !post.isStory
    }

    func buildChannels(from videos: [CountryPost], profiles: [String: Profile] = [:]) -> [YouTubeChannel] {
        let eligible = videos.filter(livingEligible)
        // Collapse every Archive / hub seed author into one channel id.
        // Also: user-authored rows that only re-host Archive media must never form a personal channel.
        let grouped = Dictionary(grouping: eligible) { post -> String in
            if post.isHubSeedVideo || HubVideoSeedService.isArchiveChannelAuthor(post.authorID) {
                return HubVideoSeedService.archiveChannelAuthorID
            }
            // Legacy feed shares of Archive clips (wrong author) → still The Archive, not the sharer.
            if PlayPlatformBridge.isArchiveCatalogMedia(post),
               !PlayPlatformBridge.isHubChannelUpload(post) {
                return HubVideoSeedService.archiveChannelAuthorID
            }
            return post.authorID
        }
        var channels: [YouTubeChannel] = []

        for (authorID, posts) in grouped {
            let isArchive = authorID == HubVideoSeedService.archiveChannelAuthorID

            // Real users: only intentional Hubs publishes belong on their channel.
            // Sharing a video to the feed must NEVER invent channel uploads for the sharer.
            let channelPosts: [CountryPost]
            if isArchive {
                // Seeds + catalog only — drop feed re-shares that were wrongly attributed here.
                channelPosts = posts.filter { post in
                    if PlayPlatformBridge.isHubFeedReshare(post) { return false }
                    if PlayPlatformBridge.isHubOriginShare(post) { return false }
                    // Keep true Archive catalog rows (seed author / seed flag / archive media with archive author).
                    return post.isHubSeedVideo
                        || HubVideoSeedService.isArchiveChannelAuthor(post.authorID)
                        || (PlayPlatformBridge.isArchiveCatalogMedia(post)
                            && HubVideoSeedService.isArchiveChannelAuthor(post.authorID))
                }
            } else {
                channelPosts = posts.filter { PlayPlatformBridge.isHubChannelUpload($0) }
            }

            let longForm = channelPosts.filter { !$0.isReel }.sorted { $0.createdAt > $1.createdAt }
            let reels = channelPosts.filter(\.isReel).sorted { $0.createdAt > $1.createdAt }
            // No channel row without real channel content (setup-only profiles stay off Hubs rails).
            guard !longForm.isEmpty || !reels.isEmpty else { continue }

            let profile = profiles[authorID]
            let customName = LivingChannelMarker.parse(from: profile?.bio)
            let author: PostAuthor? = isArchive
                ? PostAuthor(
                    userID: HubVideoSeedService.archiveChannelAuthorID,
                    displayName: HubVideoSeedService.archiveChannelDisplayName,
                    username: HubVideoSeedService.archiveChannelUsername,
                    avatarURL: nil,
                    countryName: nil,
                    countryCode: nil,
                    lastReadAt: nil
                )
                : (longForm.first?.author ?? reels.first?.author)
            let title = isArchive
                ? HubVideoSeedService.archiveChannelDisplayName
                : (customName ?? author?.displayName ?? author?.username ?? "Channel")
            let handle = isArchive
                ? "@\(HubVideoSeedService.archiveChannelUsername)"
                : author?.username.map { "@\($0)" }

            channels.append(
                YouTubeChannel(
                    id: authorID,
                    authorID: authorID,
                    title: title,
                    handle: handle,
                    author: author,
                    videos: longForm,
                    reels: reels,
                    hasCustomChannelName: isArchive || customName != nil
                )
            )
        }

        return channels.sorted {
            if $0.totalViews == $1.totalViews {
                return ($0.latestVideo?.createdAt ?? "") > ($1.latestVideo?.createdAt ?? "")
            }
            return $0.totalViews > $1.totalViews
        }
    }

    func channel(for authorID: String, in channels: [YouTubeChannel]) -> YouTubeChannel? {
        channels.first { $0.authorID == authorID }
    }

    func filterVideos(
        _ videos: [CountryPost],
        homeFilter: YouTubeHomeFilter,
        followingIDs: Set<String>,
        viewerCountry: String?
    ) -> [CountryPost] {
        _ = viewerCountry
        _ = followingIDs
        // For you / category shelves: **long-form only** — never Sparks (Sparks strip is separate).
        // Was accidentally using ReelsRankingEngine.rank which only keeps spark-eligible rows.
        let base = videos.filter { PlayPlatformBridge.isHubsForYouLongForm($0) }
        switch homeFilter {
        case .all:
            // Unsorted pool — callers apply sessionHomeFeedOrder (unviewed / following first).
            return base
        case .trending:
            return base.sorted {
                if $0.viewCount == $1.viewCount { return $0.createdAt > $1.createdAt }
                return $0.viewCount > $1.viewCount
            }
        case .recent:
            return base.sorted { $0.createdAt > $1.createdAt }
        case .social, .travel, .nature, .music, .food, .sports,
                .tech, .fitness, .film, .culture, .daily:
            let slug = homeFilter.hubSlug ?? homeFilter.rawValue
            return base.filter { post in
                let postSlug = (post.hubSlug ?? post.externalRefID ?? "").lowercased()
                if postSlug == slug || postSlug.hasPrefix(slug + "_") { return true }
                // Persona parents (e.g. travel_cities → travel) via classifier.
                let parent = HubCategoryClassifier.parentCategory(of: postSlug)
                if parent == slug { return true }
                return false
            }
        }
    }

    func reels(from videos: [CountryPost]) -> [CountryPost] {
        videos.filter {
            livingEligible($0) && $0.isReel && PlayPlatformBridge.belongsInHubsCatalog($0)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func subscriptionFeed(
        videos: [CountryPost],
        channels: [YouTubeChannel],
        followingIDs: Set<String>
    ) -> [CountryPost] {
        videos
            .filter {
                livingEligible($0)
                    && followingIDs.contains($0.authorID)
                    && PlayPlatformBridge.belongsInHubsCatalog($0)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func subscriptionChannels(_ channels: [YouTubeChannel], followingIDs: Set<String>) -> [YouTubeChannel] {
        channels.filter { followingIDs.contains($0.authorID) }
    }

    func likedVideos(_ videos: [CountryPost]) -> [CountryPost] {
        videos.filter { livingEligible($0) && $0.likedByMe }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Videos this user **published to Hubs** (channel uploads). Feed shares never count.
    func myUploads(_ videos: [CountryPost], userID: String?) -> [CountryPost] {
        guard let userID else { return [] }
        return videos
            .filter {
                livingEligible($0)
                    && $0.authorID == userID
                    && PlayPlatformBridge.isHubChannelUpload($0)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func search(query: String, videos: [CountryPost], channels: [YouTubeChannel]) -> (videos: [CountryPost], channels: [YouTubeChannel]) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return ([], []) }

        let matchedVideos = videos.filter { livingEligible($0) }.filter { post in
            (post.displayHeadline?.lowercased().contains(q) ?? false)
                || post.displayBody.lowercased().contains(q)
                || post.authorDisplayName.lowercased().contains(q)
                || (post.author?.username?.lowercased().contains(q) ?? false)
        }

        let matchedChannels = channels.filter {
            $0.title.lowercased().contains(q)
                || ($0.handle?.lowercased().contains(q) ?? false)
                || ($0.author?.displayName?.lowercased().contains(q) ?? false)
        }

        return (matchedVideos, matchedChannels)
    }

    func recordWatch(_ postID: String) {
        // Same discovery rule as Sparks/feed — already-watched long-form drops in For you.
        SparkDiscoveryEngine.markWatched(postID)
        // No signed-in user → no continue-watching trail (and never write globals).
        guard let userID = activeUserID else { return }
        var history = historyIDs()
        history.removeAll { $0 == postID }
        history.insert(postID, at: 0)
        UserDefaults.standard.set(Array(history.prefix(120)), forKey: historyKey(for: userID))
    }

    /// **For you** order — slug-shelf algorithm (YouTube-style, light):
    /// 1) Bucket by hub parent slug (social / travel / …)
    /// 2) Within each slug: unviewed first, then following, then rest
    /// 3) Round-robin across slugs so no category floods the list
    /// Cheap O(n) — never re-sorts a giant flat pool mid-scroll.
    func rankForYou(
        _ videos: [CountryPost],
        followingIDs: Set<String>,
        myUserID: String?,
        sessionSeed: UInt64
    ) -> [CountryPost] {
        rankForYouBySlugs(
            videos,
            followingIDs: followingIDs,
            myUserID: myUserID,
            sessionSeed: sessionSeed,
            focusSlug: nil
        )
    }

    /// Parent hub slug for a long-form row (explicit hub_slug → classifier).
    nonisolated static func parentHubSlug(for post: CountryPost) -> String {
        if let raw = (post.hubSlug ?? post.externalRefID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !raw.isEmpty {
            return HubCategoryClassifier.parentCategory(of: raw)
        }
        return HubCategoryClassifier.classify(
            title: post.title,
            body: post.body,
            tags: [],
            creator: post.author?.displayName,
            seedSlug: nil
        )
    }

    /// Slug-first ranking. `focusSlug` non-nil → single shelf (chip), still unviewed-first.
    func rankForYouBySlugs(
        _ videos: [CountryPost],
        followingIDs: Set<String>,
        myUserID: String?,
        sessionSeed: UInt64,
        focusSlug: String?
    ) -> [CountryPost] {
        Self.rankForYouBySlugsPure(
            videos,
            followingIDs: followingIDs,
            myUserID: myUserID,
            sessionSeed: sessionSeed,
            focusSlug: focusSlug
        )
    }

    /// Pure ranking for background threads (no MainActor).
    nonisolated static func rankForYouBySlugsPure(
        _ videos: [CountryPost],
        followingIDs: Set<String>,
        myUserID: String?,
        sessionSeed: UInt64,
        focusSlug: String?
    ) -> [CountryPost] {
        let longForm = videos.filter { PlayPlatformBridge.isHubsForYouLongForm($0) }
        guard !longForm.isEmpty else { return [] }

        let me = myUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        func isFollow(_ p: CountryPost) -> Bool { followingIDs.contains(p.authorID) }
        func isMine(_ p: CountryPost) -> Bool { !me.isEmpty && p.authorID == me }

        var buckets: [String: [CountryPost]] = [:]
        for post in longForm {
            let slug = parentHubSlug(for: post)
            if let focusSlug, slug != focusSlug, !focusSlug.isEmpty {
                let parent = HubCategoryClassifier.parentCategory(of: focusSlug)
                if slug != focusSlug && slug != parent { continue }
            }
            buckets[slug, default: []].append(post)
        }

        func rankSlugQueue(_ items: [CountryPost], salt: UInt64) -> [CountryPost] {
            var followFresh: [CountryPost] = []
            var mineFresh: [CountryPost] = []
            var otherFresh: [CountryPost] = []
            var viewed: [CountryPost] = []
            for p in items {
                if SparkDiscoveryEngine.isViewed(p) {
                    viewed.append(p)
                    continue
                }
                if isMine(p) { mineFresh.append(p) }
                else if isFollow(p) { followFresh.append(p) }
                else { otherFresh.append(p) }
            }
            func newest(_ a: [CountryPost]) -> [CountryPost] {
                a.sorted { ($0.createdDate ?? .distantPast) > ($1.createdDate ?? .distantPast) }
            }
            let others = salt == 0 ? newest(otherFresh) : seededInterleavePure(newest(otherFresh), seed: salt)
            return newest(mineFresh) + newest(followFresh) + others + newest(viewed)
        }

        let slugOrder: [String]
        if let focus = focusSlug?.lowercased(), !focus.isEmpty {
            slugOrder = [HubCategoryClassifier.parentCategory(of: focus)]
        } else {
            var order = HubVideoSeedService.hubOrder
            if sessionSeed != 0, order.count > 1 {
                let rot = Int(sessionSeed % UInt64(order.count))
                order = Array(order[rot...]) + Array(order[..<rot])
            }
            let extras = buckets.keys.filter { !order.contains($0) }.sorted()
            slugOrder = order + extras
        }

        var queues: [String: [CountryPost]] = [:]
        for (i, slug) in slugOrder.enumerated() {
            guard let raw = buckets[slug], !raw.isEmpty else { continue }
            queues[slug] = rankSlugQueue(raw, salt: sessionSeed &+ UInt64(i) &* 0x9E37)
        }

        var out: [CountryPost] = []
        out.reserveCapacity(longForm.count)
        var seen = Set<String>()
        var progressed = true
        while progressed {
            progressed = false
            for slug in slugOrder {
                guard var q = queues[slug], let next = q.first else { continue }
                q.removeFirst()
                queues[slug] = q
                if seen.insert(next.id).inserted {
                    out.append(next)
                    progressed = true
                }
            }
        }
        return out
    }

    nonisolated private static func seededInterleavePure(_ items: [CountryPost], seed: UInt64) -> [CountryPost] {
        guard items.count > 2 else { return items }
        var arr = items
        var state = seed == 0 ? 0xC0FFEE : seed
        let swaps = min(arr.count, 8)
        for i in 0..<swaps {
            state = state &* 1_103_515_245 &+ 12_345
            let j = Int(state % UInt64(arr.count))
            arr.swapAt(i % arr.count, j)
        }
        return arr
    }

    func playbackPosition(for postID: String) -> Double {
        let raw = livePlaybackPositions[postID] ?? playbackPositions[postID] ?? 0
        return SafeNumeric.nonNegativeSeconds(raw)
    }

    /// Updates in-memory position during playback; persists to disk on a short throttle.
    func notePlaybackPosition(_ seconds: Double, for postID: String, duration: Double? = nil) {
        let clamped = SafeNumeric.nonNegativeSeconds(seconds)
        guard clamped >= 0.5 else { return }

        livePlaybackPositions[postID] = clamped

        let now = Date()
        if let last = lastDiskPersistAt[postID], now.timeIntervalSince(last) < 2 {
            return
        }
        lastDiskPersistAt[postID] = now
        savePlaybackPosition(clamped, for: postID, duration: duration)
    }

    func savePlaybackPosition(_ seconds: Double, for postID: String, duration: Double? = nil) {
        let clamped = SafeNumeric.nonNegativeSeconds(seconds)
        let prior = playbackPosition(for: postID)

        if clamped < 1 {
            // Mini-player teardown can fire before seek completes; don't wipe a saved resume point.
            guard prior < 1 else { return }
            playbackPositions.removeValue(forKey: postID)
            livePlaybackPositions.removeValue(forKey: postID)
            persistPlaybackPositions()
            return
        }
        let dur = duration.map { SafeNumeric.seconds($0) }
        if let dur, dur > 0, clamped >= dur - 2 {
            playbackPositions.removeValue(forKey: postID)
            livePlaybackPositions.removeValue(forKey: postID)
            persistPlaybackPositions()
            return
        }

        playbackPositions[postID] = clamped
        livePlaybackPositions[postID] = clamped
        persistPlaybackPositions()
    }

    private func persistPlaybackPositions() {
        guard let userID = activeUserID else { return }
        let trimmed = Dictionary(
            uniqueKeysWithValues: playbackPositions
                .sorted { $0.value > $1.value }
                .prefix(80)
                .map { ($0.key, $0.value) }
        )
        playbackPositions = trimmed
        UserDefaults.standard.set(trimmed, forKey: positionsKey(for: userID))
    }

    func historyIDs() -> [String] {
        // New / signed-out accounts: never fall back to device-wide legacy history.
        guard let userID = activeUserID else { return [] }
        return UserDefaults.standard.stringArray(forKey: historyKey(for: userID)) ?? []
    }

    func historyVideos(from catalog: [CountryPost]) -> [CountryPost] {
        let ids = historyIDs()
        guard !ids.isEmpty else { return [] }
        let map = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { _, n in n })
        return ids.compactMap { map[$0] }
    }

    /// Wipe in-memory trail on logout (disk stays per-user for next login).
    func clearSessionState() {
        bindToUser(nil)
    }

    /// "More on Matterya" shelf — **unique per source video**.
    /// Seeds shuffle from `post.id` so two videos never share the same related order,
    /// even when they share a slug/author. Mixes same-slug, sibling slugs, and off-slug.
    func relatedVideos(to post: CountryPost, from catalog: [CountryPost], limit: Int = 12) -> [CountryPost] {
        let pool = catalog.filter {
            livingEligible($0)
                && $0.id != post.id
                && PlayPlatformBridge.isHubsForYouLongForm($0)
        }
        guard !pool.isEmpty else { return [] }

        let seed = Self.stableSeed(from: post.id)
        let slug = Self.parentHubSlug(for: post)
        let parent = HubCategoryClassifier.parentCategory(of: slug)

        // Bucket candidates by relationship to the source video.
        var sameSlug: [CountryPost] = []
        var siblingSlug: [CountryPost] = []
        var sameAuthor: [CountryPost] = []
        var offSlug: [CountryPost] = []
        for p in pool {
            let pSlug = Self.parentHubSlug(for: p)
            if p.authorID == post.authorID {
                sameAuthor.append(p)
            }
            if pSlug == slug {
                sameSlug.append(p)
            } else if HubCategoryClassifier.parentCategory(of: pSlug) == parent {
                siblingSlug.append(p)
            } else {
                offSlug.append(p)
            }
        }

        // Each tier is shuffled with a different salt of the source seed → unique mix per video.
        let tierSame = Self.seededShuffle(sameSlug, seed: seed &+ 0x11)
        let tierSibling = Self.seededShuffle(siblingSlug, seed: seed &+ 0x33)
        let tierAuthor = Self.seededShuffle(sameAuthor, seed: seed &+ 0x55)
        let tierOff = Self.seededShuffle(offSlug, seed: seed &+ 0x77)

        // HARD: unviewed only while any remain in the tier (watched clips last-resort only).
        func preferFresh(_ items: [CountryPost], allowSeen: Bool) -> [CountryPost] {
            let fresh = items.filter { !SparkDiscoveryEngine.isViewed($0) }
            if !fresh.isEmpty { return fresh }
            return allowSeen ? items.filter { SparkDiscoveryEngine.isViewed($0) } : []
        }

        var out: [CountryPost] = []
        var used = Set<String>()
        var authorHits: [String: Int] = [:]

        func take(_ items: [CountryPost], max: Int, allowSeen: Bool) {
            guard max > 0 else { return }
            var taken = 0
            for p in preferFresh(items, allowSeen: allowSeen) {
                guard used.insert(p.id).inserted else { continue }
                // Cap same-author spam so related doesn't look identical across an author.
                let hits = authorHits[p.authorID, default: 0]
                if hits >= 2, out.count + 1 < limit { continue }
                authorHits[p.authorID] = hits + 1
                out.append(p)
                taken += 1
                if taken >= max || out.count >= limit { return }
            }
        }

        // Recipe unique to this video: ~half same-slug, sprinkle siblings/author, rest off-slug diversity.
        // Pass 1: unviewed only across all tiers.
        let sameBudget = max(3, limit / 2)
        let siblingBudget = max(2, limit / 5)
        let authorBudget = 2
        take(tierSame, max: sameBudget, allowSeen: false)
        if out.count < limit { take(tierSibling, max: siblingBudget, allowSeen: false) }
        if out.count < limit { take(tierAuthor, max: authorBudget, allowSeen: false) }
        if out.count < limit { take(tierOff, max: limit - out.count, allowSeen: false) }
        // Pass 2: only if unviewed library exhausted for this shelf.
        if out.count < limit { take(tierSame, max: limit - out.count, allowSeen: true) }
        if out.count < limit { take(tierSibling, max: limit - out.count, allowSeen: true) }
        if out.count < limit { take(tierOff, max: limit - out.count, allowSeen: true) }
        // Fill leftovers from remaining pool (unviewed first, then seen only if needed).
        if out.count < limit {
            let restFresh = Self.seededShuffle(
                pool.filter { !used.contains($0.id) && !SparkDiscoveryEngine.isViewed($0) },
                seed: seed &+ 0x99
            )
            take(restFresh, max: limit - out.count, allowSeen: false)
        }
        if out.count < limit {
            let restSeen = Self.seededShuffle(
                pool.filter { !used.contains($0.id) },
                seed: seed &+ 0xAA
            )
            take(restSeen, max: limit - out.count, allowSeen: true)
        }
        return out
    }

    /// Stable 64-bit seed from a post id (deterministic across launches).
    private static func stableSeed(from id: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in id.utf8 {
            h ^= UInt64(b)
            h &*= 0x100000001b3
        }
        return h == 0 ? 0xC0FFEE : h
    }

    /// Deterministic Fisher–Yates so each source video gets its own related order.
    private static func seededShuffle(_ items: [CountryPost], seed: UInt64) -> [CountryPost] {
        guard items.count > 1 else { return items }
        var arr = items
        var state = seed == 0 ? 0xC0FFEE : seed
        for i in stride(from: arr.count - 1, through: 1, by: -1) {
            state = state &* 6364136223846793005 &+ 1
            let j = Int(state % UInt64(i + 1))
            arr.swapAt(i, j)
        }
        return arr
    }

    private func keywordFilter(_ videos: [CountryPost], words: [String]) -> [CountryPost] {
        videos.filter { post in
            let haystack = [
                post.displayHeadline ?? "",
                post.displayBody,
                post.mediaCaption ?? "",
                post.authorDisplayName,
            ].joined(separator: " ").lowercased()
            return words.contains { haystack.contains($0) }
        }
        .sorted { $0.createdAt > $1.createdAt }
    }
}