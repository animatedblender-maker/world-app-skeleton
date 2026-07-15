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
    private(set) var lastVoIPRegistrationError: String?
    private(set) var serverRegistrationSucceeded = false
    private(set) var voipServerRegistrationSucceeded = false

    var hasVoIPToken: Bool {
        loadPersistedTokens()
        guard let voipToken else { return false }
        return !voipToken.isEmpty
    }

    var hasAlertToken: Bool {
        loadPersistedTokens()
        guard let deviceToken else { return false }
        return !deviceToken.isEmpty
    }

    struct ServerPushStatus: Equatable {
        var endpointsAvailable: Bool
        var apnsConfigured: Bool
        var apnsProduction: Bool
        var bundleId: String
        var alertTokenCount: Int
        var voipTokenCount: Int
        var environments: [String]
        var statusMessage: String?
    }

    private(set) var lastServerPushStatus: ServerPushStatus?

    var registrationSummary: String {
        if serverRegistrationSucceeded {
            return "Alert push registered with Matterya servers."
        }
        if let lastRegistrationError {
            return lastRegistrationError
        }
        if deviceToken == nil {
            return "Waiting for Apple device token…"
        }
        return "Alert push not registered yet."
    }

    var callingRegistrationSummary: String {
        if voipServerRegistrationSucceeded {
            return "VoIP registered — incoming calls can ring when Matterya is closed."
        }
        if let lastVoIPRegistrationError {
            return lastVoIPRegistrationError
        }
        if let voipStatus = VoIPPushService.shared.lastStatusMessage {
            return voipStatus
        }
        if !VoIPPushService.shared.isSupportedOnThisDevice {
            return VoIPPushService.shared.lastStatusMessage
                ?? "VoIP requires a real iPhone. Simulator and Mac builds cannot receive call pushes."
        }
        if !hasVoIPToken {
            return "Waiting for Apple VoIP token… Open Xcode → WorldApp target → Signing & Capabilities and confirm Push Notifications + Background Modes (Voice over IP) are enabled, then reinstall on iPhone."
        }
        if !AuthService.shared.isAuthenticated {
            return "Sign in so Matterya can register this device for calls."
        }
        return "VoIP token received but not registered with server yet."
    }

    var isReadyForIncomingCalls: Bool {
        voipServerRegistrationSucceeded && hasVoIPToken
    }

    var pushEnvironmentLabel: String {
        apnsEnvironment
    }

    private var authRefreshObserver: NSObjectProtocol?

    private override init() {
        super.init()
        loadPersistedTokens()
    }

    private var apnsEnvironment: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "APSEnvironment") as? String {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "production" { return "production" }
            if normalized == "development" || normalized == "sandbox" { return "sandbox" }
        }
        if let entitlement = entitlementApsEnvironment {
            return entitlement
        }
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    private var entitlementApsEnvironment: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "Entitlements") as? [String: Any],
              let value = raw["aps-environment"] as? String
        else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "production" { return "production" }
        if normalized == "development" { return "sandbox" }
        return nil
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        installAuthRefreshObserverIfNeeded()
    }

    private func installAuthRefreshObserverIfNeeded() {
        guard authRefreshObserver == nil else { return }
        authRefreshObserver = NotificationCenter.default.addObserver(
            forName: .authTokenDidRefresh,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                VoIPPushService.shared.bootstrap()
                await PushNotificationService.shared.syncWithServer(force: true)
            }
        }
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

        await registerForRemoteNotifications()
    }

    func registerForRemoteNotificationsIfAuthorized() async {
        configure()
        guard await notificationsAuthorized() else { return }
        await registerForRemoteNotifications()
    }

    private func registerForRemoteNotifications() async {
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
        Task { @MainActor in
            // Do not tear down PushKit here — refreshRegistry() was preventing VoIP tokens from arriving.
            VoIPPushService.shared.bootstrap()
            await registerTokenIfNeeded(token, kind: "alert", force: true)
            await VoIPPushService.shared.ensureToken()
            if let voipToken = self.voipToken ?? UserDefaults.standard.string(forKey: voipTokenDefaultsKey) {
                await registerTokenIfNeeded(voipToken, kind: "voip", force: true)
            }
        }
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

    func unregisterFromServer() async {
        loadPersistedTokens()
        let tokens = Set([deviceToken, voipToken].compactMap { $0 }.filter { !$0.isEmpty })
        guard !tokens.isEmpty else { return }
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/push/ios/unregister") else { return }

        let accessToken = try? await AuthService.shared.ensureValidToken()
        for token in tokens {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let accessToken {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["deviceToken": token])
            _ = try? await URLSession.shared.data(for: request)
        }

        deviceToken = nil
        lastRegisteredToken = nil
        lastRegisteredVoIPToken = nil
        serverRegistrationSucceeded = false
        voipServerRegistrationSucceeded = false
        lastVoIPRegistrationError = nil
        UserDefaults.standard.removeObject(forKey: alertTokenDefaultsKey)
    }

    func syncWithServer(force: Bool = false) async {
        configure()
        loadPersistedTokens()
        if force {
            lastRegisteredToken = nil
            lastRegisteredVoIPToken = nil
        }

        VoIPPushService.shared.bootstrap()
        await VoIPPushService.shared.ensureToken()

        let authorized = await notificationsAuthorized()
        if authorized {
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        if let voipToken = self.voipToken ?? UserDefaults.standard.string(forKey: voipTokenDefaultsKey) {
            self.voipToken = voipToken
            await registerTokenIfNeeded(voipToken, kind: "voip", force: force)
        }

        if let token = deviceToken {
            await registerTokenIfNeeded(token, kind: "alert", force: force)
        } else if authorized {
            await requestAuthorizationAndRegister()
        }
    }

    func fetchServerCapabilities() async -> (iosPushRoutes: Bool, apnsConfigured: Bool, webPushConfigured: Bool) {
        for path in ["/push/capabilities", "/health"] {
            guard let url = URL(string: "\(AppConfig.apiBaseURL)\(path)") else { continue }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    continue
                }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                let features = json["features"] as? [String: Any]
                let iosPushRoutes =
                    json["iosPushRoutes"] as? Bool
                    ?? features?["iosPushRoutes"] as? Bool
                    ?? (path == "/push/capabilities")
                let apnsConfigured = json["apnsConfigured"] as? Bool ?? false
                let webPushConfigured = json["webPushConfigured"] as? Bool ?? false
                return (iosPushRoutes, apnsConfigured, webPushConfigured)
            } catch {
                continue
            }
        }
        return (false, false, false)
    }

    func fetchServerPushStatus() async -> ServerPushStatus? {
        let capabilities = await fetchServerCapabilities()
        guard capabilities.iosPushRoutes else {
            let status = ServerPushStatus(
                endpointsAvailable: false,
                apnsConfigured: capabilities.apnsConfigured,
                apnsProduction: false,
                bundleId: "com.matterya.worldapp",
                alertTokenCount: 0,
                voipTokenCount: 0,
                environments: [],
                statusMessage: "api.matterya.com is missing iOS push routes. Deploy the latest apps/api build on Render (branch ios-native), then redeploy."
            )
            lastServerPushStatus = status
            return status
        }

        guard AuthService.shared.isAuthenticated else { return nil }
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/push/ios/status") else { return nil }

        let accessToken: String
        do {
            accessToken = try await AuthService.shared.ensureValidToken()
        } catch {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 404 {
                let status = ServerPushStatus(
                    endpointsAvailable: false,
                    apnsConfigured: capabilities.apnsConfigured,
                    apnsProduction: false,
                    bundleId: "com.matterya.worldapp",
                    alertTokenCount: 0,
                    voipTokenCount: 0,
                    environments: [],
                    statusMessage: "Push status endpoint missing on api.matterya.com. Deploy the latest apps/api build."
                )
                lastServerPushStatus = status
                return status
            }
            guard (200...299).contains(http.statusCode) else { return nil }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let tokens = json["tokens"] as? [String: Any]
            else {
                return nil
            }

            let environments = (tokens["environments"] as? [String]) ?? []
            let status = ServerPushStatus(
                endpointsAvailable: true,
                apnsConfigured: json["apnsConfigured"] as? Bool ?? capabilities.apnsConfigured,
                apnsProduction: json["apnsProduction"] as? Bool ?? false,
                bundleId: json["bundleId"] as? String ?? "com.matterya.worldapp",
                alertTokenCount: tokens["alert"] as? Int ?? 0,
                voipTokenCount: tokens["voip"] as? Int ?? 0,
                environments: environments,
                statusMessage: nil
            )
            lastServerPushStatus = status
            return status
        } catch {
            return nil
        }
    }

    func sendTestNotification() async -> String {
        guard AuthService.shared.isAuthenticated else {
            return "Sign in first."
        }
        guard hasAlertToken else {
            return "No Apple alert token on this device. Use a real iPhone, enable notifications, then tap Refresh below."
        }
        guard serverRegistrationSucceeded else {
            return registrationSummary
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
            if (200...299).contains(http.statusCode) {
                _ = await fetchServerPushStatus()
                return "Test notification sent. Lock your phone or background the app to see it."
            }

            let message = Self.pushErrorMessage(from: data, statusCode: http.statusCode)
            _ = await fetchServerPushStatus()
            return message
        } catch {
            return error.localizedDescription
        }
    }

    private static func pushErrorMessage(from data: Data, statusCode: Int) -> String {
        if statusCode == 404 {
            return "api.matterya.com does not have iOS push routes yet. Deploy the latest apps/api build to the server."
        }

        if
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = json["message"] as? String,
            !message.isEmpty
        {
            if let error = json["error"] as? String {
                return "\(message) (\(error))"
            }
            return message
        }

        let body = String(data: data, encoding: .utf8) ?? "push_failed"
        return "Server error \(statusCode): \(body)"
    }

    @discardableResult
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> Bool {
        let payload = normalizedPayload(userInfo)
        return await routePushPayload(payload)
    }

    /// Synchronous CallKit presentation for locked/background pushes (Messenger-style fallback).
    @discardableResult
    func presentIncomingCallForBackgroundWake(_ userInfo: [AnyHashable: Any]) -> Bool {
        IncomingCallWake.handleIfNeeded(userInfo)
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
        let isVoIP = kind == "voip"
        let last = isVoIP ? lastRegisteredVoIPToken : lastRegisteredToken
        let alreadyRegistered = isVoIP ? voipServerRegistrationSucceeded : serverRegistrationSucceeded
        if !force, token == last, alreadyRegistered { return }
        guard AuthService.shared.isAuthenticated else {
            let message = "Sign in so Matterya can register this device for push."
            if isVoIP {
                lastVoIPRegistrationError = message
            } else {
                lastRegistrationError = message
            }
            return
        }
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/push/ios/register") else { return }

        let accessToken: String
        do {
            accessToken = try await AuthService.shared.ensureValidToken()
        } catch {
            if isVoIP {
                lastVoIPRegistrationError = error.localizedDescription
            } else {
                lastRegistrationError = error.localizedDescription
            }
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
                let message = "Invalid server response."
                if isVoIP {
                    lastVoIPRegistrationError = message
                    voipServerRegistrationSucceeded = false
                } else {
                    lastRegistrationError = message
                    serverRegistrationSucceeded = false
                }
                return
            }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "register_failed"
                let message: String
                if http.statusCode == 404 {
                    message = "api.matterya.com does not have iOS push routes yet. Deploy the latest apps/api server build on Render, then tap Refresh push status."
                } else if body.localizedCaseInsensitiveContains("does not exist")
                    || body.localizedCaseInsensitiveContains("ios_device_tokens")
                {
                    message = "Server database is missing ios_device_tokens. Run supabase/migrations/20260713000000_create_ios_device_tokens.sql in Supabase SQL editor, then refresh."
                } else {
                    message = "Registration failed (\(http.statusCode)): \(body)"
                }
                if isVoIP {
                    lastVoIPRegistrationError = message
                    voipServerRegistrationSucceeded = false
                } else {
                    lastRegistrationError = message
                    serverRegistrationSucceeded = false
                }
                logger.error("Push register failed: \(body, privacy: .public)")
                return
            }

            if isVoIP {
                lastRegisteredVoIPToken = token
                lastVoIPRegistrationError = nil
                voipServerRegistrationSucceeded = true
            } else {
                lastRegisteredToken = token
                lastRegistrationError = nil
                serverRegistrationSucceeded = true
            }
            logger.info("Registered \(kind, privacy: .public) token with server")
        } catch {
            if isVoIP {
                lastVoIPRegistrationError = error.localizedDescription
                voipServerRegistrationSucceeded = false
            } else {
                lastRegistrationError = error.localizedDescription
                serverRegistrationSucceeded = false
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let payload = normalizedPayload(notification.request.content.userInfo)
        let isCall = Self.isCallPayload(payload)
        let useInAppCallUI = await inAppCallUIForForegroundNotification(isCall: isCall)
        _ = await routePushPayload(payload, presentInAppUI: useInAppCallUI)
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
        let isCall = Self.isCallPayload(payload)
        let useInAppCallUI = await inAppCallUIForForegroundNotification(isCall: isCall, preferCallKit: true)
        _ = await routePushPayload(payload, presentInAppUI: useInAppCallUI)
    }

    @MainActor
    private func inAppCallUIForForegroundNotification(isCall: Bool, preferCallKit: Bool = false) -> Bool {
        guard isCall else { return false }
        if preferCallKit { return false }
        return UIApplication.shared.applicationState == .active
            && !CallSessionManager.shouldUseCallKitForIncomingRing
    }

    nonisolated private static func isCallPayload(_ payload: [String: Any]) -> Bool {
        let type = ((payload["type"] as? String) ?? (payload["category"] as? String) ?? "").lowercased()
        if type == "call" || type == "incoming_call" { return true }
        if let aps = payload["aps"] as? [String: Any] {
            let category = (aps["category"] as? String)?.lowercased()
            if category == "call" { return true }
        }
        return false
    }

    @MainActor
    private func routePushPayload(_ payload: [String: Any], presentInAppUI: Bool = false) async -> Bool {
        if Self.isCallPayload(payload) {
            return await routeIncomingCallPayload(payload, presentInAppUI: presentInAppUI)
        }

        let type = ((payload["type"] as? String) ?? (payload["category"] as? String) ?? "").lowercased()

        if type == "message", let conversationID = stringValue(payload["conversationId"]) {
            NotificationCenter.default.post(
                name: .conversationMessagesDidChange,
                object: nil,
                userInfo: ["conversationId": conversationID]
            )
            postDeepLink(type: type, conversationID: conversationID, postID: nil, username: nil)
            return false
        }

        let postID = stringValue(payload["postId"]) ?? stringValue(payload["entityId"])
        let username = stringValue(payload["username"]) ?? stringValue(payload["actorUsername"])
        if Self.socialNotificationTypes.contains(type) || postID != nil {
            NotificationCenter.default.post(name: .socialNotificationsDidChange, object: nil)
            postDeepLink(type: type, conversationID: nil, postID: postID, username: username)
        }

        return false
    }

    private func postDeepLink(
        type: String,
        conversationID: String?,
        postID: String?,
        username: String?
    ) {
        NotificationCenter.default.post(
            name: .pushDeepLinkRequested,
            object: nil,
            userInfo: [
                "type": type,
                "conversationId": conversationID as Any,
                "postId": postID as Any,
                "username": username as Any,
            ]
        )
    }

    private static let socialNotificationTypes: Set<String> = [
        "like", "comment", "comment_like", "comment_reply", "follow",
    ]

    @MainActor
    private func routeIncomingCallPayload(_ payload: [String: Any], presentInAppUI: Bool) async -> Bool {
        guard
            let conversationID = stringValue(payload["conversationId"]),
            let from = stringValue(payload["from"])
        else {
            logger.error("Call push missing conversationId/from: \(payload.keys.joined(separator: ","), privacy: .public)")
            return false
        }

        let callType = stringValue(payload["callType"]) ?? "audio"
        let callID = stringValue(payload["callId"]) ?? stringValue(payload["callID"])
        let roomName = stringValue(payload["roomName"]) ?? stringValue(payload["room"])
        let displayName =
            stringValue(payload["title"])
            ?? stringValue(payload["callerName"])
            ?? "Incoming call"

        if let me = AuthService.shared.currentUser?.id, from == me { return true }

        CallSessionManager.shared.bootstrapForIncomingCall()

        guard CallSessionManager.shared.stageIncomingCall(
            conversationID: conversationID,
            from: from,
            callType: callType,
            callID: callID,
            roomName: roomName,
            callerName: displayName
        ) else {
            if !presentInAppUI {
                CallKitManager.shared.requestEndCall(for: conversationID)
            }
            return true
        }

        await CallSessionManager.shared.finalizeIncomingCallPresentation(
            conversationID: conversationID,
            from: from,
            reportToCallKit: !presentInAppUI
        )

        if presentInAppUI {
            CallSessionManager.shared.presentInAppIncomingUI()
        }
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
        var merged = userInfo.reduce(into: [String: Any]()) { result, entry in
            if let key = entry.key as? String {
                result[key] = entry.value
            }
        }

        if let custom = merged["custom"] as? [String: Any] {
            for (key, value) in custom where merged[key] == nil {
                merged[key] = value
            }
        }
        if let data = merged["data"] as? [String: Any] {
            for (key, value) in data where merged[key] == nil {
                merged[key] = value
            }
        }

        return merged
    }
}