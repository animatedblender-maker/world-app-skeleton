import AVFoundation
import PhotosUI
import SwiftUI

struct ReelComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let country: Country
    var publishAsReel: Bool = true
    var onPosted: ((CountryPost) -> Void)?

    @State private var caption = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var selectedVideo: PhotosPickerItem?
    @State private var videoData: Data?
    @State private var previewImage: UIImage?

    private var canSubmit: Bool { videoData != nil }

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
                Text(publishAsReel ? "Vertical video works best" : "Shows in feed and Living")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
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

            if let previewImage {
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
        .overlay(alignment: .bottomTrailing) {
            PhotosPicker(selection: $selectedVideo, matching: .videos) {
                Text(videoData == nil ? "Select video" : "Change video")
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
        HStack {
            Text(canPostHere ? "Ready to publish" : "Home country only")
                .font(.caption.weight(.semibold))
                .foregroundStyle(canPostHere ? .white : Theme.danger)
            Spacer()
            Button {
                Task { await submit() }
            } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white).scaleEffect(0.85) }
                    Text(busy ? "Publishing…" : (publishAsReel ? "Publish reel" : "Publish video"))
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(canSubmit && !busy && canPostHere ? Theme.facebookBlue : Color.white.opacity(0.25), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(busy || !canSubmit || !canPostHere)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 14)
        .background(.black.opacity(0.92))
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
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw MediaError.uploadFailed("Could not read video.")
            }
            videoData = data
            previewImage = await generateThumbnail(from: data)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            videoData = nil
            previewImage = nil
        }
    }

    private func generateThumbnail(from data: Data) async -> UIImage? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try? data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func submit() async {
        guard let profile = appState.currentProfile,
              let authorID = AuthService.shared.currentUser?.id,
              let videoData,
              canPostHere else { return }

        busy = true
        errorMessage = nil
        defer { busy = false }

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
                    videoData: videoData
                )
            } else {
                post = try await PostsService.shared.createLivingVideo(
                    authorID: authorID,
                    body: trimmedCaption,
                    countryName: country.name,
                    countryCode: country.iso,
                    cityName: profile.cityName,
                    videoData: videoData
                )
            }
            onPosted?(post)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}