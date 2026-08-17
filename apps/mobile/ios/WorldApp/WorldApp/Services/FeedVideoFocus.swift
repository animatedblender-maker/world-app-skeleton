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
        // Expanded Hubs watch owns the surface. Mini hubs may coexist — feed can still autoplay
        // (muted if needed) so Sparks/Hubs cards don't stick on thumbnails.
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

/// Exactly **one** feed video plays at a time — the most visible eligible card.
///
/// Pause rule (product): only stop when **more than 70% is off-screen**
/// (visible ratio &lt; 0.30). Fully on-screen video must never pause due to
/// layout noise, mini-player presence, or tiny ratio flaps.
@MainActor
final class FeedVideoFocus {
    static let shared = FeedVideoFocus()

    /// Currently elected autoplay post id (or stable fallback key).
    private(set) var activeID: String?
    /// Token bumped whenever the winner changes so SwiftUI views can observe cheaply.
    private(set) var generation: Int = 0

    private var ratios: [String: CGFloat] = [:]
    /// Last non-zero ratio per id — used to ignore single-frame 0 glitches from GeometryReader.
    private var stickyRatios: [String: CGFloat] = [:]
    private var zeroStreak: [String: Int] = [:]
    /// Debounced silence when no winner — layout flaps used to kill in-frame hubs audio.
    private var silenceWhenEmptyTask: Task<Void, Never>?

    /// Must be at least this visible to *start* (or take over) autoplay.
    /// Tall Spark cards rarely hit 50%+ of screen height — 0.22 still means "in frame".
    private let minVisibleToPlay: CGFloat = 0.22
    /// Keep current winner until it drops below this (more than ~78% off-screen).
    private let minVisibleToKeep: CGFloat = 0.18
    /// Challenger must beat the current winner by this much to steal focus.
    private let stealEpsilon: CGFloat = 0.08
    /// Ignore this many consecutive near-zero layout reports before clearing a candidate.
    private let zeroGlitchTolerance = 6

    private init() {}

    /// Report geometry for a candidate. `ratio` is 0…1 (share of the player height on screen).
    private var recomputeScheduled = false

    func report(id: String, visibleRatio: CGFloat) {
        let clamped = max(0, min(1, visibleRatio))

        // GeometryReader often reports 0 for a frame during LazyVStack recycle —
        // that used to pause fully visible videos. Stick to last good ratio briefly.
        if clamped < 0.02 {
            let streak = (zeroStreak[id] ?? 0) + 1
            zeroStreak[id] = streak
            if streak < zeroGlitchTolerance, let sticky = stickyRatios[id], sticky >= minVisibleToKeep {
                if abs((ratios[id] ?? -1) - sticky) > 0.02 {
                    ratios[id] = sticky
                    scheduleRecompute()
                }
                return
            }
            ratios.removeValue(forKey: id)
            stickyRatios.removeValue(forKey: id)
            zeroStreak.removeValue(forKey: id)
            scheduleRecompute()
            return
        }

        zeroStreak[id] = 0
        // Skip no-op ratio noise (was recomputing every GeometryReader tick).
        if let prev = ratios[id], abs(prev - clamped) < 0.04 {
            stickyRatios[id] = clamped
            return
        }
        ratios[id] = clamped
        stickyRatios[id] = clamped
        scheduleRecompute()
    }

    /// One election per runloop — not per GeometryReader axis change.
    private func scheduleRecompute() {
        guard !recomputeScheduled else { return }
        recomputeScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.recomputeScheduled = false
            self?.recompute()
        }
    }

    func clear(id: String) {
        ratios.removeValue(forKey: id)
        stickyRatios.removeValue(forKey: id)
        zeroStreak.removeValue(forKey: id)
        scheduleRecompute()
    }

    /// Drop every candidate (tab switch / push). Cards re-report when their surface is live.
    func resetAll() {
        silenceWhenEmptyTask?.cancel()
        silenceWhenEmptyTask = nil
        guard !ratios.isEmpty || activeID != nil else { return }
        ratios.removeAll(keepingCapacity: true)
        stickyRatios.removeAll(keepingCapacity: true)
        zeroStreak.removeAll(keepingCapacity: true)
        publish(winner: nil, previous: activeID, silenceImmediately: true)
    }

    func isActive(id: String) -> Bool {
        activeID == id
    }

    private func recompute() {
        let previous = activeID

        // Current winner holds until < 30% visible (more than 70% off-screen).
        if let current = activeID,
           let currentRatio = ratios[current],
           currentRatio >= minVisibleToKeep {
            // Only yield if a challenger is clearly more visible.
            if let best = bestCandidate(minRatio: minVisibleToPlay),
               best.key != current,
               best.value >= currentRatio + stealEpsilon {
                publish(winner: best.key, previous: previous)
            }
            // else keep current — even if another card is slightly higher.
            return
        }

        // No sticky winner (or it fell below keep threshold) — elect most visible.
        if let best = bestCandidate(minRatio: minVisibleToPlay) {
            publish(winner: best.key, previous: previous)
            return
        }

        publish(winner: nil, previous: previous)
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

    private func publish(winner: String?, previous: String?, silenceImmediately: Bool = false) {
        guard winner != previous else { return }
        activeID = winner
        generation &+= 1
        if let winner {
            silenceWhenEmptyTask?.cancel()
            silenceWhenEmptyTask = nil
            _ = winner
        } else {
            // Debounce silence — LazyVStack recycle used to clear winner for one frame and
            // hard-pause a fully visible Hubs card (felt random).
            silenceWhenEmptyTask?.cancel()
            if silenceImmediately {
                MediaPlaybackCoordinator.shared.silenceAllOffScreenAudio()
            } else {
                silenceWhenEmptyTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    guard !Task.isCancelled, self.activeID == nil else { return }
                    MediaPlaybackCoordinator.shared.silenceAllOffScreenAudio()
                }
            }
        }
        NotificationCenter.default.post(name: .feedVideoFocusDidChange, object: winner)
    }

    private static var cachedViewport: CGRect = .zero
    private static var cachedViewportAt: TimeInterval = 0

    /// Visible height of `frame` inside the usable viewport / frame height.
    static func visibleRatio(for frame: CGRect, in screen: CGRect? = nil) -> CGFloat {
        guard frame.height > 1, frame.width > 1 else { return 0 }

        let now = Date().timeIntervalSinceReferenceDate
        var viewport = cachedViewport
        if screen != nil || viewport.width < 1 || now - cachedViewportAt > 0.5 {
            let full = screen ?? UIScreen.main.bounds
            if let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows)
                .first(where: { $0.isKeyWindow }) {
                let bounds = window.bounds
                let safe = window.safeAreaInsets
                viewport = CGRect(
                    x: bounds.minX,
                    y: bounds.minY + safe.top,
                    width: bounds.width,
                    height: max(1, bounds.height - safe.top - safe.bottom)
                )
            } else {
                viewport = full
            }
            if screen == nil {
                cachedViewport = viewport
                cachedViewportAt = now
            }
        }

        let intersection = frame.intersection(viewport)
        guard !intersection.isNull, intersection.height > 0 else { return 0 }
        return min(1, max(0, intersection.height / frame.height))
    }

}

extension Notification.Name {
    static let feedVideoFocusDidChange = Notification.Name("feedVideoFocusDidChange")
}
