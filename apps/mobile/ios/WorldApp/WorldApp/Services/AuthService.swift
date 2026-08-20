import Foundation

struct AuthSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case expiresAt
        case user
    }
}

enum AuthError: LocalizedError {
    case invalidCredentials
    case sessionExpired
    case emailAlreadyRegistered
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Invalid email or password."
        case .sessionExpired: "Your session has expired. Please log in again."
        case .emailAlreadyRegistered: "This email is already registered."
        case .network(let message): message
        case .server(let message): message
        }
    }
}

@MainActor
final class AuthService {
    static let shared = AuthService()

    private let sessionKey = "worldapp.auth.session"
    private(set) var session: AuthSession?
    private var refreshTask: Task<String, Error>?

    private init() {
        session = loadSession()
    }

    var isAuthenticated: Bool { session != nil }
    var currentUser: AuthUser? { session?.user }

    /// Returns the cached access token without refreshing. Prefer `ensureValidToken()` for API calls.
    func accessToken() -> String? {
        session?.accessToken
    }

    /// Returns a valid access token, refreshing via Supabase when expiry is within 60 seconds.
    func ensureValidToken() async throws -> String {
        guard let session else { throw AuthError.invalidCredentials }

        let refreshThreshold = Date().timeIntervalSince1970 + 60
        if session.expiresAt >= refreshThreshold {
            return session.accessToken
        }

        // Coalesce concurrent refreshes. Call `refreshAccessToken` directly on this
        // MainActor context when we own the refresh — wrapping in another `@MainActor`
        // Task and awaiting it from MainActor can stall under load (avatar upload freeze).
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task<String, Error> { @MainActor in
            defer { self.refreshTask = nil }
            // Re-check after winning the race.
            if let s = self.session, s.expiresAt >= Date().timeIntervalSince1970 + 60 {
                return s.accessToken
            }
            return try await self.refreshAccessToken()
        }
        refreshTask = task
        // Yield so the refresh Task can start immediately on MainActor.
        await Task.yield()
        return try await task.value
    }

    private func refreshAccessToken() async throws -> String {
        guard let session else { throw AuthError.invalidCredentials }

        let payload: [String: Any] = ["refresh_token": session.refreshToken]
        do {
            let response = try await postAuth(path: "token?grant_type=refresh_token", body: payload)
            try applyAuthResponse(response)
            NotificationCenter.default.post(name: .authTokenDidRefresh, object: nil)
            guard let refreshed = self.session?.accessToken else {
                // Response parsed but token missing — treat as expired.
                logout()
                throw AuthError.sessionExpired
            }
            return refreshed
        } catch let error as AuthError {
            // Only wipe the session when Supabase says the refresh token is dead.
            // Network blips / API DB outages must NOT log the user out.
            if case .invalidCredentials = error {
                logout()
                throw AuthError.sessionExpired
            }
            if case .server(let message) = error, Self.isDefinitiveAuthRejection(message) {
                logout()
                throw AuthError.sessionExpired
            }
            throw error
        } catch {
            // Transport / decode failures — keep disk session so retry can succeed.
            throw AuthError.network(error.localizedDescription)
        }
    }

    /// True when the auth server explicitly rejected the refresh/access token.
    private static func isDefinitiveAuthRejection(_ message: String) -> Bool {
        let m = message.lowercased()
        return m.contains("invalid refresh")
            || m.contains("refresh_token_not_found")
            || m.contains("invalid claim")
            || m.contains("session not found")
            || m.contains("user not found")
            || m.contains("token is expired")
            || m.contains("jwt expired")
            || m.contains("invalid jwt")
    }

    func login(email: String, password: String) async throws {
        if case .failure(let failure) = PasswordPolicy.validatePresent(password) {
            throw AuthError.server(failure.errorDescription ?? "Password cannot be empty.")
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            throw AuthError.server("Email is required. Enter your email address.")
        }
        let payload: [String: Any] = ["email": trimmedEmail, "password": password]
        let response = try await postAuth(path: "token?grant_type=password", body: payload)
        try applyAuthResponse(response)
    }

    /// Matterya-owned signup: API creates an unconfirmed user and emails a branded
    /// confirmation link to `https://matterya.com/confirm-email?token=…`.
    func register(email: String, password: String) async throws -> (needsEmailConfirm: Bool, isExistingEmail: Bool) {
        if case .failure(let failure) = PasswordPolicy.validateStrong(password) {
            throw AuthError.server(failure.errorDescription ?? PasswordPolicy.requirementsHint)
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            throw AuthError.server("Email is required. Enter your email address.")
        }
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/auth/signup") else {
            throw AuthError.network("Invalid signup URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": trimmedEmail,
            "password": password,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.network("No HTTP response.")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        if http.statusCode >= 400 {
            if json["isExistingEmail"] as? Bool == true
                || (json["error"] as? String) == "EMAIL_EXISTS" {
                return (false, true)
            }
            let message = json["message"] as? String
                ?? json["error"] as? String
                ?? "Signup failed (HTTP \(http.statusCode))."
            if message.range(of: "already|registered|exists", options: .regularExpression) != nil {
                return (false, true)
            }
            throw AuthError.server(message)
        }

        // Successful Matterya signup always requires opening the confirmation email.
        return (true, false)
    }

    func resendConfirmation(email: String) async throws -> String {
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/auth/resend-confirmation") else {
            throw AuthError.network("Invalid resend URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.network("No HTTP response.")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if http.statusCode >= 400 {
            throw AuthError.server(
                json["message"] as? String ?? "Could not resend confirmation email."
            )
        }
        return json["message"] as? String
            ?? "If that email needs confirmation, we sent a new Matterya link."
    }

    func logout() {
        session = nil
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    private func applyAuthResponse(_ response: [String: Any]) throws {
        guard
            let accessToken = response["access_token"] as? String,
            let refreshToken = response["refresh_token"] as? String,
            let userDict = response["user"] as? [String: Any],
            let userID = userDict["id"] as? String
        else {
            throw AuthError.invalidCredentials
        }

        let expiresIn: TimeInterval
        if let value = response["expires_in"] as? TimeInterval {
            expiresIn = value
        } else if let value = response["expires_in"] as? Int {
            expiresIn = TimeInterval(value)
        } else {
            expiresIn = 3600
        }

        let user = AuthUser(id: userID, email: userDict["email"] as? String)
        let session = AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().timeIntervalSince1970 + expiresIn,
            user: user
        )
        self.session = session
        saveSession(session)
    }

    private func postAuth(path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: "\(AppConfig.supabaseURL)/auth/v1/\(path)") else {
            throw AuthError.network("Invalid auth URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.network("No HTTP response.")
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if http.statusCode >= 400 {
            let message = json["error_description"] as? String
                ?? json["msg"] as? String
                ?? json["error"] as? String
                ?? "Auth failed (HTTP \(http.statusCode))."
            // 401/403 on refresh/login = credentials/session rejected.
            if http.statusCode == 401 || http.statusCode == 403 {
                throw AuthError.invalidCredentials
            }
            throw AuthError.server(message)
        }
        return json
    }

    private func saveSession(_ session: AuthSession) {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }

    private func loadSession() -> AuthSession? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }
}