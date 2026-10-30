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
    @State private var birthdate = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                editSection(title: "Avatar") {
                    HStack(spacing: 16) {
                        AvatarView(
                            url: avatarURL ?? appState.currentProfile?.avatarURL,
                            seed: appState.currentProfile?.userID ?? "me",
                            size: 72
                        )
                        VStack(alignment: .leading, spacing: 10) {
                            PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                                HStack(spacing: 8) {
                                    if uploadingAvatar {
                                        ProgressView().tint(Theme.ink)
                                    }
                                    Text(uploadingAvatar ? "Uploading…" : "Change avatar")
                                }
                                .matteryaSecondaryFill()
                            }
                            .buttonStyle(.plain)
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

                editSection(title: "Identity") {
                    matteryaField(title: "Display name", text: $displayName, autocap: .words)
                    matteryaField(
                        title: "Username",
                        text: $username,
                        autocap: .never,
                        disableAutocorrect: true
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Date of birth")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                        DatePicker(
                            "",
                            selection: $birthdate,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(Theme.ink)
                        Text("Private — only you can see this.")
                            .font(.caption2)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }

                editSection(title: "Location") {
                    if detectingLocation {
                        HStack(spacing: 10) {
                            ProgressView().tint(Theme.ink)
                            Text("Detecting your location…")
                                .font(.subheadline)
                                .foregroundStyle(Theme.inkMuted)
                        }
                        .padding(.vertical, 4)
                    } else if hasDetectedLocation {
                        settingsInfoLine("Country", countryName)
                        if !cityName.isEmpty {
                            settingsInfoLine("City", cityName)
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

                    Button {
                        Task { await detectLocation() }
                    } label: {
                        Text(detectingLocation ? "Detecting…" : "Detect location again")
                            .matteryaSecondaryFill()
                    }
                    .buttonStyle(.plain)
                    .disabled(detectingLocation || busy || uploadingAvatar)
                }

                editSection(title: "Bio") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bio")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkMuted)
                        TextField("Bio", text: $bio, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(
                                Theme.matteDeep,
                                in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                                    .stroke(Theme.border, lineWidth: 0.5)
                            )
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.danger)
                        .font(.footnote)
                }
                if let successMessage {
                    Text(successMessage)
                        .foregroundStyle(Theme.success)
                        .font(.footnote)
                }

                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if busy { ProgressView().tint(Theme.paper) }
                        Text(busy ? "Saving…" : "Save profile")
                        Spacer()
                    }
                    .matteryaPrimaryFill()
                }
                .buttonStyle(.plain)
                .disabled(busy || uploadingAvatar || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(
                    busy || uploadingAvatar || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? 0.55 : 1
                )

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .matteryaSecondaryFill()
                }
                .buttonStyle(.plain)
                .disabled(busy || uploadingAvatar)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 18)
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.canvas)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .tint(Theme.ink)
        .task {
            await loadProfile()
        }
        .onDisappear {
            avatarUploadTask?.cancel()
        }
    }

    // MARK: - Matterya chrome

    @ViewBuilder
    private func editSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.border.opacity(0.85), lineWidth: 0.5)
            )
        }
    }

    private func matteryaField(
        title: String,
        text: Binding<String>,
        autocap: TextInputAutocapitalization = .sentences,
        disableAutocorrect: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
            TextField(title, text: text)
                .textInputAutocapitalization(autocap)
                .autocorrectionDisabled(disableAutocorrect)
                .padding(12)
                .background(
                    Theme.matteDeep,
                    in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .stroke(Theme.border, lineWidth: 0.5)
                )
        }
    }

    private func settingsInfoLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.trailing)
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
            if let parsed = Self.parseBirthdate(profile.birthdate) {
                birthdate = parsed
            }
        }
        await detectLocation()
    }

    private static func parseBirthdate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(raw.prefix(10)))
    }

    private static func birthdateAPIString(from date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
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

                let publicURL = MediaService.normalizedAvatarURL(upload.url) ?? upload.url
                let updated = try await ProfileService.shared.updateProfile(avatarURL: publicURL)
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
                birthdate: Self.birthdateAPIString(from: birthdate),
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
