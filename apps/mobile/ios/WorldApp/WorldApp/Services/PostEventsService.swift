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
final class PostEventsService: @unchecked Sendable {
    static let shared = PostEventsService()

    private var webSocketTask: URLSessionWebSocketTask?
    private var listenTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var tokenRefreshObserver: NSObjectProtocol?
    private var isDestroyed = true
    private var isJoined = false
    private var isConnecting = false
    private var nextRef = 1
    private let channelTopic = "realtime:public:posts"
    private let joinRef = "1"
    private let stateLock = NSLock()

    private init() {}

    func start() {
        guard !AppConfig.useDemoDataset else { return }
        stateLock.lock()
        isDestroyed = false
        stateLock.unlock()

        installTokenRefreshObserverIfNeeded()
        scheduleConnect(delay: 0.75)
    }

    func stop() {
        stateLock.lock()
        isDestroyed = true
        isJoined = false
        isConnecting = false
        stateLock.unlock()

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
    }

    private func installTokenRefreshObserverIfNeeded() {
        guard tokenRefreshObserver == nil else { return }
        tokenRefreshObserver = NotificationCenter.default.addObserver(
            forName: .authTokenDidRefresh,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.scheduleReconnect(delay: 0.75)
        }
    }

    private func scheduleConnect(delay: TimeInterval) {
        stateLock.lock()
        let destroyed = isDestroyed
        stateLock.unlock()
        guard !destroyed else { return }

        reconnectTask?.cancel()
        reconnectTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self.openSocket()
        }
    }

    private func scheduleReconnect(delay: TimeInterval) {
        stateLock.lock()
        let destroyed = isDestroyed
        let joined = isJoined
        stateLock.unlock()
        guard !destroyed, joined else { return }
        teardownSocket()
        scheduleConnect(delay: delay)
    }

    private func teardownSocket() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        listenTask?.cancel()
        listenTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        stateLock.lock()
        isJoined = false
        isConnecting = false
        stateLock.unlock()
    }

    private func openSocket() async {
        stateLock.lock()
        let destroyed = isDestroyed
        let connecting = isConnecting
        stateLock.unlock()
        guard !destroyed, !connecting else { return }

        let authenticated = await MainActor.run { AuthService.shared.isAuthenticated }
        guard authenticated else { return }

        stateLock.lock()
        isConnecting = true
        stateLock.unlock()
        defer {
            stateLock.lock()
            isConnecting = false
            stateLock.unlock()
        }

        let accessToken: String
        do {
            accessToken = try await Task { @MainActor in
                try await AuthService.shared.ensureValidToken()
            }.value
        } catch {
            scheduleConnect(delay: 5)
            return
        }

        stateLock.lock()
        let stillActive = !isDestroyed
        stateLock.unlock()
        guard stillActive else { return }

        var components = URLComponents(string: "\(AppConfig.supabaseURL)/realtime/v1/websocket")!
        components.queryItems = [
            URLQueryItem(name: "apikey", value: AppConfig.supabaseAnonKey),
            URLQueryItem(name: "vsn", value: "1.0.0"),
        ]
        guard let url = components.url else { return }

        let session = URLSession(configuration: Self.makeSessionConfiguration())
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        listenTask?.cancel()
        listenTask = Task.detached(priority: .utility) { [weak self] in
            await self?.listen(on: task)
        }

        sendJoin(accessToken: accessToken, on: task)
        startHeartbeat(on: task)
    }

    private static func makeSessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        config.waitsForConnectivity = false
        return config
    }

    private func sendJoin(accessToken: String, on task: URLSessionWebSocketTask) {
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
        sendJSON(message, on: task)
    }

    private func startHeartbeat(on task: URLSessionWebSocketTask) {
        heartbeatTask?.cancel()
        heartbeatTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.sendHeartbeat(on: task)
            }
        }
    }

    private func sendHeartbeat(on task: URLSessionWebSocketTask) {
        let message: [String: Any] = [
            "topic": "phoenix",
            "event": "heartbeat",
            "payload": [:] as [String: Any],
            "ref": nextRefString(),
        ]
        sendJSON(message, on: task)
    }

    private func sendJSON(_ object: [String: Any], on task: URLSessionWebSocketTask) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else { return }
        task.send(.string(text)) { _ in }
    }

    private func nextRefString() -> String {
        stateLock.lock()
        defer { stateLock.unlock() }
        defer { nextRef += 1 }
        return String(nextRef)
    }

    private func listen(on task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            stateLock.lock()
            let destroyed = isDestroyed
            stateLock.unlock()
            guard !destroyed else { return }

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
                guard !Task.isCancelled else { return }
                stateLock.lock()
                isJoined = false
                let destroyed = isDestroyed
                stateLock.unlock()
                guard !destroyed else { return }
                scheduleConnect(delay: 3)
                return
            }
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
            stateLock.lock()
            isJoined = true
            stateLock.unlock()
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
            postInsert(
                PostRealtimeInsert(
                    id: id,
                    countryCode: record["country_code"] as? String,
                    authorID: record["author_id"] as? String
                )
            )
        case "DELETE":
            guard let record = change["old_record"] as? [String: Any],
                  let id = record["id"] as? String
            else { return }
            postDelete(
                PostRealtimeDelete(
                    id: id,
                    countryCode: record["country_code"] as? String,
                    authorID: record["author_id"] as? String
                )
            )
        default:
            break
        }
    }

    private func postInsert(_ event: PostRealtimeInsert) {
        var userInfo: [AnyHashable: Any] = ["id": event.id]
        if let countryCode = event.countryCode { userInfo["countryCode"] = countryCode }
        if let authorID = event.authorID { userInfo["authorID"] = authorID }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .postRealtimeInsert, object: nil, userInfo: userInfo)
        }
    }

    private func postDelete(_ event: PostRealtimeDelete) {
        var userInfo: [AnyHashable: Any] = ["id": event.id]
        if let countryCode = event.countryCode { userInfo["countryCode"] = countryCode }
        if let authorID = event.authorID { userInfo["authorID"] = authorID }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .postRealtimeDelete, object: nil, userInfo: userInfo)
        }
    }
}