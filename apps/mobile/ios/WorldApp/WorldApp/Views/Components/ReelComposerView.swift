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
        appState.canPostToCountry(country)
    }

    private var navTitle: String {
        publishAsReel ? MatteryaCopy.newSpark : MatteryaCopy.newVideo
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        composerHeader
                        previewSection
                        captionField
                        if let errorMessage { errorBanner(errorMessage) }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, 8)
                    .padding(.bottom, 140)
                }

                VStack {
                    Spacer()
                    publishBar
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.surface.opacity(0.94), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.inkSecondary)
                }
                ToolbarItem(placement: .principal) {
                    Text(navTitle)
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .tint(Theme.accentBright)
        .onChange(of: selectedVideo) { _, item in
            Task { await loadVideo(item) }
        }
    }

    private var composerHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: publishAsReel ? "sparkles" : "film")
                .font(.title2)
                .foregroundStyle(Theme.accentBright)
                .frame(width: 48, height: 48)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(MatteryaCopy.postToYourFeed)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)

                if isPreparingVideo {
                    Text("Compressing video · \(compressionPercentText)")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                        .monospacedDigit()
                } else if preparedVideoSizeBytes > 0 {
                    Text("Ready · \(VideoCompressionService.formattedSize(preparedVideoSizeBytes))")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                } else {
                    Text(publishAsReel ? MatteryaCopy.publishSparkHint : MatteryaCopy.publishVideoHint)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
        .shadow(color: Theme.ink.opacity(0.04), radius: 16, y: 8)
    }

    @ViewBuilder
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VIDEO")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMuted)

            ZStack {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.canvasMuted)
                    .frame(height: 420)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )

                if isPreparingVideo {
                    VStack(spacing: 12) {
                        if compressionProgress > 0 {
                            ProgressView(value: compressionProgress, total: 1)
                                .tint(Theme.accentBright)
                                .frame(maxWidth: 220)
                        } else {
                            ProgressView()
                                .tint(Theme.accentBright)
                        }
                        Text(compressionProgress > 0 ? "Compressing video · \(compressionPercentText)" : "Preparing video…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
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
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                } else if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 420)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(Theme.accentBright)
                        Text("Choose one video")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if previewVideoURL != nil {
                    Label("Preview before publishing", systemImage: "play.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.surface.opacity(0.92), in: Capsule())
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
                        .padding(14)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                PhotosPicker(selection: $selectedVideo, matching: .videos) {
                    Text(uploadVideoURL == nil ? "Select video" : "Change video")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.surface, in: Capsule())
                        .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
                }
                .padding(14)
            }
        }
    }

    private var captionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CAPTION")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMuted)
            TextField("Add a caption (optional)", text: $caption, axis: .vertical)
                .lineLimit(2...5)
                .foregroundStyle(Theme.ink)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .stroke(Theme.border, lineWidth: 0.5)
                )
        }
    }

    private var publishBar: some View {
        VStack(spacing: 0) {
            Theme.divider.frame(height: 0.5)

            if busy, uploadPhase != .idle {
                UploadProgressView(phase: uploadPhase, progress: uploadProgress)
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, 12)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(canPostHere ? Theme.ink : Theme.danger)
                    Text(canPostHere ? country.name : "Switch to your country feed to post.")
                        .font(.caption2)
                        .foregroundStyle(Theme.inkMuted)
                }
                Spacer()
                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if busy {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.85)
                        }
                        Text(busy ? "Working…" : (publishAsReel ? MatteryaCopy.publishSpark : MatteryaCopy.publishVideo))
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        canSubmit && !busy && canPostHere ? Theme.accentBright : Theme.inkMuted,
                        in: Capsule()
                    )
                    .shadow(color: Theme.accentBright.opacity(canSubmit && canPostHere ? 0.28 : 0), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .disabled(busy || isPreparingVideo || !canSubmit || !canPostHere)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 14)
            .background(Theme.surface.opacity(0.96))
        }
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
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.danger)
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.danger)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
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
            guard let picked = try await item.loadTransferable(type: PickedVideoFile.self) else {
                throw MediaError.uploadFailed("Could not read video.")
            }
            let sourceURL = picked.url

            let compressionHandler: @Sendable (Double) -> Void = { progress in
                let value = progress
                Task { @MainActor in
                    compressionProgress = value
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
            guard FileManager.default.fileExists(atPath: uploadVideoURL.path) else {
                throw MediaError.uploadFailed("Video file is missing. Select the video again.")
            }
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
                    thumbnailImage: previewImage,
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
                    thumbnailImage: previewImage,
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