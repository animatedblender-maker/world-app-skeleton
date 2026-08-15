import Foundation

/// Resolves a **currently playable** URL for R2 video posts **when needed**.
///
/// Call only when a presign is expired/near-expiry or playback failed — not on every play.
/// (GraphQL-on-every-play blocked the UI → stuck loading, feed lag, random audio.)
final class R2PlaybackResolver: @unchecked Sendable {
    static let shared = R2PlaybackResolver()

    private struct CacheEntry {
        let url: URL
        let mediaURLPayload: String?
        let cachedAt: Date
    }

    private let lock = NSLock()
    private var cache: [String: CacheEntry] = [:]
    private var inflight: [String: Task<URL?, Never>] = [:]
    private let cacheTTL: TimeInterval = 20 * 3600

    private init() {}

    /// Live play URL for a post. Prefer `fallback` path when API is slow/fails.
    func playURL(postID: String, fallback: URL? = nil) async -> URL? {
        let key = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return fallback }

        lock.lock()
        if let hit = cache[key], Date().timeIntervalSince(hit.cachedAt) < cacheTTL {
            let url = hit.url
            lock.unlock()
            return url
        }
        if let existing = inflight[key] {
            lock.unlock()
            return await existing.value ?? fallback
        }
        let task = Task<URL?, Never> {
            await self.fetchAndCache(postID: key, fallback: fallback)
        }
        inflight[key] = task
        lock.unlock()

        let result = await task.value
        lock.lock()
        inflight[key] = nil
        lock.unlock()
        return result
    }

    private func fetchAndCache(postID: String, fallback: URL?) async -> URL? {
        do {
            let media = try await fetchPlaybackMedia(postID: postID)
            if let url = URL(string: media.url), url.scheme != nil {
                lock.lock()
                cache[postID] = CacheEntry(url: url, mediaURLPayload: media.media_url, cachedAt: Date())
                if cache.count > 4000, let first = cache.keys.first {
                    cache.removeValue(forKey: first)
                }
                lock.unlock()
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
        lock.lock()
        cache.removeValue(forKey: key)
        inflight[key]?.cancel()
        inflight[key] = nil
        lock.unlock()
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
        // Prefer unauthenticated path when possible — but our GraphQL usually needs auth.
        // Use a short timeout via REST first (lighter than GraphQL for this one field).
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
        req.timeoutInterval = 8
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
