import SwiftUI
import PhotosUI

struct ProfileSetupView: View {
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
    @State private var detectingLocation = false
    @State private var locationStatus = ""
    @State private var errorMessage: String?
    /// Existing users with name/location already set only need birthdate.
    @State private var birthdateOnly = false
    @State private var loadingProfile = true

    var body: some View {
        NavigationStack {
            Group {
                if loadingProfile {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Loading your profile…")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Form {
                        if birthdateOnly {
                            birthdateOnlySections
                        } else {
                            fullSetupSections
                        }

                        if let errorMessage {
                            Section {
                                Text(errorMessage)
                                    .foregroundStyle(.red)
                            }
                        }

                        Section {
                            Button {
                                Task { await saveProfile() }
                            } label: {
                                HStack(spacing: 8) {
                                    Spacer(minLength: 0)
                                    if busy {
                                        ProgressView()
                                            .tint(Theme.paper)
                                    }
                                    Text(busy ? "Saving…" : (birthdateOnly ? "Save birthday" : "Complete Setup"))
                                    Spacer(minLength: 0)
                                }
                                .matteryaPrimaryFill()
                            }
                            .buttonStyle(.plain)
                            .disabled(busy || !canSave)
                            .opacity(busy || !canSave ? 0.55 : 1)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
                        }
                    }
                }
            }
            .navigationTitle(birthdateOnly ? "Date of birth" : "Profile Setup")
            .scrollContentBackground(.hidden)
        }
        .screenBackground()
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .tint(Theme.ink)
        .task {
            await loadInitialState()
        }
        .onChange(of: appState.currentProfile?.userID) { _, _ in
            // If profile arrives after first paint, re-apply without leaving birthday-only mode blank.
            guard !loadingProfile, let profile = appState.currentProfile else { return }
            apply(profile: profile)
        }
    }

    @ViewBuilder
    private var birthdateOnlySections: some View {
        Section {
            HStack(spacing: 14) {
                ExpandableProfileAvatar(
                    url: avatarURL ?? appState.currentProfile?.avatarURL,
                    seed: appState.currentProfile?.userID
                        ?? AuthService.shared.currentUser?.id
                        ?? "me",
                    size: 56,
                    displayName: displayName.isEmpty
                        ? appState.currentProfile?.displayName
                        : displayName
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName.isEmpty ? "Your profile" : displayName)
                        .font(.headline)
                    if !bio.isEmpty {
                        Text(LivingChannelMarker.displayBio(from: bio))
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                            .lineLimit(2)
                    } else if hasDetectedLocation {
                        Text(cityName.isEmpty ? countryName : "\(cityName), \(countryName)")
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
            Text("We need your date of birth!")
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
        }

        Section("Date of birth") {
            DatePicker(
                "Date of birth",
                selection: $birthdate,
                in: ...Date(),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.wheel)
            .tint(Theme.ink)
            Text("Required. Private — only you can see this.")
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
        }
    }

    @ViewBuilder
    private var fullSetupSections: some View {
        Section("Profile photo") {
            let profileAvatar = avatarURL ?? appState.currentProfile?.avatarURL
            let profileSeed = appState.currentProfile?.userID
                ?? AuthService.shared.currentUser?.id
                ?? "me"
            let profileName = displayName.isEmpty
                ? appState.currentProfile?.displayName
                : displayName
            let photoButtonTitle = profileAvatar == nil ? "Upload photo" : "Change photo"
            HStack(spacing: 16) {
                ExpandableProfileAvatar(
                    url: profileAvatar,
                    seed: profileSeed,
                    size: 72,
                    displayName: profileName
                )
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Text(photoButtonTitle)
                }
                .onChange(of: selectedPhoto) { _, item in
                    Task { await uploadAvatar(item) }
                }
            }
            Text("Add a photo so people recognize you on Matterya.")
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
        }

        Section("Identity") {
            TextField("Display name", text: $displayName)
            TextField("Username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            DatePicker(
                "Date of birth",
                selection: $birthdate,
                in: ...Date(),
                displayedComponents: .date
            )
            .tint(Theme.ink)
            Text("Required. Private — only you can see this.")
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
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
                        ? "We use your device location for your home country."
                        : locationStatus
                )
                .font(.footnote)
                .foregroundStyle(Theme.inkMuted)
            }

            Button(detectingLocation ? "Detecting…" : "Detect location again") {
                Task { await detectLocation() }
            }
            .disabled(detectingLocation || busy)
        }

        Section("Bio") {
            TextField("Tell the world about you…", text: $bio, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private var hasDetectedLocation: Bool {
        let country = countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !country.isEmpty && country != "Unknown"
    }

    private var canSave: Bool {
        if birthdateOnly { return true }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && hasDetectedLocation
    }

    private func loadInitialState() async {
        loadingProfile = true
        errorMessage = nil
        defer { loadingProfile = false }

        // Prefer a fresh network profile so avatar/bio/identity always show.
        var profile = appState.currentProfile
        do {
            if let remote = try await ProfileService.shared.meProfile() {
                profile = remote
                appState.currentProfile = remote
                ContentCache.shared.setProfile(remote)
            }
        } catch {
            // Keep cached profile if network fails; still try to show what we have.
            if profile == nil {
                errorMessage = "Couldn’t load your profile: \(error.localizedDescription)"
            }
        }

        if let profile {
            apply(profile: profile)
        } else if let email = AuthService.shared.currentUser?.email {
            displayName = email.split(separator: "@").first.map(String.init) ?? ""
            birthdateOnly = false
        }

        // Full setup for new users still needs location; birthday-only skips detect.
        if !birthdateOnly {
            await detectLocation()
        }
    }

    private func apply(profile: Profile) {
        displayName = profile.displayName ?? ""
        username = profile.username ?? ""
        countryName = profile.countryName ?? ""
        countryCode = profile.countryCode ?? ""
        cityName = profile.cityName ?? ""
        bio = profile.bio ?? ""
        avatarURL = profile.avatarURL
        if let parsed = Self.parseBirthdate(profile.birthdate) {
            birthdate = parsed
        }
        birthdateOnly = profile.needsBirthdateOnly

        if countryName == "Unknown" {
            // Keep established-profile birthday-only even when country was never set.
            if !birthdateOnly {
                countryName = ""
                countryCode = ""
            }
        }
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

    private func uploadAvatar(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        busy = true
        errorMessage = nil
        defer {
            busy = false
            selectedPhoto = nil
        }
        do {
            await Task.yield()
            let data = try await PhotosPickerMediaLoader.loadJPEGData(
                from: item,
                timeoutSeconds: 25,
                compressionQuality: 0.8,
                maxEdge: 1024
            )
            guard !data.isEmpty else {
                errorMessage = "Couldn't read that photo. Try another image."
                return
            }
            await Task.yield()
            let upload = try await MediaService.shared.uploadAvatar(
                data: data,
                fileExtension: "jpg",
                mimeType: "image/jpeg"
            )
            let updated = try await ProfileService.shared.updateProfile(avatarURL: upload.url)
            appState.currentProfile = updated
            ContentCache.shared.setProfile(updated)
            avatarURL = updated.avatarURL ?? upload.url
        } catch is CancellationError {
            errorMessage = "Avatar upload was cancelled."
        } catch {
            errorMessage = "Avatar upload failed: \(error.localizedDescription)"
        }
    }

    private func saveProfile() async {
        busy = true
        errorMessage = nil
        defer { busy = false }

        let birth = Self.birthdateAPIString(from: birthdate)

        do {
            let profile: Profile
            if birthdateOnly {
                profile = try await ProfileService.shared.updateProfile(birthdate: birth)
            } else {
                let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedCountry = countryName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else {
                    errorMessage = "Display name is required."
                    return
                }
                guard !trimmedCountry.isEmpty, trimmedCountry != "Unknown" else {
                    errorMessage = "Location is required. Tap Detect location and allow access."
                    return
                }
                profile = try await ProfileService.shared.updateProfile(
                    displayName: trimmedName,
                    username: username.nilIfEmpty,
                    countryName: trimmedCountry,
                    countryCode: countryCode.nilIfEmpty,
                    cityName: cityName.nilIfEmpty,
                    bio: bio.nilIfEmpty,
                    birthdate: birth,
                    avatarURL: avatarURL
                )
            }
            appState.currentProfile = profile
            ContentCache.shared.setProfile(profile)
            appState.needsProfileSetup = !profile.isComplete
            if profile.isComplete {
                await appState.refreshProfile()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
