import AVFoundation
import Foundation
import LiveKit
import UIKit

enum CallKind: String {
    case audio
    case video
}

enum OutgoingCallPhase: Equatable {
    case calling
    case ringing
    case tryingToReach
}

@MainActor
@Observable
final class CallSessionManager: NSObject {
    static let shared = CallSessionManager()

    var showUI = false
    var isMinimized = false
    var isIncoming = false
    var isConnecting = false
    var isActive = false
    var isMuted = false
    var isCameraOff = false
    /// Loudspeaker on (WhatsApp-style). Default on for video, off for audio until toggled.
    var isSpeakerOn = true
    var errorMessage: String?
    var timerSeconds = 0

    var callKind: CallKind?
    var conversationID: String?
    var peerName = "Member"
    var peerAvatarURL: String?
    var remoteVideoTrack: VideoTrack?
    var localVideoTrack: VideoTrack?
    var outgoingPhase: OutgoingCallPhase = .calling
    private(set) var isSignalingConnected = false

    private var room: Room?
    private var sessionID: String?
    private var roomName: String?
    private var fromUserID: String?
    private var peerUserID: String?
    private var incomingOffer: CallSignal?
    private var callStartAt: Date?
    private var callLogSent = false
    private var timerTask: Task<Void, Never>?
    private var incomingTimeoutTask: Task<Void, Never>?
    private var outgoingTimeoutTask: Task<Void, Never>?
    private var sentCallAccept = false
    private var incomingPresentedViaCallKit = false
    private(set) var hasEndedCurrentCall = false
    private var remoteDisconnectTask: Task<Void, Never>?
    private var roomReconnectTask: Task<Void, Never>?
    private var roomReconnectAttempts = 0

    private override init() {
        super.init()
        CallSignalingService.shared.onSignal = { [weak self] signal in
            Task { @MainActor in
                await self?.handle(signal)
            }
        }
        CallSignalingService.shared.onConnectionChange = { [weak self] connected in
            Task { @MainActor in
                self?.isSignalingConnected = connected
            }
        }
        isSignalingConnected = CallSignalingService.shared.isConnected
    }

    func bootstrap() {
        bootstrapForIncomingCall()
    }

    func bootstrapForIncomingCall() {
        VoIPPushService.shared.bootstrap()
        CallSignalingService.shared.connect()
        isSignalingConnected = CallSignalingService.shared.isConnected
    }

    func ensureSignalingReady() async {
        isSignalingConnected = await CallSignalingService.shared.ensureConnected()
    }

    func teardown() {
        cleanup(notifyRemote: isActive || isConnecting)
    }

    var canStartCall: Bool {
        !isActive && !isConnecting && !isIncoming && isSignalingConnected
    }

    var showFullCallUI: Bool {
        showUI && !isMinimized
    }

    var showCompactCallBar: Bool {
        isMinimized && (isActive || isConnecting)
    }

    func minimizeCall() {
        guard isActive || isConnecting else { return }
        isMinimized = true
    }

    func expandCall() {
        isMinimized = false
        showUI = true
    }

    func presentActiveCallUIIfNeeded() {
        guard UIApplication.shared.applicationState == .active else { return }
        guard isActive || isConnecting || (isIncoming && !incomingPresentedViaCallKit) else { return }
        guard !isMinimized else { return }
        showUI = true
    }

    func handleAppWillResignActive() {
        autoMinimizeCallIfNeeded()
    }

    func handleAppDidBecomeActive() {
        autoMinimizeCallIfNeeded()
    }

    private func autoMinimizeCallIfNeeded() {
        guard isActive || isConnecting else { return }
        guard !isIncoming else { return }
        showUI = true
        isMinimized = true
    }

    /// Foreground → Matterya overlay. Background / locked → system CallKit only (never both).
    static var shouldUseCallKitForIncomingRing: Bool {
        UIApplication.shared.applicationState != .active
    }

    func configurePeer(_ author: PostAuthor?) {
        peerName = author?.displayName ?? author?.username ?? "Member"
        peerAvatarURL = author?.avatarURL
        peerUserID = author?.userID
    }

    var titleText: String {
        let kind = callKind == .video ? "Video call" : "Voice call"
        return "\(peerName) · \(kind)"
    }

