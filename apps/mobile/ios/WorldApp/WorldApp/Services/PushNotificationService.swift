import Foundation
import OSLog
import UIKit
import UserNotifications

@MainActor
final class PushNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.matterya.worldapp", category: "Push")
    private let alertTokenDefaultsKey = "push.alert.token"
    private let voipTokenDefaultsKey = "push.voip.token"

    private var deviceToken: String?
    private var voipToken: String?
    private var lastRegisteredToken: String?
    private var lastRegisteredVoIPToken: String?

    private(set) var lastRegistrationError: String?
    private(set) var serverRegistrationSucceeded = false

    var registrationSummary: String {
        if serverRegistrationSucceeded {
            return "Registered with Matterya servers."
        }
        if let lastRegistrationError {
            return lastRegistrationError
        }
        if deviceToken == nil {
            return "Waiting for Apple device token…"
        }
        return "Not registered yet."
    }

    private override init() {
        super.init()
        loadPersistedTokens()
    }

    private var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorizationAndRegister() async {
        configure()
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                guard granted else {
                    lastRegistrationError = "Notification permission denied."
                    return
                }
            } catch {
                lastRegistrationError = error.localizedDescription
                return
            }
        case .authorized, .provisional, .ephemeral:
            break
        default:
            lastRegistrationError = "Notifications are disabled in iOS Settings."
            return
        }

        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func notificationsAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
    }

    func updateDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        UserDefaults.standard.set(token, forKey: alertTokenDefaultsKey)
        logger.info("Received APNs device token (\(self.apnsEnvironment, privacy: .public))")
        Task { await registerTokenIfNeeded(token, kind: "alert", force: true) }
    }

    func registerVoIPToken(_ token: String) async {
        voipToken = token
        UserDefaults.standard.set(token, forKey: voipTokenDefaultsKey)
        await registerTokenIfNeeded(token, kind: "voip", force: true)
    }

    func handleRegistrationFailure() {
        deviceToken = nil
        UserDefaults.standard.removeObject(forKey: alertTokenDefaultsKey)
        lastRegistrationError = "Apple push registration failed. Use a real device, not the simulator."
        serverRegistrationSucceeded = false
        logger.error("Failed to register for remote notifications")
    }

    func syncWithServer(force: Bool = false) async {
        loadPersistedTokens()
        if force {
            lastRegisteredToken = nil
            lastRegisteredVoIPToken = nil
        }

        let authorized = await notificationsAuthorized()
        if authorized {
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }

        if let token = deviceToken {
            await registerTokenIfNeeded(token, kind: "alert", force: force)
        } else if authorized {
            await requestAuthorizationAndRegister()
        }

        if let voipToken {
            await registerTokenIfNeeded(voipToken, kind: "voip", force: force)
        }
    }

    func sendTestNotification() async -> String {
        guard AuthService.shared.isAuthenticated else {
            return "Sign in first."
        }
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/push/ios/test") else {
            return "Invalid API URL."
        }

        let accessToken: String
        do {
            accessToken = try await AuthService.shared.ensureValidToken()
        } catch {
            return error.localizedDescription
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return "Unexpected server response."
            }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "push_failed"
                return "Server error \(http.statusCode): \(body)"
            }
            return "Test notification sent. Lock your phone or background the app to see it."
        } catch {
            return error.localizedDescription
        }
    }

    @discardableResult
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> Bool {
        let payload = normalizedPayload(userInfo)
        return await routePushPayload(payload)
    }

    func handleIncomingCallPayload(
        _ payload: [String: Any],
        completion: (() -> Void)? = nil
    ) async {
        _ = await routePushPayload(payload)
        completion?()
    }

    private func loadPersistedTokens() {
        deviceToken = deviceToken ?? UserDefaults.standard.string(forKey: alertTokenDefaultsKey)
        voipToken = voipToken ?? UserDefaults.standard.string(forKey: voipTokenDefaultsKey)
    }

    private func registerTokenIfNeeded(_ token: String, kind: String, force: Bool = false) async {
        let last = kind == "voip" ? lastRegisteredVoIPToken : lastRegisteredToken
        if !force, token == last, serverRegistrationSucceeded { return }
        guard AuthService.shared.isAuthenticated else {
            lastRegistrationError = "Sign in so Matterya can register this device for push."
            return
        }
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/push/ios/register") else { return }

        let accessToken: String
        do {
            accessToken = try await AuthService.shared.ensureValidToken()
        } catch {
            lastRegistrationError = error.localizedDescription
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "deviceToken": token,
            "bundleId": Bundle.main.bundleIdentifier ?? "com.matterya.worldapp",
            "kind": kind,
            "environment": apnsEnvironment,
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastRegistrationError = "Invalid server response."
                serverRegistrationSucceeded = false
                return
            }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "register_failed"
                lastRegistrationError = "Registration failed (\(http.statusCode)): \(body)"
                serverRegistrationSucceeded = false
                logger.error("Push register failed: \(body, privacy: .public)")
                return
            }

            if kind == "voip" {
                lastRegisteredVoIPToken = token
            } else {
                lastRegisteredToken = token
            }
            lastRegistrationError = nil
            serverRegistrationSucceeded = true
            logger.info("Registered \(kind, privacy: .public) token with server")
        } catch {
            lastRegistrationError = error.localizedDescription
            serverRegistrationSucceeded = false
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let payload = normalizedPayload(notification.request.content.userInfo)
        let isCall = await routePushPayload(payload)
        if isCall {
            return []
        }
        return [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let payload = normalizedPayload(response.notification.request.content.userInfo)
        _ = await routePushPayload(payload)
    }

    @MainActor
    private func routePushPayload(_ payload: [String: Any]) async -> Bool {
        let type = ((payload["type"] as? String) ?? (payload["category"] as? String) ?? "").lowercased()

        if type == "call" || type == "incoming_call" {
            return await routeIncomingCallPayload(payload)
        }

        if type == "message", let conversationID = payload["conversationId"] as? String {
            NotificationCenter.default.post(
                name: .conversationMessagesDidChange,
                object: nil,
                userInfo: ["conversationId": conversationID]
            )
            return false
        }

        if Self.socialNotificationTypes.contains(type) || payload["postId"] != nil || payload["entityId"] != nil {
            NotificationCenter.default.post(name: .socialNotificationsDidChange, object: nil)
        }

        return false
    }

    private static let socialNotificationTypes: Set<String> = [
        "like", "comment", "comment_like", "comment_reply", "follow",
    ]

    @MainActor
    private func routeIncomingCallPayload(_ payload: [String: Any]) async -> Bool {
        guard
            let conversationID = stringValue(payload["conversationId"]),
            let from = stringValue(payload["from"])
        else { return false }

        let callType = stringValue(payload["callType"]) ?? "audio"
        let callID = stringValue(payload["callId"])
        let roomName = stringValue(payload["roomName"])
        let displayName = stringValue(payload["title"]) ?? "Incoming call"

        if let me = AuthService.shared.currentUser?.id, from == me { return true }

        CallSessionManager.shared.bootstrapForIncomingCall()

        await CallKitManager.shared.reportIncomingCall(
            conversationID: conversationID,
            callerName: displayName,
            hasVideo: callType == "video"
        )

        guard CallSessionManager.shared.stageIncomingCall(
            conversationID: conversationID,
            from: from,
            callType: callType,
            callID: callID,
            roomName: roomName,
            callerName: displayName
        ) else {
            CallKitManager.shared.endCall(for: conversationID)
            return true
        }

        await CallSessionManager.shared.finalizeIncomingCallPresentation(
            conversationID: conversationID,
            from: from,
            reportToCallKit: false
        )
        return true
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    nonisolated private func normalizedPayload(_ userInfo: [AnyHashable: Any]) -> [String: Any] {
        userInfo.reduce(into: [String: Any]()) { result, entry in
            if let key = entry.key as? String {
                result[key] = entry.value
            }
        }
    }
}