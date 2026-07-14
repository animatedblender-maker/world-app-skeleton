import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        ImageCache.configureSharedCache()
        // VoIP + CallKit must exist synchronously so a cold-start push can take over the screen.
        VoIPPushService.shared.bootstrap()
        _ = CallKitManager.shared
        application.registerForRemoteNotifications()

        if let remotePayload = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            _ = IncomingCallWake.handleIfNeeded(remotePayload)
        }

        Task { @MainActor in
            PushNotificationService.shared.configure()
            VoIPPushService.shared.bootstrap()
            if AuthService.shared.isAuthenticated {
                CallSessionManager.shared.bootstrap()
            }
            await PushNotificationService.shared.syncWithServer(force: true)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationService.shared.updateDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationService.shared.handleRegistrationFailure()
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = application.beginBackgroundTask {
            if backgroundTaskID != .invalid {
                application.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }

        let callPresented = IncomingCallWake.handleIfNeeded(userInfo)

        Task { @MainActor in
            let handled: Bool
            if callPresented {
                handled = true
            } else {
                handled = await PushNotificationService.shared.handleRemoteNotification(userInfo)
            }
            completionHandler(handled ? .newData : .noData)
            if backgroundTaskID != .invalid {
                application.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
        }
    }
}