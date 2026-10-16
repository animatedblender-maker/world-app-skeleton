import Foundation

/// MainActor mirror of Frame0 signed URLs so SwiftUI can paint first frames
/// immediately after `Frame0PosterResolver.prefetch` (lives in this file so Xcode
/// target membership matches — do not split into an unlisted .swift file).
@MainActor
enum Frame0PosterCache {
    private static var map: [String: URL] = [:]

    static func url(for postID: String) -> URL? {
        let key = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return map[key]
    }

    static func store(_ postID: String, _ url: URL) {
        let key = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        map[key] = url
        if map.count > 4000, let first = map.keys.first {
            map.removeValue(forKey: first)
        }
    }

    static func storeBatch(_ posters: [String: URL]) {
        for (id, url) in posters {
            store(id, url)
        }
    }
}

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
    /// Coalesce overlapping prefetch windows (Feed + Hubs + Sparks open-path).
    private var batchInFlight = false
    private var pendingBatchIDs: Set<String> = []
    private var consecutiveBatchFailures = 0
    private var batchCircuitOpenUntil: Date = .distantPast
    private let batchCircuitCooldown: TimeInterval = 20

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
            await self.fetchAndCache(postID: key, fallback: fallback)
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        // Back on the actor after the child task — sync release (no nested await).
        releaseFetchSlot()
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
    /// Single-flight + circuit: overlapping Feed/Hubs/Sparks calls merge into one batch.
    func prefetch(postIDs: [String]) async {
        let now = Date()
        if now < batchCircuitOpenUntil { return }

        let ids = Set(
            postIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !ids.isEmpty else { return }

        let missing = ids.filter { id in
            guard let hit = cache[id] else { return true }
            return Date().timeIntervalSince(hit.cachedAt) >= cacheTTL
        }
        guard !missing.isEmpty else { return }

        pendingBatchIDs.formUnion(missing)
        if batchInFlight { return }
        batchInFlight = true

        // Chunk so a large Feed/Sparks/Hubs window does not one-shot the API.
        let chunkSize = 24
        while !pendingBatchIDs.isEmpty {
            if Date() < batchCircuitOpenUntil {
                pendingBatchIDs.removeAll()
                break
            }
            let snapshot = Array(pendingBatchIDs).prefix(chunkSize)
            pendingBatchIDs.subtract(snapshot)
            let chunk = Array(snapshot)
            guard !chunk.isEmpty else { break }
            do {
                let posters = try await fetchBatch(postIDs: chunk)
                consecutiveBatchFailures = 0
                let stamped = Date()
                var mirroredMutable: [String: URL] = [:]
                for (id, urlString) in posters {
                    guard let url = URL(string: urlString), url.scheme != nil else { continue }
                    cache[id] = CacheEntry(url: url, cachedAt: stamped)
                    mirroredMutable[id] = url
                }
                if cache.count > 6000, let first = cache.keys.first {
                    cache.removeValue(forKey: first)
                }
                let mirrored = mirroredMutable
                if !mirrored.isEmpty {
                    let urls = Array(mirrored.values)
                    await MainActor.run {
                        Frame0PosterCache.storeBatch(mirrored)
                        // Warm CDN bytes so first paint is not an empty black box.
                        ImageCache.shared.prefetch(urls, maxPixelSize: 420)
                    }
                }
            } catch {
                consecutiveBatchFailures += 1
                if consecutiveBatchFailures >= 2 {
                    batchCircuitOpenUntil = Date().addingTimeInterval(batchCircuitCooldown)
                    consecutiveBatchFailures = 0
                    pendingBatchIDs.removeAll()
                    #if DEBUG
                    print("[Frame0Poster] batch circuit open \(Int(batchCircuitCooldown))s")
                    #endif
                }
                #if DEBUG
                print("[Frame0Poster] batch failed: \(error.localizedDescription)")
                #endif
                break
            }
        }

        batchInFlight = false
        // IDs queued while the last chunk ran — drain without dropping.
        if !pendingBatchIDs.isEmpty, Date() >= batchCircuitOpenUntil {
            let leftover = Array(pendingBatchIDs)
            pendingBatchIDs.removeAll()
            await prefetch(postIDs: leftover)
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
            await MainActor.run { Frame0PosterCache.store(postID, url) }
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
        // Match Surface cold-start headroom; parallel open-path used to trip 10s.
        req.timeoutInterval = 12
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
