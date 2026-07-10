import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var appState

    @State private var query = ""
    @State private var browseMode: BrowseMode = .search
    @State private var countries: [Country] = []
    @State private var profiles: [Profile] = []
    @State private var posts: [CountryPost] = []
    @State private var isSearching = false
    @State private var countriesError: String?
    @State private var searchError: String?

    var body: some View {
        VStack(spacing: 0) {
            searchField
            modeToggle

            if isSearching {
                ProgressView().tint(Theme.accentBright).padding()
                Spacer()
            } else if browseMode == .people {
                peopleBrowseList
            } else if shouldShowCountryBrowse {
                countriesBrowseList
            } else {
                resultsList
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                MenuToolbarButton()
            }
            ToolbarItem(placement: .principal) {
                Text("Search")
                    .font(.headline.weight(.semibold))
            }
        }
        .task {
            await loadCountries()
            if appState.searchPrefersCountries {
                browseMode = .countries
                appState.searchPrefersCountries = false
            }
        }
    }

    private var shouldShowCountryBrowse: Bool {
        browseMode == .countries || normalizedQuery.isEmpty
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var countriesBrowseList: some View {
        Group {
            if let countriesError, countries.isEmpty {
                ContentUnavailableView(
                    "Countries unavailable",
                    systemImage: "globe",
                    description: Text(countriesError)
                )
            } else if countries.isEmpty {
                ProgressView("Loading countries…")
            } else {
                List {
                    Section(browseMode == .countries ? "Explore countries" : "Countries") {
                        ForEach(displayedCountries) { country in
                            Button {
                                openCountry(country)
                            } label: {
                                HStack(spacing: 12) {
                                    Text(countryFlag(country.iso))
                                        .font(.title2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(country.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Theme.ink)
                                        Text(country.iso)
                                            .font(.caption)
                                            .foregroundStyle(Theme.inkMuted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.inkMuted)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Theme.canvas)
            }
        }
    }

    private var displayedCountries: [Country] {
        let needle = normalizedQuery.lowercased()
        guard !needle.isEmpty else { return countries }
        return countries.filter {
            $0.name.lowercased().contains(needle) || $0.iso.lowercased().contains(needle)
        }
    }

    private func countryFlag(_ iso: String) -> String {
        let code = iso.uppercased()
        guard code.count == 2 else { return "🌍" }
        let base: UInt32 = 127397
        let scalars = code.unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }
        return String(String.UnicodeScalarView(scalars))
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.inkMuted)
            TextField("Search countries, people, posts…", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Theme.ink)
                .onSubmit { Task { await runSearch() } }
            if !query.isEmpty {
                Button {
                    query = ""
                    profiles = []
                    posts = []
                    searchError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.inkMuted)
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
        .shadow(color: Theme.ink.opacity(0.04), radius: 12, y: 4)
        .padding(Theme.pagePadding)
        .onChange(of: query) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                profiles = []
                posts = []
                searchError = nil
                return
            }
            if browseMode == .countries {
                browseMode = .search
            }
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if query == newValue { await runSearch() }
            }
        }
    }

    private var modeToggle: some View {
        Picker("Mode", selection: $browseMode) {
            Text("Countries").tag(BrowseMode.countries)
            Text("Search").tag(BrowseMode.search)
            Text("People").tag(BrowseMode.people)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 8)
        .onChange(of: browseMode) { _, mode in
            if mode == .people {
                Task { await loadPeopleBrowse() }
            } else if mode == .search, !normalizedQuery.isEmpty {
                Task { await runSearch() }
            }
        }
    }

    private enum BrowseMode: Hashable {
        case countries, search, people
    }

    private var resultsList: some View {
        Group {
            if let searchError, profiles.isEmpty && posts.isEmpty && matchedCountries.isEmpty {
                ContentUnavailableView("Search failed", systemImage: "magnifyingglass", description: Text(searchError))
            } else if profiles.isEmpty && posts.isEmpty && matchedCountries.isEmpty {
                ContentUnavailableView(
                    "No results",
                    systemImage: "text.magnifyingglass",
                    description: Text("Try another name, country, or keyword.")
                )
            } else {
                List {
                    if !matchedCountries.isEmpty {
                        Section("Countries") {
                            ForEach(matchedCountries) { country in
                                Button {
                                    openCountry(country)
                                } label: {
                                    HStack {
                                        Text(country.name).foregroundStyle(Theme.ink)
                                        Spacer()
                                        Text(country.iso).foregroundStyle(Theme.inkMuted)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !profiles.isEmpty {
                        Section("People") {
                            ForEach(profiles) { profile in
                                HStack {
                                    profileRow(profile)
                                    Spacer()
                                    if !profile.isDemoUser, profile.userID != appState.currentProfile?.userID {
                                        FollowButton(userID: profile.userID)
                                    }
                                }
                            }
                        }
                    }

                    if !posts.isEmpty {
                        Section("Posts") {
                            ForEach(posts) { post in
                                Button {
                                    appState.navigate(to: .post(post.id))
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(post.authorDisplayName)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Theme.ink)
                                        Text(post.displayHeadline)
                                            .font(.subheadline)
                                            .foregroundStyle(Theme.inkSecondary)
                                            .lineLimit(3)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Theme.canvas)
            }
        }
    }

    private var peopleBrowseList: some View {
        Group {
            if let searchError, profiles.isEmpty {
                ContentUnavailableView("People unavailable", systemImage: "person.2", description: Text(searchError))
            } else if profiles.isEmpty {
                ProgressView("Loading people…")
            } else {
                List {
                    ForEach(profiles) { profile in
                        HStack {
                            profileRow(profile)
                            Spacer()
                            if !profile.isDemoUser, profile.userID != appState.currentProfile?.userID {
                                FollowButton(userID: profile.userID)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Theme.canvas)
            }
        }
    }

    private func profileRow(_ profile: Profile) -> some View {
        Button {
            if let username = profile.username {
                appState.navigate(to: .publicProfile(username: username))
            }
        } label: {
            HStack(spacing: 12) {
                AvatarView(url: profile.avatarURL, seed: profile.userID, size: 40)
                VStack(alignment: .leading) {
                    Text(profile.displayName ?? profile.username ?? "User")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    if let country = profile.countryName {
                        Text(country)
                            .font(.caption)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var matchedCountries: [Country] {
        let needle = normalizedQuery.lowercased()
        guard !needle.isEmpty else { return [] }
        return countries.filter {
            $0.name.lowercased().contains(needle) || $0.iso.lowercased().contains(needle)
        }.prefix(10).map { $0 }
    }

    private func openCountry(_ country: Country) {
        appState.selectCountry(country)
    }

    private func loadCountries() async {
        countriesError = nil
        do {
            countries = try await ProfileService.shared.countries()
        } catch {
            countries = []
            countriesError = error.localizedDescription
        }
    }

    private func runSearch() async {
        let trimmed = normalizedQuery
        guard !trimmed.isEmpty else { return }
        isSearching = true
        searchError = nil
        defer { isSearching = false }

        var loadedProfiles: [Profile] = []
        var loadedPosts: [CountryPost] = []
        var errors: [String] = []

        do {
            loadedProfiles = try await ProfileService.shared.searchProfiles(trimmed, limit: 12)
        } catch {
            errors.append(error.localizedDescription)
        }

        do {
            loadedPosts = try await PostsService.shared.searchPosts(trimmed, limit: 12)
        } catch {
            errors.append(error.localizedDescription)
        }

        profiles = loadedProfiles
        posts = loadedPosts

        if loadedProfiles.isEmpty && loadedPosts.isEmpty && matchedCountries.isEmpty, !errors.isEmpty {
            searchError = errors.first
        }
    }

    private func loadPeopleBrowse() async {
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            profiles = try await ProfileService.shared.browseProfiles(limit: 40, offset: 0)
        } catch {
            profiles = []
            searchError = error.localizedDescription
        }
    }
}