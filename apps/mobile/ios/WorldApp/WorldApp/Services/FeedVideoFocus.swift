import Foundation
import UIKit

/// Exactly one feed/profile InFrame video may play at a time — the one with the highest
/// on-screen visibility ratio (and a minimum threshold).
///
/// Uses **hysteresis** so a playing hub/feed video does not pause from tiny scroll
/// jitter or LazyVStack layout flaps mid-clip.
@MainActor
final class FeedVideoFocus {
    static let shared = FeedVideoFocus()

    /// Currently elected autoplay post id (or stable fallback key).
    private(set) var activeID: String?
    /// Token bumped whenever the winner changes so SwiftUI views can observe cheaply.
    private(set) var generation: Int = 0

    private var ratios: [String: CGFloat] = [:]

    /// Must reach this ratio to *start* autoplay (or to steal from nobody).
    private let enterRatio: CGFloat = 0.30
    /// Once playing, keep the slot until ratio falls below this (sticky hold).
    private let holdRatio: CGFloat = 0.10
    /// Challenger must beat the current winner by this margin to steal focus.
    private let stealMargin: CGFloat = 0.18

    private init() {}

    /// Report geometry for a candidate. `ratio` is 0…1 (share of the player height on screen).
    func report(id: String, visibleRatio: CGFloat) {
        let clamped = max(0, min(1, visibleRatio))
        if clamped < 0.02 {
            ratios.removeValue(forKey: id)
        } else {
            ratios[id] = clamped
        }
        recompute()
    }

    func clear(id: String) {
        ratios.removeValue(forKey: id)
        recompute()
    }

    func isActive(id: String) -> Bool {
        activeID == id
    }

    private func recompute() {
        let previous = activeID

        // Sticky: keep the current winner while still reasonably on-screen,
        // unless another card is clearly more visible.
        if let current = activeID, let currentRatio = ratios[current], currentRatio >= holdRatio {
            if let best = bestCandidate(minRatio: enterRatio),
               best.key != current,
               best.value >= currentRatio + stealMargin {
                publish(winner: best.key, previous: previous)
            }
            // else keep current — no generation bump, no pause thrash
            return
        }

        // No sticky holder (off-screen or none) — elect the most visible eligible card.
        let winner = bestCandidate(minRatio: enterRatio)?.key
        publish(winner: winner, previous: previous)
    }

    private func bestCandidate(minRatio: CGFloat) -> (key: String, value: CGFloat)? {
        let eligible = ratios.filter { $0.value >= minRatio }
        guard let winner = eligible.max(by: { a, b in
            if a.value != b.value { return a.value < b.value }
            return a.key > b.key
        }) else { return nil }
        return (winner.key, winner.value)
    }

    private func publish(winner: String?, previous: String?) {
        guard winner != previous else { return }
        activeID = winner
        generation &+= 1
        NotificationCenter.default.post(name: .feedVideoFocusDidChange, object: winner)
    }

    /// Visible height of `frame` inside the screen, divided by the frame’s own height.
    /// Default screen bounds is read inside the body (not a default arg) so Swift concurrency
    /// does not treat `UIScreen.main` as a nonisolated default-argument evaluation.
    static func visibleRatio(for frame: CGRect, in screen: CGRect? = nil) -> CGFloat {
        let bounds = screen ?? UIScreen.main.bounds
        guard frame.height > 1, frame.width > 1 else { return 0 }
        let intersection = frame.intersection(bounds)
        guard !intersection.isNull, intersection.height > 0 else { return 0 }
        // Slight center bias so the more “in view” middle card wins when ratios are close.
        let fill = intersection.height / frame.height
        let midOffset = abs(frame.midY - bounds.midY) / max(bounds.height, 1)
        let centerBoost = max(0, 1 - midOffset) * 0.08
        return min(1, fill + centerBoost * fill)
    }
}

extension Notification.Name {
    static let feedVideoFocusDidChange = Notification.Name("feedVideoFocusDidChange")
}
