import Foundation
import UIKit

/// Sends every meaningful attention signal to the API → Kafka `matterya.engagement`.
///
/// - Scroll: appear/disappear on feed cards → "stopped and looked" vs "scrolled past"
/// - Hubs: open / leave / shelf / video
/// - Screens: tab switches
///
/// Batches every few seconds so Kafka stays readable without melting the battery.
@MainActor
final class EngagementTracker {
    static let shared = EngagementTracker()

    private struct PendingEvent: Sendable {
        var type: String
        var contentId: String?
        var authorId: String?
        var countryCode: String?
        var hubSlug: String?
        var mediaType: String?
        var isSpark: Bool
        var durationMs: Int?
        var progress: Double?
        var surface: String?
        var occurredAt: Date
        var meta: [String: String]?
    }

    private struct VisiblePost {
        let post: CountryPost
        let surface: String
        let startedAt: Date
    }

    private var queue: [PendingEvent] = []
    private var visible: [String: VisiblePost] = [:]
    private var flushTask: Task<Void, Never>?
    private var hubOpenedAt: Date?
    private var currentScreen: String?
    private var screenOpenedAt: Date?
    private let sessionId = UUID().uuidString

    /// Looked long enough to count as interest (not a fly-by).
    private let lookThresholdMs: Int = 1_200
    /// Faster than this → "scrolled past"
    private let skipThresholdMs: Int = 500

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.appBackgrounded()
            }
        }
    }

    // MARK: - Feed / post visibility

    func feedPostAppeared(_ post: CountryPost, surface: String = "home") {
        // Seed / hub archive posts still get tracked (behavior about content, not only live UUIDs).
        visible[post.id] = VisiblePost(post: post, surface: surface, startedAt: Date())
        scheduleFlush()
    }

    func feedPostDisappeared(_ post: CountryPost) {
        guard let entry = visible.removeValue(forKey: post.id) else { return }
        let ms = Int(Date().timeIntervalSince(entry.startedAt) * 1000)
        if ms < 80 { return } // layout flicker

        if ms >= lookThresholdMs {
            enqueue(
                type: "scroll_dwell",
                post: entry.post,
                surface: entry.surface,
                durationMs: ms
            )
        } else if ms <= skipThresholdMs {
            enqueue(
                type: "scroll_skip",
                post: entry.post,
                surface: entry.surface,
                durationMs: ms
            )
        } else {
            // Brief glance
            enqueue(
                type: "scroll_dwell",
                post: entry.post,
                surface: entry.surface,
                durationMs: ms
            )
        }
    }

    // MARK: - Video

    func videoProgress(post: CountryPost, progress: Double, durationMs: Int, surface: String) {
        let type = progress >= 0.92 ? "watch_complete" : "watch_partial"
        enqueue(
            type: type,
            post: post,
            surface: surface,
            durationMs: durationMs,
            progress: min(1, max(0, progress))
        )
    }

    // MARK: - Hubs

    func hubsOpened() {
        hubOpenedAt = Date()
        enqueue(type: "hub_open", surface: "hubs", meta: ["place": "hubs_tab"])
    }

    func hubsLeft() {
        guard let opened = hubOpenedAt else { return }
        let ms = Int(Date().timeIntervalSince(opened) * 1000)
        hubOpenedAt = nil
        enqueue(type: "hub_leave", surface: "hubs", durationMs: ms, meta: ["place": "hubs_tab"])
    }

    func enqueuePersonFollow(targetID: String, following: Bool) {
        enqueue(
            type: following ? "person_follow" : "person_unfollow",
            authorId: targetID,
            surface: "profile",
            meta: ["targetUserId": targetID]
        )
    }

    func hubShelfSelected(_ name: String) {
        enqueue(
            type: "hub_shelf",
            surface: "hubs",
            hubSlug: name,
            meta: ["shelf": name]
        )
    }

    func hubVideoOpened(_ post: CountryPost) {
        enqueue(type: "hub_video_open", post: post, surface: "hubs")
    }

    /// Explicit like / unlike taps (Kafka algorithm + reports).
    func enqueueLike(post: CountryPost, liked: Bool) {
        enqueue(
            type: liked ? "post_like" : "post_unlike",
            post: post,
            surface: "home",
            meta: ["liked": liked ? "1" : "0"]
        )
    }

    // MARK: - Profile / follow (also emitted server-side; client adds context)

    func profileOpened(userID: String, username: String?) {
        enqueue(
            type: "profile_open",
            authorId: userID,
            surface: "profile",
            meta: ["targetUserId": userID, "username": username ?? ""]
        )
    }

    // MARK: - Tabs / screens

    func screenOpened(_ name: String) {
        if let prev = currentScreen, let started = screenOpenedAt, prev != name {
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            enqueue(type: "screen_leave", surface: prev, durationMs: ms, meta: ["screen": prev])
        }
        currentScreen = name
        screenOpenedAt = Date()
        enqueue(type: "screen_open", surface: name, meta: ["screen": name])
    }

    private func appBackgrounded() {
        // Close any open looks
        let keys = Array(visible.keys)
        for id in keys {
            if let post = visible[id]?.post {
                feedPostDisappeared(post)
            }
        }
        if hubOpenedAt != nil { hubsLeft() }
        if let screen = currentScreen {
            let ms = screenOpenedAt.map { Int(Date().timeIntervalSince($0) * 1000) }
            enqueue(type: "screen_leave", surface: screen, durationMs: ms, meta: ["screen": screen])
            currentScreen = nil
            screenOpenedAt = nil
        }
        Task { await flushNow() }
    }

    // MARK: - Recommendation decisions (RecSys Phase 0)

    /// Impression / ranked_served / viewport_visible / hide / not_interested.
    /// Keeps the event envelope small; full decision reconstruction uses meta + sessionId.
    func enqueueRecommendationEvent(
        type: String,
        contentId: String? = nil,
        authorId: String? = nil,
        surface: String? = nil,
        meta: [String: String]? = nil
    ) {
        var m = meta ?? [:]
        m["schemaVersion"] = "1"
        m["sessionId"] = sessionId
        enqueue(
            type: type,
            contentId: contentId,
            authorId: authorId,
            surface: surface,
            meta: m
        )
    }

    // MARK: - Queue

    private func enqueue(
        type: String,
        post: CountryPost? = nil,
        contentId: String? = nil,
        authorId: String? = nil,
        surface: String? = nil,
        hubSlug: String? = nil,
        durationMs: Int? = nil,
        progress: Double? = nil,
        meta: [String: String]? = nil
    ) {
        let p = post
        queue.append(
            PendingEvent(
                type: type,
                contentId: contentId ?? p?.id,
                authorId: authorId ?? p?.authorID,
                countryCode: p?.countryCode,
                hubSlug: hubSlug,
                mediaType: p?.mediaType,
                isSpark: p?.isReel ?? false,
                durationMs: durationMs,
                progress: progress,
                surface: surface,
                occurredAt: Date(),
                meta: meta
            )
        )
        if queue.count >= 12 {
            Task { await flushNow() }
        } else {
            scheduleFlush()
        }
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            await flushNow()
        }
    }

    func flushNow() async {
        flushTask?.cancel()
        flushTask = nil
        guard !queue.isEmpty else { return }
        let batch = queue
        queue.removeAll(keepingCapacity: true)

        let token: String
        do {
            token = try await AuthService.shared.ensureValidToken()
        } catch {
            // Put back if auth blip
            queue.insert(contentsOf: batch, at: 0)
            return
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let events: [[String: Any]] = batch.map { e in
            var dict: [String: Any] = [
                "type": e.type,
                "occurredAt": iso.string(from: e.occurredAt),
                "deviceClass": deviceClass(),
            ]
            if let v = e.contentId { dict["contentId"] = v }
            if let v = e.authorId { dict["authorId"] = v }
            if let v = e.countryCode { dict["countryCode"] = v }
            if let v = e.hubSlug { dict["hubSlug"] = v }
            if let v = e.mediaType { dict["mediaType"] = v }
            if e.isSpark { dict["isSpark"] = true }
            if let v = e.durationMs { dict["durationMs"] = v }
            if let v = e.progress { dict["progress"] = v }
            if let v = e.surface { dict["surface"] = v }
            if let m = e.meta, !m.isEmpty { dict["meta"] = m }
            return dict
        }

        let body: [String: Any] = [
            "sessionId": sessionId,
            "events": events,
        ]

        guard let url = URL(string: "\(AppConfig.apiBaseURL)/v1/engagement/batch"),
              let data = try? JSONSerialization.data(withJSONObject: body)
        else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = data
        req.timeoutInterval = 20

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                #if DEBUG
                print("[EngagementTracker] batch HTTP \(http.statusCode)")
                #endif
            }
        } catch {
            #if DEBUG
            print("[EngagementTracker] batch failed: \(error.localizedDescription)")
            #endif
            // Drop on network failure — next session continues (avoid infinite retry storms)
        }
    }

    private func deviceClass() -> String {
        if ProcessInfo.processInfo.isiOSAppOnMac { return "mac" }
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: return "tablet"
        default: return "phone"
        }
    }
}
