import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AnonymousComposerView: View {
    let spaceId: String
    let spaceTitle: String

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var store = AnonymousStore.shared
    @State private var isPublishing = false

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedVideo: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var imageData: Data?
    @State private var videoFileURL: URL?
    @State private var isPreparingVideo = false

    private var canSubmit: Bool {
        let hasText = !store.composerBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !store.composerTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasMedia = imageData != nil || videoFileURL != nil
        return (hasText || hasMedia) && !isPublishing && !isPreparingVideo
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Posting in \(spaceTitle)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)

                    TextField("Title (optional)", text: Binding(
                        get: { store.composerTitle },
                        set: { store.composerTitle = $0 }
                    ))
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.controlRadius)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )

                    ZStack(alignment: .topLeading) {
                        if store.composerBody.isEmpty {
                            Text("Share something…")
                                .foregroundStyle(Theme.inkMuted)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                        }
                        TextEditor(text: Binding(
                            get: { store.composerBody },
                            set: { store.composerBody = $0 }
                        ))
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.controlRadius)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )

                    mediaSection

                    Text(MatteryaCopy.anonymousComposerPrivacyNudge)
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
                .padding(Theme.pagePadding)
            }
            .screenBackground()
            .navigationTitle("New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isPublishing ? "Posting…" : "Post") {
                        Task { await publish() }
                    }
                    .foregroundStyle(Theme.ink)
                    .disabled(!canSubmit)
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                Task { await loadPhoto(item) }
            }
            .onChange(of: selectedVideo) { _, item in
                Task { await loadVideo(item) }
            }
            .onDisappear {
                clearTempVideo()
            }
        }
    }

    @ViewBuilder
    private var mediaSection: some View {
        if let previewImage {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )
                clearMediaButton
            }
        } else if videoFileURL != nil {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.matteDeep)
                    .frame(height: 160)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "video.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.ink)
                            Text(isPreparingVideo ? "Preparing video…" : "Video ready")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )
                clearMediaButton
            }
        } else {
            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    mediaChip(title: "Photo", systemImage: "photo")
                }
                .buttonStyle(.plain)

                PhotosPicker(selection: $selectedVideo, matching: .videos) {
                    mediaChip(title: "Video", systemImage: "video")
                }
                .buttonStyle(.plain)
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

    private func mediaChip(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.matteDeep, in: Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 0.5))
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        clearTempVideo()
        videoFileURL = nil
        selectedVideo = nil
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else { return }
            let jpeg = (try? PhotosPickerMediaLoader.normalizeToJPEG(raw, quality: 0.84, maxEdge: 2048)) ?? raw
            imageData = jpeg
            previewImage = UIImage(data: jpeg)
            selectedPhoto = nil
        } catch {
            appState.showToast(error.localizedDescription, style: .error)
            clearMedia()
        }
    }

    private func loadVideo(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        imageData = nil
        previewImage = nil
        selectedPhoto = nil
        isPreparingVideo = true
        defer { isPreparingVideo = false }
        do {
            guard let movie = try await item.loadTransferable(type: MovieFile.self) else {
                appState.showToast("Couldn’t read that video.", style: .error)
                return
            }
            clearTempVideo()
            videoFileURL = movie.url
            selectedVideo = nil
        } catch {
            appState.showToast(error.localizedDescription, style: .error)
            clearMedia()
        }
    }

    private func clearMedia() {
        imageData = nil
        previewImage = nil
        selectedPhoto = nil
        selectedVideo = nil
        clearTempVideo()
        videoFileURL = nil
    }

    private func clearTempVideo() {
        if let videoFileURL {
            try? FileManager.default.removeItem(at: videoFileURL)
        }
    }

    private func publish() async {
        guard canSubmit else { return }
        isPublishing = true
        defer { isPublishing = false }

        var mediaType: String?
        var mediaURL: String?
        let wantedMedia = imageData != nil || videoFileURL != nil
        do {
            if let imageData {
                let upload = try await MediaService.shared.uploadPostMedia(
                    data: imageData,
                    fileExtension: "jpg",
                    mimeType: "image/jpeg"
                )
                mediaType = "image"
                mediaURL = upload.publicURL
            } else if let videoFileURL {
                let upload = try await MediaService.shared.uploadPostMedia(
                    fileURL: videoFileURL,
                    fileExtension: videoFileURL.pathExtension.isEmpty ? "mp4" : videoFileURL.pathExtension,
                    mimeType: "video/mp4"
                )
                mediaType = "video"
                mediaURL = upload.publicURL
            }
        } catch {
            appState.showToast(error.localizedDescription, style: .error)
            return
        }
        if wantedMedia, mediaURL == nil || mediaURL?.isEmpty == true {
            appState.showToast("Photo/video didn’t upload. Try again.", style: .error)
            return
        }

        if let posted = await store.publishPost(
            spaceId: spaceId,
            mediaType: mediaType,
            mediaURL: mediaURL,
            thumbURL: nil
        ) {
            if wantedMedia, posted.mediaURL == nil || posted.mediaURL?.isEmpty == true {
                appState.showToast("Posted, but media didn’t save. Open the Space to check.", style: .error)
            } else {
                appState.showToast("Posted", style: .success)
            }
            clearMedia()
            dismiss()
        } else if let err = store.consumeError() {
            appState.showToast(err, style: .error)
        }
    }
}

/// Minimal transferable for PhotosPicker videos (copies into a temp file).
private struct MovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mp4" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("masquerade-\(UUID().uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: received.file, to: dest)
            return MovieFile(url: dest)
        }
    }
}
