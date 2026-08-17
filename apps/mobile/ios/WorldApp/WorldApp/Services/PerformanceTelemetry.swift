import Foundation
import UIKit

/// User-perceived performance milestones (butter-smooth program).
/// No UI. Batches to `POST /v1/metrics/batch`. Sample rate from remote config later.
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

    private static var sessionId = UUID().uuidString
    private static var processStart = Date().timeIntervalSince1970
    private static var pending: [Event] = []
    private static var flushTask: Task<Void, Never>?
    private static let maxPending = 40
    private static var marks: [String: TimeInterval] = [:]

    static func newSession() {
        sessionId = UUID().uuidString
        processStart = Date().timeIntervalSince1970
        marks.removeAll(keepingCapacity: true)
    }

    /// Absolute process-relative mark.
    static func mark(_ name: String) {
        marks[name] = Date().timeIntervalSince1970
    }

    static func markIfAbsent(_ name: String) {
        if marks[name] == nil { mark(name) }
    }

    /// Record duration from process start to now.
    static func milestoneFromLaunch(
        _ name: String,
        surface: String,
        ok: Bool = true,
        meta: [String: String] = [:]
    ) {
        let t1 = Date().timeIntervalSince1970
        let duration = max(0, Int(((t1 - processStart) * 1000).rounded()))
        record(
            name: name,
            surface: surface,
            durationMs: duration,
            t0: processStart,
            t1: t1,
            ok: ok,
            meta: meta
        )
    }

    /// Record duration between two named marks (or mark→now).
    static func milestone(
        _ name: String,
        surface: String,
        from markName: String,
        ok: Bool = true,
        meta: [String: String] = [:]
    ) {
        let t1 = Date().timeIntervalSince1970
        let t0 = marks[markName] ?? processStart
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
        let end = t1 ?? Date().timeIntervalSince1970
        let start = t0 ?? (end - Double(durationMs) / 1000)
        pending.append(
            Event(
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
        if pending.count >= maxPending {
            flushSoon(delayMs: 0)
        } else {
            flushSoon(delayMs: 2_500)
        }
    }

    private static func flushSoon(delayMs: UInt64) {
        flushTask?.cancel()
        flushTask = Task {
            if delayMs > 0 {
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
            guard !Task.isCancelled else { return }
            await flushNow()
        }
    }

    static func flushNow() async {
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll(keepingCapacity: true)

        let token = try? await AuthService.shared.ensureValidToken()
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/v1/metrics/batch") else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 4
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
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
            "sessionId": sessionId,
            "appVersion": appVersion,
            "os": "ios",
            "deviceClass": deviceClass(),
            "events": events,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        req.httpBody = data
        _ = try? await URLSession.shared.data(for: req)
    }

    private static func deviceClass() -> String {
        // Coarse class for SLO segmentation (floor = iphone11).
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
