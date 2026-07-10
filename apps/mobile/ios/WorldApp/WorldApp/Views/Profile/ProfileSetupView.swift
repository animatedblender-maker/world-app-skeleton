import SwiftUI

struct ProfileSetupView: View {
    @Environment(AppState.self) private var appState

    @State private var displayName = ""
    @State private var username = ""
    @State private var countryName = ""
    @State private var countryCode = ""
    @State private var cityName = ""
    @State private var bio = ""
    @State private var countries: [Country] = []
    @State private var busy = false
    @State private var detectingLocation = false
    @State private var locationStatus = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Display name", text: $displayName)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Location") {
                    if !locationStatus.isEmpty {
                        Text(locationStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button(detectingLocation ? "Detecting location…" : "Detect my location") {
                        Task { await detectLocation() }
                    }
                    .disabled(detectingLocation || busy)

                    Picker("Country", selection: $countryCode) {
                        Text("Select a country").tag("")
                        ForEach(countries) { country in
                            Text(country.name).tag(country.iso)
                        }
                    }
                    .onChange(of: countryCode) { _, newValue in
                        syncCountryName(for: newValue)
                    }

                    TextField("City", text: $cityName)
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

    private var canSave: Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = resolvedCountryName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !country.isEmpty && country != "Unknown"
    }

    private var resolvedCountryName: String {
        let trimmed = countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != "Unknown" {
            return trimmed
        }
        guard !countryCode.isEmpty else { return trimmed }
        return countries.first(where: { $0.iso == countryCode })?.name ?? trimmed
    }

    private func loadInitialState() async {
        if let profile = appState.currentProfile {
            displayName = profile.displayName ?? ""
            username = profile.username ?? ""
            countryName = profile.countryName ?? ""
            countryCode = profile.countryCode ?? ""
            cityName = profile.cityName ?? ""
            bio = profile.bio ?? ""
        } else if let email = AuthService.shared.currentUser?.email {
            displayName = email.split(separator: "@").first.map(String.init) ?? ""
        }

        if countryName == "Unknown" {
            countryName = ""
            countryCode = ""
        }

        countries = (try? await ProfileService.shared.countries()) ?? []
        syncCountryName(for: countryCode)

        if resolvedCountryName.isEmpty {
            await detectLocation()
        }
    }

    private func syncCountryName(for code: String) {
        guard !code.isEmpty else { return }
        countryName = countries.first(where: { $0.iso == code })?.name ?? countryName
    }

    private func detectLocation() async {
        detectingLocation = true
        locationStatus = ""
        defer { detectingLocation = false }

        guard let coordinate = await LocationService.shared.currentCoordinate() else {
            locationStatus = "Location unavailable. Select your country manually."
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
            }
            locationStatus = "Detected: \(detected.countryName)"
        } catch {
            locationStatus = "Could not detect location. Select your country manually."
        }
    }

    private func saveProfile() async {
        busy = true
        errorMessage = nil
        defer { busy = false }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = resolvedCountryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Display name is required."
            return
        }
        guard !trimmedCountry.isEmpty, trimmedCountry != "Unknown" else {
            errorMessage = "Select a valid country to continue."
            return
        }

        do {
            let profile = try await ProfileService.shared.updateProfile(
                displayName: trimmedName,
                username: username.nilIfEmpty,
                countryName: trimmedCountry,
                countryCode: countryCode.nilIfEmpty,
                cityName: cityName.nilIfEmpty,
                bio: bio.nilIfEmpty
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