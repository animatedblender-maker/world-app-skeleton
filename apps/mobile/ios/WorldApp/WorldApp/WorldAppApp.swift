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
            .preferredColorScheme(.light)
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
                    if appState.isAuthenticated {
                        VoIPPushService.shared.bootstrap()
                        CallSessionManager.shared.bootstrap()
                        await PushNotificationService.shared.syncWithServer(force: true)
                    }
                    await appState.handleBecameActive()
                }
            }
        }
    }

    /// Splash paints first (Core Animation glow) → AppState hydrate off the glow path →
    /// shell under splash → dismiss on a timer. Glow does not wait on bootstrap.
    @MainActor
    private func runLaunchSequence() async {
        PerformanceTelemetry.markIfAbsent("process_start")

        // Let the CA glow mount and paint before any sync hydrate.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 32_000_000)

        PerformanceTelemetry.markIfAbsent("shell_first_frame")
        PerformanceTelemetry.milestoneFromLaunch("app_start_to_shell", surface: "app")

        let splashStarted = Date()

        // Sync hydrate after glow is already looping on the render server.
        // (CA animations continue through short main-thread Keychain/UserDefaults work.)
        let state = AppState()
        appState = state
        Keyboard.installDismissOnOutsideTap()

        // Bootstrap in parallel — do NOT block splash dismiss on feed/push/VoIP.
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

        // ~1.2s so at least one full glow pass is visible; never wait on network.
        let minVisible: TimeInterval = 1.15
        let elapsed = Date().timeIntervalSince(splashStarted)
        if elapsed < minVisible {
            try? await Task.sleep(nanoseconds: UInt64((minVisible - elapsed) * 1_000_000_000))
        }

        withAnimation(.easeOut(duration: 0.28)) {
            showsLaunchSplash = false
        }
        // Bootstrap keeps running under the shell.
        _ = boot
    }
}
