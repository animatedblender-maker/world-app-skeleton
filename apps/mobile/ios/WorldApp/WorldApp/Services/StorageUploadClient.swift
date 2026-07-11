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
    case compressing
    case uploading
    case publishing
}

final class StorageUploadClient: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, @unchecked Sendable {
    static let shared = StorageUploadClient()

    private let lock = NSLock()
    private var handlers: [Int: UploadHandler] = [:]
    private var progressObservations: [Int: NSKeyValueObservation] = [:]

    private struct UploadHandler {
        let continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>
        var receivedData: Data
        let onProgress: (@Sendable (UploadProgress) -> Void)?
        let expectedFileSize: Int64
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
        let expectedFileSize = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.uploadTask(with: request, fromFile: fileURL)

            lock.lock()
            handlers[task.taskIdentifier] = UploadHandler(
                continuation: continuation,
                receivedData: Data(),
                onProgress: onProgress,
                expectedFileSize: expectedFileSize
            )
            lock.unlock()

            if let onProgress {
                emitProgress(
                    fractionCompleted: 0,
                    bytesSent: 0,
                    totalBytes: expectedFileSize,
                    handler: onProgress
                )

                let observation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
                    guard let self else { return }
                    let total = expectedFileSize > 0
                        ? expectedFileSize
                        : max(progress.totalUnitCount, 1)
                    let sent = expectedFileSize > 0
                        ? Int64(Double(expectedFileSize) * progress.fractionCompleted)
                        : progress.completedUnitCount
                    self.lock.lock()
                    let handler = self.handlers[task.taskIdentifier]?.onProgress
                    self.lock.unlock()
                    guard let handler else { return }
                    self.emitProgress(
                        fractionCompleted: min(1, max(0, progress.fractionCompleted)),
                        bytesSent: sent,
                        totalBytes: total,
                        handler: handler
                    )
                }

                lock.lock()
                progressObservations[task.taskIdentifier] = observation
                lock.unlock()
            }

            task.resume()
        }
    }

    nonisolated private func emitProgress(
        fractionCompleted: Double,
        bytesSent: Int64,
        totalBytes: Int64,
        handler: @Sendable (UploadProgress) -> Void
    ) {
        let progress = UploadProgress(
            fractionCompleted: fractionCompleted,
            bytesSent: bytesSent,
            totalBytes: max(totalBytes, bytesSent, 1)
        )
        handler(progress)
    }

    nonisolated private func cleanup(taskID: Int) {
        lock.lock()
        progressObservations.removeValue(forKey: taskID)
        lock.unlock()
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        lock.lock()
        let handler = handlers[task.taskIdentifier]
        lock.unlock()
        guard let onProgress = handler?.onProgress else { return }

        let expected = handler?.expectedFileSize ?? 0
        let total = totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : (expected > 0 ? expected : 1)
        let fraction = min(1, Double(totalBytesSent) / Double(total))
        emitProgress(
            fractionCompleted: fraction,
            bytesSent: totalBytesSent,
            totalBytes: total,
            handler: onProgress
        )
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
        cleanup(taskID: task.taskIdentifier)

        lock.lock()
        guard let handler = handlers.removeValue(forKey: task.taskIdentifier) else {
            lock.unlock()
            return
        }
        let responseData = handler.receivedData
        let continuation = handler.continuation
        let onProgress = handler.onProgress
        let expectedFileSize = handler.expectedFileSize
        lock.unlock()

        if let onProgress {
            if error == nil {
                emitProgress(
                    fractionCompleted: 1,
                    bytesSent: expectedFileSize > 0 ? expectedFileSize : 1,
                    totalBytes: expectedFileSize > 0 ? expectedFileSize : 1,
                    handler: onProgress
                )
            }
        }

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