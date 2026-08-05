import Foundation

/// Internet Archive / hub_video_seed loader for Matterya Hubs + Sparks.
///
/// Loads `hub_videos.jsonl` and maps rows to playable `CountryPost` videos.
/// **Spark rule:** duration under 60 seconds → `mediaType = "reel"` (Sparks feed).
actor HubVideoSeedService {
    static let shared = HubVideoSeedService()

    /// Clips shorter than this become Sparks (vertical reels).
    static let sparkMaxDurationSeconds: Double = 60

    private var videos: [CountryPost] = []
    private var videosByID: [String: CountryPost] = [:]
    private var videosByHub: [String: [CountryPost]] = [:]
    private var sparkVideos: [CountryPost] = []
    private var didLoad = false

    struct HubVideoMeta: Sendable {
        let hubSlug: String
        let attribution: String
        let license: String?
        let licenseURL: String?
        let itemURL: String?
        let creator: String?
        let durationSeconds: Double?
    }

    private var attributions: [String: HubVideoMeta] = [:]

    /// Ordered hub shelves (long-form). Keep in sync with `YouTubeHomeFilter.hubCategories`.
    /// Shorts still land under these hubs as Sparks.
    static let hubOrder = [
        "social", "travel", "nature", "music", "food", "sports",
        "tech", "fitness", "film", "culture", "daily",
    ]

    /// Human-readable channel name for hub seed cards / attribution.
    static func channelDisplayName(hubSlug: String, isSpark: Bool = false) -> String {
        let slug = hubSlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let titled: String = {
            switch slug {
            case "social": return "Social"
            case "travel": return "Travel"
            case "nature": return "Nature"
            case "music": return "Music"
            case "food": return "Food"
            case "sports": return "Sports"
            case "tech": return "Tech"
            case "fitness": return "Fitness"
            case "film": return "Film"
            case "culture": return "Culture"
            case "daily": return "Daily"
            case "": return isSpark ? "Sparks" : "Hubs"
            default:
                return slug
                    .split(separator: "_")
                    .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                    .joined(separator: " ")
            }
        }()
        return isSpark ? "\(titled) Sparks" : titled
    }

    func allVideos() async -> [CountryPost] {
        await loadIfNeeded()
        return videos
    }

    /// Hub long-form only (not Sparks).
    func longFormVideos() async -> [CountryPost] {
        await loadIfNeeded()
        return videos.filter { !$0.isReel }
    }

    /// Slug-capped long-form catalog for Hubs home shelves (matches TF `catalogLongFormVideos`).
    /// Caps per hub so the first paint stays light; full channel lists still use `videos(forHub:)`.
    func catalogLongFormVideos(perHub: Int = 8) async -> [CountryPost] {
        await loadIfNeeded()
        var out: [CountryPost] = []
        var counts: [String: Int] = [:]
        for post in videos where !post.isReel {
            let slug = (post.externalRefID ?? post.hubSlug ?? "daily").lowercased()
            let n = counts[slug, default: 0]
            guard n < perHub else { continue }
            counts[slug] = n + 1
            out.append(post)
        }
        return out
    }

    /// Archive clips under 60s — for Sparks / reels strip.
    /// - Parameters:
    ///   - limit: Max clips to return (default all).
    ///   - shuffleSeed: When set, deterministic shuffle so each open feels fresh.
    func sparkSeedVideos(limit: Int? = nil, shuffleSeed: UInt64? = nil) async -> [CountryPost] {
        await loadIfNeeded()
        var result = sparkVideos
        if let shuffleSeed {
            var rng = SeededGenerator(seed: shuffleSeed)
            result.shuffle(using: &rng)
        }
        if let limit, limit >= 0 {
            result = Array(result.prefix(limit))
        }
        return result
    }

    /// Simple deterministic PRNG for spark reshuffles (no Foundation dependency on GameplayKit).
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    func videos(forHub slug: String) async -> [CountryPost] {
        await loadIfNeeded()
        return videosByHub[slug.lowercased()] ?? []
    }

    func post(id: String) async -> CountryPost? {
        await loadIfNeeded()
        return videosByID[id]
    }

    func meta(forPostID id: String) async -> HubVideoMeta? {
        await loadIfNeeded()
        return attributions[id]
    }

    func isHubVideoID(_ id: String) async -> Bool {
        await loadIfNeeded()
        return videosByID[id] != nil
    }

    private func loadIfNeeded() async {
        if didLoad { return }
        await loadFromDiskOrRemote()
        didLoad = true
    }

    private func loadFromDiskOrRemote() async {
        if let path = Self.resolveJSONLPath() {
            await streamFile(path: path)
        }
        // If cache was empty/corrupt, try every known source until we get rows.
        if videos.isEmpty {
            for path in Self.candidateSeedPaths() {
                await streamFile(path: path)
                if !videos.isEmpty { break }
            }
        }
        #if DEBUG
        print("[HubVideoSeed] loaded \(videos.count) videos sparks=\(sparkVideos.count) path=\(Self.resolveJSONLPath() ?? "none")")
        #endif
    }

    private func streamFile(path: String) async {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8), !text.isEmpty else {
            #if DEBUG
            print("[HubVideoSeed] FAILED read \(path)")
            #endif
            return
        }
        var batch: [CountryPost] = []
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let mapped = mapRow(json)
            else { continue }
            batch.append(mapped.post)
            attributions[mapped.post.id] = mapped.meta
        }
        apply(batch)
    }

    private func apply(_ batch: [CountryPost]) {
        guard !batch.isEmpty else { return }
        videos = batch
        videosByID = Dictionary(uniqueKeysWithValues: batch.map { ($0.id, $0) })
        videosByHub = [:]
        sparkVideos = []
        for post in batch {
            let slug = (post.externalRefID ?? "daily").lowercased()
            videosByHub[slug, default: []].append(post)
            if post.isReel {
                sparkVideos.append(post)
            }
        }
    }

    private func mapRow(_ row: [String: Any]) -> (post: CountryPost, meta: HubVideoMeta)? {
        guard let id = row["id"] as? String, !id.isEmpty else { return nil }
        let hubSlug = ((row["hub_slug"] as? String) ?? "daily").lowercased()
        let title = (row["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (row["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let media = row["media"] as? [String: Any]
        guard let mediaURL = media?["url"] as? String, !mediaURL.isEmpty else { return nil }
        // DVD / container extracts that AVPlayer cannot progressive-play.
        let lowerURL = mediaURL.lowercased()
        if lowerURL.contains("video_ts") || lowerURL.hasSuffix(".vob") || lowerURL.hasSuffix(".iso") {
            return nil
        }
        let thumb = media?["thumb_url"] as? String
        let creator = (row["creator"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let attribution = (row["attribution"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? {
                let t = title ?? "Untitled"
                let who = creator ?? "Internet Archive"
                let lic = (row["license"] as? String) ?? ""
                let item = (row["item_url"] as? String) ?? ""
                return "\"\(t)\" by \(who) — Internet Archive — \(lic) — \(item)"
            }()
        let itemURL = row["item_url"] as? String
        let license = row["license"] as? String
        let licenseURL = row["license_url"] as? String

        let duration = Self.parseDurationSeconds(media?["duration"])
        // Under 60s → Spark (reel). Tags may also force spark.
        let tags = (row["tags"] as? [String]) ?? []
        let taggedSpark = tags.contains { $0.lowercased() == "spark" || $0.lowercased() == "short" }
        // ≤ 60s counts as a Spark (TikTok-length / under a minute).
        let isSpark = (duration != nil && duration! > 0 && duration! <= Self.sparkMaxDurationSeconds) || taggedSpark
        let mediaType = isSpark ? "reel" : "video"

        let authorID = isSpark ? "hub_spark_\(hubSlug)" : "hub_\(hubSlug)"
        let displayName = (creator?.isEmpty == false) ? creator! : (isSpark ? "Sparks" : "Internet Archive")
        let author = PostAuthor(
            userID: authorID,
            displayName: displayName,
            username: isSpark ? "sparks_\(hubSlug)" : hubSlug,
            avatarURL: nil,
            countryName: nil,
            countryCode: nil,
            lastReadAt: nil
        )

        let now = ISO8601DateFormatter().string(from: Date())
        // Sparks get a body marker so other layers treat them as reels if mediaType is lost.
        let bodyOut: String
        if isSpark {
            let base = body.isEmpty ? (title ?? "Spark") : body
            bodyOut = base.contains("__spark__|") ? base : "__spark__|\(base)"
        } else {
            bodyOut = body.isEmpty ? attribution : body
        }

        let post = CountryPost(
            id: id,
            title: title,
            body: bodyOut,
            mediaType: mediaType,
            mediaURL: mediaURL,
            thumbURL: thumb,
            mediaCaption: attribution,
            sharedPostID: nil,
            visibility: .public,
            likeCount: 0,
            commentCount: 0,
            viewCount: 0,
            likedByMe: false,
            savedByMe: false,
            createdAt: now,
            updatedAt: now,
            authorID: authorID,
            countryName: nil,
            countryCode: nil,
            cityName: nil,
            author: author,
            linkURL: itemURL,
            linkTitle: "Internet Archive",
            externalRefType: "hub",
            externalRefID: hubSlug
        )

        let meta = HubVideoMeta(
            hubSlug: hubSlug,
            attribution: attribution,
            license: license,
            licenseURL: licenseURL,
            itemURL: itemURL,
            creator: creator,
            durationSeconds: duration
        )
        return (post, meta)
    }

    private static func parseDurationSeconds(_ raw: Any?) -> Double? {
        guard let raw else { return nil }
        if let n = raw as? Double, n > 0 { return n }
        if let n = raw as? Int, n > 0 { return Double(n) }
        if let s = raw as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return nil }
            if let v = Double(t), v > 0 { return v }
            let parts = t.split(separator: ":")
            if parts.count == 2,
               let m = Double(parts[0]),
               let sec = Double(parts[1]) {
                return m * 60 + sec
            }
            if parts.count == 3,
               let h = Double(parts[0]),
               let m = Double(parts[1]),
               let sec = Double(parts[2]) {
                return h * 3600 + m * 60 + sec
            }
        }
        return nil
    }

    /// Prefer the largest non-empty seed (bundle wins over a stale/empty cache).
    private static func candidateSeedPaths() -> [String] {
        var paths: [String] = []
        if let p = Bundle.main.url(forResource: "hub_videos", withExtension: "jsonl", subdirectory: "hub_video_seed")?.path {
            paths.append(p)
        }
        if let p = Bundle.main.url(forResource: "hub_videos", withExtension: "jsonl")?.path {
            paths.append(p)
        }
        paths.append(contentsOf: [
            "/Users/animated/Development/world-app-skeleton/hub_video_seed/hub_videos.jsonl",
            "/Volumes/MatteryaSSD/Development/Projects/World_App/world-app-skeleton/hub_video_seed/hub_videos.jsonl",
            "/Volumes/MatteryaSSD/Development/Projects/World_App/world-app-skeleton/apps/mobile/ios/WorldApp/WorldApp/Resources/hub_video_seed/hub_videos.jsonl",
            "/Users/animated/Development/world-app-skeleton/apps/mobile/ios/WorldApp/WorldApp/Resources/hub_video_seed/hub_videos.jsonl",
        ])
        return paths
    }

    private static func resolveJSONLPath() -> String? {
        let fm = FileManager.default
        // v4: large funny/shorts Archive fill — bump so old small caches are replaced.
        let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hub_video_seed_v5", isDirectory: true)
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cacheFile = cacheDir.appendingPathComponent("hub_videos.jsonl").path

        let candidates = candidateSeedPaths().filter { fm.fileExists(atPath: $0) }
        // Largest non-empty source is the best seed.
        let bestSource = candidates
            .compactMap { path -> (String, Int)? in
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let size = attrs[.size] as? NSNumber,
                      size.intValue > 100
                else { return nil }
                return (path, size.intValue)
            }
            .max(by: { $0.1 < $1.1 })?
            .0

        if let bestSource {
            let bestSize = (try? fm.attributesOfItem(atPath: bestSource)[.size] as? NSNumber)?.intValue ?? 0
            let cacheSize = (try? fm.attributesOfItem(atPath: cacheFile)[.size] as? NSNumber)?.intValue ?? 0
            if cacheSize < bestSize {
                try? fm.removeItem(atPath: cacheFile)
                try? fm.copyItem(atPath: bestSource, toPath: cacheFile)
            }
        }

        if fm.fileExists(atPath: cacheFile),
           let size = try? fm.attributesOfItem(atPath: cacheFile)[.size] as? NSNumber,
           size.intValue > 100 {
            return cacheFile
        }
        return bestSource
    }
}

extension CountryPost {
    var hubSlug: String? {
        guard externalRefType == "hub" else { return nil }
        return externalRefID?.lowercased()
    }

    var isHubSeedVideo: Bool { externalRefType == "hub" }

    var hubAttributionText: String? {
        guard isHubSeedVideo else { return nil }
        let caption = mediaCaption?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let caption, !caption.isEmpty { return caption }
        return nil
    }
}
