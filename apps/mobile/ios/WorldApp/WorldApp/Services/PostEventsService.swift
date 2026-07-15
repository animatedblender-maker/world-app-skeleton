import Foundation

struct PostRealtimeInsert: Sendable {
    let id: String
    let countryCode: String?
    let authorID: String?
}

struct PostRealtimeDelete: Sendable {
    let id: String
    let countryCode: String?
    let authorID: String?
}

/// Supabase Realtime listener for `public.posts` — mirrors web `PostEventsService`.
@MainActor
final class PostEventsService {
    static let shared = PostEventsService()

    private var webSocketTask: URLSessionWebSocketTask?
    private var listenTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var tokenRefreshObserver: NSObjectProtocol?
    private var isDestroyed = false
    private var isJoined = false
    private var nextRef = 1
    private let channelTopic = "realtime:public:posts"
    private let joinRef = "1"

    private init() {}

    func start() {
        guard !AppConfig.useDemoDataset else { return }
        isDestroyed = false
        installTokenRefreshObserverIfNeeded()
        if isJoined, let webSocketTask, webSocketTask.state == .running {
            return
        }
        reconnectTask?.cancel()
        reconnectTask = Task { await openSocket() }
    }

    func stop() {
        isDestroyed = true
        if let tokenRefreshObserver {
            NotificationCenter.default.removeObserver(tokenRefreshObserver)
            self.tokenRefreshObserver = nil
        }
        heartbeatTask?.cancel()
        heartbeatTask = nil
        listenTask?.cancel()
        listenTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isJoined = false
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
        heartbeatTask?.cancel()
        listenTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isJoined = false
        reconnectTask?.cancel()
        reconnectTask = Task { await openSocket() }
    }

    private func openSocket() async {
        guard !isDestroyed else { return }
        guard AuthService.shared.isAuthenticated else { return }

        let accessToken: String
        do {
            accessToken = try await AuthService.shared.ensureValidToken()
        } catch {
            scheduleReconnect(after: 3)
            return
        }

        var components = URLComponents(string: "\(AppConfig.supabaseURL)/realtime/v1/websocket")!
        components.queryItems = [
            URLQueryItem(name: "apikey", value: AppConfig.supabaseAnonKey),
            URLQueryItem(name: "vsn", value: "1.0.0"),
        ]
        guard let url = components.url else { return }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        listenTask?.cancel()
        listenTask = Task { await listen(on: task) }

        sendJoin(accessToken: accessToken)
        startHeartbeat()
    }

    private func sendJoin(accessToken: String) {
        let ref = nextRefString()
        let message: [String: Any] = [
            "topic": channelTopic,
            "event": "phx_join",
            "payload": [
                "config": [
                    "broadcast": ["ack": false, "self": false],
                    "presence": ["enabled": false],
                    "postgres_changes": [
                        ["event": "INSERT", "schema": "public", "table": "posts"],
                        ["event": "DELETE", "schema": "public", "table": "posts"],
                    ],
                ],
                "access_token": accessToken,
            ],
            "ref": ref,
            "join_ref": joinRef,
        ]
        sendJSON(message)
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task {
            while !Task.isCancelled, !self.isDestroyed {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard !Task.isCancelled, !self.isDestroyed else { return }
                self.sendHeartbeat()
            }
        }
    }

    private func sendHeartbeat() {
        let message: [String: Any] = [
            "topic": "phoenix",
            "event": "heartbeat",
            "payload": [:] as [String: Any],
            "ref": nextRefString(),
        ]
        sendJSON(message)
    }

    private func sendJSON(_ object: [String: Any]) {
        guard let webSocketTask else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else { return }
        webSocketTask.send(.string(text)) { _ in }
    }

    private func nextRefString() -> String {
        defer { nextRef += 1 }
        return String(nextRef)
    }

    private func listen(on task: URLSessionWebSocketTask) async {
        while !Task.isCancelled, !isDestroyed {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                guard !Task.isCancelled, !isDestroyed else { return }
                isJoined = false
                scheduleReconnect(after: 2)
                return
            }
        }
    }

    private func scheduleReconnect(after seconds: TimeInterval) {
        guard !isDestroyed else { return }
        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, !self.isDestroyed else { return }
            await self.openSocket()
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else { return }

        let topic: String?
        let event: String?
        let payload: [String: Any]?

        if let dict = json as? [String: Any] {
            topic = dict["topic"] as? String
            event = dict["event"] as? String
            payload = dict["payload"] as? [String: Any]
        } else if let array = json as? [Any], array.count >= 5 {
            topic = array[2] as? String
            event = array[3] as? String
            payload = array[4] as? [String: Any]
        } else {
            return
        }

        if event == "phx_reply",
           let payload,
           payload["status"] as? String == "ok" {
            isJoined = true
            return
        }

        guard event == "postgres_changes",
              topic == channelTopic,
              let payload,
              let change = payload["data"] as? [String: Any]
        else { return }

        switch change["type"] as? String {
        case "INSERT":
            guard let record = change["record"] as? [String: Any],
                  let id = record["id"] as? String
            else { return }
            let insert = PostRealtimeInsert(
                id: id,
                countryCode: record["country_code"] as? String,
                authorID: record["author_id"] as? String
            )
            NotificationCenter.default.post(
                name: .postRealtimeInsert,
                object: nil,
                userInfo: ["event": insert]
            )
        case "DELETE":
            guard let record = change["old_record"] as? [String: Any],
                  let id = record["id"] as? String
            else { return }
            let deleted = PostRealtimeDelete(
                id: id,
                countryCode: record["country_code"] as? String,
                authorID: record["author_id"] as? String
            )
            NotificationCenter.default.post(
                name: .postRealtimeDelete,
                object: nil,
                userInfo: ["event": deleted]
            )
        default:
            break
        }
    }
}