import Foundation

/// Matterya Studio — Hubs channel owner analytics (`/v1/studio/*`).
enum StudioService {
    enum Range: String, CaseIterable, Identifiable, Sendable {
        case d7 = "7d"
        case d28 = "28d"
        case d90 = "90d"
        var id: String { rawValue }
        var label: String { rawValue }
    }

    enum Sort: String, CaseIterable, Identifiable, Sendable {
        case views
        case watch
        case ctr
        case newest
        var id: String { rawValue }
        var label: String {
            switch self {
            case .views: "Views"
            case .watch: "Watch time"
            case .ctr: "CTR"
            case .newest: "Newest"
            }
        }
    }

    struct Channel: Sendable, Identifiable {
        var id: String
        var ownerUserId: String
        var name: String
        var handle: String?
        var about: String?
        var avatarUrl: String?
        var coverUrl: String?
        var videoCount: Int
    }

    struct VideoRow: Sendable, Identifiable, Hashable {
        var id: String
        var title: String?
        var thumbUrl: String?
        var mediaType: String?
        var createdAt: String?
        var hubSlug: String?
        var views: Int
        var watchMs: Int
        var impressions: Int
        var clicks: Int
        var ctr: Double?
        var completes: Int
        var qualityScore: Double?
    }

    struct DailyPoint: Sendable {
        var day: String
        var views: Int
        var watchMs: Int
        var impressions: Int
    }

    struct KPIs: Sendable {
        var views: Int
        var watchMs: Int
        var impressions: Int
        var clicks: Int
        var ctr: Double?
        var avgViewDurationMs: Int?
        var avgViewPercentage: Double?
        var completes: Int
        var skips: Int
        var likes: Int
        var comments: Int
        var subscribers: Int
        var videos: Int
    }

    struct Dashboard: Sendable {
        var range: Range
        var rangeDays: Int
        var channelId: String
        var kpis: KPIs
        var daily: [DailyPoint]
        var topVideos: [VideoRow]
        var note: String
    }

    struct Funnel: Sendable {
        var impressions: Int
        var clicks: Int
        var ctr: Double?
        var views: Int
        var completes: Int
        var skips: Int
        var likes: Int
        var comments: Int
        var watchMs: Int
    }

    struct SourceRow: Sendable, Identifiable {
        var id: String { source }
        var source: String
        var views: Int
    }

    struct RetentionBucket: Sendable, Identifiable {
        var id: Int { bucket }
        var bucket: Int
        var reached: Double
    }

    struct VideoAnalytics: Sendable {
        var range: Range
        var video: VideoRow
        var funnel: Funnel
        var sources: [SourceRow]
        var retention: [RetentionBucket]
        var daily: [DailyPoint]
        var note: String
    }

    enum StudioError: LocalizedError, Equatable {
        case unauthenticated
        case channelRequired
        case timedOut
        case message(String)

        var errorDescription: String? {
            switch self {
            case .unauthenticated: "Sign in to open Studio."
            case .channelRequired: "channel_required"
            case .timedOut: "Studio request timed out."
            case .message(let s): s
            }
        }
    }

    // MARK: - API

    static func channel() async throws -> (hasChannel: Bool, channel: Channel?) {
        let json = try await getJSON(path: "/v1/studio/channel")
        let has = (json["hasChannel"] as? Bool) ?? false
        let channel = parseChannel(json["channel"] as? [String: Any])
        return (has, channel)
    }

    static func dashboard(range: Range = .d28) async throws -> Dashboard {
        let json = try await getJSON(path: "/v1/studio/dashboard", query: ["range": range.rawValue])
        guard let raw = json["dashboard"] as? [String: Any],
              let parsed = parseDashboard(raw)
        else {
            throw StudioError.message("Invalid dashboard response.")
        }
        return parsed
    }

    static func videos(
        range: Range = .d28,
        sort: Sort = .views,
        cursor: String? = nil,
        limit: Int = 30
    ) async throws -> (videos: [VideoRow], nextCursor: String?, range: Range) {
        var q: [String: String] = [
            "range": range.rawValue,
            "sort": sort.rawValue,
            "limit": String(limit),
        ]
        if let cursor, !cursor.isEmpty { q["cursor"] = cursor }
        let json = try await getJSON(path: "/v1/studio/videos", query: q)
        let rows = (json["videos"] as? [[String: Any]] ?? []).compactMap(parseVideoRow)
        let next = json["nextCursor"] as? String
        let r = Range(rawValue: (json["range"] as? String) ?? range.rawValue) ?? range
        return (rows, next, r)
    }

