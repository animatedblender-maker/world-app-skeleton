import AVFoundation
import Foundation
import WhisperKit

/// Shared playhead clock so live CC always reads the *current* time (not a stale capture).
final class CaptionPlayheadClock: @unchecked Sendable {
    var seconds: Double = 0
    var duration: Double = 0
}

/// Live Hubs CC: transcribe just ahead of the playhead so captions appear within
/// seconds of tapping CC (no wait for the whole film).
@MainActor
final class LiveCaptionHandle {
    private let id = UUID()
    private var task: Task<Void, Never>?
    private(set) var postID: String

    init(postID: String) {
        self.postID = postID
    }

    fileprivate func attach(_ task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task?.cancel()
        task = nil
        LiveCaptionCoordinator.shared.clear(postID: postID, handleID: id)
    }

    fileprivate var handleID: UUID { id }
}

/// Coordinates one live session per post so feed/hubs don't double-run Whisper.
@MainActor
enum LiveCaptionCoordinator {
    static let shared = LiveCaptionStore()
}

@MainActor
final class LiveCaptionStore {
    private var active: [String: LiveCaptionHandle] = [:]

    func handle(for postID: String) -> LiveCaptionHandle? {
        active[postID]
    }

    func register(_ handle: LiveCaptionHandle) {
        active[handle.postID]?.cancel()
        active[handle.postID] = handle
    }

    func clear(postID: String, handleID: UUID) {
        if active[postID]?.handleID == handleID {
            active[postID] = nil
        }
    }
}

enum LiveCaptionEngine {
    /// Seconds of audio decoded per Whisper pass.
    private static let chunkSeconds: Double = 8
    /// Keep this far ahead of the playhead when possible.
    private static let leadSeconds: Double = 16
    private static let minChunkSeconds: Double = 1.2
    /// Overlap consecutive windows so phrases straddling chunk edges are not dropped.
    private static let overlapSeconds: Double = 1.6

    /// Start live captions. Calls `onUpdate` on the main actor as soon as each chunk lands.
    @MainActor
    @discardableResult
    static func start(
        postID: String,
        mediaURL: URL,
        playhead: @escaping @Sendable () -> Double,
        duration: @escaping @Sendable () -> Double,
        onUpdate: @escaping @MainActor (TranscriptService.Transcript) -> Void
    ) -> LiveCaptionHandle {
        let key = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        let handle = LiveCaptionHandle(postID: key)
        LiveCaptionCoordinator.shared.register(handle)

        // Instant paint from disk/memory if we already finished this film once.
        if let cached = TranscriptService.cached(key), cached.isReady {
            onUpdate(cached)
        }

        let task = Task.detached(priority: .userInitiated) {
            await runLoop(
                postID: key,
                mediaURL: mediaURL,
                playhead: playhead,
                duration: duration,
                onUpdate: onUpdate
            )
        }
        handle.attach(task)
        return handle
    }

    private static func runLoop(
        postID: String,
        mediaURL: URL,
        playhead: @escaping @Sendable () -> Double,
        duration: @escaping @Sendable () -> Double,
        onUpdate: @escaping @MainActor (TranscriptService.Transcript) -> Void
    ) async {
        do {
            try await WhisperKitEngine.shared.prepare()
        } catch {
            let failed = TranscriptService.Transcript(
                postID: postID,
                status: "failed",
                text: nil,
                segments: [],
                language: nil,
                error: error.localizedDescription
            )
            await MainActor.run { onUpdate(failed) }
            return
        }

        var segments: [TranscriptService.Segment] = TranscriptService.cached(postID)?.segments ?? []
        var language: String? = TranscriptService.cached(postID)?.language
        var cursor = max(0, playhead() - 0.35)

        // If cache already covers far ahead of playhead, skip work until needed.
        if let last = segments.map(\.end).max(), last > playhead() + leadSeconds {
            cursor = last
        }

        while !Task.isCancelled {
            let t = max(0, playhead())
            var filmEnd = duration()
            if filmEnd <= 0 { filmEnd = max(t + chunkSeconds * 4, cursor + chunkSeconds) }

            if cursor >= filmEnd - 0.25 {
                let ready = makeTranscript(postID: postID, segments: segments, language: language)
                TranscriptService.storeLiveResult(ready)
                await MainActor.run { onUpdate(ready) }
                break
            }

            // Stay a bit ahead of the viewer; don't race infinitely into the future.
            if cursor > t + leadSeconds {
                try? await Task.sleep(nanoseconds: 180_000_000)
                continue
            }

            let windowStart = cursor
            let windowEnd = min(filmEnd, windowStart + chunkSeconds)
            if windowEnd - windowStart < minChunkSeconds {
                try? await Task.sleep(nanoseconds: 150_000_000)
                continue
            }

            do {
                var samples = try await extractPCMWindow(
                    mediaURL: mediaURL,
                    start: windowStart,
                    end: windowEnd
                )
                // One retry on thin/failed decode — skipping the window was dropping phrases.
                if samples.count <= Int(WhisperKit.sampleRate) / 2 {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    samples = (try? await extractPCMWindow(
                        mediaURL: mediaURL,
                        start: windowStart,
                        end: windowEnd
                    )) ?? samples
                }
                if samples.count > Int(WhisperKit.sampleRate) / 2 {
                    let results = try await WhisperKitEngine.shared.transcribe(samples: samples)
                    for result in results {
                        language = language ?? result.language
                        for seg in result.segments {
                            let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { continue }
                            let start = windowStart + Double(seg.start)
                            let end = max(windowStart + Double(seg.end), start + 0.35)
                            segments.append(
                                TranscriptService.Segment(start: start, end: end, text: text)
                            )
                        }
                    }
                    segments = coalesce(segments)
                    let live = makeTranscript(
                        postID: postID,
                        segments: segments,
                        language: language,
                        status: windowEnd >= filmEnd - 0.5 ? "ready" : "processing"
                    )
                    TranscriptService.storeLiveResult(live)
                    await MainActor.run { onUpdate(live) }
                }
                // Keep overlap so edge phrases survive the next pass.
                cursor = max(windowStart + minChunkSeconds, windowEnd - overlapSeconds)
            } catch {
                #if DEBUG
                print("[LiveCaption] chunk \(windowStart)-\(windowEnd) fail: \(error)")
                #endif
                // Nudge forward only a little so we retry most of the failed window.
                cursor = windowStart + max(0.6, minChunkSeconds * 0.5)
                try? await Task.sleep(nanoseconds: 220_000_000)
            }
        }
    }

