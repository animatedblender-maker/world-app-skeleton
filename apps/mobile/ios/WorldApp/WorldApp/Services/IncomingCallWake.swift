import Foundation
import UIKit

/// Presents incoming calls immediately when a push wakes the app (locked / background / killed).
enum IncomingCallWake {
    struct Payload {
        let conversationID: String
        let from: String
        let callType: String
        let callID: String?
        let roomName: String?
        let displayName: String
    }

    @discardableResult
    static func handleIfNeeded(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let payload = parse(userInfo) else { return false }

        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                present(payload)
            }
        }

        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                present(payload)
            }
        }
    }

    @MainActor
    @discardableResult
    private static func present(_ payload: Payload) -> Bool {
        if let me = AuthService.shared.currentUser?.id, payload.from == me {
            return false
        }

        if UIApplication.shared.applicationState == .active {
            return presentInApp(payload)
        }

        return presentWithCallKit(payload)
    }

    @MainActor
    @discardableResult
    private static func presentInApp(_ payload: Payload) -> Bool {
        CallSessionManager.shared.bootstrapForIncomingCall()

        let staged = CallSessionManager.shared.stageIncomingCall(
            conversationID: payload.conversationID,
            from: payload.from,
            callType: payload.callType,
            callID: payload.callID,
            roomName: payload.roomName,
            callerName: payload.displayName
        )

        guard staged else { return false }

        Task {
            await CallSessionManager.shared.finalizeIncomingCallPresentation(
                conversationID: payload.conversationID,
                from: payload.from,
                reportToCallKit: false
            )
        }
        return true
    }

    @MainActor
    @discardableResult
    private static func presentWithCallKit(_ payload: Payload) -> Bool {
        _ = CallKitManager.shared
        CallSessionManager.shared.bootstrapForIncomingCall()

        CallKitManager.shared.reportIncomingCall(
            conversationID: payload.conversationID,
            callerName: payload.displayName,
            hasVideo: payload.callType == "video"
        ) { _ in }

        let staged = CallSessionManager.shared.stageIncomingCall(
            conversationID: payload.conversationID,
            from: payload.from,
            callType: payload.callType,
            callID: payload.callID,
            roomName: payload.roomName,
            callerName: payload.displayName
        )

        if staged {
            Task {
                await CallSessionManager.shared.finalizeIncomingCallPresentation(
                    conversationID: payload.conversationID,
                    from: payload.from,
                    reportToCallKit: false
                )
            }
        } else {
            CallKitManager.shared.requestEndCall(for: payload.conversationID)
        }

        return staged
    }

    static func parse(_ userInfo: [AnyHashable: Any]) -> Payload? {
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

        let type = ((merged["type"] as? String) ?? (merged["category"] as? String) ?? "").lowercased()
        let apsCategory = (merged["aps"] as? [String: Any])?["category"] as? String
        let isCall =
            type == "call"
            || type == "incoming_call"
            || apsCategory?.lowercased() == "call"
        guard isCall else { return nil }

        guard
            let conversationID =
                stringValue(merged["conversationId"])
                ?? stringValue(merged["conversationID"])
                ?? stringValue(merged["conversation_id"]),
            let from =
                stringValue(merged["from"])
                ?? stringValue(merged["callerId"])
                ?? stringValue(merged["callerID"])
                ?? stringValue(merged["senderId"])
        else {
            return nil
        }

        return Payload(
            conversationID: conversationID,
            from: from,
            callType: stringValue(merged["callType"]) ?? "audio",
            callID: stringValue(merged["callId"]) ?? stringValue(merged["callID"]),
            roomName: stringValue(merged["roomName"]) ?? stringValue(merged["room"]),
            displayName: stringValue(merged["title"])
                ?? stringValue(merged["callerName"])
                ?? "Incoming call"
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
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