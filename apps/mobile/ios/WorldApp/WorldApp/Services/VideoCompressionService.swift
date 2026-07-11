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

    func prepareVideoForUpload(sourceURL: URL) async throws -> URL {
        let sourceSize = fileSize(at: sourceURL)
        let ext = sourceURL.pathExtension.lowercased()
        if sourceSize > 0,
           sourceSize <= Self.skipCompressionBelowBytes,
           ext == "mp4" || ext == "m4v" {
            return sourceURL
        }

        let presets = [
            AVAssetExportPreset1280x720,
            AVAssetExportPreset960x540,
            AVAssetExportPresetMediumQuality,
        ]

        var lastError = "Video compression failed."
        for preset in presets {
            do {
                let outputURL = try await export(assetURL: sourceURL, presetName: preset)
                let outputSize = fileSize(at: outputURL)
                if outputSize <= Self.maxUploadBytes {
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

    private func export(assetURL: URL, presetName: String) async throws -> URL {
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

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
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