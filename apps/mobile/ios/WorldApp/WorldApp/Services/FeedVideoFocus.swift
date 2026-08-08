import Foundation
import UIKit

/// Where an autoplay card lives. Feed stays mounted under other tabs (opacity 0),
/// so cards must only report focus while their surface is actually on screen.
enum FeedAutoplaySurface: String, Equatable, Sendable {
    case home
    case profile

    /// Whether this surface should elect an autoplay winner right now.
    @MainActor
    func isLive(appState: AppState) -> Bool {
        guard appState.reelsViewerContext == nil else { return false }
        // Expanded hubs watch owns audio/video; mini may continue separately.
        if appState.hubPlaybackPost != nil, appState.hubPlaybackExpanded { return false }

        switch self {
        case .home:
            // Home feed only when its tab is selected and nothing is pushed over it.
            return appState.selectedTab == .feed && appState.navigationPath.isEmpty
        case .profile:
            // Own Profile tab (root).
            if appState.selectedTab == .profile, appState.navigationPath.isEmpty {
                return true
            }
            // Public profile pushed from feed / people / etc.
            return appState.navigationPath.contains { destination in
                switch destination {
                case .publicProfile, .publicProfileByUserID:
                    return true
                default:
                    return false
                }
            }
        }
    }
}

/// Exactly **one** feed video plays at a time — the one with the highest on-screen
/// visibility. Stops when less than half the video remains in the viewport.
@MainActor
final class FeedVideoFocus {
    static let shared = FeedVideoFocus()

    /// Currently elected autoplay post id (or stable fallback key).
    private(set) var activeID: String?
    /// Token bumped whenever the winner changes so SwiftUI views can observe cheaply.
    private(set) var generation: Int = 0

    private var ratios: [String: CGFloat] = [:]

    /// Must be at least this visible to play (or keep playing).
    /// “More than 50% out of the frame” → stop (visible ratio < 0.5).
    private let minVisibleRatio: CGFloat = 0.50
    /// When two videos both qualify, the higher ratio always wins (tiny epsilon only).
    private let stealEpsilon: CGFloat = 0.01

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

    /// Drop every candidate (tab switch / push). Cards re-report when their surface is live.
    func resetAll() {
        guard !ratios.isEmpty || activeID != nil else { return }
        ratios.removeAll(keepingCapacity: true)
        publish(winner: nil, previous: activeID)
    }

    func isActive(id: String) -> Bool {
        activeID == id
    }

    private func recompute() {
        let previous = activeID

        // Eligible = ≥ 50% of the video still in the viewport.
        guard let best = bestCandidate(minRatio: minVisibleRatio) else {
            // Nobody ≥ 50% visible → stop everything.
            publish(winner: nil, previous: previous)
            return
        }

        // Always prefer the most-visible card. Keep current only on a pure tie.
        if let current = activeID,
           let currentRatio = ratios[current],
           currentRatio >= minVisibleRatio,
           best.key != current,
           best.value < currentRatio + stealEpsilon
        {
            // Current still ≥ 50% and challenger is not meaningfully more visible.
            return
        }

        publish(winner: best.key, previous: previous)
    }

    private func bestCandidate(minRatio: CGFloat) -> (key: String, value: CGFloat)? {
        let eligible = ratios.filter { $0.value >= minRatio }
        guard let winner = eligible.max(by: { a, b in
            if a.value != b.value { return a.value < b.value }
            // Stable tie-break so we don't flip-flop on equal ratios.
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
    /// Pure visibility — no center bias (highest percentage in frame wins).
    static func visibleRatio(for frame: CGRect, in screen: CGRect? = nil) -> CGFloat {
        let bounds = screen ?? UIScreen.main.bounds
        guard frame.height > 1, frame.width > 1 else { return 0 }
        let intersection = frame.intersection(bounds)
        guard !intersection.isNull, intersection.height > 0 else { return 0 }
        return min(1, max(0, intersection.height / frame.height))
    }
}

extension Notification.Name {
    static let feedVideoFocusDidChange = Notification.Name("feedVideoFocusDidChange")
}
