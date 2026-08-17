import SwiftUI
import UIKit

@main
struct WorldAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(.light)
                .tint(Theme.accentBright)
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
                        VoIPPushService.shared.bootstrap()
                        await appState.handleBecameActive()
                        await PushNotificationService.shared.syncWithServer(force: true)
                        if appState.isAuthenticated {
                            CallSessionManager.shared.bootstrap()
                        }
                    }
                }
        }
    }
}