    private static func makeTranscript(
        postID: String,
        segments: [TranscriptService.Segment],
        language: String?,
        status: String = "ready"
    ) -> TranscriptService.Transcript {
        let text = segments.map(\.text).joined(separator: " ")
        return TranscriptService.Transcript(
            postID: postID,
            status: segments.isEmpty ? "processing" : status,
            text: text.isEmpty ? nil : text,
            segments: segments,
            language: language,
            error: nil
        )
    }

    private static func coalesce(_ input: [TranscriptService.Segment]) -> [TranscriptService.Segment] {
        guard !input.isEmpty else { return [] }
        let sorted = input.sorted { $0.start < $1.start }
        var out: [TranscriptService.Segment] = []
        for seg in sorted {
            let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let normalized = Self.normalizeCue(text)

            if let last = out.last {
                let lastNorm = Self.normalizeCue(last.text)
                // Exact / near-duplicate from overlapping windows.
                if abs(last.start - seg.start) < 0.55, lastNorm == normalized {
                    if seg.end > last.end {
                        out[out.count - 1] = TranscriptService.Segment(
                            start: last.start,
                            end: seg.end,
                            text: last.text.count >= text.count ? last.text : text
                        )
                    }
                    continue
                }
                // Heavy overlap of the same words — keep the longer line.
                let overlap = min(last.end, seg.end) - max(last.start, seg.start)
                if overlap > 0.35, Self.cuesAreNearDuplicate(lastNorm, normalized) {
                    if text.count > last.text.count || seg.end > last.end {
                        out[out.count - 1] = TranscriptService.Segment(
                            start: min(last.start, seg.start),
                            end: max(last.end, seg.end),
                            text: text.count >= last.text.count ? text : last.text
                        )
                    }
                    continue
                }
            }
            out.append(TranscriptService.Segment(start: seg.start, end: seg.end, text: text))
        }
        return out
    }

    private static func normalizeCue(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func cuesAreNearDuplicate(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if a.isEmpty || b.isEmpty { return false }
        return a.contains(b) || b.contains(a)
    }

    /// PCM float mono @ Whisper sample rate for `[start, end)` on the media URL.
    private static func extractPCMWindow(
        mediaURL: URL,
        start: Double,
        end: Double
    ) async throws -> [Float] {
        let source = R2PresignedPlayback.httpsURL(from: mediaURL) ?? mediaURL
        let (asset, loader) = R2PresignedPlayback.makeAsset(for: source)
        let retained = loader
        defer { _ = retained }

        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw NSError(
                domain: "LiveCaptionEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "audio_missing"]
            )
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: WhisperKit.sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw NSError(
                domain: "LiveCaptionEngine",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "audio_reader_unavailable"]
            )
        }
        reader.add(output)

        let timescale: CMTimeScale = 600
        let startTime = CMTime(seconds: max(0, start), preferredTimescale: timescale)
        let duration = CMTime(seconds: max(0.1, end - start), preferredTimescale: timescale)
        reader.timeRange = CMTimeRange(start: startTime, duration: duration)

        guard reader.startReading() else {
            throw reader.error
                ?? NSError(
                    domain: "LiveCaptionEngine",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "audio_reader_failed"]
                )
        }

        var samples: [Float] = []
        samples.reserveCapacity(Int((end - start) * Double(WhisperKit.sampleRate)) + 1024)

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length > 1 else { continue }
            var data = Data(count: length)
            data.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return }
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
            }
            let int16Count = length / MemoryLayout<Int16>.size
            data.withUnsafeBytes { raw in
                let ints = raw.bindMemory(to: Int16.self)
                for i in 0..<int16Count {
                    samples.append(Float(ints[i]) / Float(Int16.max))
                }
            }
        }

        if reader.status == .failed {
            throw reader.error
                ?? NSError(
                    domain: "LiveCaptionEngine",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "audio_reader_failed"]
                )
        }
        return samples
    }
}
