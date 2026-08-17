import Foundation

/// Slug-first Hubs load unit — thin pages only, never the full catalog.
///
/// Surfaces:
/// - `for_you` → GET /v1/hubs/for-you
/// - chip slug → GET /v1/hubs/shelves/:slug
///
/// Memory: at most a few shelves × ~80 thin posts. Warm only active + 1 neighbor.
@MainActor
final class SlugShelfStore {
    static let shared = SlugShelfStore()

    /// Max posts retained per slug (or for_you key).
    static let maxPerShelf = 80
    /// Max distinct shelves kept in RAM.
    static let maxShelves = 8
    /// First paint / page size.
    static let pageSize = 20

    /// Synthetic key for the mixed For you stream.
    static let forYouKey = "for_you"

    struct Page: Sendable {
        var items: [CountryPost]
        var nextCursor: String?
        var slugsUsed: [String]
        var session: String?
    }

    private struct ShelfState {
        var posts: [CountryPost] = []
        var nextCursor: String?
        var exhausted = false
        var lastFetchAt: Date?
    }

    private var shelves: [String: ShelfState] = [:]
    private var sessionToken: String = {
        "s\(UInt64.random(in: 1...UInt64.max))-\(Int(Date().timeIntervalSince1970))"
    }()
    private var inFlight: Set<String> = []

    private init() {}

    /// Rotate session (pull-to-refresh / new Hubs visit).
    func newSession() {
        sessionToken = "s\(UInt64.random(in: 1...UInt64.max))-\(Int(Date().timeIntervalSince1970))"
        // Keep cached shelves but clear for_you so mix refreshes.
        shelves[Self.forYouKey] = ShelfState()
    }

    func cachedPosts(for key: String) -> [CountryPost] {
        shelves[key]?.posts ?? []
    }

    func hasMore(for key: String) -> Bool {
        guard let s = shelves[key] else { return true }
        return !s.exhausted
    }

    // MARK: - Public load

    /// First page of For you (or cached if warm).
    func loadForYou(force: Bool = false) async -> Page {
        await loadPage(key: Self.forYouKey, slug: nil, force: force, append: false)
    }

    /// Next page of For you.
    func loadMoreForYou() async -> Page {
        await loadPage(key: Self.forYouKey, slug: nil, force: false, append: true)
    }

    /// Chip shelf first page.
    func loadShelf(_ slug: String, force: Bool = false) async -> Page {
        let key = normalizeSlug(slug)
        return await loadPage(key: key, slug: key, force: force, append: false)
    }

    /// Chip shelf next page.
    func loadMoreShelf(_ slug: String) async -> Page {
        let key = normalizeSlug(slug)
        return await loadPage(key: key, slug: key, force: false, append: true)
    }

    /// Prefetch neighbor shelf thumbs only (no full catalog).
    func warmNeighbor(of slug: String?) {
        let parent = normalizeSlug(slug ?? "daily")
        let neighbor = Self.neighbor(of: parent)
        Task(priority: .utility) {
            let page = await loadShelf(neighbor, force: false)
            ImageCache.shared.prefetchPostThumbnails(
                Array(page.items.prefix(8)),
                maxPixelSize: YouTubeMediaLayout.hubsListThumbMaxPixel,
                aggressive: false
            )
        }
    }

    /// Active key for current home filter.
    static func key(for filter: YouTubeHomeFilter) -> String {
        if let slug = filter.hubSlug { return slug }
        return forYouKey
    }

    // MARK: - Internals

    private func loadPage(
        key: String,
        slug: String?,
        force: Bool,
        append: Bool
    ) async -> Page {
        if inFlight.contains(key) {
            // Coalesce — return what we have.
            let s = shelves[key] ?? ShelfState()
            return Page(items: s.posts, nextCursor: s.nextCursor, slugsUsed: slug.map { [$0] } ?? [], session: sessionToken)
        }

        var state = shelves[key] ?? ShelfState()
        if !force, !append, !state.posts.isEmpty, let at = state.lastFetchAt, Date().timeIntervalSince(at) < 45 {
            return Page(items: state.posts, nextCursor: state.nextCursor, slugsUsed: [], session: sessionToken)
        }
        if append, state.exhausted {
            return Page(items: state.posts, nextCursor: nil, slugsUsed: [], session: sessionToken)
        }
        if append, state.nextCursor == nil, !state.posts.isEmpty {
            state.exhausted = true
            shelves[key] = state
            return Page(items: state.posts, nextCursor: nil, slugsUsed: [], session: sessionToken)
        }

        inFlight.insert(key)
        defer { inFlight.remove(key) }

        let cursor = append ? state.nextCursor : nil
        let remote: Page?
        if let slug {
            remote = await fetchShelf(slug: slug, cursor: cursor)
        } else {
            remote = await fetchForYou(cursor: cursor)
        }

        guard let remote else {
            // Network failed — keep cache; signal empty page for append.
            if !append, state.posts.isEmpty {
                // Local fallback from session catalog (slug-filtered, capped).
                let local = localFallback(slug: slug)
                if !local.isEmpty {
                    state.posts = Array(local.prefix(Self.maxPerShelf))
                    state.lastFetchAt = Date()
                    shelves[key] = state
                    pruneShelves(keeping: key)
                    return Page(items: state.posts, nextCursor: nil, slugsUsed: slug.map { [$0] } ?? [], session: sessionToken)
                }
            }
            return Page(items: append ? [] : state.posts, nextCursor: state.nextCursor, slugsUsed: [], session: sessionToken)
        }

        if append {
            var seen = Set(state.posts.map(\.id))
            var merged = state.posts
            for p in remote.items where seen.insert(p.id).inserted {
                merged.append(p)
            }
            if merged.count > Self.maxPerShelf {
                merged = Array(merged.suffix(Self.maxPerShelf))
            }
            state.posts = merged
        } else {
            state.posts = Array(remote.items.prefix(Self.maxPerShelf))
        }
        state.nextCursor = remote.nextCursor
        state.exhausted = remote.nextCursor == nil || remote.items.isEmpty
        state.lastFetchAt = Date()
        shelves[key] = state
        pruneShelves(keeping: key)

        // Warm only this page head.
        ImageCache.shared.prefetchPostThumbnails(
            Array(remote.items.prefix(8)),
            maxPixelSize: YouTubeMediaLayout.hubsListThumbMaxPixel,
            aggressive: false
        )

        return Page(
            items: append ? remote.items : state.posts,
            nextCursor: state.nextCursor,
            slugsUsed: remote.slugsUsed,
            session: remote.session ?? sessionToken
        )
    }

