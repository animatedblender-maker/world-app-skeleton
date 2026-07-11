import AVFoundation
import Foundation

enum VideoCompressionError: LocalizedError {
    case exportFailed(String)
    case tooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .exportFailed(let message):
            return message
        case .tooLarge(let bytes):
            let megabytes = Double(bytes) / (1024 * 1024)
            return String(
                format: "Video is still %.0f MB after compression. Try a shorter clip.",
                megabytes
            )
        }
    }
}

final class VideoCompressionService {
    static let shared = VideoCompressionService()

    static let maxUploadBytes = 48 * 1024 * 1024
    private static let skipCompressionBelowBytes = 24 * 1024 * 1024

    private init() {}

    func prepareVideoForUpload(
        sourceURL: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let sourceSize = fileSize(at: sourceURL)
        let ext = sourceURL.pathExtension.lowercased()
        if sourceSize > 0,
           sourceSize <= Self.skipCompressionBelowBytes,
           ext == "mp4" || ext == "m4v" {
            onProgress?(1)
            return sourceURL
        }

        let presets = [
            AVAssetExportPreset1280x720,
            AVAssetExportPreset960x540,
            AVAssetExportPresetMediumQuality,
        ]

        onProgress?(0)

        var lastError = "Video compression failed."
        let presetCount = Double(presets.count)
        for (index, preset) in presets.enumerated() {
            let baseProgress = Double(index) / presetCount
            let slice = 1 / presetCount
            do {
                let outputURL = try await export(
                    assetURL: sourceURL,
                    presetName: preset,
                    onProgress: { sessionProgress in
                        let overall = baseProgress + (Double(sessionProgress) * slice)
                        onProgress?(min(1, overall))
                    }
                )
                let outputSize = fileSize(at: outputURL)
                if outputSize <= Self.maxUploadBytes {
                    onProgress?(1)
                    return outputURL
                }
                try? FileManager.default.removeItem(at: outputURL)
                lastError = VideoCompressionError.tooLarge(outputSize).localizedDescription
            } catch {
                lastError = error.localizedDescription
            }
        }

        throw VideoCompressionError.exportFailed(lastError)
    }

    private func export(
        assetURL: URL,
        presetName: String,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let asset = AVURLAsset(url: assetURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw VideoCompressionError.exportFailed("Could not prepare this video.")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).mp4")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        let progressTask: Task<Void, Never>? = onProgress.map { handler in
            Task { @MainActor in
                handler(0)
                while !Task.isCancelled {
                    handler(Double(session.progress))
                    switch session.status {
                    case .completed, .failed, .cancelled:
                        return
                    default:
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                progressTask?.cancel()
                switch session.status {
                case .completed:
                    if let onProgress {
                        Task { @MainActor in onProgress(1) }
                    }
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: VideoCompressionError.exportFailed("Video compression was cancelled."))
                case .failed:
                    let message = session.error?.localizedDescription ?? "Video compression failed."
                    continuation.resume(throwing: VideoCompressionError.exportFailed(message))
                default:
                    continuation.resume(throwing: VideoCompressionError.exportFailed("Video compression did not finish."))
                }
            }
        }

        return outputURL
    }

    private func fileSize(at url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    static func formattedSize(_ bytes: Int) -> String {
        guard bytes > 0 else { return "0 MB" }
        let megabytes = Double(bytes) / (1024 * 1024)
        if megabytes >= 1 {
            return String(format: "%.1f MB", megabytes)
        }
        let kilobytes = Double(bytes) / 1024
        return String(format: "%.0f KB", kilobytes)
    }
}