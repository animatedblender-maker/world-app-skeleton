import AVFoundation
import PhotosUI
import SwiftUI

struct PostComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let country: Country
    var onPosted: ((CountryPost) -> Void)?

    @State private var bodyText = ""
    @State private var title = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedVideo: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var previewImage: UIImage?
    @State private var uploadVideoURL: URL?
    @State private var previewVideoURL: URL?
    @State private var preparedVideoSizeBytes = 0
    @State private var videoMimeType = "video/mp4"
    @State private var videoFileExtension = "mp4"
    @State private var isPreparingVideo = false
    @State private var compressionProgress: Double = 0
    @State private var quotedEmbed: SharedPostPreview?
    @State private var visibility: PostVisibility = .public
    @FocusState private var focusedField: ComposerField?

    private enum ComposerField: Hashable {
        case title, body
    }

    private let maxBodyLength = 2_000

    private var trimmedBody: String {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasVideo: Bool { uploadVideoURL != nil }

    private var canSubmit: Bool {
        !trimmedBody.isEmpty
            || imageData != nil
            || hasVideo
            || appState.quotedSharePostID != nil
    }

    private var canPostHere: Bool {
        appState.canPostToCountry(country)
    }

    private var compressionPercentText: String {
        "\(Int((compressionProgress * 100).rounded()))%"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PaperBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        composerHeader
                        if let quotedEmbed {
                            SharedPostEmbedView(embed: quotedEmbed)
                        }
                        // No headlines on posts — caption/body only.
                        bodyField
                        PostVisibilityControl(visibility: $visibility)
                        mediaSection
                        if let errorMessage {
                            errorBanner(errorMessage)
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
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
                    Text("New post")
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .tint(Theme.ink)
        .task {
            await loadQuotedShare()
        }
        .onDisappear {
            appState.quotedSharePostID = nil
        }
        .onChange(of: selectedPhoto) { _, item in
            Task { await loadSelectedPhoto(item) }
        }
        .onChange(of: selectedVideo) { _, item in
            Task { await loadSelectedVideo(item) }
        }
        .onAppear {
            focusedField = .body
        }
    }

    private var composerHeader: some View {
        HStack(spacing: 14) {
            AvatarView(
                url: appState.currentProfile?.avatarURL,
                seed: appState.currentProfile?.userID ?? "me",
                size: 52
            )
            .overlay {
                Circle()
                    .stroke(Theme.border, lineWidth: 0.5)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(appState.currentProfile?.displayName ?? appState.currentProfile?.username ?? "You")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.ink)

                Text(MatteryaCopy.postToYourFeed)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.accentSoft, in: Capsule())
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

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HEADLINE")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMuted)

            TextField("Optional headline", text: $title, axis: .vertical)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Theme.ink)
                .lineLimit(1...3)
                .focused($focusedField, equals: .title)
                .padding(16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .stroke(focusedField == .title ? Theme.accent.opacity(0.45) : Theme.border, lineWidth: 0.5)
                )
        }
    }

    private var bodyField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("YOUR STORY")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkMuted)
                Spacer()
                Text("\(bodyText.count)/\(maxBodyLength)")
                    .font(.caption2)
                    .foregroundStyle(bodyText.count > maxBodyLength ? Theme.danger : Theme.inkMuted)
            }

            ZStack(alignment: .topLeading) {
                if trimmedBody.isEmpty {
                    Text("What's happening in \(country.name)?")
                        .font(.body)
                        .foregroundStyle(Theme.inkMuted.opacity(0.7))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                }

                TextEditor(text: $bodyText)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .focused($focusedField, equals: .body)
                    .onChange(of: bodyText) { _, newValue in
                        if newValue.count > maxBodyLength {
                            bodyText = String(newValue.prefix(maxBodyLength))
                        }
                    }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(focusedField == .body ? Theme.accent.opacity(0.45) : Theme.border, lineWidth: 0.5)
            )
        }
    }

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MEDIA")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMuted)

            if isPreparingVideo {
                preparingVideoCard
            } else if hasVideo {
                videoPreviewCard
            } else if let previewImage {
                photoPreviewCard(previewImage)
            } else {
                mediaPickers
            }
        }
    }

    private var mediaPickers: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                mediaPickerRow(
                    icon: "photo.on.rectangle.angled",
                    title: "Add a photo",
                    subtitle: "High-resolution images look best in the feed."
                )
            }
            .buttonStyle(.plain)

            PhotosPicker(selection: $selectedVideo, matching: .videos) {
                mediaPickerRow(
                    icon: "video.badge.plus",
                    title: "Add a video",
                    subtitle: "Vertical clips work best in the feed."
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func mediaPickerRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.ink)
                .frame(width: 48, height: 48)
                .background(Theme.matteDeep, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.border, lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer()
            Image(systemName: "plus")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.inkMuted)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private func photoPreviewCard(_ image: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .stroke(Theme.border, lineWidth: 0.5)
                )

            clearMediaButton
        }
    }

    private var preparingVideoCard: some View {
        VStack(spacing: 12) {
            if compressionProgress > 0 {
                ProgressView(value: compressionProgress, total: 1)
                    .tint(Theme.ink)
                    .frame(maxWidth: 220)
            } else {
                ProgressView()
                    .tint(Theme.ink)
            }
            Text(compressionProgress > 0 ? "Compressing video · \(compressionPercentText)" : "Preparing video…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.inkSecondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private var videoPreviewCard: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let previewVideoURL {
                    VideoPlayerView(
                        url: previewVideoURL,
                        posterURL: nil,
                        adsEnabled: false,
                        isActive: true,
                        loops: true,
                        muted: false,
                        showsControls: true
                    )
                } else if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )

            clearMediaButton

            if preparedVideoSizeBytes > 0 {
                Text(VideoCompressionService.formattedSize(preparedVideoSizeBytes))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.surface.opacity(0.92), in: Capsule())
                    .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
    }

    private var clearMediaButton: some View {
        Button {
            clearMedia()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.black.opacity(0.55))
                .padding(10)
        }
        .buttonStyle(.plain)
    }

    private var publishBar: some View {
        VStack(spacing: 0) {
            Theme.divider.frame(height: 0.5)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(canPostHere ? "Ready to publish" : "Set your home country")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(canPostHere ? Theme.ink : Theme.danger)
                    Text(canPostHere ? "Posts to the main feed" : "Add a home country in your profile first.")
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
                                .tint(Theme.paper)
                                .scaleEffect(0.85)
                        }
                        Text(busy ? "Publishing…" : "Publish")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Theme.paper)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(
                        canSubmit && !busy && canPostHere && !isPreparingVideo ? Theme.ink : Theme.inkMuted,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .disabled(busy || isPreparingVideo || !canSubmit || !canPostHere)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 14)
            .background(Theme.surface.opacity(0.96))
        }
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

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        clearVideoMedia()
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else { return }
            guard let image = UIImage(data: raw) else { return }
            let jpeg = image.jpegData(compressionQuality: 0.88) ?? raw
            imageData = jpeg
            previewImage = UIImage(data: jpeg)
            selectedPhoto = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            clearMedia()
        }
    }

    private func loadSelectedVideo(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isPreparingVideo = true
        compressionProgress = 0
        errorMessage = nil
        clearPhotoMedia()
        clearVideoMedia(keepPreparingFlag: true)
        defer {
            isPreparingVideo = false
            compressionProgress = 0
            selectedVideo = nil
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
            clearVideoMedia()
        }
    }

    private func generateThumbnail(from url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func clearPhotoMedia() {
        imageData = nil
        if uploadVideoURL == nil {
            previewImage = nil
        }
        selectedPhoto = nil
    }

    private func clearVideoMedia(keepPreparingFlag: Bool = false) {
        if let uploadVideoURL {
            try? FileManager.default.removeItem(at: uploadVideoURL)
        }
        if previewVideoURL != uploadVideoURL, let previewVideoURL {
            try? FileManager.default.removeItem(at: previewVideoURL)
        }
        uploadVideoURL = nil
        previewVideoURL = nil
        preparedVideoSizeBytes = 0
        videoMimeType = "video/mp4"
        videoFileExtension = "mp4"
        selectedVideo = nil
        if imageData == nil {
            previewImage = nil
        }
        if !keepPreparingFlag {
            isPreparingVideo = false
        }
    }

    private func clearMedia() {
        clearPhotoMedia()
        clearVideoMedia()
        previewImage = nil
    }

    private func loadQuotedShare() async {
        guard let shareID = appState.quotedSharePostID else { return }
        guard let post = try? await PostsService.shared.getPostByID(shareID) else { return }
        quotedEmbed = SharedPostPreview(
            id: post.id,
            title: post.title,
            body: post.body,
            mediaType: post.mediaType,
            mediaURL: post.mediaURL,
            thumbURL: post.thumbURL,
            authorID: post.authorID,
            author: post.author
        )
    }

    private func submit() async {
        guard let profile = appState.currentProfile,
              let authorID = AuthService.shared.currentUser?.id else { return }
        guard canPostHere else {
            errorMessage = MatteryaCopy.homeCountryOnlyPost
            return
        }
        guard canSubmit, !isPreparingVideo else { return }

        if let uploadVideoURL {
            await submitVideo(
                authorID: authorID,
                cityName: profile.cityName,
                videoURL: uploadVideoURL
            )
            return
        }

        busy = true
        errorMessage = nil
        defer { busy = false }

        do {
            var mediaType: String?
            var mediaURL: String?
            if let imageData {
                let upload = try await MediaService.shared.uploadPostMedia(
                    data: imageData,
                    fileExtension: "jpg",
                    mimeType: "image/jpeg"
                )
                mediaType = "image"
                mediaURL = upload.publicURL
            }

            // Always main feed (public) — country is metadata only, not a separate feed.
            let post = try await PostsService.shared.createPost(
                authorID: authorID,
                body: trimmedBody,
                countryName: country.name,
                countryCode: country.iso,
                cityName: profile.cityName,
                title: title.nilIfEmpty,
                visibility: .public,
                mediaType: mediaType,
                mediaURL: mediaURL,
                sharedPostID: appState.quotedSharePostID
            )
            appState.quotedSharePostID = nil
            onPosted?(post)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Video in Post composer publishes via createReel (feed spark) with no Spark UI copy and no channel.
    private func submitVideo(
        authorID: String,
        cityName: String?,
        videoURL: URL
    ) async {
        busy = true
        errorMessage = nil

        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            busy = false
            errorMessage = "Video file is missing. Select the video again."
            return
        }

        let localCaption = trimmedBody
        let localVideoURL = videoURL
        let localMime = videoMimeType
        let localExt = videoFileExtension
        let localPreview = previewImage
        let localCountry = country

        let placeholderID = appState.beginFeedVideoUpload(
            caption: localCaption,
            previewImage: localPreview,
            isHub: false
        )
        busy = false
        dismiss()

        let progressHandler: @Sendable (UploadProgress) -> Void = { progress in
            Task { @MainActor in
                HomeFeedStore.shared.updateVideoUpload(
                    id: placeholderID,
                    progress: max(0.05, progress.fractionCompleted * 0.9),
                    phaseLabel: "Uploading"
                )
            }
        }
        let publishingHandler: @Sendable () -> Void = {
            Task { @MainActor in
                HomeFeedStore.shared.updateVideoUpload(
                    id: placeholderID,
                    progress: 0.94,
                    phaseLabel: "Publishing"
                )
            }
        }

        do {
            // Plain caption only — createReel stamps __spark__; no HubChannelPostMarker / hubSlug.
            let post = try await PostsService.shared.createReel(
                authorID: authorID,
                body: localCaption,
                countryName: localCountry.name,
                countryCode: localCountry.iso,
                cityName: cityName,
                videoFileURL: localVideoURL,
                mimeType: localMime,
                fileExtension: localExt,
                thumbnailImage: localPreview,
                hubSlug: nil,
                onUploadProgress: progressHandler,
                onPublishing: publishingHandler
            )
            await MainActor.run {
                appState.finishFeedVideoUpload(placeholderID: placeholderID, post: post)
                onPosted?(post)
            }
        } catch {
            await MainActor.run {
                appState.failFeedVideoUpload(placeholderID: placeholderID, message: error.localizedDescription)
            }
        }
    }
}

struct PostVisibilityControl: View {
    @Binding var visibility: PostVisibility

    private let options: [PostVisibility] = [.public, .followers, .private]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRIVACY")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMuted)

            HStack(spacing: 8) {
                ForEach(options, id: \.rawValue) { option in
                    Button {
                        visibility = option
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: icon(for: option))
                                .font(.caption.weight(.semibold))
                            Text(label(for: option))
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(visibility == option ? Theme.ink : Theme.inkSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            visibility == option ? Theme.matteDeep : Theme.surface,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(visibility == option ? Theme.ink.opacity(0.35) : Theme.border, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func label(for visibility: PostVisibility) -> String {
        switch visibility {
        case .public: "Public"
        case .followers: "Followers"
        case .private: "Only me"
        case .country: "Country"
        }
    }

    private func icon(for visibility: PostVisibility) -> String {
        switch visibility {
        case .public: "globe"
        case .followers: "person.2.fill"
        case .private: "lock.fill"
        case .country: "flag.fill"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
