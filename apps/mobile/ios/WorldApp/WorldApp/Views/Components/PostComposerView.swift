import SwiftUI
import PhotosUI

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
    @State private var imageData: Data?
    @State private var previewImage: UIImage?
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

    private var canSubmit: Bool {
        !trimmedBody.isEmpty || imageData != nil || appState.quotedSharePostID != nil
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
                        if let quotedEmbed {
                            SharedPostEmbedView(embed: quotedEmbed)
                        }
                        titleField
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
        .tint(Theme.accentBright)
        .task {
            await loadQuotedShare()
        }
        .onDisappear {
            appState.quotedSharePostID = nil
        }
        .onChange(of: selectedPhoto) { _, item in
            Task { await loadSelectedPhoto(item) }
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

                HStack(spacing: 6) {
                    Text(countryFlag(country.iso))
                    Text(MatteryaCopy.postToYourFeed)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
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

            if let previewImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .stroke(Theme.border, lineWidth: 0.5)
                        )

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
            } else {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack(spacing: 14) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title2)
                            .foregroundStyle(Theme.accentBright)
                            .frame(width: 48, height: 48)
                            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Add a photo")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text("High-resolution images look best in the feed.")
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
                .buttonStyle(.plain)
            }
        }
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
                                .tint(.white)
                                .scaleEffect(0.85)
                        }
                        Text(busy ? "Publishing…" : "Publish")
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
                .disabled(busy || !canSubmit || !canPostHere)
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

    private func clearMedia() {
        imageData = nil
        previewImage = nil
        selectedPhoto = nil
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

    private func countryFlag(_ iso: String) -> String {
        let code = iso.uppercased()
        guard code.count == 2 else { return "🌍" }
        let base: UInt32 = 127397
        let scalars = code.unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }
        return String(String.UnicodeScalarView(scalars))
    }

    private func submit() async {
        guard let profile = appState.currentProfile,
              let authorID = AuthService.shared.currentUser?.id else { return }
        guard canPostHere else {
            errorMessage = MatteryaCopy.homeCountryOnlyPost
            return
        }
        guard canSubmit else { return }

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
                        .foregroundStyle(visibility == option ? Theme.accentBright : Theme.inkSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            visibility == option ? Theme.accentSoft : Theme.surface,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(visibility == option ? Theme.accent.opacity(0.45) : Theme.border, lineWidth: 0.5)
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