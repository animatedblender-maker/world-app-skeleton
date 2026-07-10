import Foundation

struct CallSignal: Sendable {
    let type: String
    let conversationID: String
    let from: String
    let callType: String?
    let callID: String?
    let roomName: String?
}

@MainActor
@Observable
final class CallSignalingService {
    static let shared = CallSignalingService()

    private(set) var isConnected = false {
        didSet {
            guard oldValue != isConnected else { return }
            onConnectionChange?(isConnected)
        }
    }

    var onSignal: ((CallSignal) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    private var webSocketTask: URLSessionWebSocketTask?
    private var listenTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var tokenRefreshObserver: NSObjectProtocol?
    private var isDestroyed = false

    private init() {}

    func connect() {
        isDestroyed = false
        installTokenRefreshObserverIfNeeded()
        if isConnected, let webSocketTask, webSocketTask.state == .running {
            return
        }
        reconnectTask?.cancel()
        reconnectTask = Task { await openSocket() }
    }

    func ensureConnected(timeoutSeconds: Double = 6) async -> Bool {
        connect()
        if isConnected { return true }
        let attempts = max(1, Int(timeoutSeconds / 0.25))
        for _ in 0..<attempts {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if isConnected { return true }
        }
        return isConnected
    }

    func disconnect() {
        listenTask?.cancel()
        reconnectTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    func shutdown() {
        isDestroyed = true
        if let tokenRefreshObserver {
            NotificationCenter.default.removeObserver(tokenRefreshObserver)
            self.tokenRefreshObserver = nil
        }
        disconnect()
    }

    private func installTokenRefreshObserverIfNeeded() {
        guard tokenRefreshObserver == nil else { return }
        tokenRefreshObserver = NotificationCenter.default.addObserver(
            forName: .authTokenDidRefresh,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.reconnectWithFreshToken() }
        }
    }

    private func reconnectWithFreshToken() async {
        guard !isDestroyed else { return }
        listenTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        reconnectTask?.cancel()
        reconnectTask = Task { await openSocket() }
    }

    func send(
        type: String,
        conversationID: String,
        from: String,
        callType: String? = nil,
        callID: String? = nil,
        roomName: String? = nil,
        to: String? = nil
    ) {
        guard let webSocketTask, isConnected else { return }
        var payload: [String: Any] = [
            "type": type,
            "conversationId": conversationID,
            "from": from,
        ]
        if let callType { payload["callType"] = callType }
        if let callID { payload["callId"] = callID }
        if let roomName { payload["roomName"] = roomName }
        if let to { payload["to"] = to }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8)
        else { return }
        webSocketTask.send(.string(text)) { _ in }
    }

    private func openSocket() async {
        let token: String?
        do {
            token = try await AuthService.shared.ensureValidToken()
        } catch {
            token = nil
        }
        guard let token else {
            isConnected = false
            scheduleReconnect()
            return
        }

        let wsBase = AppConfig.apiBaseURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        guard let url = URL(string: "\(wsBase)/ws?token=\(token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token)") else {
            isConnected = false
            scheduleReconnect()
            return
        }

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false

        let task = URLSession.shared.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        let opened = await waitForSocketOpen(task)
        guard opened, !isDestroyed, webSocketTask === task else {
            isConnected = false
            if !isDestroyed {
                scheduleReconnect()
            }
            return
        }

        isConnected = true
        listenTask?.cancel()
        listenTask = Task { await listen(on: task) }
    }

    private func waitForSocketOpen(_ task: URLSessionWebSocketTask) async -> Bool {
        await withCheckedContinuation { continuation in
            task.sendPing { error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    private func listen(on task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                guard case .string(let raw) = message else { continue }
                handle(raw)
            } catch {
                isConnected = false
                scheduleReconnect()
                break
            }
        }
    }

    private func handle(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              let conversationID = json["conversationId"] as? String,
              let from = json["from"] as? String
        else { return }

        let signal = CallSignal(
            type: type,
            conversationID: conversationID,
            from: from,
            callType: json["callType"] as? String,
            callID: json["callId"] as? String,
            roomName: json["roomName"] as? String
        )
        onSignal?(signal)
    }

    private func scheduleReconnect() {
        guard !isDestroyed else { return }
        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await openSocket()
        }
    }
}