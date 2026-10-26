import SwiftUI
import UIKit

@main
struct WorldAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Created after first splash frame — never block cold open on hydrate.
    @State private var appState: AppState?
    @State private var showsLaunchSplash = true

    var body: some Scene {
        WindowGroup {
            // Read here so Observation invalidates this scene when Sparks/menu toggles.
            let needsLightStatusBar = appState?.reelsViewerContext != nil
                || appState?.showAppMenu == true
            ZStack {
                // Shell mounts under the splash as soon as AppState exists so bootstrap
                // and first paint happen while Matterya still glows (no white hang).
                if let appState {
                    RootView()
                        .environment(appState)
                }

                if showsLaunchSplash {
                    MatteryaSplashView(showsProgress: true)
                        .transition(.opacity)
                        .zIndex(1_000)
                }
            }
            // Dark while Sparks / side menu are up → white notch clock & battery on black.
            // Nested `.preferredColorScheme(.dark)` alone loses to a hard-coded root `.light`.
            .preferredColorScheme(needsLightStatusBar ? .dark : .light)
            .tint(Theme.ink)
            .animation(.easeOut(duration: 0.28), value: showsLaunchSplash)
            .task {
                await runLaunchSequence()
            }
            .onOpenURL { url in
                appState?.handleDeepLink(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                Task { @MainActor in
                    CallSessionManager.shared.handleAppWillResignActive()
                    // Persist feed head for next-open demote (same posts every launch).
                    HomeFeedStore.shared.noteSessionPaused()
                    // Sparks/warm-pool audio pause is owned by MediaPlaybackCoordinator
                    // (willResignActive / didEnterBackground observers).
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task { @MainActor in
                    guard let appState else { return }
                    Keyboard.installDismissOnOutsideTap()
                    CallSessionManager.shared.handleAppDidBecomeActive()
                    // Re-assert white glyphs if Sparks/menu survived backgrounding.
                    MatteryaStatusBar.setLightContent(
                        appState.reelsViewerContext != nil || appState.showAppMenu
                    )
                    // Defer push/VoIP re-sync — force:true on every become-active stacked with cold open.
                    if appState.isAuthenticated {
                        Task(priority: .utility) {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            VoIPPushService.shared.bootstrap()
                            CallSessionManager.shared.bootstrap()
                            await PushNotificationService.shared.syncWithServer(force: false)
                        }
                    }
                    await appState.handleBecameActive()
                }
            }
        }
    }

    /// Splash until Feed cache can paint (variable), floor for brand, hard cap so offline never spins forever.
    /// No AV under splash — autoplay stays locked until dismiss + settle.
    @MainActor
    private func runLaunchSequence() async {
        PerformanceTelemetry.markIfAbsent("process_start")
        FeedVideoFocus.shared.lockAutoplayForColdOpen()

        // Let the CA glow mount and paint before any sync hydrate.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 32_000_000)

        PerformanceTelemetry.markIfAbsent("shell_first_frame")
        PerformanceTelemetry.milestoneFromLaunch("app_start_to_shell", surface: "app")

        let splashStarted = Date()

        // Sync hydrate after glow is already looping on the render server.
        let state = AppState()
        state.isLaunchSplashVisible = true
        appState = state
        Keyboard.installDismissOnOutsideTap()

        // Bootstrap in parallel — do NOT block splash dismiss on push/VoIP.
        // Feed mounts under splash (returning users are session-ready) and paints via
        // FeedView → beginFreshSession; warmHead stays lite until autoplay unlocks.
        let boot = Task { @MainActor in
            await state.bootstrap()
            PerformanceTelemetry.milestoneFromLaunch(
                "app_bootstrap_complete",
                surface: "app",
                meta: [
                    "authed": state.isAuthenticated ? "1" : "0",
                    "ready": state.isSessionReady ? "1" : "0",
                ]
            )
        }

        await waitForSplashReady(state: state, started: splashStarted)

        withAnimation(.easeOut(duration: 0.28)) {
            showsLaunchSplash = false
            state.isLaunchSplashVisible = false
        }
        // Load bundled WhisperKit Small off the critical path (no download UX).
        TranscriptService.warmModelInBackground()
        PerformanceTelemetry.milestoneFromLaunch(
            "splash_dismiss",
            surface: "app",
            meta: [
                "didPaint": HomeFeedStore.shared.didPaint ? "1" : "0",
                "posts": "\(HomeFeedStore.shared.displayedPosts.count)",
            ]
        )

        // Unlock fast after splash — mute-until-frames keeps first audible frame clean.
        FeedVideoFocus.shared.unlockAutoplayAfterFirstPaint(delayMs: 100)
        _ = boot
    }

    /// Floor ~0.4s brand glow; wait for Feed paint when authed; hard cap ~3.5s.
    @MainActor
    private func waitForSplashReady(state: AppState, started: Date) async {
        let floor: TimeInterval = 0.40
        let paintBudget: TimeInterval = 2.80
        let hardCap: TimeInterval = 3.50

        // Brand floor first so the glow always reads once.
        let elapsedFloor = Date().timeIntervalSince(started)
        if elapsedFloor < floor {
            try? await Task.sleep(nanoseconds: UInt64((floor - elapsedFloor) * 1_000_000_000))
        }

        // Logged out / profile setup: no Feed paint to wait on.
        if !state.isAuthenticated || state.needsProfileSetup {
            return
        }

        // Wait until Feed painted from cache/network, or budgets expire.
        while Date().timeIntervalSince(started) < hardCap {
            if HomeFeedStore.shared.didPaint || !HomeFeedStore.shared.displayedPosts.isEmpty {
                PerformanceTelemetry.milestoneFromLaunch("feed_did_paint", surface: "feed")
                // Tiny yield so first cells can layout under the glow.
                try? await Task.sleep(nanoseconds: 50_000_000)
                return
            }
            // After paint budget, leave splash even if still empty (offline / cold API).
            if Date().timeIntervalSince(started) >= paintBudget {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