    var statusText: String {
        if let errorMessage { return errorMessage }
        if isIncoming {
            return callKind == .video ? "Incoming video call" : "Incoming voice call"
        }
        if isActive { return "In call" }
        if isOutgoingCaller {
            switch outgoingPhase {
            case .ringing:
                return "Ringing…"
            case .tryingToReach:
                return "Trying to reach…"
            case .calling:
                return isConnecting ? "Connecting…" : "Calling…"
            }
        }
        if isConnecting { return "Connecting…" }
        return "Calling…"
    }

    var isOutgoingCaller: Bool {
        guard let me = AuthService.shared.currentUser?.id else { return false }
        return fromUserID == me && !isIncoming
    }

    var subtitleText: String {
        switch callKind {
        case .video: "Video call"
        case .audio: "Voice call"
        case .none: "Call"
        }
    }

    var timerLabel: String {
        guard callStartAt != nil else { return "00:00" }
        return Message.formatDuration(timerSeconds)
    }

    func startCall(conversationID: String, kind: CallKind, peer: PostAuthor?) async {
        guard let me = AuthService.shared.currentUser?.id else { return }
        guard !isActive, !isConnecting, !isIncoming else { return }

        isSignalingConnected = await CallSignalingService.shared.ensureConnected()
        guard isSignalingConnected else {
            errorMessage = "Calling is offline. Check your connection and try again."
            return
        }

        configurePeer(peer)
        self.conversationID = conversationID
        callKind = kind
        fromUserID = me
        sessionID = UUID().uuidString
        roomName = "call_\(conversationID)_\(sessionID!)"
        isConnecting = true
        isIncoming = false
        isActive = false
        errorMessage = nil
        showUI = true
        isMinimized = false
        callStartAt = nil
        callLogSent = false
        outgoingPhase = .calling
        hasEndedCurrentCall = false
        roomReconnectAttempts = 0

        do {
            CallKitManager.shared.reportOutgoingCall(
                conversationID: conversationID,
                callerName: peerName,
                hasVideo: kind == .video
            )
            CallKitManager.shared.reportOutgoingCallStartedConnecting(conversationID: conversationID)
            await prepareAudioForCall(usesCallKit: shouldUseCallKitAudio(for: conversationID))
            try await connectRoom(video: kind == .video)
            CallSignalingService.shared.send(
                type: "call-offer",
                conversationID: conversationID,
                from: me,
                callType: kind.rawValue,
                callID: sessionID,
                roomName: roomName
            )
            beginOutgoingFeedback()
            scheduleOutgoingCallTimeout()
        } catch {
            errorMessage = error.localizedDescription
            cleanup(notifyRemote: false)
        }
    }

    @discardableResult
    func stageIncomingCall(
        conversationID: String,
        from userID: String,
        callType: String,
        callID: String?,
        roomName: String?,
        callerName: String? = nil
    ) -> Bool {
        if let me = AuthService.shared.currentUser?.id, userID == me { return false }
        if isActive { return false }
        if isIncoming, self.conversationID == conversationID { return true }
        if isIncoming || isConnecting { return false }

        let normalizedCallID = Self.nonEmpty(callID)
        let normalizedRoom = Self.nonEmpty(roomName)
            ?? normalizedCallID.map { "call_\(conversationID)_\($0)" }
            ?? "call_\(conversationID)_\(userID)"

        incomingOffer = CallSignal(
            type: "call-offer",
            conversationID: conversationID,
            from: userID,
            callType: callType,
            callID: normalizedCallID,
            roomName: normalizedRoom,
            connectedAt: nil
        )
        self.conversationID = conversationID
        callKind = callType == "video" ? .video : .audio
        fromUserID = userID
        sessionID = normalizedCallID
        self.roomName = normalizedRoom
        isIncoming = true
        isConnecting = false
        isActive = false
        errorMessage = nil
        hasEndedCurrentCall = false

        let appIsActive = UIApplication.shared.applicationState == .active
        incomingPresentedViaCallKit = !appIsActive
        isMinimized = false
        showUI = appIsActive
        if appIsActive {
            CallSoundService.shared.start(.incomingRing)
        }

        if let callerName = Self.nonEmpty(callerName) {
            peerName = callerName
        }

        sendCallRinging(
            conversationID: conversationID,
            to: userID,
            callID: normalizedCallID
        )
        scheduleIncomingCallTimeout()
        return true
    }

    func presentInAppIncomingUI() {
        guard isIncoming else { return }
        isMinimized = false
        showUI = true
        CallSoundService.shared.start(.incomingRing)
    }

