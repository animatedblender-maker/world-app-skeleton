import PhotosUI
import SwiftUI

/// First-time Hubs channel creation: name, photo, about.
struct ChannelSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    /// After a successful setup, open the hub video composer.
    var onFinished: (() -> Void)?

    @State private var channelName = ""
    @State private var about = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var busy = false
    @State private var errorMessage: String?
    /// Local snapshot so PhotosPicker label stays free of MainActor isolation issues.
    @State private var avatarURL: String?
    @State private var profileUserID = "me"
    @State private var profileDisplayName: String?

    private var canSave: Bool {
        !channelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
    }

    private var photoButtonTitle: String {
        avatarURL == nil ? "Add photo" : "Change photo"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("CHANNEL PHOTO")
                        HStack(spacing: 16) {
                            ExpandableProfileAvatar(
                                url: avatarURL,
                                seed: profileUserID,
                                size: 72,
                                displayName: channelName.isEmpty ? profileDisplayName : channelName
                            )
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Text(photoButtonTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.accentBright)
                            }
                            .onChange(of: selectedPhoto) { _, item in
                                Task { await uploadAvatar(item) }
                            }
                        }
                        Text("This photo shows on your Hubs channel and profile.")
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("CHANNEL NAME")
                        TextField("e.g. Travel with Maya", text: $channelName)
                            .padding(14)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                                    .stroke(Theme.border, lineWidth: 0.5)
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("ABOUT")
                        TextField("What is your channel about?", text: $about, axis: .vertical)
                            .lineLimit(3...8)
                            .padding(14)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                                    .stroke(Theme.border, lineWidth: 0.5)
                            )
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? "Creating…" : "Create channel")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(canSave ? Theme.accentBright : Theme.inkMuted, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .padding(.top, 8)
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.vertical, 20)
            }
            .background(Theme.canvas)
            .navigationTitle("Create your channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(Theme.accentBright)
        .task {
            syncFromProfile()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            MatteryaHubsLogoView(size: 56)
            Text("Publish to Matterya Hubs")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("Set up a channel name, photo, and about. Then you can post long-form videos to Hubs — separate from normal feed videos.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkMuted)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(Theme.inkMuted)
    }

    @MainActor
    private func syncFromProfile() {
        let profile = appState.currentProfile
        avatarURL = profile?.avatarURL
        profileUserID = profile?.userID ?? "me"
        profileDisplayName = profile?.displayName
        if let existing = LivingChannelMarker.parse(from: profile?.bio) {
            channelName = existing
        }
        about = LivingChannelMarker.displayBio(from: profile?.bio)
    }

    @MainActor
    private func uploadAvatar(_ item: PhotosPickerItem?) async {
        guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
        busy = true
        defer { busy = false }
        do {
            let upload = try await MediaService.shared.uploadAvatar(
                data: data,
                fileExtension: "jpg",
                mimeType: "image/jpeg"
            )
            let updated = try await ProfileService.shared.updateProfile(avatarURL: upload.url)
            appState.currentProfile = updated
            avatarURL = updated.avatarURL
            profileUserID = updated.userID
            profileDisplayName = updated.displayName
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        let name = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let aboutText = about.trimmingCharacters(in: .whitespacesAndNewlines)
            let profile = try await ProfileService.shared.updateProfile(
                bio: LivingChannelMarker.buildBio(
                    displayBio: aboutText,
                    channelName: name
                ).nilIfEmpty
            )
            appState.currentProfile = profile
            dismiss()
            onFinished?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
