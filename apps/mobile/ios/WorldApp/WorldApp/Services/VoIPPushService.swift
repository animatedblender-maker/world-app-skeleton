import Foundation
import OSLog
import PushKit
import UIKit

struct IncomingCallPushPayload: Sendable {
    let conversationID: String
    let from: String
    let callType: String
    let callID: String?
    let roomName: String?
    let displayName: String
}

final class VoIPPushService: NSObject, PKPushRegistryDelegate {
    nonisolated(unsafe) static let shared = VoIPPushService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.matterya.worldapp", category: "VoIP")
    private var registry: PKPushRegistry?
    private var refreshTask: Task<Void, Never>?

    private(set) var lastStatusMessage: String?

    var isRegistryActive: Bool {
        registry != nil
    }

    private override init() {
        super.init()
    }

    var isSupportedOnThisDevice: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        if ProcessInfo.processInfo.isiOSAppOnMac {
            return false
        }
        return true
        #endif
    }

    func bootstrap() {
        runOnMain {
            self.bootstrapOnMain()
        }
    }

    func refreshRegistry() {
        runOnMain {
            self.refreshRegistryOnMain()
        }
    }

    @MainActor
    func bootstrapOnMain() {
        bootstrapOnMainUnlocked()
    }

    @MainActor
    func refreshRegistryOnMain() {
        refreshRegistryOnMainUnlocked()
    }

    @MainActor
    func teardownOnMain() {
        teardownOnMainUnlocked()
    }

    func ensureToken(maxAttempts: Int = 15) async {
        guard isSupportedOnThisDevice else {
            await setStatusMessage(unsupportedDeviceMessage)
            return
        }

        await bootstrapOnMain()

        if await hasVoIPToken() {
            await setStatusMessage(nil)
            return
        }

        if await PushNotificationService.shared.notificationsAuthorized() {
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }

        for attempt in 0..<maxAttempts {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if await hasVoIPToken() {
                await setStatusMessage(nil)
                return
            }
            if attempt == 3 || attempt == 8 || attempt == 13 {
                await refreshRegistryOnMain()
            }
        }

        if !(await hasVoIPToken()) {
            await setStatusMessage(
                "Apple has not issued a VoIP token. Delete Matterya from your iPhone, rebuild in Xcode (Signing & Capabilities: Push Notifications + Background Modes → Voice over IP + Remote notifications), then install again on a real iPhone — not Simulator or Mac."
            )
            await MainActor.run {
                Self.shared.logger.error("Timed out waiting for VoIP push token (registry active: \(Self.shared.isRegistryActive))")
            }
        }
    }

    func teardown() {
        runOnMain {
            self.teardownOnMainUnlocked()
        }
    }

    nonisolated func pushRegistry(
        _ registry: PKPushRegistry,
        didUpdate pushCredentials: PKPushCredentials,
        for type: PKPushType
    ) {
        guard type == .voIP else { return }
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            Self.shared.logger.info("Received VoIP push token")
            await PushNotificationService.shared.registerVoIPToken(token)
        }
    }

    nonisolated func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else {
            completion()
            return
        }

        let dictionary = payload.dictionaryPayload.reduce(into: [String: Any]()) { result, entry in
            if let key = entry.key as? String {
                result[key] = entry.value
            }
        }

        guard let callPayload = Self.parseIncomingCallPayload(dictionary) else {
            Task { @MainActor in
                Self.shared.logger.error("VoIP push missing call fields: \(dictionary.keys.joined(separator: ","), privacy: .public)")
            }
            completion()
            return
        }

        let finish: @Sendable () -> Void = {
            completion()
        }

        let handlePush = { @MainActor in
            Self.shared.handleIncomingVoIPPush(callPayload, finish: finish)
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                handlePush()
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    handlePush()
                }
            }
        }
    }

    nonisolated func pushRegistry(
        _ registry: PKPushRegistry,
        didInvalidatePushTokenFor type: PKPushType
    ) {
        guard type == .voIP else { return }
        Task { @MainActor in
            Self.shared.logger.warning("VoIP push token invalidated; refreshing PushKit registry")
            Self.shared.refreshRegistryOnMain()
            await PushNotificationService.shared.syncWithServer(force: true)
        }
    }

    @MainActor
    private func handleIncomingVoIPPush(_ callPayload: IncomingCallPushPayload, finish: @escaping @Sendable () -> Void) {
        logger.info("Incoming VoIP call push for conversation \(callPayload.conversationID, privacy: .public)")

        if let me = AuthService.shared.currentUser?.id, callPayload.from == me {
            finish()
            return
        }

        CallSessionManager.shared.bootstrapForIncomingCall()

        let useCallKit = CallSessionManager.shouldUseCallKitForIncomingRing
        if useCallKit {
            CallKitManager.shared.reportIncomingCall(
                conversationID: callPayload.conversationID,
                callerName: callPayload.displayName,
                hasVideo: callPayload.callType == "video"
            ) { _ in
                finish()
            }
        } else {
            finish()
        }

        let staged = CallSessionManager.shared.stageIncomingCall(
            conversationID: callPayload.conversationID,
            from: callPayload.from,
            callType: callPayload.callType,
            callID: callPayload.callID,
            roomName: callPayload.roomName,
            callerName: callPayload.displayName
        )

        if staged {
            Task { @MainActor in
                await CallSessionManager.shared.finalizeIncomingCallPresentation(
                    conversationID: callPayload.conversationID,
                    from: callPayload.from,
                    reportToCallKit: false
                )
                if UIApplication.shared.applicationState == .active {
                    CallSessionManager.shared.presentInAppIncomingUI()
                }
            }
        } else if useCallKit {
            logger.warning("Could not stage incoming call after VoIP push")
            CallKitManager.shared.requestEndCall(for: callPayload.conversationID)
        }
    }

    @MainActor
    private func bootstrapOnMainUnlocked() {
        guard isSupportedOnThisDevice else {
            lastStatusMessage = unsupportedDeviceMessage
            logger.warning("VoIP push unavailable on this device build")
            return
        }
        if let registry {
            registry.delegate = self
            registry.desiredPushTypes = [.voIP]
            return
        }
        let pushRegistry = PKPushRegistry(queue: .main)
        pushRegistry.delegate = self
        pushRegistry.desiredPushTypes = [.voIP]
        registry = pushRegistry
        lastStatusMessage = nil
        logger.info("PushKit VoIP registry started")
        scheduleTokenRefreshIfNeeded()
    }

    @MainActor
    private func refreshRegistryOnMainUnlocked() {
        guard isSupportedOnThisDevice else {
            lastStatusMessage = unsupportedDeviceMessage
            return
        }
        teardownOnMainUnlocked()
        bootstrapOnMainUnlocked()
    }

    @MainActor
    private func teardownOnMainUnlocked() {
        refreshTask?.cancel()
        refreshTask = nil
        registry?.delegate = nil
        registry?.desiredPushTypes = []
        registry = nil
    }

    @MainActor
    private func scheduleTokenRefreshIfNeeded() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            guard !PushNotificationService.shared.hasVoIPToken else { return }
            Self.shared.refreshRegistryOnMain()
        }
    }

    @MainActor
    private func hasVoIPToken() -> Bool {
        PushNotificationService.shared.hasVoIPToken
    }

    @MainActor
    private func setStatusMessage(_ message: String?) {
        lastStatusMessage = message
    }

    private var unsupportedDeviceMessage: String {
        #if targetEnvironment(simulator)
        return "VoIP is unavailable in the iOS Simulator. Install Matterya on a real iPhone."
        #else
        if ProcessInfo.processInfo.isiOSAppOnMac {
            return "VoIP calls do not work when running the iPhone app on Mac. Install on a real iPhone."
        }
        return "VoIP push is unavailable on this device."
        #endif
    }

    private func runOnMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            Task { @MainActor in
                work()
            }
        }
    }

    nonisolated private static func parseIncomingCallPayload(_ payload: [String: Any]) -> IncomingCallPushPayload? {
        let merged = mergePayloadDictionaries(payload)

        guard
            let conversationID = payloadString(merged, keys: ["conversationId", "conversationID", "conversation_id"]),
            let from = payloadString(merged, keys: ["from", "callerId", "callerID", "caller_id", "senderId", "sender_id"])
        else {
            return nil
        }

        let callType = payloadString(merged, keys: ["callType", "call_type", "kind"]) ?? "audio"
        return IncomingCallPushPayload(
            conversationID: conversationID,
            from: from,
            callType: callType == "video" ? "video" : "audio",
            callID: payloadString(merged, keys: ["callId", "callID", "call_id", "sessionId", "session_id"]),
            roomName: payloadString(merged, keys: ["roomName", "room_name", "room"]),
            displayName: payloadString(merged, keys: ["title", "callerName", "caller_name", "name"]) ?? "Incoming call"
        )
    }

    nonisolated private static func mergePayloadDictionaries(_ payload: [String: Any]) -> [String: Any] {
        var merged = payload
        if let custom = payload["custom"] as? [String: Any] {
            for (key, value) in custom {
                merged[key] = value
            }
        }
        if let data = payload["data"] as? [String: Any] {
            for (key, value) in data {
                merged[key] = value
            }
        }
        return merged
    }

    nonisolated private static func payloadString(_ payload: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = payload[key], let parsed = normalizedString(value) {
                return parsed
            }
        }
        return nil
    }

    nonisolated private static func normalizedString(_ value: Any) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }
}