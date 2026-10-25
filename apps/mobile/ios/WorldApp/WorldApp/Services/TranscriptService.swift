import AVFoundation
import Foundation
import SwiftUI
import WhisperKit

/// On-device captions via WhisperKit (Core ML). Keeps the film overlay font/style;
/// no server Groq / `/v1/transcript` calls.
enum TranscriptService {
    struct Segment: Sendable, Equatable, Codable {
        var start: Double
        var end: Double
        var text: String
    }

    struct Transcript: Sendable, Equatable, Codable {
        var postID: String
        var status: String
        var text: String?
        var segments: [Segment]
        var language: String?
        var error: String?

        var isReady: Bool { status == "ready" && (!segments.isEmpty || !(text ?? "").isEmpty) }
        var isPending: Bool { status == "pending" || status == "processing" || status == "missing" }
    }

    /// Bundled WhisperKit Small (copied into the app at build time).
    static let whisperModelName = "openai_whisper-small"

    private static let preferenceKey = "matterya.hubs.cc.enabled"

    /// Legacy key — CC must not stick across videos. Always reads/writes as off.
    static var captionsEnabledPreference: Bool {
        get {
            // Clear any stale "on" from older builds so nothing re-enables CC by default.
            if UserDefaults.standard.object(forKey: preferenceKey) != nil {
                UserDefaults.standard.set(false, forKey: preferenceKey)
            }
            return false
        }
        set {
            UserDefaults.standard.set(false, forKey: preferenceKey)
        }
    }