    private func sendCallRinging(conversationID: String, to userID: String, callID: String?) {
        guard let me = AuthService.shared.currentUser?.id else {
            Task {
                _ = await CallSignalingService.shared.ensureConnected()
                guard let me = AuthService.shared.currentUser?.id else { return }
                CallSignalingService.shared.send(
                    type: "call-ringing",
                    conversationID: conversationID,
                    from: me,
                    callID: callID,
                    to: userID
                )
            }
            return
        }

        CallSignalingService.shared.send(
            type: "call-ringing",
            conversationID: conversationID,
            from: me,
            callID: callID,
            to: userID
        )
    }

    func finalizeIncomingCallPresentation(
        conversationID: String,
        from userID: String,
        reportToCallKit: Bool
    ) async {
        guard isIncoming, self.conversationID == conversationID else { return }

        if reportToCallKit {
            incomingPresentedViaCallKit = true
            CallSoundService.shared.stop()
            await CallKitManager.shared.reportIncomingCall(
                conversationID: conversationID,
                callerName: peerName,
                hasVideo: callKind == .video
            )
        }

        await resolvePeer(from: userID, conversationID: conversationID)
    }

    func prepareIncomingCall(
        conversationID: String,
        from userID: String,
        callType: String,
        callID: String?,
        roomName: String?,
        callerName: String? = nil,
        reportToCallKit: Bool = true
    ) async {
        guard stageIncomingCall(
            conversationID: conversationID,
            from: userID,
            callType: callType,
            callID: callID,
            roomName: roomName,
            callerName: callerName
        ) else { return }

        await finalizeIncomingCallPresentation(
            conversationID: conversationID,
            from: userID,
            reportToCallKit: reportToCallKit
        )
    }

    @discardableResult
    func acceptCall() async -> Bool {
        if isConnecting || isActive {
            return isActive || isConnecting
        }
        guard isIncoming else { return false }

        incomingTimeoutTask?.cancel()
        incomingTimeoutTask = nil
        sentCallAccept = false
        bootstrapForIncomingCall()
        isSignalingConnected = await CallSignalingService.shared.ensureConnected(timeoutSeconds: 15)

        guard let offer = incomingOffer ?? pendingIncomingSignal(),
              let me = AuthService.shared.currentUser?.id
        else {
            errorMessage = "Could not join call."
            cleanup(notifyRemote: false)
            return false
        }

        CallSoundService.shared.stop()
        conversationID = offer.conversationID
        callKind = offer.callType == "video" ? .video : .audio
        fromUserID = offer.from
        sessionID = offer.callID
        roomName = resolvedRoomName(for: offer)
        isIncoming = false
        isConnecting = true
        showUI = true
        isMinimized = false
        errorMessage = nil
        hasEndedCurrentCall = false

        do {
            let usesCallKitAudio = shouldUseCallKitAudio(for: offer.conversationID)
            await prepareAudioForCall(usesCallKit: usesCallKitAudio)
            try await connectRoom(video: callKind == .video)
            incomingOffer = nil
            sentCallAccept = true
            let connectedAt = Date().timeIntervalSince1970
            applySynchronizedCallStart(at: connectedAt)
            CallSignalingService.shared.send(
                type: "call-accept",
                conversationID: offer.conversationID,
                from: me,
                callType: callKind?.rawValue,
                callID: sessionID,
                roomName: roomName,
                to: offer.from,
                connectedAt: connectedAt
            )
            await refreshLocalAudioCapture()
            evaluateConnectedState()
            isMinimized = false
            showUI = true
            presentActiveCallUIIfNeeded()
            return isActive || isConnecting
        } catch {
            errorMessage = error.localizedDescription
            incomingOffer = offer
            cleanup(notifyRemote: false, endCallKit: true)
            return false
        }
    }

    func declineCall(fromCallKit: Bool = false) {
        guard conversationID != nil else { return }
        CallSoundService.shared.stop()
        if let conversationID, let me = AuthService.shared.currentUser?.id {
            CallSignalingService.shared.send(type: "call-decline", conversationID: conversationID, from: me, callID: sessionID)
        }
        Task {
            await sendCallLog(status: "missed")
            cleanup(notifyRemote: false, endCallKit: !fromCallKit)
        }
    }

