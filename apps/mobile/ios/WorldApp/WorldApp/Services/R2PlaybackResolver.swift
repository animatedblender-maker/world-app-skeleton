import Foundation

/// Resolves a **currently playable** URL for R2 (and other) video posts.
///
/// The object in R2 never expires — only old presigned links do. This service always
/// asks the API for a live URL (`playbackMedia`) and caches it for most of a day.
@MainActor
final class R2PlaybackResolver {
    static let shared = R2PlaybackResolver()

    private struct CacheEntry {
        let url: URL
        let mediaURLPayload: String?
        let cachedAt: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private var inflight: [String: Task<URL?, Never>] = [:]
    /// Cache TTL — server re-presigns for 7d; refresh daily so clients stay safe.
    private let cacheTTL: TimeInterval = 20 * 3600

    private init() {}

    /// Live play URL for a post. Returns nil only when the API has nothing playable.
    func playURL(postID: String, fallback: URL? = nil) async -> URL? {
        let key = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return fallback }

        if let hit = cache[key], Date().timeIntervalSince(hit.cachedAt) < cacheTTL {
            return hit.url
        }
        if let task = inflight[key] {
            return await task.value ?? fallback
        }

        let task = Task<URL?, Never> { [weak self] in
            guard let self else { return fallback }
            do {
                let media = try await self.fetchPlaybackMedia(postID: key)
                if let url = URL(string: media.url), url.scheme != nil {
                    await MainActor.run {
                        self.cache[key] = CacheEntry(
                            url: url,
                            mediaURLPayload: media.media_url,
                            cachedAt: Date()
                        )
                        self.inflight[key] = nil
                        // Bound cache size.
                        if self.cache.count > 4000, let first = self.cache.keys.first {
                            self.cache.removeValue(forKey: first)
                        }
                    }
                    return url
                }
            } catch {
                #if DEBUG
                print("[R2Playback] resolve failed \(key.prefix(8)): \(error.localizedDescription)")
                #endif
            }
            await MainActor.run { self.inflight[key] = nil }
            return fallback
        }
        inflight[key] = task
        return await task.value
    }

    /// Drop cache entry so the next play re-fetches (after 403 / unavailable).
    func invalidate(postID: String) {
        let key = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        cache.removeValue(forKey: key)
        inflight[key]?.cancel()
        inflight[key] = nil
    }

    private struct PlaybackMediaDTO: Decodable {
        let post_id: String
        let url: String
        let media_url: String
        let r2_key: String?
    }

    private struct PlaybackMediaResponse: Decodable {
        let playbackMedia: PlaybackMediaDTO?
    }

    private func fetchPlaybackMedia(postID: String) async throws -> PlaybackMediaDTO {
        struct Response: Decodable { let playbackMedia: PlaybackMediaDTO? }
        let query = """
        query($post_id: ID!) {
          playbackMedia(post_id: $post_id) {
            post_id url media_url r2_key
          }
        }
        """
        let result: Response = try await GraphQLService.shared.authenticatedRequest(
            query: query,
            variables: ["post_id": postID]
        )
        if let media = result.playbackMedia { return media }

        // REST fallback if GraphQL field not deployed yet.
        return try await fetchPlaybackMediaREST(postID: postID)
    }

    private func fetchPlaybackMediaREST(postID: String) async throws -> PlaybackMediaDTO {
        let base = AppConfig.apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/v1/playback/\(postID)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = try? await AuthService.shared.ensureValidToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        struct REST: Decodable {
            let ok: Bool?
            let post_id: String?
            let url: String
            let media_url: String?
            let r2_key: String?
        }
        let body = try JSONDecoder().decode(REST.self, from: data)
        return PlaybackMediaDTO(
            post_id: body.post_id ?? postID,
            url: body.url,
            media_url: body.media_url ?? body.url,
            r2_key: body.r2_key
        )
    }
}
