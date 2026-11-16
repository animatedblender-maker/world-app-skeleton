import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

private enum VideoPublishAudience: String, CaseIterable, Identifiable {
    case hubs
    case sparks
    case feed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hubs: return MatteryaCopy.matteryaHubs
        case .sparks: return MatteryaCopy.spark
        case .feed: return "Feed"
        }
    }

    var subtitle: String {
        switch self {
        case .hubs: return "Long-form on your channel"
        case .sparks: return "Short vertical clip"
        case .feed: return "Home feed only"
        }
    }
}

struct ReelComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let country: Country
    var publishAsReel: Bool = true
    /// When false and not a reel: home-feed video. When true: Hubs channel long-form.
    var publishToHubChannel: Bool = false
    var onPosted: ((CountryPost) -> Void)?

    @State private var caption = ""
    /// Required for Hubs channel long-form uploads.
    @State private var videoTitle = ""
    @State private var audience: VideoPublishAudience = .sparks
    @State private var selectedCategory: YouTubeHomeFilter = .daily
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
    /// Custom thumbnail (Hubs / channel Spark). Falls back to frame-0 when nil.
    @State private var customThumbImage: UIImage?
    @State private var thumbPickerItem: PhotosPickerItem?
    /// nil until the creator answers (required for channel publishes).
    @State private var madeForKids: Bool? = nil
    @State private var hasPaidPromotion = false
    @State private var alteredContent = false
    /// Auto-detected short from Hubs video sheet (vertical + ≤60s).
    @State private var detectedAsSpark = false
    @State private var videoDurationSeconds: Double = 0
    @State private var videoAspectHeightOverWidth: Double = 0

    private var isReelAudience: Bool { audience == .sparks || (locksToHubs && detectedAsSpark) }
    private var isHubAudience: Bool { audience == .hubs }
    private var needsCategory: Bool { audience == .hubs || audience == .sparks || detectedAsSpark }
    /// Hubs video sheet: stay on channel — no Sparks/Feed audience switch.
    private var locksToHubs: Bool { publishToHubChannel && !publishAsReel }
    /// Channel Spark or Hubs video — show Studio-style disclosures + thumbnail.
    private var showsChannelDetails: Bool { publishToHubChannel }

    private var categoryChoices: [YouTubeHomeFilter] {
        YouTubeHomeFilter.hubCategories.filter { $0.hubSlug != nil }
    }

    private var titleOK: Bool {
        // Auto-Spark and Plus→Spark use caption only; long-form Hubs needs a title.
        if isReelAudience { return true }
        if !isHubAudience { return true }
        return !videoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var kidsOK: Bool {
        if showsChannelDetails { return madeForKids != nil }
        return true
    }

    private var canSubmit: Bool {
        uploadVideoURL != nil && !isPreparingVideo && titleOK && kidsOK
    }

    private var effectiveThumb: UIImage? {
        customThumbImage ?? previewImage
    }

    private var canPostHere: Bool {
        appState.canPostToCountry(country)
    }

    private var navTitle: String {
        if locksToHubs && detectedAsSpark { return MatteryaCopy.newSpark }
        switch audience {
        case .sparks: return MatteryaCopy.newSpark
        case .hubs: return "New channel video"
        case .feed: return "New feed video"
        }
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
                        if detectedAsSpark && locksToHubs {
                            sparkDetectedChip
                        }
                        if !locksToHubs {
                            audiencePicker
                        }
                        if needsCategory {
                            categoryPicker
                        }
                        if isHubAudience && !detectedAsSpark {
                            titleField
                        }
                        captionField
                        if showsChannelDetails {
                            thumbnailSection
                            detailsSection
                        }
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
        .tint(Theme.ink)
        .onAppear {
            if publishAsReel {
                audience = .sparks
            } else if publishToHubChannel {
                audience = .hubs
            } else {
                audience = .feed
            }
        }
        .onChange(of: selectedVideo) { _, item in
            Task { await loadVideo(item) }
        }
        .onChange(of: thumbPickerItem) { _, item in
            Task { await loadCustomThumb(item) }
        }
    }

    private var sparkDetectedChip: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text("Detected as \(MatteryaCopy.spark)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Vertical · under 1 min · publishes on your Hubs channel")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.matteDeep, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private var thumbnailSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("THUMBNAIL")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMuted)
            Text("Shown on \(MatteryaCopy.matteryaHubs) shelves and your channel.")
                .font(.caption2)
                .foregroundStyle(Theme.inkMuted)

            HStack(alignment: .center, spacing: 14) {
                Group {
                    if let thumb = effectiveThumb {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Theme.matteDeep
                    }
                }
                .frame(width: 96, height: detectedAsSpark || isReelAudience ? 170 : 54)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.border, lineWidth: 0.5)
                )

                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $thumbPickerItem, matching: .images) {
                        Text(customThumbImage == nil ? "Upload thumbnail" : "Change thumbnail")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Theme.matte, in: Capsule(style: .continuous))
                            .overlay(Capsule(style: .continuous).stroke(Theme.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)

                    if customThumbImage != nil {
                        Button("Use auto frame") {
                            customThumbImage = nil
                            thumbPickerItem = nil
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DETAILS")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMuted)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text("Made for kids")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Required")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.danger)
                }
                Text("Tell Matterya if this video is made for kids. This affects where it can appear.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                HStack(spacing: 8) {
                    kidsChip(title: "Yes", value: true)
                    kidsChip(title: "No", value: false)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .stroke(
                        kidsOK ? Theme.border : Theme.danger.opacity(0.55),
                        lineWidth: 0.5
                    )
            )

            disclosureToggle(
                title: "Includes paid promotion",
                subtitle: "Turn on if this video includes paid product placement, sponsorship, or promotion.",
                isOn: $hasPaidPromotion
            )

            disclosureToggle(
                title: "Altered or AI-made content",
                subtitle: "Turn on if this video includes realistic altered or AI-made content that could mislead viewers.",
                isOn: $alteredContent
            )
        }
    }

    private func kidsChip(title: String, value: Bool) -> some View {
        Button {
            madeForKids = value
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(madeForKids == value ? Theme.paper : Theme.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(madeForKids == value ? Theme.ink : Theme.matte)
                )
                .overlay {
                    if madeForKids != value {
                        Capsule(style: .continuous).stroke(Theme.border, lineWidth: 0.5)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func disclosureToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            MatteryaSwitch(isOn: isOn)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private var composerHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: isReelAudience ? "sparkles" : "film")
                .font(.title2)
                .foregroundStyle(Theme.ink)
                .frame(width: 48, height: 48)
                .background(Theme.matteDeep, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(destinationHeadline)
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
                    Text(destinationHint)
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

    private var audiencePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHERE")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.inkMuted)

            HStack(spacing: 8) {
                ForEach(VideoPublishAudience.allCases) { option in
                    Button {
                        audience = option
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(audience == option ? Theme.paper : Theme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Text(option.subtitle)
                                .font(.caption2)
                                .foregroundStyle(audience == option ? Theme.paper.opacity(0.8) : Theme.inkMuted)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(
                            audience == option ? Theme.ink : Theme.surface,
                            in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                                .stroke(Theme.border, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("CATEGORY")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkMuted)
                Text("Required")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.danger)
            }
            Text("Helps people find your video on \(MatteryaCopy.matteryaHubs) shelves.")
                .font(.caption2)
                .foregroundStyle(Theme.inkMuted)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: 8)],
                spacing: 8
            ) {
                ForEach(categoryChoices) { filter in
                    Button {
                        selectedCategory = filter
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.icon)
                                .font(.caption.weight(.semibold))
                            Text(filter.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selectedCategory == filter ? Theme.paper : Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(
                            selectedCategory == filter ? Theme.ink : Theme.surface,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().stroke(Theme.border, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
                            .foregroundStyle(Theme.ink)
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

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("TITLE")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkMuted)
                Text("Required")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.danger)
            }
            TextField("Give your video a title", text: $videoTitle)
                .foregroundStyle(Theme.ink)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .stroke(
                            titleOK ? Theme.border : Theme.danger.opacity(0.55),
                            lineWidth: 0.5
                        )
                )
            Text("Every Hubs channel video needs a title so people can find it.")
                .font(.caption2)
                .foregroundStyle(Theme.inkMuted)
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
                        Text(busy ? "Working…" : MatteryaCopy.publishVideo)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Theme.paper)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        canSubmit && !busy && canPostHere ? Theme.ink : Theme.inkMuted,
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

    private var destinationHeadline: String {
        if locksToHubs && detectedAsSpark {
            let name = LivingChannelMarker.parse(from: appState.currentProfile?.bio)
            return name.map { "\(MatteryaCopy.spark) on \($0)" } ?? "\(MatteryaCopy.spark) on your channel"
        }
        switch audience {
        case .sparks:
            if publishToHubChannel {
                let name = LivingChannelMarker.parse(from: appState.currentProfile?.bio)
                return name.map { "\(MatteryaCopy.spark) on \($0)" } ?? "\(MatteryaCopy.spark) on your channel"
            }
            return MatteryaCopy.postToYourFeed
        case .hubs:
            let name = LivingChannelMarker.parse(from: appState.currentProfile?.bio)
            return name.map { "Post to \($0)" } ?? "Post to your channel"
        case .feed:
            return "Post to your feed"
        }
    }

    private var destinationHint: String {
        if locksToHubs && detectedAsSpark {
            return "Vertical short · Sparks + your Hubs channel"
        }
        switch audience {
        case .sparks:
            return publishToHubChannel
                ? MatteryaCopy.sparksOnHubs
                : MatteryaCopy.publishSparkHint
        case .hubs:
            return "Appears on your Hubs channel and as a simple card in the feed."
        case .feed:
            return "Appears in the home feed like a normal post with video."
        }
    }

    private var resolvedHubSlug: String? {
        guard needsCategory else { return nil }
        return selectedCategory.hubSlug ?? selectedCategory.rawValue
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
            customThumbImage = nil
            thumbPickerItem = nil
            let probe = await probeVideoGeometry(preparedURL)
            videoDurationSeconds = probe.duration
            videoAspectHeightOverWidth = probe.aspect
            // Hubs video sheet: vertical (≥0.8) + ≤60s → channel Spark automatically.
            detectedAsSpark = locksToHubs && probe.aspect >= 0.8 && probe.duration > 0 && probe.duration <= 60
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
        customThumbImage = nil
        thumbPickerItem = nil
        detectedAsSpark = false
        videoDurationSeconds = 0
        videoAspectHeightOverWidth = 0
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

    private func loadCustomThumb(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                customThumbImage = image
            }
        } catch {
            errorMessage = "Could not load thumbnail."
        }
    }

    /// Display aspect after preferred transform (height / width). ≥0.8 ≈ vertical / square-ish short.
    private func probeVideoGeometry(_ url: URL) async -> (duration: Double, aspect: Double) {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration).seconds
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                return (duration, 0)
            }
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let transformed = size.applying(transform)
            let width = abs(Double(transformed.width))
            let height = abs(Double(transformed.height))
            let aspect = width > 0 ? height / width : 0
            return (duration, aspect)
        } catch {
            return (0, 0)
        }
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

        guard FileManager.default.fileExists(atPath: uploadVideoURL.path) else {
            busy = false
            uploadPhase = .idle
            uploadProgress = nil
            errorMessage = "Video file is missing. Select the video again."
            return
        }

        if showsChannelDetails, madeForKids == nil {
            busy = false
            uploadPhase = .idle
            uploadProgress = nil
            errorMessage = "Choose whether this video is made for kids."
            return
        }

        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let localVideoURL = uploadVideoURL
        let localMime = videoMimeType
        let localExt = videoFileExtension
        let localPreview = effectiveThumb
        let localCountry = country
        let localProfileCity = profile.cityName
        // Re-assert short→Spark at publish (probe can miss on pick; square/vertical ≤60s must be Spark).
        let shortHubSpark =
            locksToHubs
            && videoDurationSeconds > 0
            && videoDurationSeconds <= 60
            && videoAspectHeightOverWidth >= 0.8
        if shortHubSpark { detectedAsSpark = true }
        let asReel = isReelAudience || shortHubSpark
        let toHub = isHubAudience || (locksToHubs && (detectedAsSpark || shortHubSpark))
        let hubSlug = resolvedHubSlug
        let localKids = madeForKids
        let localPromo = hasPaidPromotion
        let localAI = alteredContent
        let channelBoundSpark = publishToHubChannel || (locksToHubs && (detectedAsSpark || shortHubSpark))

        // Long-form video (feed or hubs): jump to feed with a shadow card while uploading.
        // Sparks publish then open Sparks — they don't pin on the home feed list.
        let landsOnFeed = !asReel
        let placeholderID: String? = landsOnFeed
            ? appState.beginFeedVideoUpload(
                caption: trimmedCaption,
                previewImage: localPreview,
                isHub: toHub
            )
            : nil

        if landsOnFeed {
            // Leave composer immediately — upload continues; feed shows the shadow card.
            busy = false
            dismiss()
        }

        let progressHandler: @Sendable (UploadProgress) -> Void = { progress in
            Task { @MainActor in
                if let placeholderID {
                    HomeFeedStore.shared.updateVideoUpload(
                        id: placeholderID,
                        progress: max(0.05, progress.fractionCompleted * 0.9),
                        phaseLabel: "Uploading"
                    )
                } else {
                    uploadProgress = progress
                }
            }
        }
        let publishingHandler: @Sendable () -> Void = {
            Task { @MainActor in
                if let placeholderID {
                    HomeFeedStore.shared.updateVideoUpload(
                        id: placeholderID,
                        progress: 0.94,
                        phaseLabel: "Publishing"
                    )
                } else {
                    uploadPhase = .publishing
                }
            }
        }

        do {
            let post: CountryPost
            if asReel {
                // Channel Sparks (Plus → Spark or auto-detected Hubs short) stamp the channel.
                let sparkBody = channelBoundSpark
                    ? HubChannelPostMarker.markBody(trimmedCaption)
                    : trimmedCaption
                post = try await PostsService.shared.createReel(
                    authorID: authorID,
                    body: sparkBody,
                    countryName: localCountry.name,
                    countryCode: localCountry.iso,
                    cityName: localProfileCity,
                    videoFileURL: localVideoURL,
                    mimeType: localMime,
                    fileExtension: localExt,
                    thumbnailImage: localPreview,
                    hubSlug: channelBoundSpark ? hubSlug : nil,
                    madeForKids: localKids,
                    hasPaidPromotion: localPromo,
                    alteredContent: localAI,
                    durationSeconds: videoDurationSeconds > 0 ? videoDurationSeconds : nil,
                    onUploadProgress: progressHandler,
                    onPublishing: publishingHandler
                )
            } else if toHub {
                let trimmedTitle = await MainActor.run {
                    videoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard !trimmedTitle.isEmpty else {
                    throw MediaError.uploadFailed("Add a title for your Hubs video.")
                }
                post = try await PostsService.shared.createLivingVideo(
                    authorID: authorID,
                    body: trimmedCaption,
                    countryName: localCountry.name,
                    countryCode: localCountry.iso,
                    cityName: localProfileCity,
                    title: trimmedTitle,
                    videoFileURL: localVideoURL,
                    mimeType: localMime,
                    fileExtension: localExt,
                    thumbnailImage: localPreview,
                    publishToHubChannel: true,
                    hubSlug: hubSlug,
                    madeForKids: localKids,
                    hasPaidPromotion: localPromo,
                    alteredContent: localAI,
                    onUploadProgress: progressHandler,
                    onPublishing: publishingHandler
                )
            } else {
                post = try await PostsService.shared.createFeedVideo(
                    authorID: authorID,
                    body: trimmedCaption,
                    countryName: localCountry.name,
                    countryCode: localCountry.iso,
                    cityName: localProfileCity,
                    videoFileURL: localVideoURL,
                    mimeType: localMime,
                    fileExtension: localExt,
                    thumbnailImage: localPreview,
                    madeForKids: localKids,
                    hasPaidPromotion: localPromo,
                    alteredContent: localAI,
                    onUploadProgress: progressHandler,
                    onPublishing: publishingHandler
                )
            }

            if let placeholderID {
                appState.finishFeedVideoUpload(placeholderID: placeholderID, post: post)
            } else {
                await MainActor.run {
                    busy = false
                    uploadPhase = .idle
                    uploadProgress = nil
                    onPosted?(post)
                    dismiss()
                }
            }
            // Notify hubs/profile even when we already finished via finishFeedVideoUpload.
            if placeholderID == nil {
                await MainActor.run {
                    onPosted?(post)
                }
            }
        } catch {
            let message = error.localizedDescription
            if let placeholderID {
                appState.failFeedVideoUpload(placeholderID: placeholderID, message: message)
            } else {
                await MainActor.run {
                    busy = false
                    uploadPhase = .idle
                    uploadProgress = nil
                    errorMessage = message
                }
            }
        }
    }
}