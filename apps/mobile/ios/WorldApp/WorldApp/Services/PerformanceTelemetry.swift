import Foundation

/// User-perceived performance milestones (butter-smooth program).
/// **Never blocks the UI thread** — no MainActor network, no token refresh.
@MainActor
enum PerformanceTelemetry {
    struct Event: Sendable {
        var name: String
        var surface: String
        var durationMs: Int
        var t0: TimeInterval
        var t1: TimeInterval
        var ok: Bool
        var traceId: String?
        var meta: [String: String]
    }

    private static let store = MetricsStore.shared

    static func newSession() {
        store.newSession()
    }

    static func mark(_ name: String) {
        store.mark(name)
    }

    static func markIfAbsent(_ name: String) {
        store.markIfAbsent(name)
    }

    static func milestoneFromLaunch(
        _ name: String,
        surface: String,
        ok: Bool = true,
        meta: [String: String] = [:]
    ) {
        store.milestoneFromLaunch(name, surface: surface, ok: ok, meta: meta)
    }

    static func milestone(
        _ name: String,
        surface: String,
        from markName: String,
        ok: Bool = true,
        meta: [String: String] = [:]
    ) {
        store.milestone(name, surface: surface, from: markName, ok: ok, meta: meta)
    }

    static func record(
        name: String,
        surface: String,
        durationMs: Int,
        t0: TimeInterval? = nil,
        t1: TimeInterval? = nil,
        ok: Bool = true,
        traceId: String? = nil,
        meta: [String: String] = [:]
    ) {
        store.record(
            name: name,
            surface: surface,
            durationMs: durationMs,
            t0: t0,
            t1: t1,
            ok: ok,
            traceId: traceId,
            meta: meta
        )
    }

    static func flushNow() async {
        await store.flushNow()
    }
}

// MARK: - Background store (never MainActor)

/// Thread-safe queue + background URLSession flush.
/// Critical: do **not** call AuthService.ensureValidToken (MainActor refresh stalls UI).
private final class MetricsStore: @unchecked Sendable {
    static let shared = MetricsStore()

