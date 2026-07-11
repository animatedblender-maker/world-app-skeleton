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
        guard let code = appState.currentProfile?.countryCode?.uppercased() else { return false }
        return code == country.iso.uppercased()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.18, green: 0.12, blue: 0.28),
                        Color(red: 0.42, green: 0.18, blue: 0.36),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 18) {
                    Text("Stories disappear after 24 hours")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.top, 8)

                    previewCard

                    TextField("Add text (optional)", text: $caption)
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    HStack(spacing: 10) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            pickerChip("Photo", icon: "photo")
                        }
                        PhotosPicker(selection: $selectedVideo, matching: .videos) {
                            pickerChip("Video", icon: "video")
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                    }

                    Spacer()

                    if busy, uploadPhase != .idle, isVideo {
                        UploadProgressView(phase: uploadPhase, progress: uploadProgress)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        Text(busy ? "Sharing…" : "Share to story")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSubmit && !busy && canPostHere ? Theme.accentBright : Color.white.opacity(0.2), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy || isPreparingVideo || !canSubmit || !canPostHere)
                }
                .padding(Theme.pagePadding)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.85))
                }
                ToolbarItem(placement: .principal) {
                    Text("New story")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onChange(of: selectedPhoto) { _, item in
            Task { await loadPhoto(item) }
        }
        .onChange(of: selectedVideo) { _, item in
            Task { await loadVideo(item) }
        }
    }

    private var previewCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(height: 380)

            if isPreparingVideo {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Preparing video…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
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
                .frame(height: 380)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 380)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Pick a photo or video")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

        }
    }

    private func pickerChip(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        defer { isPreparingVideo = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let format = Self.videoFormat(for: item)
            let sourceURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("story-source-\(UUID().uuidString).\(format.extension)")
            try data.write(to: sourceURL)

            let preparedURL = try await VideoCompressionService.shared.prepareVideoForUpload(sourceURL: sourceURL)
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