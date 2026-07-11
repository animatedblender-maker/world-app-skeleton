import Foundation

struct UploadProgress: Sendable, Equatable {
    let fractionCompleted: Double
    let bytesSent: Int64
    let totalBytes: Int64

    var percentText: String {
        "\(Int((fractionCompleted * 100).rounded()))%"
    }

    var bytesText: String {
        "\(Self.formattedBytes(bytesSent)) / \(Self.formattedBytes(totalBytes))"
    }

    static func formattedBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 MB" }
        let megabytes = Double(bytes) / (1024 * 1024)
        if megabytes >= 1 {
            return String(format: "%.1f MB", megabytes)
        }
        let kilobytes = Double(bytes) / 1024
        return String(format: "%.0f KB", kilobytes)
    }
}

enum MediaUploadPhase: Equatable {
    case idle
    case uploading
    case publishing
}

final class StorageUploadClient: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = StorageUploadClient()

    private let lock = NSLock()
    private var handlers: [Int: UploadHandler] = [:]

    private struct UploadHandler {
        let continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>
        var receivedData: Data
        let onProgress: (@Sendable (UploadProgress) -> Void)?
    }

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60 * 20
        configuration.timeoutIntervalForResource = 60 * 30
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private override init() {
        super.init()
    }

    func upload(
        request: URLRequest,
        fileURL: URL,
        onProgress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.uploadTask(with: request, fromFile: fileURL)
            lock.lock()
            handlers[task.taskIdentifier] = UploadHandler(
                continuation: continuation,
                receivedData: Data(),
                onProgress: onProgress
            )
            lock.unlock()
            task.resume()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress = UploadProgress(
            fractionCompleted: min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)),
            bytesSent: totalBytesSent,
            totalBytes: totalBytesExpectedToSend
        )
        lock.lock()
        let handler = handlers[task.taskIdentifier]
        lock.unlock()
        handler?.onProgress?(progress)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        if var handler = handlers[dataTask.taskIdentifier] {
            handler.receivedData.append(data)
            handlers[dataTask.taskIdentifier] = handler
        }
        lock.unlock()
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        guard let handler = handlers.removeValue(forKey: task.taskIdentifier) else {
            lock.unlock()
            return
        }
        let responseData = handler.receivedData
        let continuation = handler.continuation
        lock.unlock()

        if let error {
            if let urlError = error as? URLError, urlError.code == .timedOut {
                continuation.resume(throwing: MediaError.uploadFailed("Upload timed out. Try a shorter video or stronger Wi‑Fi."))
            } else {
                continuation.resume(throwing: MediaError.uploadFailed(error.localizedDescription))
            }
            return
        }

        guard let http = task.response as? HTTPURLResponse else {
            continuation.resume(throwing: MediaError.uploadFailed("Missing upload response."))
            return
        }

        continuation.resume(returning: (responseData, http))
    }
}