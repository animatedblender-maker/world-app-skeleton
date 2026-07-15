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
/// Runs off the main thread so launch and UI stay responsive on device builds.
final class PostEventsService: @unchecked Sendable {
    static let shared = PostEventsService()

    private let worker = PostEventsWorker()

    private init() {}

    func start() {
        guard !AppConfig.useDemoDataset else { return }
        Task { await worker.start() }
    }

    func stop() {
        Task { await worker.stop() }
    }
}

private actor PostEventsWorker {
    private var webSocketTask: URLSessionWebSocketTask?
    private var listenTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var tokenRefreshObserver: NSObjectProtocol?
    private var isDestroyed = false
    private var isJoined = false
    private var nextRef = 1
    private var isConnecting = false
    private let channelTopic = "realtime:public:posts"
    private let joinRef = "1"

    func start() {
        isDestroyed = false
        installTokenRefreshObserverIfNeeded()
        scheduleConnect(delay: 0)
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
        isConnecting = false
    }

    private func installTokenRefreshObserverIfNeeded() {
        guard tokenRefreshObserver == nil else { return }
        tokenRefreshObserver = NotificationCenter.default.addObserver(
            forName: .authTokenDidRefresh,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.handleTokenRefresh() }
        }
    }

    private func handleTokenRefresh() async {
        guard !isDestroyed, isJoined else { return }
        await reconnectWithFreshToken()
    }

    private func reconnectWithFreshToken() async {
        guard !isDestroyed else { return }
        heartbeatTask?.cancel()
        listenTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isJoined = false
        isConnecting = false
        reconnectTask?.cancel()
        scheduleConnect(delay: 0.5)
    }

    private func scheduleConnect(delay: TimeInterval) {
        guard !isDestroyed else { return }
        reconnectTask?.cancel()
        reconnectTask = Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, !self.isDestroyed else { return }
            await self.openSocket()
        }
    }

    private func openSocket() async {
        guard !isDestroyed else { return }
        guard !isConnecting else { return }
        guard await MainActor.run(body: { AuthService.shared.isAuthenticated }) else { return }

        isConnecting = true
        defer { isConnecting = false }

        let accessToken: String
        do {
            accessToken = try await fetchAccessToken()
        } catch {
            scheduleConnect(delay: 5)
            return
        }

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

    private func fetchAccessToken() async throws -> String {
        try await Task { @MainActor in
            try await AuthService.shared.ensureValidToken()
        }.value
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
                guard !Task.isCancelled else { return }
                await self?.sendHeartbeat(on: task)
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
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else { return }
        task.send(.string(text)) { _ in }
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
                    await handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                guard !Task.isCancelled, !isDestroyed else { return }
                isJoined = false
                scheduleConnect(delay: 3)
                return
            }
        }
    }

    private func handleMessage(_ text: String) async {
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
            await postInsert(insert)
        case "DELETE":
            guard let record = change["old_record"] as? [String: Any],
                  let id = record["id"] as? String
            else { return }
            let deleted = PostRealtimeDelete(
                id: id,
                countryCode: record["country_code"] as? String,
                authorID: record["author_id"] as? String
            )
            await postDelete(deleted)
        default:
            break
        }
    }

    private func postInsert(_ event: PostRealtimeInsert) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .postRealtimeInsert,
                object: nil,
                userInfo: [
                    "id": event.id,
                    "countryCode": event.countryCode as Any,
                    "authorID": event.authorID as Any,
                ]
            )
        }
    }

    private func postDelete(_ event: PostRealtimeDelete) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .postRealtimeDelete,
                object: nil,
                userInfo: [
                    "id": event.id,
                    "countryCode": event.countryCode as Any,
                    "authorID": event.authorID as Any,
                ]
            )
        }
    }
}