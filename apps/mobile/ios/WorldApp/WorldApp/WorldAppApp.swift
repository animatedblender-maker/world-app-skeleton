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
                .task {
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