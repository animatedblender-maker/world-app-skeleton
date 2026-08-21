import Foundation

/// Instant Frame 0 posters from the R2 pack path (server signs `…/frame0_512.webp`).
/// Prefer this over AVAssetImageGenerator — no client decode wait.
actor Frame0PosterResolver {
    static let shared = Frame0PosterResolver()

    private struct CacheEntry {
        let url: URL
        let cachedAt: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private var inflight: [String: Task<URL?, Never>] = [:]
    private let cacheTTL: TimeInterval = 6 * 3600
    /// Cap parallel single-poster GETs — neighbors were opening dozens of connections.
    private var activeFetches = 0
    private let maxConcurrentFetches = 4
    private var fetchWaiters: [CheckedContinuation<Void, Never>] = []

    /// Signed Frame 0 URL for a post (derived from media_path / r2_key on the server).
    func posterURL(postID: String, fallback: URL? = nil) async -> URL? {
        let key = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return fallback }

        if let hit = cache[key], Date().timeIntervalSince(hit.cachedAt) < cacheTTL {
            return hit.url
        }
        if let existing = inflight[key] {
            return await existing.value ?? fallback
        }

        await acquireFetchSlot()
        if let hit = cache[key], Date().timeIntervalSince(hit.cachedAt) < cacheTTL {
            releaseFetchSlot()
            return hit.url
        }
        if let existing = inflight[key] {
            releaseFetchSlot()
            return await existing.value ?? fallback
        }

        let task = Task { () -> URL? in
            defer { Task { await self.releaseFetchSlot() } }
            return await self.fetchAndCache(postID: key, fallback: fallback)
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        return result
    }

    private func acquireFetchSlot() async {
        if activeFetches < maxConcurrentFetches {
            activeFetches += 1
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            fetchWaiters.append(cont)
        }
        activeFetches += 1
    }

    private func releaseFetchSlot() {
        activeFetches = max(0, activeFetches - 1)
        if !fetchWaiters.isEmpty {
            fetchWaiters.removeFirst().resume()
        }
    }

    /// Warm a Sparks/Hubs window — one round-trip for many posts.
    func prefetch(postIDs: [String]) async {
        let ids = Array(
            Set(
                postIDs
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).prefix(24)
        guard !ids.isEmpty else { return }

        let missing = ids.filter { id in
            guard let hit = cache[id] else { return true }
            return Date().timeIntervalSince(hit.cachedAt) >= cacheTTL
        }
        guard !missing.isEmpty else { return }

        do {
            let posters = try await fetchBatch(postIDs: Array(missing))
            let now = Date()
            for (id, urlString) in posters {
                guard let url = URL(string: urlString), url.scheme != nil else { continue }
                cache[id] = CacheEntry(url: url, cachedAt: now)
            }
            if cache.count > 6000, let first = cache.keys.first {
                cache.removeValue(forKey: first)
            }
        } catch {
            #if DEBUG
            print("[Frame0Poster] batch failed: \(error.localizedDescription)")
            #endif
        }
    }

    func invalidate(postID: String) {
        let key = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        cache.removeValue(forKey: key)
        inflight[key]?.cancel()
        inflight[key] = nil
    }

    private func fetchAndCache(postID: String, fallback: URL?) async -> URL? {
        do {
            let url = try await fetchOne(postID: postID)
            cache[postID] = CacheEntry(url: url, cachedAt: Date())
            if cache.count > 6000, let first = cache.keys.first {
                cache.removeValue(forKey: first)
            }
            return url
        } catch {
            #if DEBUG
            print("[Frame0Poster] \(postID.prefix(8)): \(error.localizedDescription)")
            #endif
            return fallback
        }
    }

    private func fetchOne(postID: String) async throws -> URL {
        let base = AppConfig.apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let endpoint = URL(string: "\(base)/v1/poster/\(postID)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.timeoutInterval = 6
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = await MainActor.run(body: { AuthService.shared.accessToken() }) {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        struct REST: Decodable {
            let ok: Bool?
            let url: String
        }
        let body = try JSONDecoder().decode(REST.self, from: data)
        guard let url = URL(string: body.url), url.scheme != nil else {
            throw URLError(.cannotParseResponse)
        }
        return url
    }

    private func fetchBatch(postIDs: [String]) async throws -> [String: String] {
        let base = AppConfig.apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let endpoint = URL(string: "\(base)/v1/poster/batch") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await MainActor.run(body: { AuthService.shared.accessToken() }) {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["postIds": postIDs])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        struct REST: Decodable {
            let ok: Bool?
            let posters: [String: String]?
        }
        let body = try JSONDecoder().decode(REST.self, from: data)
        return body.posters ?? [:]
    }
}
