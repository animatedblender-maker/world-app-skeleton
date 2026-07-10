import Foundation
import PushKit

@MainActor
final class VoIPPushService: NSObject, PKPushRegistryDelegate {
    static let shared = VoIPPushService()

    private var registry: PKPushRegistry?

    private override init() {
        super.init()
    }

    func bootstrap() {
        guard registry == nil else { return }
        let pushRegistry = PKPushRegistry(queue: .main)
        pushRegistry.delegate = self
        pushRegistry.desiredPushTypes = [.voIP]
        registry = pushRegistry
    }

    func teardown() {
        registry?.desiredPushTypes = []
        registry = nil
    }

    nonisolated func pushRegistry(
        _ registry: PKPushRegistry,
        didUpdate pushCredentials: PKPushCredentials,
        for type: PKPushType
    ) {
        guard type == .voIP else { return }
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
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

        guard
            let conversationID = Self.payloadString(dictionary, key: "conversationId"),
            let from = Self.payloadString(dictionary, key: "from")
        else {
            completion()
            return
        }

        let callType = Self.payloadString(dictionary, key: "callType") ?? "audio"
        let callID = Self.payloadString(dictionary, key: "callId")
        let roomName = Self.payloadString(dictionary, key: "roomName")
        let displayName = Self.payloadString(dictionary, key: "title") ?? "Incoming call"

        let handlePush = {
            MainActor.assumeIsolated {
                if let me = AuthService.shared.currentUser?.id, from == me {
                    completion()
                    return
                }

                CallSessionManager.shared.bootstrapForIncomingCall()

                // Apple requires every VoIP push to be surfaced through CallKit immediately.
                CallKitManager.shared.reportIncomingCall(
                    conversationID: conversationID,
                    callerName: displayName,
                    hasVideo: callType == "video"
                ) { _ in
                    completion()
                }

                let staged = CallSessionManager.shared.stageIncomingCall(
                    conversationID: conversationID,
                    from: from,
                    callType: callType,
                    callID: callID,
                    roomName: roomName,
                    callerName: displayName
                )

                if staged {
                    Task {
                        await CallSessionManager.shared.finalizeIncomingCallPresentation(
                            conversationID: conversationID,
                            from: from,
                            reportToCallKit: false
                        )
                    }
                } else {
                    CallKitManager.shared.endCall(for: conversationID)
                }
            }
        }

        if Thread.isMainThread {
            handlePush()
        } else {
            DispatchQueue.main.sync(execute: handlePush)
        }
    }

    nonisolated func pushRegistry(
        _ registry: PKPushRegistry,
        didInvalidatePushTokenFor type: PKPushType
    ) {}

    nonisolated private static func payloadString(_ payload: [String: Any], key: String) -> String? {
        guard let value = payload[key] else { return nil }
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