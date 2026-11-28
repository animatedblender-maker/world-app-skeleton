import Foundation

/// Soft launch window after splash unlock — readable from any isolation
/// (MediaBudget statics, utility Tasks) without hopping to MainActor.
enum ColdOpenGate {
    private static let lock = NSLock()
    private static var until: Date = .distantPast

    static func begin(seconds: TimeInterval = 12) {
        lock.lock()
        until = Date().addingTimeInterval(seconds)
        lock.unlock()
    }

    static func clear() {
        lock.lock()
        until = .distantPast
        lock.unlock()
    }

    static var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return Date() < until
    }
}
