import AVFoundation
import Foundation
import LiveKit

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
    var isIncoming = false
    var isConnecting = false
    var isActive = false
    var isMuted = false
    var isCameraOff = false
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
        callStartAt = nil
        callLogSent = false
        outgoingPhase = .calling

        do {
            CallKitManager.shared.reportOutgoingCall(
                conversationID: conversationID,
                callerName: peerName,
                hasVideo: kind == .video
            )
            await CallKitManager.shared.waitForAudioSessionActivation()
            prepareCallAudioSession()
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

        incomingOffer = CallSignal(
            type: "call-offer",
            conversationID: conversationID,
            from: userID,
            callType: callType,
            callID: normalizedCallID,
            roomName: normalizedRoom
        )
        self.conversationID = conversationID
        callKind = callType == "video" ? .video : .audio
        fromUserID = userID
        sessionID = normalizedCallID
        self.roomName = normalizedRoom
        isIncoming = true
        isConnecting = false
        isActive = false
        showUI = true
        errorMessage = nil

        if let callerName = Self.nonEmpty(callerName) {
            peerName = callerName
        }

        sendCallRinging(
            conversationID: conversationID,
            to: userID,
            callID: normalizedCallID
        )
        return true
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

    func acceptCall() async {
        bootstrapForIncomingCall()
        _ = await ensureSignalingReady()

        guard let offer = incomingOffer ?? pendingIncomingSignal(),
              let me = AuthService.shared.currentUser?.id
        else {
            errorMessage = "Could not join call."
            return
        }

        CallSoundService.shared.stop()
        conversationID = offer.conversationID
        callKind = offer.callType == "video" ? .video : .audio
        fromUserID = offer.from
        sessionID = offer.callID
        roomName = Self.nonEmpty(offer.roomName)
            ?? offer.callID.flatMap { Self.nonEmpty($0) }.map { "call_\(offer.conversationID)_\($0)" }
        isIncoming = false
        isConnecting = true
        showUI = true
        errorMessage = nil

        guard let roomName else {
            errorMessage = "Missing call room."
            incomingOffer = nil
            cleanup(notifyRemote: false)
            return
        }

        do {
            await CallKitManager.shared.waitForAudioSessionActivation()
            prepareCallAudioSession()
            try await connectRoom(video: callKind == .video)
            incomingOffer = nil
            CallSignalingService.shared.send(
                type: "call-accept",
                conversationID: offer.conversationID,
                from: me,
                callType: callKind?.rawValue,
                callID: sessionID,
                roomName: roomName
            )
        } catch {
            errorMessage = error.localizedDescription
            incomingOffer = offer
            cleanup(notifyRemote: false)
        }
    }

    func declineCall() {
        guard let conversationID else { return }
        CallSoundService.shared.stop()
        if let me = AuthService.shared.currentUser?.id {
            CallSignalingService.shared.send(type: "call-decline", conversationID: conversationID, from: me, callID: sessionID)
        }
        cleanup(notifyRemote: false)
    }

    func endCall() {
        let status = isActive || callStartAt != nil ? "ended" : "missed"
        Task { await sendCallLog(status: status) }
        cleanup(notifyRemote: true)
    }

    func toggleMute() {
        isMuted.toggle()
        Task {
            try? await room?.localParticipant.setMicrophone(enabled: !isMuted)
        }
    }

    func toggleCamera() {
        isCameraOff.toggle()
        Task {
            try? await room?.localParticipant.setCamera(enabled: !isCameraOff)
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
            roomName: roomName
        )
    }

    private func handle(_ signal: CallSignal) async {
        guard let me = AuthService.shared.currentUser?.id, signal.from != me else { return }

        switch signal.type {
        case "call-offer":
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
                reportToCallKit: true
            )

        case "call-ringing":
            guard isOutgoingCaller, conversationID == signal.conversationID else { return }
            outgoingPhase = .ringing
            CallSoundService.shared.start(.outgoingRing)

        case "call-unreachable":
            guard isOutgoingCaller, conversationID == signal.conversationID, outgoingPhase != .ringing else { return }
            outgoingPhase = .tryingToReach
            CallSoundService.shared.start(.tryingToReach)

        case "call-accept":
            guard fromUserID == me, conversationID == signal.conversationID else { return }
            if let name = signal.roomName { roomName = name }
            markActive()

        case "call-decline", "call-busy":
            if fromUserID == me {
                await sendCallLog(status: "missed")
            }
            cleanup(notifyRemote: false)

        case "call-end":
            cleanup(notifyRemote: false)

        default:
            break
        }
    }

    private func prepareCallAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothHFP, .defaultToSpeaker, .mixWithOthers]
        )
        try? session.setActive(true)
    }

    private func connectRoom(video: Bool) async throws {
        guard let roomName else { throw CallError.missingRoom }
        await disconnectRoom()

        let tokenInfo = try await fetchLiveKitToken(roomName: roomName)
        guard !tokenInfo.url.isEmpty else { throw CallError.liveKitNotConfigured }

        let newRoom = Room()
        newRoom.add(delegate: self)
        room = newRoom
        isCameraOff = !video
        isMuted = false

        try await newRoom.connect(
            url: tokenInfo.url,
            token: tokenInfo.token,
            connectOptions: ConnectOptions(enableMicrophone: true)
        )
        try await newRoom.localParticipant.setCamera(enabled: video)
        try await newRoom.localParticipant.setMicrophone(enabled: true)
        updateLocalVideoTrack(from: newRoom.localParticipant)
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
        CallSoundService.shared.stop()
        isConnecting = false
        isActive = true
        isIncoming = false
        outgoingPhase = .calling
        if callStartAt == nil {
            callStartAt = Date()
            startTimer()
        }
    }

    private func beginOutgoingFeedback() {
        guard isOutgoingCaller else { return }
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard isOutgoingCaller, !isActive, !isIncoming, showUI else { return }
            if outgoingPhase == .calling {
                outgoingPhase = .tryingToReach
                CallSoundService.shared.start(.tryingToReach)
            }
        }
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

    private func cleanup(notifyRemote: Bool) {
        let endedConversationID = conversationID
        CallSoundService.shared.stop()
        CallKitManager.shared.endCall(for: endedConversationID)
        if notifyRemote, let conversationID, let me = AuthService.shared.currentUser?.id {
            CallSignalingService.shared.send(type: "call-end", conversationID: conversationID, from: me, callID: sessionID)
        }
        timerTask?.cancel()
        timerTask = nil
        Task { await disconnectRoom() }

        showUI = false
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
            self.markActive()
            self.updateRemoteVideoTrack(for: participant)
        }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor in
            if self.isActive {
                self.endCall()
            }
        }
    }

    nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor in
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

    nonisolated func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        Task { @MainActor in
            if let error {
                self.errorMessage = error.localizedDescription
            }
            self.cleanup(notifyRemote: false)
        }
    }
}