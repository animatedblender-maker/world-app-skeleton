import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ReelComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let country: Country
    var publishAsReel: Bool = true
    var onPosted: ((CountryPost) -> Void)?

    @State private var caption = ""
    @State private var busy = false
    @State private var uploadPhase: MediaUploadPhase = .idle
    @State private var uploadProgress: UploadProgress?
    @State private var isPreparingVideo = false
    @State private var compressionProgress: Double = 0
    @State private var errorMessage: String?
    @State private var selectedVideo: PhotosPickerItem?
    @State private var uploadVideoURL: URL?
    @State private var previewImage: UIImage?
    @State private var previewVideoURL: URL?
    @State private var preparedVideoSizeBytes = 0
    @State private var videoMimeType = "video/mp4"
    @State private var videoFileExtension = "mp4"

    private var canSubmit: Bool { uploadVideoURL != nil && !isPreparingVideo }

    private var canPostHere: Bool {
        guard let code = appState.currentProfile?.countryCode?.uppercased() else { return false }
        return code == country.iso.uppercased()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        previewSection
                        captionField
                        if let errorMessage { errorBanner(errorMessage) }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.bottom, 100)
                }

                VStack {
                    Spacer()
                    publishBar
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.8))
                }
                ToolbarItem(placement: .principal) {
                    Text(publishAsReel ? "New reel" : "New video")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.black.opacity(0.9), for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onChange(of: selectedVideo) { _, item in
            Task { await loadVideo(item) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle.fill")
                .foregroundStyle(Theme.facebookBlue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Publishing to \(country.name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if isPreparingVideo {
                    Text("Compressing video · \(compressionPercentText)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .monospacedDigit()
                } else if preparedVideoSizeBytes > 0 {
                    Text("Ready · \(VideoCompressionService.formattedSize(preparedVideoSizeBytes))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                } else {
                    Text(publishAsReel ? "Vertical video works best" : "Shows in feed and Living")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var previewSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(height: 420)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )

            if isPreparingVideo {
                VStack(spacing: 12) {
                    ProgressView(value: compressionProgress)
                        .tint(.white)
                        .frame(maxWidth: 220)
                    Text("Compressing video · \(compressionPercentText)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .monospacedDigit()
                }
                .padding(.horizontal, 24)
            } else if let previewVideoURL {
                VideoPlayerView(
                    url: previewVideoURL,
                    posterURL: nil,
                    adsEnabled: false,
                    isActive: true,
                    loops: true,
                    muted: false,
                    showsControls: true
                )
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("Choose one video")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if previewVideoURL != nil {
                Label("Preview before publishing", systemImage: "play.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(14)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            PhotosPicker(selection: $selectedVideo, matching: .videos) {
                Text(uploadVideoURL == nil ? "Select video" : "Change video")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(14)
        }
    }

    private var captionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CAPTION")
                .font(.caption.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.55))
            TextField("Add a caption (optional)", text: $caption, axis: .vertical)
                .lineLimit(2...5)
                .foregroundStyle(.white)
                .padding(14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var publishBar: some View {
        VStack(spacing: 12) {
            if busy, uploadPhase != .idle {
                UploadProgressView(phase: uploadPhase, progress: uploadProgress)
            }

            HStack {
                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(canPostHere ? .white : Theme.danger)
                Spacer()
                Button {
                    Task { await submit() }
                } label: {
                    Text(busy ? "Working…" : (publishAsReel ? "Publish reel" : "Publish video"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(canSubmit && !busy && canPostHere ? Theme.facebookBlue : Color.white.opacity(0.25), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(busy || isPreparingVideo || !canSubmit || !canPostHere)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 14)
        .background(.black.opacity(0.92))
    }

    private var compressionPercentText: String {
        "\(Int((compressionProgress * 100).rounded()))%"
    }

    private var statusLabel: String {
        if !canPostHere { return "Home country only" }
        if busy {
            switch uploadPhase {
            case .compressing:
                return uploadProgress.map { "Compressing \($0.percentText)" } ?? "Compressing video…"
            case .uploading:
                return uploadProgress.map { "Uploading \($0.percentText)" } ?? "Uploading video…"
            case .publishing:
                return "Publishing post…"
            case .idle:
                return "Starting upload…"
            }
        }
        return "Ready to publish"
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(Theme.danger)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.danger.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func loadVideo(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isPreparingVideo = true
        compressionProgress = 0
        errorMessage = nil
        clearSelectedVideo(keepPreparingFlag: true)
        defer {
            isPreparingVideo = false
            compressionProgress = 0
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw MediaError.uploadFailed("Could not read video.")
            }
            let format = Self.videoFormat(for: item)
            let sourceURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("composer-source-\(UUID().uuidString).\(format.extension)")
            try data.write(to: sourceURL)

            let compressionHandler: @Sendable (Double) -> Void = { progress in
                Task { @MainActor in
                    compressionProgress = progress
                }
            }
            let preparedURL = try await VideoCompressionService.shared.prepareVideoForUpload(
                sourceURL: sourceURL,
                onProgress: compressionHandler
            )
            if preparedURL != sourceURL {
                try? FileManager.default.removeItem(at: sourceURL)
            }

            let sizeBytes = (try? preparedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            uploadVideoURL = preparedURL
            previewVideoURL = preparedURL
            preparedVideoSizeBytes = sizeBytes
            videoMimeType = "video/mp4"
            videoFileExtension = "mp4"
            previewImage = await generateThumbnail(from: preparedURL)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            clearSelectedVideo()
        }
    }

    private func clearSelectedVideo(keepPreparingFlag: Bool = false) {
        if let uploadVideoURL {
            try? FileManager.default.removeItem(at: uploadVideoURL)
        }
        if previewVideoURL != uploadVideoURL, let previewVideoURL {
            try? FileManager.default.removeItem(at: previewVideoURL)
        }
        uploadVideoURL = nil
        previewImage = nil
        previewVideoURL = nil
        preparedVideoSizeBytes = 0
        videoMimeType = "video/mp4"
        videoFileExtension = "mp4"
        if !keepPreparingFlag {
            isPreparingVideo = false
        }
    }

    private static func videoFormat(for item: PhotosPickerItem) -> (extension: String, mimeType: String) {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .mpeg4Movie) }) {
            return ("mp4", "video/mp4")
        }
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .quickTimeMovie) }) {
            return ("mov", "video/quicktime")
        }
        return ("mp4", "video/mp4")
    }

    private func generateThumbnail(from url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func submit() async {
        guard let profile = appState.currentProfile,
              let authorID = AuthService.shared.currentUser?.id,
              let uploadVideoURL,
              canPostHere else { return }

        busy = true
        uploadPhase = .uploading
        uploadProgress = UploadProgress(fractionCompleted: 0, bytesSent: 0, totalBytes: Int64(preparedVideoSizeBytes))
        errorMessage = nil
        defer {
            busy = false
            uploadPhase = .idle
            uploadProgress = nil
        }

        let progressHandler: @Sendable (UploadProgress) -> Void = { progress in
            Task { @MainActor in
                uploadProgress = progress
            }
        }
        let publishingHandler: @Sendable () -> Void = {
            Task { @MainActor in
                uploadPhase = .publishing
            }
        }

        do {
            let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let post: CountryPost
            if publishAsReel {
                post = try await PostsService.shared.createReel(
                    authorID: authorID,
                    body: trimmedCaption,
                    countryName: country.name,
                    countryCode: country.iso,
                    cityName: profile.cityName,
                    videoFileURL: uploadVideoURL,
                    mimeType: videoMimeType,
                    fileExtension: videoFileExtension,
                    onUploadProgress: progressHandler,
                    onPublishing: publishingHandler
                )
            } else {
                post = try await PostsService.shared.createLivingVideo(
                    authorID: authorID,
                    body: trimmedCaption,
                    countryName: country.name,
                    countryCode: country.iso,
                    cityName: profile.cityName,
                    videoFileURL: uploadVideoURL,
                    mimeType: videoMimeType,
                    fileExtension: videoFileExtension,
                    onUploadProgress: progressHandler,
                    onPublishing: publishingHandler
                )
            }
            onPosted?(post)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}