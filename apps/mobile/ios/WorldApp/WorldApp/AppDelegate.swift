import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Portrait by default; fullscreen hub video temporarily allows landscape.
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        ImageCache.configureSharedCache()
        // Notification delegate MUST be set before return — otherwise tap-to-open
        // on cold start never delivers didReceive and the user lands on home.
        PushNotificationService.shared.configure()

        // VoIP/CallKit only when already signed in OR cold-start is an incoming call.
        // Doing this on the login screen hung the main thread (can't type email/password).
        // Incoming-call wake still needs the stack before return; otherwise defer past
        // first paint so cold launch stays on the Matterya splash instead of white.
        let launchedFromRemote = launchOptions?[.remoteNotification] as? [AnyHashable: Any]
        let isIncomingCallWake =
            launchedFromRemote != nil && IncomingCallWake.looksLikeIncomingCall(launchedFromRemote)

        if isIncomingCallWake {
            VoIPPushService.shared.bootstrap()
            _ = CallKitManager.shared
            application.registerForRemoteNotifications()
        }

        if let remotePayload = launchedFromRemote {
            if IncomingCallWake.handleIfNeeded(remotePayload) == false {
                Task { @MainActor in
                    _ = await PushNotificationService.shared.handleRemoteNotification(remotePayload)
                }
            }
        }

        Task { @MainActor in
            // Yield so RootView / splash can paint before CallKit + PushKit work.
            await Task.yield()
            if AuthService.shared.isAuthenticated || isIncomingCallWake {
                VoIPPushService.shared.bootstrap()
                _ = CallKitManager.shared
                CallSessionManager.shared.bootstrap()
                UIApplication.shared.registerForRemoteNotifications()
                await PushNotificationService.shared.syncWithServer(force: true)
            }
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
