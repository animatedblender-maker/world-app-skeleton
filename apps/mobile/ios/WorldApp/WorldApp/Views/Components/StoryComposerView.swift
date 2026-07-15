import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct StoryComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let country: Country
    var onPosted: ((CountryPost) -> Void)?

    @State private var caption = ""
    @State private var busy = false
    @State private var uploadPhase: MediaUploadPhase = .idle
    @State private var uploadProgress: UploadProgress?
    @State private var isPreparingVideo = false
    @State private var compressionProgress: Double = 0
    @State private var errorMessage: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedVideo: PhotosPickerItem?
    @State private var mediaData: Data?
    @State private var uploadMediaFileURL: URL?
    @State private var mediaMime = "image/jpeg"
    @State private var mediaExtension = "jpg"
    @State private var previewImage: UIImage?
    @State private var previewVideoURL: URL?
    @State private var isVideo = false

    private var canSubmit: Bool {
        (mediaData != nil || uploadMediaFileURL != nil) && !isPreparingVideo
    }

    private var canPostHere: Bool {
        appState.canPostToCountry(country)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        composerHeader
                        previewCard
                        captionField
                        mediaPickers
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
                    Text("New moment")
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .tint(Theme.accentBright)
        .onChange(of: selectedPhoto) { _, item in
            Task { await loadPhoto(item) }
        }
        .onChange(of: selectedVideo) { _, item in
            Task { await loadVideo(item) }
        }
    }

    private var composerHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "circle.dashed")
                .font(.title2)
                .foregroundStyle(Theme.accentBright)
                .frame(width: 48, height: 48)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("Sharing to your country feed")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                Text("Moments disappear after 24 hours")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
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

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MEDIA")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMuted)

            ZStack {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.canvasMuted)
                    .frame(height: 240)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )

                if isPreparingVideo {
                    VStack(spacing: 10) {
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
                } else if let previewVideoURL, isVideo {
                    VideoPlayerView(
                        url: previewVideoURL,
                        posterURL: nil,
                        adsEnabled: false,
                        isActive: true,
                        loops: true,
                        muted: false,
                        showsControls: true
                    )
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                } else if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                } else {
                    VStack(spacing: 18) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(Theme.accentBright)
                        Text("Pick a photo or video")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(.vertical, 24)
                }
            }
        }
    }

    private var captionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TEXT")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMuted)
            TextField("Add text (optional)", text: $caption)
                .foregroundStyle(Theme.ink)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .stroke(Theme.border, lineWidth: 0.5)
                )
        }
    }

    private var mediaPickers: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                pickerChip("Photo", icon: "photo")
            }
            PhotosPicker(selection: $selectedVideo, matching: .videos) {
                pickerChip("Video", icon: "video")
            }
        }
    }

    private var publishBar: some View {
        VStack(spacing: 0) {
            Theme.divider.frame(height: 0.5)

            if busy, uploadPhase != .idle, isVideo {
                UploadProgressView(phase: uploadPhase, progress: uploadProgress)
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, 12)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(canPostHere ? "Ready to share" : "Home country only")
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
                        Text(busy ? "Sharing…" : "Share moment")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
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

    private func pickerChip(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
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

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        selectedVideo = nil
        clearVideoPreview()
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else { return }
            guard let image = UIImage(data: raw), let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
            uploadMediaFileURL = nil
            mediaData = jpeg
            mediaMime = "image/jpeg"
            mediaExtension = "jpg"
            previewImage = image
            isVideo = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadVideo(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        selectedPhoto = nil
        clearVideoPreview()
        isPreparingVideo = true
        compressionProgress = 0
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

            mediaData = nil
            uploadMediaFileURL = preparedURL
            mediaMime = "video/mp4"
            mediaExtension = "mp4"
            previewVideoURL = preparedURL
            previewImage = await generateThumbnail(from: preparedURL)
            isVideo = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            clearVideoPreview()
        }
    }

    private func clearVideoPreview() {
        if let uploadMediaFileURL {
            try? FileManager.default.removeItem(at: uploadMediaFileURL)
        }
        if previewVideoURL != uploadMediaFileURL, let previewVideoURL {
            try? FileManager.default.removeItem(at: previewVideoURL)
        }
        uploadMediaFileURL = nil
        previewVideoURL = nil
        mediaData = nil
        isVideo = false
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
              canPostHere,
              mediaData != nil || uploadMediaFileURL != nil else { return }

        busy = true
        if isVideo {
            uploadPhase = .uploading
            let totalBytes = Int64((try? uploadMediaFileURL?.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            uploadProgress = UploadProgress(fractionCompleted: 0, bytesSent: 0, totalBytes: totalBytes)
        }
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
            let post = try await PostsService.shared.createStory(
                authorID: authorID,
                body: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                countryName: country.name,
                countryCode: country.iso,
                cityName: profile.cityName,
                mediaData: mediaData,
                mediaFileURL: uploadMediaFileURL,
                mimeType: mediaMime,
                fileExtension: mediaExtension,
                onUploadProgress: isVideo ? progressHandler : nil,
                onPublishing: isVideo ? publishingHandler : nil
            )
            onPosted?(post)
            await appState.refreshStories()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}