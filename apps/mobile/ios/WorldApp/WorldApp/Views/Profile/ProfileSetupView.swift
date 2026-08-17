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
    @State private var avatarURL: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var busy = false
    @State private var detectingLocation = false
    @State private var locationStatus = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
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

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(busy ? "Saving…" : "Complete Setup") {
                        Task { await saveProfile() }
                    }
                    .disabled(busy || !canSave)
                }
            }
            .navigationTitle("Profile Setup")
            .scrollContentBackground(.hidden)
        }
        .screenBackground()
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .tint(Theme.accentBright)
        .task {
            await loadInitialState()
        }
    }

    private var hasDetectedLocation: Bool {
        let country = countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !country.isEmpty && country != "Unknown"
    }

    private var canSave: Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && hasDetectedLocation
    }

    private func loadInitialState() async {
        if let profile = appState.currentProfile {
            displayName = profile.displayName ?? ""
            username = profile.username ?? ""
            countryName = profile.countryName ?? ""
            countryCode = profile.countryCode ?? ""
            cityName = profile.cityName ?? ""
            bio = profile.bio ?? ""
            avatarURL = profile.avatarURL
        } else if let email = AuthService.shared.currentUser?.email {
            displayName = email.split(separator: "@").first.map(String.init) ?? ""
        }

        if countryName == "Unknown" {
            countryName = ""
            countryCode = ""
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

        do {
            let profile = try await ProfileService.shared.updateProfile(
                displayName: trimmedName,
                username: username.nilIfEmpty,
                countryName: trimmedCountry,
                countryCode: countryCode.nilIfEmpty,
                cityName: cityName.nilIfEmpty,
                bio: bio.nilIfEmpty,
                avatarURL: avatarURL
            )
            appState.currentProfile = profile
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
