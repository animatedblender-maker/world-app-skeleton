import Foundation

/// User-perceived performance milestones.
/// Fully off the hot path: never blocks UI, never refreshes tokens, never traps on bad floats.
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

    @MainActor
    static func newSession() { store.newSession() }

    @MainActor
    static func mark(_ name: String) { store.mark(name) }

    @MainActor
    static func markIfAbsent(_ name: String) { store.markIfAbsent(name) }

    @MainActor
    static func milestoneFromLaunch(
        _ name: String,
        surface: String,
        ok: Bool = true,
        meta: [String: String] = [:]
    ) {
        store.milestoneFromLaunch(name, surface: surface, ok: ok, meta: meta)
    }

    @MainActor
    static func milestone(
        _ name: String,
        surface: String,
        from markName: String,
        ok: Bool = true,
        meta: [String: String] = [:]
    ) {
        store.milestone(name, surface: surface, from: markName, ok: ok, meta: meta)
    }

    @MainActor
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

    /// Flush soon so Grafana Step 3 fills during a 30–60s smoke (handoff / swipe).
    @MainActor
    static func flushSoon(delaySec: Double = 1.5) {
        store.flushSoon(delaySec: delaySec)
    }
}

// MARK: - Background store

private final class MetricsStore: @unchecked Sendable {
    static let shared = MetricsStore()

    private let lock = NSLock()
    private var sessionId = UUID().uuidString
    private var processStart = Date().timeIntervalSince1970
    private var pending: [PerformanceTelemetry.Event] = []
    private var marks: [String: TimeInterval] = [:]
    private var emittedNames = Set<String>()
    private var flushScheduled = false
    private var isFlushing = false
    private var deviceClassCached: String = "unknown"
    private var appVersion: String = "?"

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 3
        c.timeoutIntervalForResource = 4
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    private init() {
        deviceClassCached = Self.computeDeviceClass()
        appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

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
        let duration = Self.safeMs(t1 - t0)
        record(name: name, surface: surface, durationMs: duration, t0: t0, t1: t1, ok: ok, meta: meta)
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
        let duration = Self.safeMs(t1 - t0)
        record(name: name, surface: surface, durationMs: duration, t0: t0, t1: t1, ok: ok, meta: meta)
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
        let start = t0 ?? (end - Double(max(0, durationMs)) / 1000)

        lock.lock()
        // Once-per-session: cold-start / first-useful only.
        // Handoff + swipe must repeat every interaction for Grafana SLOs.
        let oncePerSession =
            name.hasPrefix("app_")
            || name == "hubs_first_useful"
            || name == "hubs_interactive"
            || name.hasPrefix("profile_")
            || name.hasPrefix("messages_inbox")
            || name == "sparks_open_first_frame"
        if oncePerSession {
            if emittedNames.contains(name) {
                lock.unlock()
                return
            }
            emittedNames.insert(name)
        }
        if pending.count >= 80 {
            pending.removeFirst(min(40, pending.count))
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
        let urgent =
            name.contains("handoff")
            || name == "reel_swipe_first_frame"
            || name == "sparks_open_first_frame"
        let shouldSchedule = !flushScheduled && !isFlushing
        if shouldSchedule { flushScheduled = true }
        lock.unlock()

        if shouldSchedule {
            scheduleFlush(delaySec: urgent ? 1.5 : 8)
        } else if urgent {
            flushSoon(delaySec: 1.5)
        }
    }

    func flushSoon(delaySec: Double = 1.5) {
        lock.lock()
        let shouldSchedule = !flushScheduled && !isFlushing
        if shouldSchedule { flushScheduled = true }
        lock.unlock()
        if shouldSchedule {
            scheduleFlush(delaySec: max(0.3, delaySec))
        }
    }

    private func scheduleFlush(delaySec: Double) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delaySec) { [weak self] in
            self?.flushNowSync()
        }
    }

    /// Fully synchronous background flush — no Task/MainActor hops that can re-enter UI.
    private func flushNowSync() {
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

        // Do not touch AuthService from background (MainActor). Metrics accept unauthenticated.
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 3

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
        let sem = DispatchSemaphore(value: 0)
        session.dataTask(with: req) { _, _, _ in
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 4)
    }

    private static func safeMs(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite, !seconds.isNaN else { return 0 }
        let ms = seconds * 1000
        guard ms.isFinite, !ms.isNaN else { return 0 }
        return max(0, min(Int(ms.rounded()), 600_000))
    }

    private static func computeDeviceClass() -> String {
        var sys = utsname()
        uname(&sys)
        let mirror = Mirror(reflecting: sys.machine)
        var id = ""
        id.reserveCapacity(32)
        for child in mirror.children {
            guard let v = child.value as? Int8, v != 0 else { break }
            // bitPattern avoids trap on negative Int8
            let u = UInt8(bitPattern: v)
            if u < 32 || u > 126 { continue }
            id.append(Character(UnicodeScalar(u)))
        }
        if id.hasPrefix("iPhone12") || id.hasPrefix("iPhone11") { return "iphone11_class" }
        if id.hasPrefix("iPhone") { return "iphone" }
        return id.isEmpty ? "unknown" : String(id.prefix(32))
    }
}
