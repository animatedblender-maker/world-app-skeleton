import AVFoundation
import CallKit
import Foundation
import LiveKit
import UIKit

final class CallKitManager: NSObject, CXProviderDelegate {
    static let shared = CallKitManager()

    private let provider: CXProvider
    private let callController = CXCallController()
    private var callUUIDByConversationID: [String: UUID] = [:]
    private var conversationIDByCallUUID: [UUID: String] = [:]
    private var audioSessionWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var isAudioSessionActivated = false

    private override init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        configuration.maximumCallsPerCallGroup = 1
        configuration.maximumCallGroups = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.ringtoneSound = "MatteryaCall.caf"
        configuration.includesCallsInRecents = false
        if let icon = UIImage(named: "BrandLogo")?.pngData() {
            configuration.iconTemplateImageData = icon
        }
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
        let callUUID = callUUIDByConversationID[conversationID] ?? UUID()
        callUUIDByConversationID[conversationID] = callUUID
        conversationIDByCallUUID[callUUID] = conversationID

        let handle = CXHandle(type: .generic, value: conversationID)
        let action = CXStartCallAction(call: callUUID, handle: handle)
        action.isVideo = hasVideo
        action.contactIdentifier = callerName
        callController.request(CXTransaction(action: action)) { _ in }
    }

    func reportOutgoingCallStartedConnecting(conversationID: String) {
        guard let callUUID = callUUIDByConversationID[conversationID] else { return }
        provider.reportOutgoingCall(with: callUUID, startedConnectingAt: Date())
    }

    func reportCallConnected(conversationID: String) {
        guard let callUUID = callUUIDByConversationID[conversationID] else { return }
        provider.reportOutgoingCall(with: callUUID, connectedAt: Date())
    }

    func hasCall(conversationID: String) -> Bool {
        callUUIDByConversationID[conversationID] != nil
    }

    func waitForAudioSessionActivation(timeoutSeconds: Double = 8) async {
        if isAudioSessionActivated {
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

    func requestEndCall(for conversationID: String?) {
        guard let conversationID,
              let callUUID = callUUIDByConversationID[conversationID]
        else { return }

        clearMapping(for: conversationID)
        let action = CXEndCallAction(call: callUUID)
        callController.request(CXTransaction(action: action)) { _ in }
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        action.fulfill()
        Task { @MainActor in
            CallSessionManager.shared.bootstrapForIncomingCall()
            _ = await CallSessionManager.shared.acceptCall()
        }
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor in
            let manager = CallSessionManager.shared
            if !manager.hasEndedCurrentCall {
                if manager.isIncoming && !manager.isActive && !manager.isConnecting {
                    manager.declineCall(fromCallKit: true)
                } else {
                    manager.endCall(fromCallKit: true)
                }
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

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Task { @MainActor in
            CallSessionManager.shared.setMuted(action.isMuted)
            action.fulfill()
        }
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        isAudioSessionActivated = true
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = true
        try? AudioManager.shared.setEngineAvailability(.default)
        resumeAudioSessionWaiters()
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        isAudioSessionActivated = false
        Task { @MainActor in
            let manager = CallSessionManager.shared
            // CallKit swaps audio sessions when a call connects; don't tear down
            // LiveKit while the Matterya call is still active.
            guard !manager.isActive, !manager.isConnecting else { return }
            AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
            try? AudioManager.shared.setEngineAvailability(.none)
            CallSoundService.shared.stop()
        }
    }

    func providerDidReset(_ provider: CXProvider) {
        callUUIDByConversationID.removeAll()
        conversationIDByCallUUID.removeAll()
        isAudioSessionActivated = false
    }

    private func clearMapping(for conversationID: String) {
        if let callUUID = callUUIDByConversationID.removeValue(forKey: conversationID) {
            conversationIDByCallUUID.removeValue(forKey: callUUID)
        }
    }
}