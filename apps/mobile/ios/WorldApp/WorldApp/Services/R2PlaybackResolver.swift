import Foundation

/// Resolves a **currently playable** URL for R2 video posts **when needed**.
///
/// Call only when a presign is expired/near-expiry or playback failed — not on every play.
/// Actor isolation keeps cache access async-safe (no NSLock in async contexts).
actor R2PlaybackResolver {
    static let shared = R2PlaybackResolver()

    private struct CacheEntry {
        let url: URL
        let mediaURLPayload: String?
        let cachedAt: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private var inflight: [String: Task<URL?, Never>] = [:]
    private let cacheTTL: TimeInterval = 20 * 3600

    /// Live play URL for a post. Prefer `fallback` path when API is slow/fails.
    func playURL(postID: String, fallback: URL? = nil) async -> URL? {
        let key = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return fallback }

        if let hit = cache[key], Date().timeIntervalSince(hit.cachedAt) < cacheTTL {
            return hit.url
        }
        if let existing = inflight[key] {
            return await existing.value ?? fallback
        }

        let task = Task { () -> URL? in
            await self.fetchAndCache(postID: key, fallback: fallback)
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        return result
    }

    private func fetchAndCache(postID: String, fallback: URL?) async -> URL? {
        do {
            let media = try await fetchPlaybackMedia(postID: postID)
            if let url = URL(string: media.url), url.scheme != nil {
                cache[postID] = CacheEntry(url: url, mediaURLPayload: media.media_url, cachedAt: Date())
                if cache.count > 4000, let first = cache.keys.first {
                    cache.removeValue(forKey: first)
                }
                return url
            }
        } catch {
            #if DEBUG
            print("[R2Playback] resolve failed \(postID.prefix(8)): \(error.localizedDescription)")
            #endif
        }
        return fallback
    }

    /// Drop cache so the next play re-fetches (after 403 / unavailable).
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

    private func fetchPlaybackMedia(postID: String) async throws -> PlaybackMediaDTO {
        struct Response: Decodable { let playbackMedia: PlaybackMediaDTO? }
        let query = """
        query($post_id: ID!) {
          playbackMedia(post_id: $post_id) {
            post_id url media_url r2_key
          }
        }
        """
        if let rest = try? await fetchPlaybackMediaREST(postID: postID) {
            return rest
        }
        let result: Response = try await GraphQLService.shared.authenticatedRequest(
            query: query,
            variables: ["post_id": postID]
        )
        if let media = result.playbackMedia { return media }
        throw URLError(.resourceUnavailable)
    }

    private func fetchPlaybackMediaREST(postID: String) async throws -> PlaybackMediaDTO {
        let base = AppConfig.apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/v1/playback/\(postID)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // Cached token only — ensureValidToken on every play made Hubs feel stuck.
        if let token = await MainActor.run(body: { AuthService.shared.accessToken() }) {
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