    private func pruneShelves(keeping key: String) {
        guard shelves.count > Self.maxShelves else { return }
        let drop = shelves.keys.filter { $0 != key && $0 != Self.forYouKey }
        for k in drop.prefix(shelves.count - Self.maxShelves) {
            shelves.removeValue(forKey: k)
        }
    }

    private func localFallback(slug: String?) -> [CountryPost] {
        let pool = PostsService.shared.hubsSessionCatalog
            .filter { PlayPlatformBridge.isHubsForYouLongForm($0) }
        guard !pool.isEmpty else { return [] }
        if let slug {
            let parent = normalizeSlug(slug)
            return pool.filter { YouTubeCatalogService.parentHubSlug(for: $0) == parent }
        }
        return YouTubeCatalogService.shared.rankForYouBySlugs(
            Array(pool.prefix(120)),
            followingIDs: [],
            myUserID: nil,
            sessionSeed: UInt64(Date().timeIntervalSince1970),
            focusSlug: nil
        )
    }

    private func normalizeSlug(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return "daily" }
        if HubCategoryClassifier.categories.contains(s) { return s }
        let parent = HubCategoryClassifier.parentCategory(of: s)
        return parent
    }

    static func neighbor(of slug: String) -> String {
        let cats = HubCategoryClassifier.categories
        guard let i = cats.firstIndex(of: slug) else { return "daily" }
        return cats[(i + 1) % cats.count]
    }

    // MARK: - Network

    private func fetchForYou(cursor: String?) async -> Page? {
        var comps = URLComponents(string: "\(AppConfig.apiBaseURL)/v1/hubs/for-you")
        var q: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(Self.pageSize)"),
            URLQueryItem(name: "session", value: sessionToken),
        ]
        if let cursor, !cursor.isEmpty {
            q.append(URLQueryItem(name: "cursor", value: cursor))
        }
        comps?.queryItems = q
        guard let url = comps?.url else { return nil }
        return await getPage(url: url, defaultSlug: nil)
    }

    private func fetchShelf(slug: String, cursor: String?) async -> Page? {
        let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        var comps = URLComponents(string: "\(AppConfig.apiBaseURL)/v1/hubs/shelves/\(encoded)")
        var q: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "\(Self.pageSize)"),
        ]
        if let cursor, !cursor.isEmpty {
            q.append(URLQueryItem(name: "cursor", value: cursor))
        }
        comps?.queryItems = q
        guard let url = comps?.url else { return nil }
        return await getPage(url: url, defaultSlug: slug)
    }

    private func getPage(url: URL, defaultSlug: String?) async -> Page? {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // Snappy first paint — never await token refresh (that made hubs “take years”).
        req.timeoutInterval = 4
        // Cached access token only (public shelves work without auth too).
        if let token = AuthService.shared.accessToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                json["ok"] as? Bool == true,
                let rawItems = json["items"] as? [[String: Any]]
            else { return nil }

            let posts = rawItems.compactMap {
                SurfacePageClient.mapThinCard($0, allowMissingMedia: false, fallbackSlug: defaultSlug)
            }
            let next = json["nextCursor"] as? String
            let slugsUsed = json["slugsUsed"] as? [String] ?? []
            let session = json["session"] as? String
            #if DEBUG
            print("[SlugShelf] \(url.path) items=\(posts.count) next=\(next != nil)")
            #endif
            // Media session 09: shelf list = posters only. Continuous player warms on open.
            ImageCache.shared.prefetchPostThumbnails(
                Array(posts.prefix(8)),
                maxPixelSize: 360,
                aggressive: false
            )
            return Page(items: posts, nextCursor: next, slugsUsed: slugsUsed, session: session)
        } catch {
            #if DEBUG
            print("[SlugShelf] fail \(url.path): \(error.localizedDescription)")
            #endif
            return nil
        }
    }

}
