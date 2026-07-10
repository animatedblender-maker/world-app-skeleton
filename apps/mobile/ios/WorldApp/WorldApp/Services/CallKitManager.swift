import AVFoundation
import CallKit
import Foundation

final class CallKitManager: NSObject, CXProviderDelegate {
    static let shared = CallKitManager()

    private let provider: CXProvider
    private let callController = CXCallController()
    private var callUUIDByConversationID: [String: UUID] = [:]
    private var conversationIDByCallUUID: [UUID: String] = [:]
    private var audioSessionWaiters: [CheckedContinuation<Void, Never>] = []

    private override init() {
        let configuration = CXProviderConfiguration(localizedName: "Matterya")
        configuration.supportsVideo = true
        configuration.maximumCallsPerCallGroup = 1
        configuration.maximumCallGroups = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.ringtoneSound = "MatteryaCall.caf"
        configuration.includesCallsInRecents = false
        provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: DispatchQueue.main)
    }

    func reportIncomingCall(
        conversationID: String,
        callerName: String,
        hasVideo: Bool
    ) async {
        await withCheckedContinuation { continuation in
            reportIncomingCall(
                conversationID: conversationID,
                callerName: callerName,
                hasVideo: hasVideo
            ) { _ in
                continuation.resume()
            }
        }
    }

    func reportIncomingCall(
        conversationID: String,
        callerName: String,
        hasVideo: Bool,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        let callUUID = callUUIDByConversationID[conversationID] ?? UUID()
        callUUIDByConversationID[conversationID] = callUUID
        conversationIDByCallUUID[callUUID] = conversationID

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: conversationID)
        update.localizedCallerName = callerName
        update.hasVideo = hasVideo

        provider.reportNewIncomingCall(with: callUUID, update: update, completion: completion)
    }

    func reportOutgoingCall(conversationID: String, callerName: String, hasVideo: Bool) {
        let callUUID = UUID()
        callUUIDByConversationID[conversationID] = callUUID
        conversationIDByCallUUID[callUUID] = conversationID

        let handle = CXHandle(type: .generic, value: conversationID)
        let action = CXStartCallAction(call: callUUID, handle: handle)
        action.isVideo = hasVideo
        action.contactIdentifier = callerName
        callController.request(CXTransaction(action: action)) { _ in }
    }

    func waitForAudioSessionActivation(timeoutSeconds: Double = 5) async {
        let session = AVAudioSession.sharedInstance()
        if session.category == .playAndRecord {
            try? session.setActive(true)
            return
        }

        await withCheckedContinuation { continuation in
            audioSessionWaiters.append(continuation)
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                resumeAudioSessionWaiters()
            }
        }
    }

    private func resumeAudioSessionWaiters() {
        let waiters = audioSessionWaiters
        audioSessionWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func endCall(for conversationID: String?) {
        guard let conversationID,
              let callUUID = callUUIDByConversationID[conversationID]
        else { return }

        let action = CXEndCallAction(call: callUUID)
        callController.request(CXTransaction(action: action)) { _ in }
        clearMapping(for: conversationID)
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Task { @MainActor in
            CallSessionManager.shared.bootstrapForIncomingCall()
            await CallSessionManager.shared.acceptCall()
            action.fulfill()
        }
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor in
            let manager = CallSessionManager.shared
            if manager.isIncoming && !manager.isActive && !manager.isConnecting {
                manager.declineCall()
            } else {
                manager.endCall()
            }
            if let conversationID = conversationIDByCallUUID[action.callUUID] {
                clearMapping(for: conversationID)
            }
            action.fulfill()
        }
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetoothHFP, .defaultToSpeaker, .mixWithOthers]
            )
            try audioSession.setActive(true)
        } catch {}
        resumeAudioSessionWaiters()
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        Task { @MainActor in
            CallSoundService.shared.stop()
        }
    }

    func providerDidReset(_ provider: CXProvider) {
        callUUIDByConversationID.removeAll()
        conversationIDByCallUUID.removeAll()
    }

    private func clearMapping(for conversationID: String) {
        if let callUUID = callUUIDByConversationID.removeValue(forKey: conversationID) {
            conversationIDByCallUUID.removeValue(forKey: callUUID)
        }
    }
}