    /// Any non-empty post id — on-device works for UUID shares and local hub ids.
    static func isTranscriptablePostID(_ postID: String?) -> Bool {
        guard let raw = postID?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return false
        }
        return true
    }

    static func cached(_ postID: String) -> Transcript? {
        if let hit = TranscriptMemory.shared.get(postID) { return hit }
        if let disk = loadDisk(postID) {
            TranscriptMemory.shared.set(disk)
            return disk
        }
        return nil
    }

    /// Active cue only. Never returns the full transcript blob.
    /// Works for live/partial transcripts (status still `processing`) as soon as segments exist.
    /// Prefers an overlapping cue; if the playhead sits in a short gap, holds the nearest
    /// recent line so brief ASR holes do not flash empty.
    static func textAt(time seconds: Double, in transcript: Transcript) -> String? {
        guard !transcript.segments.isEmpty else { return nil }
        let t = max(0, seconds)
        if let hit = transcript.segments.first(where: {
            t >= $0.start - 0.18 && t <= $0.end + 0.45
        }) {
            let trimmed = hit.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        // Hold last spoken line for up to ~0.9s across small segment gaps.
        let prior = transcript.segments
            .filter { $0.end <= t + 0.05 && t - $0.end <= 0.9 }
            .max(by: { $0.end < $1.end })
        let trimmed = prior?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func invalidateCache(postID: String) {
        TranscriptMemory.shared.remove(postID)
        try? FileManager.default.removeItem(at: diskURL(for: postID))
    }

    /// Cache-only lookup (no network). Prefer `generate(postID:mediaURL:)` for CC.
    @discardableResult
    static func fetch(postID: String, force: Bool = false) async -> Transcript? {
        guard isTranscriptablePostID(postID) else { return nil }
        if force { invalidateCache(postID: postID) }
        return cached(postID)
    }

    /// Server enqueue removed — captions run on-device.
    @discardableResult
    static func enqueue(postID: String, runNow: Bool = false, force: Bool = false) async -> String? {
        _ = postID
        _ = runNow
        _ = force
        return nil
    }

    static func looksTruncated(_ transcript: Transcript, videoDuration: Double) -> Bool {
        guard transcript.isReady else { return false }
        let duration = max(0, videoDuration)
        guard duration > 95 else { return false }
        let lastEnd = transcript.segments.map(\.end).max() ?? 0
        if lastEnd > 0, lastEnd < min(duration * 0.72, duration - 25) {
            return true
        }
        return transcript.segments.isEmpty
    }

    /// True when the bundled Small model is present in the app package.
    static func isModelReadyOnDisk() -> Bool {
        bundledModelFolder() != nil
    }

    /// Absolute path to `Resources/WhisperKit/openai_whisper-small` inside the app bundle.
    static func bundledModelFolder() -> String? {
        // Folder reference copies the directory into the bundle root or a WhisperKit/ subfolder.
        let candidates: [URL?] = [
            Bundle.main.url(forResource: whisperModelName, withExtension: nil, subdirectory: "WhisperKit"),
            Bundle.main.url(forResource: whisperModelName, withExtension: nil),
            Bundle.main.resourceURL?
                .appendingPathComponent("WhisperKit", isDirectory: true)
                .appendingPathComponent(whisperModelName, isDirectory: true),
            Bundle.main.resourceURL?
                .appendingPathComponent(whisperModelName, isDirectory: true),
        ]
        for url in candidates {
            guard let url else { continue }
            let melModelc = url.appendingPathComponent("MelSpectrogram.mlmodelc", isDirectory: true)
            let melPackage = url.appendingPathComponent("MelSpectrogram.mlpackage", isDirectory: true)
            if FileManager.default.fileExists(atPath: melModelc.path)
                || FileManager.default.fileExists(atPath: melPackage.path) {
                return url.path
            }
        }
        return nil
    }

    /// Warm the bundled model after launch so the first CC tap is fast (no UI).
    static func warmModelInBackground() {
        Task.detached(priority: .utility) {
            _ = try? await WhisperKitEngine.shared.prepare()
        }
    }

    /// Persist a live/partial transcript so `textAt` and later CC opens stay warm.
    static func storeLiveResult(_ transcript: Transcript) {
        store(transcript)
        if transcript.isReady {
            saveDiskPublic(transcript)
        }
    }

    /// Run WhisperKit on the video’s audio using the bundled model.
    /// `onPhase` receives short UI hints (preparing audio / generating) — never a download.
    @discardableResult
    static func generate(
        postID: String,
        mediaURL: URL,
        force: Bool = false,
        onPhase: (@MainActor @Sendable (String) -> Void)? = nil
    ) async -> Transcript {
        let key = postID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return Transcript(
                postID: postID,
                status: "failed",
                text: nil,
                segments: [],
                language: nil,
                error: "missing_post_id"
            )
        }

        if !force, let hit = cached(key), hit.isReady {
            return hit
        }
        if force { invalidateCache(postID: key) }
        return await TranscriptFlight.shared.run(key: key) {
            await Self.runGenerate(postID: key, mediaURL: mediaURL, onPhase: onPhase)
        }
    }

    // MARK: - Private

    private static func runGenerate(
        postID: String,
        mediaURL: URL,
        onPhase: (@MainActor @Sendable (String) -> Void)?
    ) async -> Transcript {
        store(
            Transcript(
                postID: postID,
                status: "processing",
                text: nil,
                segments: [],
                language: nil,
                error: nil
            )
        )

        do {
            guard isModelReadyOnDisk() else {
                throw makeError(
                    code: 10,
                    "captions_model_missing — rebuild the app (scripts/fetch_whisperkit_model.sh)"
                )
            }
            await reportPhase(onPhase, "Generating captions…")
            try await WhisperKitEngine.shared.prepare()

            await reportPhase(onPhase, "Preparing audio…")
            let audioURL = try await extractAudio(from: mediaURL, postID: postID)
            defer { try? FileManager.default.removeItem(at: audioURL) }

            await reportPhase(onPhase, "Generating captions…")
            let results = try await WhisperKitEngine.shared.transcribe(audioPath: audioURL.path)
            var segments: [Segment] = []
            var fullText: [String] = []
            var language: String?
            for result in results {
                language = language ?? result.language
                for seg in result.segments {
                    let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    let start = Double(seg.start)
                    let end = max(Double(seg.end), start + 0.4)
                    segments.append(Segment(start: start, end: end, text: text))
                    fullText.append(text)
                }
                let blob = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !blob.isEmpty, fullText.isEmpty {
                    fullText.append(blob)
                }
            }

            segments = coalesceSegments(segments)

            let transcript = Transcript(
                postID: postID,
                status: segments.isEmpty && fullText.isEmpty ? "failed" : "ready",
                text: fullText.isEmpty ? nil : fullText.joined(separator: " "),
                segments: segments,
                language: language,
                error: segments.isEmpty && fullText.isEmpty ? "empty_transcript" : nil
            )
            store(transcript)
            saveDisk(transcript)
            return transcript
        } catch {
            #if DEBUG
            print("[Transcript] generate fail \(postID.prefix(8)): \(error)")
            #endif
            let failed = Transcript(
                postID: postID,
                status: "failed",
                text: nil,
                segments: [],
                language: nil,
                error: describeError(error)
            )
            store(failed)
            return failed
        }
    }

    private static func reportPhase(
        _ onPhase: (@MainActor @Sendable (String) -> Void)?,
        _ message: String
    ) async {
        guard let onPhase else { return }
        await MainActor.run { onPhase(message) }
    }

    private static func describeError(_ error: Error) -> String {
        if let ns = error as NSError? {
            let parts = [ns.localizedDescription, ns.localizedFailureReason]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parts.isEmpty { return parts.joined(separator: " — ") }
        }
        return error.localizedDescription
    }

    private static func coalesceSegments(_ input: [Segment]) -> [Segment] {
        guard !input.isEmpty else { return [] }
        let sorted = input.sorted { $0.start < $1.start }
        var out: [Segment] = []
        for seg in sorted {
            if let last = out.last,
               abs(last.start - seg.start) < 0.35,
               last.text == seg.text {
                continue
            }
            out.append(seg)
        }
        return out
    }

    fileprivate static func store(_ transcript: Transcript) {
        TranscriptMemory.shared.set(transcript)
    }

    fileprivate static func saveDiskPublic(_ transcript: Transcript) {
        saveDisk(transcript)
    }

    private static func diskURL(for postID: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MatteryaCaptions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = postID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return dir.appendingPathComponent("\(safe).json")
    }

    private static func loadDisk(_ postID: String) -> Transcript? {
        let url = diskURL(for: postID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Transcript.self, from: data)
    }

    private static func saveDisk(_ transcript: Transcript) {
        guard transcript.isReady else { return }
        let url = diskURL(for: transcript.postID)
        guard let data = try? JSONEncoder().encode(transcript) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Audio extract (R2-aware)

    /// Hubs media is often a GET-only R2 presign. Plain `AVURLAsset` export 403s / fails —
    /// must use `R2PresignedPlayback.makeAsset` (same path as the player).
    private static func extractAudio(from mediaURL: URL, postID: String) async throws -> URL {
        let source = R2PresignedPlayback.httpsURL(from: mediaURL) ?? mediaURL

        if let local = try? await exportAudioUsingR2Asset(from: source, postID: postID) {
            return local
        }

        // Fallback: download the object, then export from a real file URL.
        let downloaded = try await downloadMedia(from: source, postID: postID)
        defer { try? FileManager.default.removeItem(at: downloaded) }
        return try await exportAudioFromLocalFile(downloaded, postID: postID)
    }

    private static func exportAudioUsingR2Asset(from source: URL, postID: String) async throws -> URL {
        let (asset, loader) = R2PresignedPlayback.makeAsset(for: source)
        // Retain loader for the whole export — resourceLoader keeps a weak delegate.
        let retainedLoader = loader
        defer { _ = retainedLoader }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw makeError(code: 1, "audio_missing")
        }
        _ = try? await asset.load(.duration)

        return try await runExportSession(asset: asset, postID: postID, preferM4A: true)
    }

    private static func exportAudioFromLocalFile(_ fileURL: URL, postID: String) async throws -> URL {
        let asset = AVURLAsset(url: fileURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw makeError(code: 1, "audio_missing")
        }
        return try await runExportSession(asset: asset, postID: postID, preferM4A: true)
    }

    private static func runExportSession(
        asset: AVAsset,
        postID: String,
        preferM4A: Bool
    ) async throws -> URL {
        let presets: [String] = preferM4A
            ? [AVAssetExportPresetAppleM4A, AVAssetExportPresetLowQuality, AVAssetExportPresetPassthrough]
            : [AVAssetExportPresetLowQuality, AVAssetExportPresetPassthrough, AVAssetExportPresetAppleM4A]

        var lastMessage = "audio_export_unavailable"
        for preset in presets {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            let isM4A = preset == AVAssetExportPresetAppleM4A
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "cc-\(postID.prefix(8))-\(UUID().uuidString).\(isM4A ? "m4a" : "mp4")"
                )
            try? FileManager.default.removeItem(at: out)
            session.outputURL = out
            session.outputFileType = isM4A ? .m4a : .mp4
            session.shouldOptimizeForNetworkUse = true
            session.timeRange = CMTimeRange(start: .zero, duration: .positiveInfinity)

            do {
                try await exportAsync(session)
                let size = (try? out.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                if size > 1024 {
                    return out
                }
                lastMessage = "audio_export_empty"
                try? FileManager.default.removeItem(at: out)
            } catch {
                lastMessage = describeError(error)
                try? FileManager.default.removeItem(at: out)
            }
        }
        throw makeError(code: 4, lastMessage)
    }

    private static func exportAsync(_ session: AVAssetExportSession) async throws {
        nonisolated(unsafe) let exportSession = session
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: makeError(code: 3, "audio_export_cancelled"))
                default:
                    let message = exportSession.error?.localizedDescription ?? "audio_export_failed"
                    continuation.resume(throwing: makeError(code: 4, message))
                }
            }
        }
    }

    private static func downloadMedia(from source: URL, postID: String) async throws -> URL {
        var req = URLRequest(url: source)
        req.httpMethod = "GET"
        req.timeoutInterval = 300
        req.cachePolicy = .reloadIgnoringLocalCacheData

        let (tempURL, response) = try await URLSession.shared.download(for: req)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) && http.statusCode != 206 {
            throw makeError(code: 5, "audio_download_http_\(http.statusCode)")
        }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-dl-\(postID.prefix(8))-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    private static func makeError(code: Int, _ message: String) -> NSError {
        NSError(
            domain: "TranscriptService",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

// MARK: - In-memory cache (sync) + single-flight (actor)

final class TranscriptMemory: @unchecked Sendable {
    static let shared = TranscriptMemory()
    private let lock = NSLock()
    private var cache: [String: TranscriptService.Transcript] = [:]

    func get(_ postID: String) -> TranscriptService.Transcript? {
        lock.lock(); defer { lock.unlock() }
        return cache[postID]
    }

    func set(_ transcript: TranscriptService.Transcript) {
        lock.lock(); defer { lock.unlock() }
        cache[transcript.postID] = transcript
    }

    func remove(_ postID: String) {
        lock.lock(); defer { lock.unlock() }
        cache.removeValue(forKey: postID)
    }
}

actor TranscriptFlight {
    static let shared = TranscriptFlight()
    private var inflight: [String: Task<TranscriptService.Transcript, Never>] = [:]

    func run(
        key: String,
        work: @escaping @Sendable () async -> TranscriptService.Transcript
    ) async -> TranscriptService.Transcript {
        if let existing = inflight[key] {
            return await existing.value
        }
        let task = Task { await work() }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        return result
    }
}

// MARK: - WhisperKit engine (single shared pipeline)

actor WhisperKitEngine {
    static let shared = WhisperKitEngine()

    private var kit: WhisperKit?

    func prepare() async throws {
        _ = try await ensureReady()
    }

    func transcribe(audioPath: String) async throws -> [TranscriptionResult] {
        let pipe = try await ensureReady()
        // Use the decodeOptions-only overload — works across WhisperKit 0.12–0.18
        // (audioInputOptions was added later; default is full-file load).
        return try await pipe.transcribe(
            audioPath: audioPath,
            decodeOptions: liveDecodeOptions(),
            callback: nil
        )
    }

    /// Live CC chunks — PCM already at Whisper sample rate.
    func transcribe(samples: [Float]) async throws -> [TranscriptionResult] {
        let pipe = try await ensureReady()
        return try await pipe.transcribe(
            audioArray: samples,
            decodeOptions: liveDecodeOptions(),
            callback: nil
        )
    }

    private func liveDecodeOptions() -> DecodingOptions {
        DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: nil,
            temperature: 0,
            detectLanguage: true,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            wordTimestamps: false,
            // VAD was dropping quiet / trailing phrases on short live windows.
            chunkingStrategy: .none
        )
    }

    private func ensureReady() async throws -> WhisperKit {
        if let kit { return kit }
        guard let folder = TranscriptService.bundledModelFolder() else {
            throw NSError(
                domain: "TranscriptService",
                code: 10,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "captions_model_missing — rebuild the app (scripts/fetch_whisperkit_model.sh)",
                ]
            )
        }
        // Bundled model only — never download from Hugging Face at runtime.
        let config = WhisperKitConfig(
            model: TranscriptService.whisperModelName,
            modelFolder: folder,
            verbose: false,
            logLevel: .error,
            prewarm: true,
            load: true,
            download: false,
            useBackgroundDownloadSession: false
        )
        let pipe = try await WhisperKit(config)
        if pipe.modelState != .loaded {
            try await pipe.loadModels()
        }
        self.kit = pipe
        return pipe
    }
}

/// Netflix-style film captions: clean white type, soft shadow, no black box.
struct MatteryaFilmCaption: View {
    let text: String
    var maxWidthPadding: CGFloat = 36
    var bottomPadding: CGFloat = 28

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            Text(text)
                .font(.system(size: 17, weight: .semibold, design: .default))
                .tracking(0.15)
                .multilineTextAlignment(.center)
                .lineSpacing(2.5)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.95), radius: 1.1, x: 0, y: 0)
                .shadow(color: .black.opacity(0.72), radius: 3.2, x: 0, y: 1.1)
                .shadow(color: .black.opacity(0.35), radius: 9, x: 0, y: 2.5)
                .padding(.horizontal, maxWidthPadding)
                .padding(.bottom, bottomPadding)
        }
        .allowsHitTesting(false)
    }
}