    func endCall(fromCallKit: Bool = false) {
        guard !hasEndedCurrentCall else { return }
        let status = isActive || callStartAt != nil ? "ended" : "missed"
        Task {
            await sendCallLog(status: status)
            cleanup(notifyRemote: true, endCallKit: !fromCallKit)
        }
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        Task {
            if !muted {
                await refreshLocalAudioCapture()
            } else {
                _ = try? await room?.localParticipant.setMicrophone(enabled: false)
            }
        }
    }

    func toggleCamera() {
        isCameraOff.toggle()
        Task {
            _ = try? await room?.localParticipant.setCamera(enabled: !isCameraOff)
        }
    }

    /// Route call audio to loudspeaker (on) or earpiece (off).
    func toggleSpeaker() {
        isSpeakerOn.toggle()
        applySpeakerRoute()
    }

    func applySpeakerRoute() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: isSpeakerOn ? [.defaultToSpeaker, .allowBluetooth] : [.allowBluetooth]
            )
            try session.setActive(true, options: [])
            if isSpeakerOn {
                try session.overrideOutputAudioPort(.speaker)
            } else {
                try session.overrideOutputAudioPort(.none)
            }
        } catch {
            #if DEBUG
            print("[Call] speaker route failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func resolvePeer(from userID: String, conversationID: String) async {
        if let conversations = try? await MessagesService.shared.listConversations(limit: 100),
           let conversation = conversations.first(where: { $0.id == conversationID }),
           let member = conversation.members.first(where: { $0.userID == userID }) {
            configurePeer(member)
            return
        }
        peerUserID = userID
        if peerName == "Member" {
            peerName = "Incoming call"
        }
    }

    private func pendingIncomingSignal() -> CallSignal? {
        guard isIncoming, let conversationID, let fromUserID else { return nil }
        return CallSignal(
            type: "call-offer",
            conversationID: conversationID,
            from: fromUserID,
            callType: callKind?.rawValue,
            callID: sessionID,
            roomName: roomName,
            connectedAt: nil
        )
    }

    private func handle(_ signal: CallSignal) async {
        guard let me = AuthService.shared.currentUser?.id, signal.from != me else { return }

        switch signal.type {
        case "call-offer":
            if isIncoming, conversationID == signal.conversationID {
                // VoIP push may have already staged this call and reported it to CallKit.
                return
            }
            if isActive || isIncoming || (isConnecting && fromUserID == me) {
                CallSignalingService.shared.send(type: "call-busy", conversationID: signal.conversationID, from: me, callID: signal.callID)
                return
            }
            await prepareIncomingCall(
                conversationID: signal.conversationID,
                from: signal.from,
                callType: signal.callType ?? "audio",
                callID: signal.callID,
                roomName: signal.roomName,
                reportToCallKit: Self.shouldUseCallKitForIncomingRing
            )

        case "call-ringing":
            guard isOutgoingCaller, conversationID == signal.conversationID else { return }
            outgoingPhase = .ringing
            if !isConnecting, !isActive {
                CallSoundService.shared.start(.outgoingRing)
            }

        case "call-unreachable":
            guard isOutgoingCaller, conversationID == signal.conversationID, outgoingPhase != .ringing else { return }
            outgoingPhase = .tryingToReach
            if !isConnecting, !isActive {
                CallSoundService.shared.start(.tryingToReach)
            }

        case "call-accept":
            guard fromUserID == me, matchesCurrentCall(signal) else { return }
            if let name = signal.roomName { roomName = name }
            outgoingPhase = .ringing
            if let connectedAt = signal.connectedAt {
                applySynchronizedCallStart(at: connectedAt)
            }
            if let room, !room.remoteParticipants.isEmpty {
                markActive()
            }

        case "call-decline", "call-busy":
            guard matchesCurrentCall(signal) else { return }
            if fromUserID == me {
                await sendCallLog(status: "missed")
            }
            cleanup(notifyRemote: false)

        case "call-end":
            guard matchesCurrentCall(signal) else { return }
            if isActive || callStartAt != nil {
                await sendCallLog(status: "ended")
            } else if isIncoming || isConnecting {
                await sendCallLog(status: "missed")
            }
            cleanup(notifyRemote: false)

        default:
            break
        }
    }

    private func shouldUseCallKitAudio(for conversationID: String) -> Bool {
        if CallKitManager.shared.isAudioSessionActivated {
            return true
        }
        if CallKitManager.shared.hasCall(conversationID: conversationID) {
            return true
        }
        if UIApplication.shared.applicationState != .active {
            return incomingPresentedViaCallKit
        }
        return false
    }

    private func matchesCurrentCall(_ signal: CallSignal) -> Bool {
        guard let conversationID, signal.conversationID == conversationID else { return false }
        if let currentID = sessionID,
           let signalID = Self.nonEmpty(signal.callID),
           currentID != signalID {
            return false
        }
        return true
    }

    private func applySynchronizedCallStart(at unixTime: TimeInterval) {
        let startDate = Date(timeIntervalSince1970: unixTime)
        if let existingStart = callStartAt {
            callStartAt = min(existingStart, startDate)
        } else {
            callStartAt = startDate
            startTimer()
        }
    }

    private func remotePeerUserID() -> String? {
        guard let me = AuthService.shared.currentUser?.id else { return nil }
        if fromUserID == me {
            return peerUserID
        }
        return fromUserID
    }

    private func resolvedRoomName(for offer: CallSignal) -> String {
        if let explicit = Self.nonEmpty(offer.roomName) {
            return explicit
        }
        if let callID = Self.nonEmpty(offer.callID) {
            return "call_\(offer.conversationID)_\(callID)"
        }
        return "call_\(offer.conversationID)_\(offer.from)"
    }

    private func prepareAudioForCall(usesCallKit: Bool) async {
        CallSoundService.shared.stop()
        if usesCallKit {
            await CallKitManager.shared.waitForAudioSessionActivation()
            activateLiveKitAudio()
        } else {
            prepareInAppCallAudio()
        }
    }

    private func prepareInAppCallAudio() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try? session.setActive(true)
        activateLiveKitAudio()
    }

    private func activateLiveKitAudio() {
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = true
        try? AudioManager.shared.setEngineAvailability(.default)
    }

    private func refreshLocalAudioCapture() async {
        activateLiveKitAudio()
        _ = try? await room?.localParticipant.setMicrophone(enabled: !isMuted)
        _ = try? await Task.sleep(nanoseconds: 250_000_000)
        _ = try? await room?.localParticipant.setMicrophone(enabled: !isMuted)
    }

    private func connectRoom(video: Bool) async throws {
        guard let roomName else { throw CallError.missingRoom }
        await disconnectRoom()

        let tokenInfo = try await fetchLiveKitToken(roomName: roomName)
        guard !tokenInfo.url.isEmpty else { throw CallError.liveKitNotConfigured }

        var lastError: Error?
        for attempt in 0..<2 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await disconnectRoom()
            }

            let newRoom = Room()
            newRoom.add(delegate: self)
            room = newRoom
            isCameraOff = !video
            isMuted = false

            do {
                activateLiveKitAudio()
                try await newRoom.connect(
                    url: tokenInfo.url,
                    token: tokenInfo.token,
                    connectOptions: ConnectOptions(enableMicrophone: true)
                )
                try await newRoom.localParticipant.setCamera(enabled: video)
                await refreshLocalAudioCapture()
                updateLocalVideoTrack(from: newRoom.localParticipant)
                evaluateConnectedState()
                return
            } catch {
                lastError = error
                room?.remove(delegate: self)
                room = nil
            }
        }

        throw lastError ?? CallError.tokenFailed("Could not join call room.")
    }

    private func evaluateConnectedState() {
        guard let room, !isActive else { return }
        guard !room.remoteParticipants.isEmpty else { return }
        markActive()
        for participant in room.remoteParticipants.values {
            updateRemoteVideoTrack(for: participant)
        }
    }

    private func fetchLiveKitToken(roomName: String) async throws -> (token: String, url: String) {
        let token: String
        do {
            token = try await AuthService.shared.ensureValidToken()
        } catch {
            throw CallError.notAuthenticated
        }
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/livekit/token") else {
            throw CallError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "room": roomName,
            "name": AuthService.shared.currentUser?.id ?? "member",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lkToken = json["token"] as? String
        else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw CallError.tokenFailed(message ?? "LiveKit auth failed.")
        }
        let serverURL = (json["url"] as? String) ?? ""
        return (lkToken, serverURL)
    }

    private func markActive() {
        guard !isActive else { return }
        CallSoundService.shared.stop()
        incomingTimeoutTask?.cancel()
        incomingTimeoutTask = nil
        outgoingTimeoutTask?.cancel()
        outgoingTimeoutTask = nil
        isConnecting = false
        isActive = true
        isIncoming = false
        showUI = true
        outgoingPhase = .calling
        if let conversationID {
            CallKitManager.shared.reportCallConnected(conversationID: conversationID)
        }
        presentActiveCallUIIfNeeded()
        if callStartAt == nil {
            callStartAt = Date()
            startTimer()
        }
        Task {
            if let conversationID {
                await prepareAudioForCall(usesCallKit: shouldUseCallKitAudio(for: conversationID))
            }
            await refreshLocalAudioCapture()
        }
    }

    private func beginOutgoingFeedback() {
        guard isOutgoingCaller else { return }
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard isOutgoingCaller, !isActive, !isConnecting, !isIncoming, showUI else { return }
            if outgoingPhase == .calling {
                outgoingPhase = .tryingToReach
                CallSoundService.shared.start(.tryingToReach)
            }
        }
    }

    private func scheduleIncomingCallTimeout() {
        incomingTimeoutTask?.cancel()
        incomingTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard !Task.isCancelled else { return }
            await missUnansweredIncomingCall()
        }
    }

    private func scheduleOutgoingCallTimeout() {
        outgoingTimeoutTask?.cancel()
        outgoingTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            guard isOutgoingCaller, !isActive, showUI || isConnecting else { return }
            endCall()
        }
    }

    private func missUnansweredIncomingCall() async {
        guard isIncoming, !isActive, !isConnecting else { return }
        if let conversationID, let me = AuthService.shared.currentUser?.id, let fromUserID {
            CallSignalingService.shared.send(
                type: "call-decline",
                conversationID: conversationID,
                from: me,
                callID: sessionID,
                to: fromUserID
            )
        }
        await sendCallLog(status: "missed")
        cleanup(notifyRemote: false)
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let callStartAt {
                    timerSeconds = max(0, Int(Date().timeIntervalSince(callStartAt)))
                }
            }
        }
    }

    private func sendCallLog(status: String) async {
        guard !callLogSent, let conversationID, let kind = callKind else { return }
        let duration = callStartAt.map { max(0, Int(Date().timeIntervalSince($0))) } ?? 0
        let body = Message.callLogBody(status: status, kind: kind.rawValue, durationSeconds: duration)
        if let _ = try? await MessagesService.shared.sendMessage(conversationID: conversationID, body: body) {
            NotificationCenter.default.post(
                name: .conversationMessagesDidChange,
                object: nil,
                userInfo: ["conversationId": conversationID]
            )
        }
        callLogSent = true
    }

    func handleIncomingPushCall(
        conversationID: String,
        from userID: String,
        callType: String,
        callID: String?,
        roomName: String?,
        callerName: String? = nil
    ) async {
        if isIncoming, self.conversationID == conversationID { return }
        await prepareIncomingCall(
            conversationID: conversationID,
            from: userID,
            callType: callType,
            callID: callID,
            roomName: roomName,
            callerName: callerName,
            reportToCallKit: false
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func notifyCallerCallEnded() {
        guard sentCallAccept || isActive else { return }
        guard let conversationID, let me = AuthService.shared.currentUser?.id else { return }
        CallSignalingService.shared.send(
            type: "call-end",
            conversationID: conversationID,
            from: me,
            callID: sessionID,
            to: fromUserID
        )
    }

    private func cleanup(notifyRemote: Bool, endCallKit: Bool = true) {
        guard !hasEndedCurrentCall else { return }
        hasEndedCurrentCall = true

        incomingTimeoutTask?.cancel()
        incomingTimeoutTask = nil
        outgoingTimeoutTask?.cancel()
        outgoingTimeoutTask = nil
        remoteDisconnectTask?.cancel()
        remoteDisconnectTask = nil
        roomReconnectTask?.cancel()
        roomReconnectTask = nil
        roomReconnectAttempts = 0
        let endedConversationID = conversationID
        let shouldNotifyRemote = notifyRemote || sentCallAccept || isActive
        CallSoundService.shared.stop()
        if endCallKit {
            CallKitManager.shared.requestEndCall(for: endedConversationID)
        }
        if shouldNotifyRemote, let conversationID, let me = AuthService.shared.currentUser?.id {
            Task {
                _ = await CallSignalingService.shared.ensureConnected(timeoutSeconds: 2)
                CallSignalingService.shared.send(
                    type: "call-end",
                    conversationID: conversationID,
                    from: me,
                    callID: sessionID,
                    to: remotePeerUserID()
                )
            }
        }
        sentCallAccept = false
        incomingPresentedViaCallKit = false
        timerTask?.cancel()
        timerTask = nil
        Task { await disconnectRoom() }

        showUI = false
        isMinimized = false
        outgoingPhase = .calling
        isIncoming = false
        isConnecting = false
        isActive = false
        isMuted = false
        isCameraOff = false
        errorMessage = nil
        timerSeconds = 0
        callKind = nil
        conversationID = nil
        fromUserID = nil
        sessionID = nil
        roomName = nil
        incomingOffer = nil
        callStartAt = nil
        remoteVideoTrack = nil
        localVideoTrack = nil
    }

    private func disconnectRoom() async {
        if let room {
            room.remove(delegate: self)
            await room.disconnect()
        }
        room = nil
    }

    private func updateLocalVideoTrack(from participant: LocalParticipant? = nil) {
        let local = participant ?? room?.localParticipant
        guard let local else { return }
        localVideoTrack = local.trackPublications.values
            .compactMap { $0 as? LocalTrackPublication }
            .first(where: { $0.kind == .video })?
            .track as? VideoTrack
    }

    private func updateRemoteVideoTrack(for participant: RemoteParticipant) {
        remoteVideoTrack = participant.trackPublications.values
            .compactMap { $0 as? RemoteTrackPublication }
            .first(where: { $0.kind == .video })?
            .track as? VideoTrack
    }

    enum CallError: LocalizedError {
        case notAuthenticated
        case invalidURL
        case missingRoom
        case liveKitNotConfigured
        case tokenFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: "Not authenticated."
            case .invalidURL: "Invalid LiveKit URL."
            case .missingRoom: "Missing call room."
            case .liveKitNotConfigured: "Calling is not configured on the server."
            case .tokenFailed(let msg): msg
            }
        }
    }
}

