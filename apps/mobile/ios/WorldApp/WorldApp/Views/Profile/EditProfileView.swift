import SwiftUI
import PhotosUI
import UIKit

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var displayName = ""
    @State private var username = ""
    @State private var countryName = ""
    @State private var countryCode = ""
    @State private var cityName = ""
    @State private var bio = ""
    @State private var avatarURL: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var busy = false
    @State private var uploadingAvatar = false
    @State private var detectingLocation = false
    @State private var locationStatus = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?
    /// Detached upload job so SwiftUI cancellations / view updates don't hang MainActor.
    @State private var avatarUploadTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Avatar") {
                HStack(spacing: 16) {
                    AvatarView(
                        url: avatarURL ?? appState.currentProfile?.avatarURL,
                        seed: appState.currentProfile?.userID ?? "me",
                        size: 64
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                            HStack {
                                if uploadingAvatar {
                                    ProgressView()
                                }
                                Text(uploadingAvatar ? "Uploading…" : "Change avatar")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(busy || uploadingAvatar)
                        .onChange(of: selectedPhoto) { _, item in
                            guard let item else { return }
                            startAvatarUpload(item)
                        }
                        Text(uploadingAvatar
                             ? "Please wait — photo is uploading…"
                             : "Pick a photo from your library.")
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }

            Section("Identity") {
                TextField("Display name", text: $displayName)
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Location") {
                if detectingLocation {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Detecting your location…")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkMuted)
                    }
                } else if hasDetectedLocation {
                    LabeledContent("Country", value: countryName)
                    if !cityName.isEmpty {
                        LabeledContent("City", value: cityName)
                    }
                    Text("Location is detected automatically and can’t be edited.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                } else {
                    Text(
                        locationStatus.isEmpty
                            ? "Tap below to detect your location from this device."
                            : locationStatus
                    )
                    .font(.footnote)
                    .foregroundStyle(Theme.inkMuted)
                }

                Button(detectingLocation ? "Detecting…" : "Detect location again") {
                    Task { await detectLocation() }
                }
                .disabled(detectingLocation || busy || uploadingAvatar)
            }

            Section("Bio") {
                TextField("Bio", text: $bio, axis: .vertical)
                    .lineLimit(3...6)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.danger)
                        .font(.footnote)
                }
            }
            if let successMessage {
                Section {
                    Text(successMessage)
                        .foregroundStyle(Theme.success)
                        .font(.footnote)
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if busy { ProgressView() }
                        Text(busy ? "Saving…" : "Save Profile")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(busy || uploadingAvatar || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Edit Profile")
        .scrollContentBackground(.hidden)
        .screenBackground()
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .tint(Theme.accentBright)
        .task {
            await loadProfile()
        }
        .onDisappear {
            avatarUploadTask?.cancel()
        }
    }

    private var hasDetectedLocation: Bool {
        let country = countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !country.isEmpty && country != "Unknown"
    }

    private func loadProfile() async {
        if let profile = appState.currentProfile {
            displayName = profile.displayName ?? ""
            username = profile.username ?? ""
            countryName = profile.countryName ?? ""
            countryCode = profile.countryCode ?? ""
            cityName = profile.cityName ?? ""
            bio = LivingChannelMarker.displayBio(from: profile.bio)
            avatarURL = profile.avatarURL
        }
        await detectLocation()
    }

    private func detectLocation() async {
        detectingLocation = true
        locationStatus = ""
        defer { detectingLocation = false }

        guard let coordinate = await LocationService.shared.currentCoordinate() else {
            locationStatus =
                "Location unavailable. Enable Location for Matterya in Settings, then try again."
            return
        }

        do {
            let detected = try await ProfileService.shared.detectLocation(
                lat: coordinate.latitude,
                lng: coordinate.longitude
            )
            countryName = detected.countryName
            countryCode = detected.countryCode
            if let city = detected.cityName, !city.isEmpty {
                cityName = city
            } else {
                cityName = ""
            }
            locationStatus = "Detected: \(detected.countryName)"
        } catch {
            locationStatus = "Could not detect location. Check your connection and try again."
        }
    }

    /// Kick off upload on a free-standing Task so MainActor is free to paint the spinner.
    private func startAvatarUpload(_ item: PhotosPickerItem) {
        avatarUploadTask?.cancel()
        uploadingAvatar = true
        errorMessage = nil
        successMessage = nil

        avatarUploadTask = Task { @MainActor in
            defer {
                if !Task.isCancelled {
                    uploadingAvatar = false
                    selectedPhoto = nil
                }
            }
            do {
                // Yield so SwiftUI can render “Uploading…” before heavy work.
                await Task.yield()
                try Task.checkCancellation()

                let data = try await PhotosPickerMediaLoader.loadJPEGData(
                    from: item,
                    timeoutSeconds: 25,
                    compressionQuality: 0.8,
                    maxEdge: 1024
                )
                try Task.checkCancellation()
                guard !data.isEmpty else {
                    errorMessage = "Couldn't read that photo. Try another image."
                    uploadingAvatar = false
                    selectedPhoto = nil
                    return
                }

                await Task.yield()
                let upload = try await MediaService.shared.uploadAvatar(
                    data: data,
                    fileExtension: "jpg",
                    mimeType: "image/jpeg"
                )
                try Task.checkCancellation()

                let updated = try await ProfileService.shared.updateProfile(avatarURL: upload.url)
                appState.currentProfile = updated
                ContentCache.shared.setProfile(updated)
                avatarURL = updated.avatarURL ?? upload.url
                successMessage = "Profile photo updated."
                appState.showToast("Profile photo updated.", style: .success)
            } catch is CancellationError {
                // View disappeared or new pick — ignore.
            } catch {
                errorMessage = "Avatar upload failed: \(error.localizedDescription)"
            }
            uploadingAvatar = false
            selectedPhoto = nil
        }
    }

    private func save() async {
        busy = true
        errorMessage = nil
        successMessage = nil
        defer { busy = false }

        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Display name is required."
            return
        }

        let existingChannel = LivingChannelMarker.parse(from: appState.currentProfile?.bio)
        let composedBio = LivingChannelMarker.buildBio(
            displayBio: bio,
            channelName: existingChannel
        )

        do {
            let profile = try await ProfileService.shared.updateProfile(
                displayName: name,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                countryName: countryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                countryCode: countryCode.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                cityName: cityName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                bio: composedBio,
                avatarURL: avatarURL
            )
            appState.currentProfile = profile
            ContentCache.shared.setProfile(profile)
            appState.needsProfileSetup = !profile.isComplete
            appState.showToast("Profile saved.", style: .success)
            dismiss()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
