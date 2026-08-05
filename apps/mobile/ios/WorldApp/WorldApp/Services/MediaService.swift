import Foundation
import UIKit

enum MediaError: LocalizedError {
    case notAuthenticated
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "Not authenticated."
        case .uploadFailed(let msg): msg
        }
    }
}

@MainActor
final class MediaService {
    static let shared = MediaService()

    private let uploadSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60 * 20
        configuration.timeoutIntervalForResource = 60 * 30
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    private init() {}

    func uploadAdMedia(data: Data, fileExtension: String, mimeType: String) async throws -> (path: String, publicURL: String) {
        guard mimeType.hasPrefix("video/") else {
            throw MediaError.uploadFailed("Ad creative must be a video file.")
        }
        let ext = fileExtension.lowercased().isEmpty ? "mp4" : fileExtension.lowercased()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ad-upload-\(UUID().uuidString).\(ext)")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        return try await uploadAdMedia(fileURL: tempURL, fileExtension: ext, mimeType: mimeType)
    }

    func uploadAdMedia(
        fileURL: URL,
        fileExtension: String,
        mimeType: String,
        onProgress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> (path: String, publicURL: String) {
        guard mimeType.hasPrefix("video/") else {
            throw MediaError.uploadFailed("Ad creative must be a video file.")
        }
        guard let userID = AuthService.shared.currentUser?.id else { throw MediaError.notAuthenticated }
        let ext = fileExtension.lowercased().isEmpty ? "mp4" : fileExtension.lowercased()
        let path = "\(userID)/ads/\(UUID().uuidString).\(ext)"
        try await upload(
            bucket: "posts",
            path: path,
            fileURL: fileURL,
            mimeType: mimeType,
            onProgress: onProgress
        )
        let publicURL = "\(AppConfig.supabaseURL)/storage/v1/object/public/posts/\(path)"
        return (path, publicURL)
    }

    func uploadPostMedia(data: Data, fileExtension: String, mimeType: String) async throws -> (path: String, publicURL: String) {
        guard let userID = AuthService.shared.currentUser?.id else { throw MediaError.notAuthenticated }
        let path = "\(userID)/\(UUID().uuidString).\(fileExtension)"
        try await upload(bucket: "posts", path: path, data: data, mimeType: mimeType)
        let publicURL = "\(AppConfig.supabaseURL)/storage/v1/object/public/posts/\(path)"
        return (path, publicURL)
    }

    func uploadPostMedia(
        fileURL: URL,
        fileExtension: String,
        mimeType: String,
        onProgress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> (path: String, publicURL: String) {
        guard let userID = AuthService.shared.currentUser?.id else { throw MediaError.notAuthenticated }
        let path = "\(userID)/\(UUID().uuidString).\(fileExtension)"
        try await uploadVideoToPosts(
            path: path,
            fileURL: fileURL,
            mimeType: mimeType,
            onProgress: onProgress
        )
        let publicURL = "\(AppConfig.supabaseURL)/storage/v1/object/public/posts/\(path)"
        return (path, publicURL)
    }

    func uploadAvatar(data: Data, fileExtension: String, mimeType: String) async throws -> (path: String, url: String) {
        guard let userID = AuthService.shared.currentUser?.id else { throw MediaError.notAuthenticated }
        if mimeType == "image/gif" { throw MediaError.uploadFailed("GIF avatars are disabled.") }
        let path = "\(userID)/\(UUID().uuidString).\(fileExtension)"
        try await upload(bucket: "avatars", path: path, data: data, mimeType: mimeType, upsert: true)
        return (path, Self.publicAvatarURL(for: path))
    }

    nonisolated static func normalizedAvatarURL(_ url: String?) -> String? {
        guard let raw = url?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("data:") || raw.hasPrefix("blob:") { return raw }

        let objectPrefix = "\(AppConfig.supabaseURL)/storage/v1/object/"
        let signMarker = "\(objectPrefix)sign/avatars/"
        if let range = raw.range(of: signMarker) {
            let path = String(raw[range.upperBound...]).split(separator: "?").first.map(String.init) ?? ""
            let decoded = path.removingPercentEncoding ?? path
            return publicAvatarURL(for: decoded)
        }

        let publicMarker = "\(objectPrefix)public/avatars/"
        if raw.hasPrefix(publicMarker) {
            return String(raw.split(separator: "?").first ?? Substring(raw))
        }

        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return String(raw.split(separator: "?").first ?? Substring(raw))
        }

        return publicAvatarURL(for: raw.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    nonisolated private static func publicAvatarURL(for path: String) -> String {
        let cleaned = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(AppConfig.supabaseURL)/storage/v1/object/public/avatars/\(cleaned)"
    }

    private var signedMessageURLCache: [String: (url: String, expiresAt: Date)] = [:]

    func signedMessageURL(path: String) async throws -> String {
        if let cached = signedMessageURLCache[path], cached.expiresAt > Date() {
            return cached.url
        }
        let url = try await createSignedURL(bucket: "messages", path: path)
        signedMessageURLCache[path] = (url, Date().addingTimeInterval(55 * 60))
        return url
    }

    func uploadMessageMedia(data: Data, conversationID: String, fileName: String, mimeType: String) async throws -> (path: String, name: String, mime: String, size: Int) {
        guard let userID = AuthService.shared.currentUser?.id else { throw MediaError.notAuthenticated }
        let ext = (fileName as NSString).pathExtension.lowercased()
        let safeExt = ext.isEmpty ? "bin" : ext
        let path = "\(userID)/\(conversationID)/\(UUID().uuidString).\(safeExt)"
        try await upload(bucket: "messages", path: path, data: data, mimeType: mimeType)
        return (path, fileName, mimeType, data.count)
    }

    private func upload(bucket: String, path: String, data: Data, mimeType: String, upsert: Bool = false) async throws {
        try await performUpload(
            bucket: bucket,
            path: path,
            mimeType: mimeType,
            upsert: upsert
        ) { request in
            let (responseData, response) = try await uploadSession.upload(for: request, from: data)
            return (responseData, response)
        }
    }

    private func uploadVideoToPosts(
        path: String,
        fileURL: URL,
        mimeType: String,
        onProgress: (@Sendable (UploadProgress) -> Void)?
    ) async throws {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                try await uploadDirect(
                    bucket: "posts",
                    path: path,
                    fileURL: fileURL,
                    mimeType: mimeType,
                    upsert: false,
                    onProgress: onProgress
                )
                return
            } catch {
                lastError = error
                if attempt == 0 {
                    _ = try? await AuthService.shared.ensureValidToken()
                }
            }
        }
        throw lastError ?? MediaError.uploadFailed("Upload failed.")
    }

    private func upload(
        bucket: String,
        path: String,
        fileURL: URL,
        mimeType: String,
        upsert: Bool = false,
        onProgress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws {
        try await uploadDirect(
            bucket: bucket,
            path: path,
            fileURL: fileURL,
            mimeType: mimeType,
            upsert: upsert,
            onProgress: onProgress
        )
    }

    private func uploadDirect(
        bucket: String,
        path: String,
        fileURL: URL,
        mimeType: String,
        upsert: Bool,
        onProgress: (@Sendable (UploadProgress) -> Void)?
    ) async throws {
        let request = try await makeUploadRequest(bucket: bucket, path: path, mimeType: mimeType, upsert: upsert)
        let (responseData, http) = try await StorageUploadClient.shared.upload(
            request: request,
            fileURL: fileURL,
            onProgress: onProgress
        )
        guard (200...299).contains(http.statusCode) else {
            throw MediaError.uploadFailed(Self.storageErrorMessage(from: responseData, statusCode: http.statusCode))
        }
    }

    private func performUpload(
        bucket: String,
        path: String,
        mimeType: String,
        upsert: Bool,
        send: (URLRequest) async throws -> (Data, URLResponse)
    ) async throws {
        let request = try await makeUploadRequest(bucket: bucket, path: path, mimeType: mimeType, upsert: upsert)
        do {
            let (responseData, response) = try await send(request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw MediaError.uploadFailed(Self.storageErrorMessage(from: responseData, statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0))
            }
        } catch let error as URLError where error.code == .timedOut {
            throw MediaError.uploadFailed("Upload timed out. Try a shorter video or stronger Wi‑Fi.")
        } catch let error as MediaError {
            throw error
        } catch {
            throw MediaError.uploadFailed(error.localizedDescription)
        }
    }

    private func makeUploadRequest(
        bucket: String,
        path: String,
        mimeType: String,
        upsert: Bool
    ) async throws -> URLRequest {
        let token: String
        do {
            token = try await AuthService.shared.ensureValidToken()
        } catch {
            throw MediaError.notAuthenticated
        }
        guard let url = Self.storageObjectURL(bucket: bucket, path: path) else {
            throw MediaError.uploadFailed("Invalid upload URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if upsert {
            request.setValue("true", forHTTPHeaderField: "x-upsert")
        }
        return request
    }

    private static func storageErrorMessage(from data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let message = json["message"] as? String, !message.isEmpty {
                return message
            }
            if let error = json["error"] as? String, !error.isEmpty {
                return error
            }
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        if statusCode == 413 {
            return "Video is too large for storage. Try a shorter clip."
        }
        if statusCode > 0 {
            return "Upload failed (HTTP \(statusCode))."
        }
        return "Upload failed."
    }

    private func createSignedURL(bucket: String, path: String) async throws -> String {
        let token: String
        do {
            token = try await AuthService.shared.ensureValidToken()
        } catch {
            throw MediaError.notAuthenticated
        }
        guard let url = Self.storageSignURL(bucket: bucket, path: path) else {
            throw MediaError.uploadFailed("Invalid sign URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["expiresIn": 3600])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let signed = json["signedURL"] as? String
        else {
            throw MediaError.uploadFailed("Failed to sign avatar URL.")
        }

        if signed.hasPrefix("http") { return signed }
        return "\(AppConfig.supabaseURL)/storage/v1\(signed)"
    }

    private static func encodedStoragePath(_ path: String) -> String {
        path
            .split(separator: "/")
            .map { segment in
                segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(segment)
            }
            .joined(separator: "/")
    }

    private static func storageObjectURL(bucket: String, path: String) -> URL? {
        let encodedPath = encodedStoragePath(path)
        return URL(string: "\(AppConfig.supabaseURL)/storage/v1/object/\(bucket)/\(encodedPath)")
    }

    private static func storageSignURL(bucket: String, path: String) -> URL? {
        let encodedPath = encodedStoragePath(path)
        return URL(string: "\(AppConfig.supabaseURL)/storage/v1/object/sign/\(bucket)/\(encodedPath)")
    }
}