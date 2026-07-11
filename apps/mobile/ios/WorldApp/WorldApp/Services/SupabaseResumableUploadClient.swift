import Foundation

/// Supabase Storage TUS resumable uploads for large video files.
/// https://supabase.com/docs/guides/storage/uploads/resumable-uploads
final class SupabaseResumableUploadClient: @unchecked Sendable {
    static let shared = SupabaseResumableUploadClient()

    private static let chunkSize = 6 * 1024 * 1024
    private static let tusVersion = "1.0.0"

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60 * 20
        configuration.timeoutIntervalForResource = 60 * 30
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    private init() {}

    func upload(
        bucket: String,
        path: String,
        fileURL: URL,
        mimeType: String,
        accessToken: String,
        onProgress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws {
        let fileSize = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard fileSize > 0 else {
            throw MediaError.uploadFailed("Video file is empty.")
        }

        let uploadURL = try await createUploadSession(
            bucket: bucket,
            path: path,
            fileSize: fileSize,
            mimeType: mimeType,
            accessToken: accessToken
        )

        try await uploadChunks(
            uploadURL: uploadURL,
            fileURL: fileURL,
            fileSize: fileSize,
            accessToken: accessToken,
            onProgress: onProgress
        )
    }

    private func createUploadSession(
        bucket: String,
        path: String,
        fileSize: Int64,
        mimeType: String,
        accessToken: String
    ) async throws -> URL {
        guard let endpoint = URL(string: "\(AppConfig.supabaseStorageURL)/storage/v1/upload/resumable") else {
            throw MediaError.uploadFailed("Invalid Supabase upload URL.")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(Self.tusVersion, forHTTPHeaderField: "Tus-Resumable")
        request.setValue("\(fileSize)", forHTTPHeaderField: "Upload-Length")
        request.setValue(
            tusMetadata([
                ("bucketName", bucket),
                ("objectName", path),
                ("contentType", mimeType),
                ("cacheControl", "3600"),
            ]),
            forHTTPHeaderField: "Upload-Metadata"
        )
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MediaError.uploadFailed("Missing upload response.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw MediaError.uploadFailed(storageErrorMessage(from: responseData, statusCode: http.statusCode))
        }
        guard let location = http.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: location)
        else {
            throw MediaError.uploadFailed("Supabase did not return an upload location.")
        }
        return uploadURL
    }

    private func uploadChunks(
        uploadURL: URL,
        fileURL: URL,
        fileSize: Int64,
        accessToken: String,
        onProgress: (@Sendable (UploadProgress) -> Void)?
    ) async throws {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        var offset: Int64 = 0
        emitProgress(bytesSent: 0, totalBytes: fileSize, handler: onProgress)

        while offset < fileSize {
            let remaining = fileSize - offset
            let chunkLength = Int(min(Int64(Self.chunkSize), remaining))
            let chunkData = fileHandle.readData(ofLength: chunkLength)
            guard chunkData.count == chunkLength else {
                throw MediaError.uploadFailed("Could not read video file for upload.")
            }

            var request = URLRequest(url: uploadURL)
            request.httpMethod = "PATCH"
            request.setValue(Self.tusVersion, forHTTPHeaderField: "Tus-Resumable")
            request.setValue("\(offset)", forHTTPHeaderField: "Upload-Offset")
            request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")

            let (responseData, response) = try await session.upload(for: request, from: chunkData)
            guard let http = response as? HTTPURLResponse else {
                throw MediaError.uploadFailed("Missing chunk upload response.")
            }
            guard (200...299).contains(http.statusCode) else {
                throw MediaError.uploadFailed(storageErrorMessage(from: responseData, statusCode: http.statusCode))
            }

            if let newOffset = http.value(forHTTPHeaderField: "Upload-Offset"),
               let parsed = Int64(newOffset) {
                offset = parsed
            } else {
                offset += Int64(chunkLength)
            }

            emitProgress(bytesSent: offset, totalBytes: fileSize, handler: onProgress)
        }

        emitProgress(bytesSent: fileSize, totalBytes: fileSize, handler: onProgress)
    }

    private func tusMetadata(_ pairs: [(String, String)]) -> String {
        pairs.map { key, value in
            let encoded = Data(value.utf8).base64EncodedString()
            return "\(key) \(encoded)"
        }.joined(separator: ",")
    }

    private func emitProgress(
        bytesSent: Int64,
        totalBytes: Int64,
        handler: (@Sendable (UploadProgress) -> Void)?
    ) {
        guard let handler else { return }
        let total = max(totalBytes, 1)
        let fraction = min(1, Double(bytesSent) / Double(total))
        handler(
            UploadProgress(
                fractionCompleted: fraction,
                bytesSent: bytesSent,
                totalBytes: total
            )
        )
    }

    private func storageErrorMessage(from data: Data, statusCode: Int) -> String {
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
        return "Supabase upload failed (HTTP \(statusCode))."
    }
}