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
                    // Install after first frame so AuthView text fields stay responsive.
                    DispatchQueue.main.async {
                        Keyboard.installDismissOnOutsideTap()
                    }
                }
                .task {
                    // Yield so login UI paints before any session work.
                    await Task.yield()
                    await appState.bootstrap()
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