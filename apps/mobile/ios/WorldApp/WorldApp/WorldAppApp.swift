import SwiftUI
import UIKit

@main
struct WorldAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    /// Bridges the system launch screen into SwiftUI so cold open never flashes white.
    @State private var showsLaunchSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()

                if showsLaunchSplash {
                    MatteryaSplashView(showsProgress: false)
                        .transition(.opacity)
                        .zIndex(1_000)
                }
            }
            .environment(appState)
            .preferredColorScheme(.light)
            .tint(Theme.accentBright)
            .animation(.easeOut(duration: 0.28), value: showsLaunchSplash)
            .onAppear {
                PerformanceTelemetry.markIfAbsent("process_start")
                // Install after first frame so AuthView text fields stay responsive.
                DispatchQueue.main.async {
                    Keyboard.installDismissOnOutsideTap()
                    PerformanceTelemetry.markIfAbsent("shell_first_frame")
                    PerformanceTelemetry.milestoneFromLaunch(
                        "app_start_to_shell",
                        surface: "app"
                    )
                    // Keep splash up for one runloop so RootView can paint underneath.
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.28)) {
                            showsLaunchSplash = false
                        }
                    }
                }
            }
            .task {
                // Session already hydrated in AppState.init (no login flash).
                // Bootstrap only warms feed / push / VoIP for returning users.
                await appState.bootstrap()
                PerformanceTelemetry.milestoneFromLaunch(
                    "app_bootstrap_complete",
                    surface: "app",
                    meta: [
                        "authed": appState.isAuthenticated ? "1" : "0",
                        "ready": appState.isSessionReady ? "1" : "0",
                    ]
                )
            }
            .onOpenURL { url in
                appState.handleDeepLink(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                Task { @MainActor in
                    CallSessionManager.shared.handleAppWillResignActive()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task { @MainActor in
                    Keyboard.installDismissOnOutsideTap()
                    CallSessionManager.shared.handleAppDidBecomeActive()
                    // Never warm PushKit/CallKit on the login screen — hangs email/password typing.
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
}