    private let lock = NSLock()
    private var sessionId = UUID().uuidString
    private var processStart = Date().timeIntervalSince1970
    private var pending: [PerformanceTelemetry.Event] = []
    private var marks: [String: TimeInterval] = [:]
    /// One sample per milestone name per session (avoids spam + work storms).
    private var emittedNames = Set<String>()
    private var flushScheduled = false
    private var isFlushing = false
    private lazy var deviceClassCached: String = Self.computeDeviceClass()
    private lazy var appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }()

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 3
        c.timeoutIntervalForResource = 4
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    func newSession() {
        lock.lock()
        sessionId = UUID().uuidString
        processStart = Date().timeIntervalSince1970
        marks.removeAll(keepingCapacity: true)
        emittedNames.removeAll(keepingCapacity: true)
        pending.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func mark(_ name: String) {
        let t = Date().timeIntervalSince1970
        lock.lock()
        marks[name] = t
        lock.unlock()
    }

    func markIfAbsent(_ name: String) {
        lock.lock()
        if marks[name] == nil {
            marks[name] = Date().timeIntervalSince1970
        }
        lock.unlock()
    }

    func milestoneFromLaunch(
        _ name: String,
        surface: String,
        ok: Bool,
        meta: [String: String]
    ) {
        let t1 = Date().timeIntervalSince1970
        lock.lock()
        let t0 = processStart
        lock.unlock()
        let duration = max(0, Int(((t1 - t0) * 1000).rounded()))
        record(
            name: name,
            surface: surface,
            durationMs: duration,
            t0: t0,
            t1: t1,
            ok: ok,
            meta: meta
        )
    }

    func milestone(
        _ name: String,
        surface: String,
        from markName: String,
        ok: Bool,
        meta: [String: String]
    ) {
        let t1 = Date().timeIntervalSince1970
        lock.lock()
        let t0 = marks[markName] ?? processStart
        lock.unlock()
        let duration = max(0, Int(((t1 - t0) * 1000).rounded()))
        record(
            name: name,
            surface: surface,
            durationMs: duration,
            t0: t0,
            t1: t1,
            ok: ok,
            meta: meta
        )
    }

    func record(
        name: String,
        surface: String,
        durationMs: Int,
        t0: TimeInterval?,
        t1: TimeInterval?,
        ok: Bool,
        traceId: String? = nil,
        meta: [String: String]
    ) {
        let end = t1 ?? Date().timeIntervalSince1970
        let start = t0 ?? (end - Double(durationMs) / 1000)

        lock.lock()
        // Dedupe one-shot launch/surface milestones only (not per-action metrics).
        let oncePerSession =
            name.hasPrefix("app_")
            || name.hasPrefix("hubs_")
            || name.hasPrefix("profile_")
            || name.hasPrefix("messages_inbox")
            || name == "reel_swipe_first_frame"
        if oncePerSession {
            if emittedNames.contains(name) {
                lock.unlock()
                return
            }
            emittedNames.insert(name)
        }
        // Cap queue so a runaway emitter cannot grow unbounded.
        if pending.count >= 80 {
            pending.removeFirst(pending.count - 40)
        }
        pending.append(
            PerformanceTelemetry.Event(
                name: name,
                surface: surface,
                durationMs: max(0, durationMs),
                t0: start,
                t1: end,
                ok: ok,
                traceId: traceId,
                meta: meta
            )
        )
        let shouldSchedule = !flushScheduled && !isFlushing
        if shouldSchedule { flushScheduled = true }
        let count = pending.count
        lock.unlock()

        guard shouldSchedule else {
            if count >= 20 { scheduleFlush(delaySec: 0.05) }
            return
        }
        // Debounce: never flush mid-frame / mid-bootstrap.
        scheduleFlush(delaySec: 8)
    }

    private func scheduleFlush(delaySec: Double) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delaySec) { [weak self] in
            guard let self else { return }
            Task.detached(priority: .utility) {
                await self.flushNow()
            }
        }
    }

    func flushNow() async {
        lock.lock()
        flushScheduled = false
        guard !isFlushing, !pending.isEmpty else {
            lock.unlock()
            return
        }
        isFlushing = true
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        let sid = sessionId
        let device = deviceClassCached
        let ver = appVersion
        lock.unlock()

        defer {
            lock.lock()
            isFlushing = false
            let again = !pending.isEmpty
            if again { flushScheduled = true }
            lock.unlock()
            if again { scheduleFlush(delaySec: 5) }
        }

        guard let url = URL(string: "\(AppConfig.apiBaseURL)/v1/metrics/batch") else { return }

        // Cached token only — never refresh here (MainActor refresh freezes UI under load).
        let token = await MainActor.run {
            AuthService.shared.accessToken()
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 3
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let events: [[String: Any]] = batch.map { e in
            var row: [String: Any] = [
                "name": e.name,
                "surface": e.surface,
                "durationMs": e.durationMs,
                "t0": e.t0,
                "t1": e.t1,
                "ok": e.ok,
            ]
            if let tid = e.traceId { row["traceId"] = tid }
            if !e.meta.isEmpty { row["meta"] = e.meta }
            return row
        }
        let body: [String: Any] = [
            "sessionId": sid,
            "appVersion": ver,
            "os": "ios",
            "deviceClass": device,
            "events": events,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        req.httpBody = data
        _ = try? await session.data(for: req)
    }

    private static func computeDeviceClass() -> String {
        var sys = utsname()
        uname(&sys)
        let mirror = Mirror(reflecting: sys.machine)
        let id = mirror.children.reduce("") { acc, el in
            guard let v = el.value as? Int8, v != 0 else { return acc }
            return acc + String(UnicodeScalar(UInt8(v)))
        }
        if id.hasPrefix("iPhone12") || id.hasPrefix("iPhone11") { return "iphone11_class" }
        if id.hasPrefix("iPhone1") { return "iphone_legacy" }
        return id.isEmpty ? "unknown" : id
    }
}
