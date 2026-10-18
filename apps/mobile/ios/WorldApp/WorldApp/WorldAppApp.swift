import SwiftUI
import UIKit

@main
struct WorldAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Created AFTER the splash paints — `AppState()` hydrate was blocking first frame.
    @State private var appState: AppState?
    @State private var showsLaunchSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Mount the shell only after splash dismisses so Feed/Hubs init
                // never steals the main thread during the Matterya glow.
                if !showsLaunchSplash, let appState {
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
            .animation(.easeOut(duration: 0.35), value: showsLaunchSplash)
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

    /// Splash first → then hydrate/bootstrap under the looping glow → then open.
    @MainActor
    private func runLaunchSequence() async {
        PerformanceTelemetry.markIfAbsent("process_start")

        // Let SwiftUI commit the splash frame before any session/disk work.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 32_000_000)

        PerformanceTelemetry.markIfAbsent("shell_first_frame")
        PerformanceTelemetry.milestoneFromLaunch("app_start_to_shell", surface: "app")

        let splashStarted = Date()

        // Heavy work while Matterya letters keep glowing.
        let state = AppState()
        appState = state
        Keyboard.installDismissOnOutsideTap()
        await state.bootstrap()
        PerformanceTelemetry.milestoneFromLaunch(
            "app_bootstrap_complete",
            surface: "app",
            meta: [
                "authed": state.isAuthenticated ? "1" : "0",
                "ready": state.isSessionReady ? "1" : "0",
            ]
        )

        // At least one full glow pass so the word is never a one-frame flash.
        let minVisible: TimeInterval = 1.35
        let elapsed = Date().timeIntervalSince(splashStarted)
        if elapsed < minVisible {
            let remaining = minVisible - elapsed
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }

        withAnimation(.easeOut(duration: 0.35)) {
            showsLaunchSplash = false
        }
    }
}