extension CallSessionManager: RoomDelegate {
    nonisolated func room(_ room: Room, participant: LocalParticipant, didPublishTrack publication: LocalTrackPublication) {
        Task { @MainActor in
            if publication.kind == .video {
                self.localVideoTrack = publication.track as? VideoTrack
            }
        }
    }

    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor in
            self.remoteDisconnectTask?.cancel()
            self.remoteDisconnectTask = nil
            self.markActive()
            self.updateRemoteVideoTrack(for: participant)
        }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in
            guard self.isActive, self.room === room else { return }
            // Wait for explicit call-end signaling; LiveKit can briefly drop participants
            // during track or network churn.
            self.remoteDisconnectTask?.cancel()
            self.remoteDisconnectTask = Task {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled, self.isActive, self.room === room else { return }
                guard self.room?.remoteParticipants.isEmpty == true else { return }
                self.endCall()
            }
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor in
            if publication.kind == .audio {
                self.activateLiveKitAudio()
                if !self.isActive {
                    self.markActive()
                }
            }
            if publication.kind == .video {
                self.remoteVideoTrack = publication.track as? VideoTrack
                self.markActive()
            }
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor in
            if publication.kind == .video {
                self.remoteVideoTrack = nil
            }
        }
    }

    private func scheduleRoomReconnect(reason: String?) {
        guard isActive, !hasEndedCurrentCall, roomReconnectAttempts < 3 else {
            if isActive { endCall() }
            return
        }
        roomReconnectTask?.cancel()
        roomReconnectTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, self.isActive, !self.hasEndedCurrentCall else { return }
            self.roomReconnectAttempts += 1
            if let reason, !reason.isEmpty {
                self.errorMessage = "Reconnecting…"
            }
            do {
                try await self.connectRoom(video: self.callKind == .video)
                self.errorMessage = nil
                self.roomReconnectAttempts = 0
                await self.refreshLocalAudioCapture()
                self.evaluateConnectedState()
            } catch {
                self.scheduleRoomReconnect(reason: error.localizedDescription)
            }
        }
    }

    nonisolated func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        Task { @MainActor in
            guard self.room === room, !self.hasEndedCurrentCall else { return }
            if self.isActive {
                self.scheduleRoomReconnect(reason: error?.localizedDescription)
            } else if self.sentCallAccept {
                if let error { self.errorMessage = error.localizedDescription }
                self.cleanup(notifyRemote: true, endCallKit: true)
            } else if self.isConnecting || self.isIncoming {
                if let error { self.errorMessage = error.localizedDescription }
                self.cleanup(notifyRemote: false, endCallKit: true)
            } else {
                self.cleanup(notifyRemote: true, endCallKit: true)
            }
        }
    }
}