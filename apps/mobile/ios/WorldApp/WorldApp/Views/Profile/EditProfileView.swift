import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var displayName = ""
    @State private var username = ""
    @State private var countryName = ""
    @State private var countryCode = ""
    @State private var cityName = ""
    @State private var bio = ""
    @State private var channelEnabled = false
    @State private var channelName = ""
    @State private var countries: [Country] = []
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var busy = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Avatar") {
                HStack {
                    ExpandableProfileAvatar(
                        url: appState.currentProfile?.avatarURL,
                        seed: appState.currentProfile?.userID ?? "me",
                        size: 64,
                        displayName: appState.currentProfile?.displayName
                    )
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Text("Change avatar")
                    }
                    .onChange(of: selectedPhoto) { _, item in
                        Task { await uploadAvatar(item) }
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
                Picker("Country", selection: $countryCode) {
                    Text("Select").tag("")
                    ForEach(countries) { country in
                        Text(country.name).tag(country.iso)
                    }
                }
                .onChange(of: countryCode) { _, code in
                    countryName = countries.first(where: { $0.iso == code })?.name ?? ""
                }
                TextField("City", text: $cityName)
            }

            Section("Bio") {
                TextField("Bio", text: $bio, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Living channel") {
                Toggle("Publish as a channel", isOn: $channelEnabled)
                if channelEnabled {
                    TextField("Channel name", text: $channelName)
                    Text("Your feed videos still appear in Home. Channels are optional and show up in Living → Channels.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                } else {
                    Text("Without a channel, your videos still appear in the home feed and Living.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section {
                Button(busy ? "Saving…" : "Save Profile") { Task { await save() } }
                    .disabled(busy)
            }
        }
        .navigationTitle("Edit Profile")
        .scrollContentBackground(.hidden)
        .screenBackground()
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .tint(Theme.accentBright)
        .task {
            if let profile = appState.currentProfile {
                displayName = profile.displayName ?? ""
                username = profile.username ?? ""
                countryName = profile.countryName ?? ""
                countryCode = profile.countryCode ?? ""
                cityName = profile.cityName ?? ""
                bio = LivingChannelMarker.displayBio(from: profile.bio)
                channelName = LivingChannelMarker.parse(from: profile.bio) ?? ""
                channelEnabled = !(channelName.isEmpty)
            }
            countries = (try? await ProfileService.shared.countries()) ?? []
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem?) async {
        guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
        busy = true
        defer { busy = false }
        do {
            let upload = try await MediaService.shared.uploadAvatar(data: data, fileExtension: "jpg", mimeType: "image/jpeg")
            let updated = try await ProfileService.shared.updateProfile(avatarURL: upload.url)
            appState.currentProfile = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let profile = try await ProfileService.shared.updateProfile(
                displayName: displayName.nilIfEmpty,
                username: username.nilIfEmpty,
                countryName: countryName.nilIfEmpty,
                countryCode: countryCode.nilIfEmpty,
                cityName: cityName.nilIfEmpty,
                bio: LivingChannelMarker.buildBio(
                    displayBio: bio,
                    channelName: channelEnabled ? channelName : nil
                ).nilIfEmpty
            )
            appState.currentProfile = profile
            dismiss()
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