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
            .tint(Theme.accentBright)
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

    /// Splash paints first → quick AppState hydrate → shell under glow → dismiss without
    /// waiting on network bootstrap (that was the long white / awkward hang).
    @MainActor
    private func runLaunchSequence() async {
        PerformanceTelemetry.markIfAbsent("process_start")

        // One frame so Matterya is on screen before any disk work.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 16_000_000)

        PerformanceTelemetry.markIfAbsent("shell_first_frame")
        PerformanceTelemetry.milestoneFromLaunch("app_start_to_shell", surface: "app")

        let splashStarted = Date()

        // Sync hydrate only (Keychain/UserDefaults) — must stay off the network path.
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

        // One clean glow pass (~0.95s), then open — never wait on network bootstrap.
        let minVisible: TimeInterval = 0.95
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