    static func videoAnalytics(id: String, range: Range = .d28) async throws -> VideoAnalytics {
        let json = try await getJSON(
            path: "/v1/studio/videos/\(id)/analytics",
            query: ["range": range.rawValue]
        )
        guard let raw = json["analytics"] as? [String: Any],
              let parsed = parseVideoAnalytics(raw)
        else {
            throw StudioError.message("Invalid analytics response.")
        }
        return parsed
    }

    // MARK: - Formatters

    static func formatWatch(_ ms: Int?) -> String {
        let s = max(0, Int(round(Double(ms ?? 0) / 1000.0)))
        if s < 60 { return "\(s)s" }
        let m = s / 60
        let rem = s % 60
        if m < 60 { return rem > 0 ? "\(m)m \(rem)s" : "\(m)m" }
        let h = m / 60
        let rm = m % 60
        return rm > 0 ? "\(h)h \(rm)m" : "\(h)h"
    }

    static func formatCtr(_ ctr: Double?) -> String {
        guard let ctr, ctr.isFinite else { return "—" }
        return String(format: "%.1f%%", ctr * 100)
    }

    static func formatCount(_ n: Int?) -> String {
        let v = n ?? 0
        if v >= 1_000_000 { return String(format: "%.1fM", Double(v) / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fK", Double(v) / 1_000) }
        return String(v)
    }

    static func formatDate(_ iso: String?) -> String {
        guard let iso, let date = RelativeTime.parseDate(iso) else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    // MARK: - HTTP

    private static func getJSON(
        path: String,
        query: [String: String] = [:]
    ) async throws -> [String: Any] {
        guard let token = try? await AuthService.shared.ensureValidToken(), !token.isEmpty else {
            throw StudioError.unauthenticated
        }
        var comps = URLComponents(string: "\(AppConfig.apiBaseURL)\(path)")
        if !query.isEmpty {
            comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps?.url else {
            throw StudioError.message("Invalid Studio URL.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let http = response as? HTTPURLResponse
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let status = http?.statusCode ?? 0
            if (200..<300).contains(status) {
                return json
            }
            let err = String(json["error"] as? String ?? "Request failed (\(status))")
            if status == 404, err == "channel_required" {
                throw StudioError.channelRequired
            }
            if status == 401 {
                throw StudioError.unauthenticated
            }
            throw StudioError.message(err)
        } catch let e as StudioError {
            throw e
        } catch let e as URLError where e.code == .timedOut || e.code == .cancelled {
            throw StudioError.timedOut
        } catch {
            throw StudioError.message(error.localizedDescription)
        }
    }

    // MARK: - Parse

    private static func parseChannel(_ raw: [String: Any]?) -> Channel? {
        guard let raw,
              let id = stringValue(raw["id"]),
              let owner = stringValue(raw["owner_user_id"]) ?? stringValue(raw["ownerUserId"]),
              let name = stringValue(raw["name"])
        else { return nil }
        return Channel(
            id: id,
            ownerUserId: owner,
            name: name,
            handle: stringValue(raw["handle"]),
            about: stringValue(raw["about"]),
            avatarUrl: stringValue(raw["avatar_url"]) ?? stringValue(raw["avatarUrl"]),
            coverUrl: stringValue(raw["cover_url"]) ?? stringValue(raw["coverUrl"]),
            videoCount: intValue(raw["video_count"]) ?? intValue(raw["videoCount"]) ?? 0
        )
    }

    private static func parseDashboard(_ raw: [String: Any]) -> Dashboard? {
        guard let channelId = stringValue(raw["channelId"]) ?? stringValue(raw["channel_id"]),
              let kpisRaw = raw["kpis"] as? [String: Any]
        else { return nil }
        let range = Range(rawValue: stringValue(raw["range"]) ?? "28d") ?? .d28
        let kpis = KPIs(
            views: intValue(kpisRaw["views"]) ?? 0,
            watchMs: intValue(kpisRaw["watchMs"]) ?? intValue(kpisRaw["watch_ms"]) ?? 0,
            impressions: intValue(kpisRaw["impressions"]) ?? 0,
            clicks: intValue(kpisRaw["clicks"]) ?? 0,
            ctr: doubleValue(kpisRaw["ctr"]),
            avgViewDurationMs: intValue(kpisRaw["avgViewDurationMs"]) ?? intValue(kpisRaw["avg_view_duration_ms"]),
            avgViewPercentage: doubleValue(kpisRaw["avgViewPercentage"]) ?? doubleValue(kpisRaw["avg_view_percentage"]),
            completes: intValue(kpisRaw["completes"]) ?? 0,
            skips: intValue(kpisRaw["skips"]) ?? 0,
            likes: intValue(kpisRaw["likes"]) ?? 0,
            comments: intValue(kpisRaw["comments"]) ?? 0,
            subscribers: intValue(kpisRaw["subscribers"]) ?? 0,
            videos: intValue(kpisRaw["videos"]) ?? 0
        )
        let daily = (raw["daily"] as? [[String: Any]] ?? []).compactMap(parseDaily)
        let top = (raw["topVideos"] as? [[String: Any]] ?? []).compactMap(parseVideoRow)
        return Dashboard(
            range: range,
            rangeDays: intValue(raw["rangeDays"]) ?? intValue(raw["range_days"]) ?? 28,
            channelId: channelId,
            kpis: kpis,
            daily: daily,
            topVideos: top,
            note: stringValue(raw["note"]) ?? ""
        )
    }

    private static func parseVideoAnalytics(_ raw: [String: Any]) -> VideoAnalytics? {
        guard let videoRaw = raw["video"] as? [String: Any],
              let video = parseVideoRow(videoRaw),
              let funnelRaw = raw["funnel"] as? [String: Any]
        else { return nil }
        let range = Range(rawValue: stringValue(raw["range"]) ?? "28d") ?? .d28
        let funnel = Funnel(
            impressions: intValue(funnelRaw["impressions"]) ?? 0,
            clicks: intValue(funnelRaw["clicks"]) ?? 0,
            ctr: doubleValue(funnelRaw["ctr"]),
            views: intValue(funnelRaw["views"]) ?? 0,
            completes: intValue(funnelRaw["completes"]) ?? 0,
            skips: intValue(funnelRaw["skips"]) ?? 0,
            likes: intValue(funnelRaw["likes"]) ?? 0,
            comments: intValue(funnelRaw["comments"]) ?? 0,
            watchMs: intValue(funnelRaw["watchMs"]) ?? intValue(funnelRaw["watch_ms"]) ?? 0
        )
        let sources = (raw["sources"] as? [[String: Any]] ?? []).compactMap { row -> SourceRow? in
            guard let source = stringValue(row["source"]) else { return nil }
            return SourceRow(source: source, views: intValue(row["views"]) ?? 0)
        }
        let retention = (raw["retention"] as? [[String: Any]] ?? []).compactMap { row -> RetentionBucket? in
            guard let bucket = intValue(row["bucket"]) else { return nil }
            return RetentionBucket(bucket: bucket, reached: doubleValue(row["reached"]) ?? 0)
        }
        return VideoAnalytics(
            range: range,
            video: video,
            funnel: funnel,
            sources: sources,
            retention: retention,
            daily: (raw["daily"] as? [[String: Any]] ?? []).compactMap(parseDaily),
            note: stringValue(raw["note"]) ?? ""
        )
    }

    private static func parseVideoRow(_ raw: [String: Any]) -> VideoRow? {
        guard let id = stringValue(raw["id"]) else { return nil }
        return VideoRow(
            id: id,
            title: stringValue(raw["title"]),
            thumbUrl: stringValue(raw["thumbUrl"]) ?? stringValue(raw["thumb_url"]),
            mediaType: stringValue(raw["mediaType"]) ?? stringValue(raw["media_type"]),
            createdAt: stringValue(raw["createdAt"]) ?? stringValue(raw["created_at"]),
            hubSlug: stringValue(raw["hubSlug"]) ?? stringValue(raw["hub_slug"]),
            views: intValue(raw["views"]) ?? 0,
            watchMs: intValue(raw["watchMs"]) ?? intValue(raw["watch_ms"]) ?? 0,
            impressions: intValue(raw["impressions"]) ?? 0,
            clicks: intValue(raw["clicks"]) ?? 0,
            ctr: doubleValue(raw["ctr"]),
            completes: intValue(raw["completes"]) ?? 0,
            qualityScore: doubleValue(raw["qualityScore"]) ?? doubleValue(raw["quality_score"])
        )
    }

    private static func parseDaily(_ raw: [String: Any]) -> DailyPoint? {
        guard let day = stringValue(raw["day"]) else { return nil }
        return DailyPoint(
            day: day,
            views: intValue(raw["views"]) ?? 0,
            watchMs: intValue(raw["watchMs"]) ?? intValue(raw["watch_ms"]) ?? 0,
            impressions: intValue(raw["impressions"]) ?? 0
        )
    }

    private static func stringValue(_ any: Any?) -> String? {
        if let s = any as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String, let i = Int(s) { return i }
        if let d = any as? Double { return Int(d) }
        return nil
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if any is NSNull { return nil }
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String, let d = Double(s) { return d }
        if let i = any as? Int { return Double(i) }
        return nil
    }
}
