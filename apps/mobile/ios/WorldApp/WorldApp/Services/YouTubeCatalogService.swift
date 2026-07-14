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

enum YouTubeHomeFilter: String, CaseIterable, Identifiable {
    case all, trending, music, gaming, news, live, recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "For you"
        case .trending: "Trending"
        case .music: "Music"
        case .gaming: "Gaming"
        case .news: "News"
        case .live: "Live"
        case .recent: "Latest"
        }
    }

    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .trending: "flame"
        case .music: "music.note"
        case .gaming: "gamecontroller"
        case .news: "newspaper"
        case .live: "dot.radiowaves.left.and.right"
        case .recent: "clock"
        }
    }

    static var hubCategories: [YouTubeHomeFilter] {
        allCases.filter { $0 != .all }
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

    private let historyKey = "matterya.play.watch_history_v1"
    private let legacyHistoryKey = "youtube.watch_history_v1"
    private let playbackPositionsKey = "matterya.play.playback_positions_v1"
    private var playbackPositions: [String: Double] = [:]

    private init() {
        if let stored = UserDefaults.standard.dictionary(forKey: playbackPositionsKey) as? [String: Double] {
            playbackPositions = stored
        }
    }

    func livingEligible(_ post: CountryPost) -> Bool {
        post.hasVideo && !post.isStory
    }

    func buildChannels(from videos: [CountryPost], profiles: [String: Profile] = [:]) -> [YouTubeChannel] {
        let eligible = videos.filter(livingEligible)
        let grouped = Dictionary(grouping: eligible) { $0.authorID }
        var channels: [YouTubeChannel] = []

        for (authorID, posts) in grouped {
            let longForm = posts.filter { !$0.isReel }.sorted { $0.createdAt > $1.createdAt }
            let reels = posts.filter(\.isReel).sorted { $0.createdAt > $1.createdAt }
            guard !longForm.isEmpty || !reels.isEmpty else { continue }

            let profile = profiles[authorID]
            let customName = LivingChannelMarker.parse(from: profile?.bio)
            let author = longForm.first?.author ?? reels.first?.author
            let title = customName
                ?? author?.displayName
                ?? author?.username
                ?? "Channel"
            let handle = author?.username.map { "@\($0)" }

            channels.append(
                YouTubeChannel(
                    id: authorID,
                    authorID: authorID,
                    title: title,
                    handle: handle,
                    author: author,
                    videos: longForm,
                    reels: reels,
                    hasCustomChannelName: customName != nil
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
        let base = videos.filter { livingEligible($0) && !$0.isReel }
        switch homeFilter {
        case .all:
            return ReelsRankingEngine.rank(base, viewerCountry: viewerCountry, followingIDs: followingIDs)
        case .trending:
            return base.sorted {
                if $0.viewCount == $1.viewCount { return $0.createdAt > $1.createdAt }
                return $0.viewCount > $1.viewCount
            }
        case .recent:
            return base.sorted { $0.createdAt > $1.createdAt }
        case .music:
            return keywordFilter(base, words: ["music", "song", "album", "concert", "live session", "cover"])
        case .gaming:
            return keywordFilter(base, words: ["game", "gaming", "playthrough", "walkthrough", "esports", "minecraft"])
        case .news:
            return keywordFilter(base, words: ["news", "report", "breaking", "update", "headline"])
        case .live:
            return keywordFilter(base, words: ["live", "stream", "broadcast", "premiere"])
        }
    }

    func reels(from videos: [CountryPost]) -> [CountryPost] {
        videos.filter { livingEligible($0) && $0.isReel }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func subscriptionFeed(
        videos: [CountryPost],
        channels: [YouTubeChannel],
        followingIDs: Set<String>
    ) -> [CountryPost] {
        videos
            .filter { livingEligible($0) && followingIDs.contains($0.authorID) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func subscriptionChannels(_ channels: [YouTubeChannel], followingIDs: Set<String>) -> [YouTubeChannel] {
        channels.filter { followingIDs.contains($0.authorID) }
    }

    func likedVideos(_ videos: [CountryPost]) -> [CountryPost] {
        videos.filter { livingEligible($0) && $0.likedByMe }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func myUploads(_ videos: [CountryPost], userID: String?) -> [CountryPost] {
        guard let userID else { return [] }
        return videos.filter { livingEligible($0) && $0.authorID == userID }
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
        var history = historyIDs()
        history.removeAll { $0 == postID }
        history.insert(postID, at: 0)
        UserDefaults.standard.set(Array(history.prefix(120)), forKey: historyKey)
    }

    func playbackPosition(for postID: String) -> Double {
        playbackPositions[postID] ?? 0
    }

    func savePlaybackPosition(_ seconds: Double, for postID: String, duration: Double? = nil) {
        let clamped = max(0, seconds)
        if clamped < 1 {
            playbackPositions.removeValue(forKey: postID)
            persistPlaybackPositions()
            return
        }
        if let duration, duration > 0, clamped >= duration - 2 {
            playbackPositions.removeValue(forKey: postID)
            persistPlaybackPositions()
            return
        }
        playbackPositions[postID] = clamped
        persistPlaybackPositions()
    }

    private func persistPlaybackPositions() {
        let trimmed = Dictionary(
            uniqueKeysWithValues: playbackPositions
                .sorted { $0.value > $1.value }
                .prefix(80)
                .map { ($0.key, $0.value) }
        )
        playbackPositions = trimmed
        UserDefaults.standard.set(trimmed, forKey: playbackPositionsKey)
    }

    func historyIDs() -> [String] {
        if let current = UserDefaults.standard.stringArray(forKey: historyKey), !current.isEmpty {
            return current
        }
        return UserDefaults.standard.stringArray(forKey: legacyHistoryKey) ?? []
    }

    func historyVideos(from catalog: [CountryPost]) -> [CountryPost] {
        let ids = historyIDs()
        let map = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        return ids.compactMap { map[$0] }
    }

    func relatedVideos(to post: CountryPost, from catalog: [CountryPost], limit: Int = 12) -> [CountryPost] {
        catalog
            .filter { livingEligible($0) && $0.id != post.id && !$0.isReel }
            .sorted { lhs, rhs in
                let lhsSameAuthor = lhs.authorID == post.authorID
                let rhsSameAuthor = rhs.authorID == post.authorID
                if lhsSameAuthor != rhsSameAuthor { return lhsSameAuthor }
                if lhs.viewCount == rhs.viewCount { return lhs.createdAt > rhs.createdAt }
                return lhs.viewCount > rhs.viewCount
            }
            .prefix(limit)
            .map { $0 }
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