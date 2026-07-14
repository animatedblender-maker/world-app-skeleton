import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var appState

    @State private var query = ""
    @State private var countries: [Country] = []
    @State private var profiles: [Profile] = []
    @State private var content: [CountryPost] = []
    @State private var isSearching = false
    @State private var countriesError: String?
    @State private var searchError: String?
    @State private var searchGeneration = 0

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchedCountries: [Country] {
        guard !normalizedQuery.isEmpty else { return countries }
        return MatteryaSearchEngine.searchCountries(countries, query: normalizedQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            if isSearching {
                ProgressView().tint(Theme.accentBright).padding()
                Spacer()
            } else if normalizedQuery.isEmpty {
                exploreCountriesList
            } else {
                resultsList
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Search")
                    .font(.headline.weight(.semibold))
            }
        }
        .task {
            await loadCountries()
            appState.searchPrefersCountries = false
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.inkMuted)
            TextField("Search countries, people, content…", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(Theme.ink)
                .onSubmit { Task { await runSearch() } }
            if !query.isEmpty {
                Button {
                    query = ""
                    profiles = []
                    content = []
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
                content = []
                searchError = nil
                return
            }
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if query == newValue { await runSearch() }
            }
        }
    }

    private var exploreCountriesList: some View {
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
                    Section("Explore countries") {
                        ForEach(countries) { country in
                            countryRow(country)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Theme.canvas)
            }
        }
    }

    private var resultsList: some View {
        Group {
            if let searchError, profiles.isEmpty && content.isEmpty && matchedCountries.isEmpty {
                ContentUnavailableView("Search failed", systemImage: "magnifyingglass", description: Text(searchError))
            } else if profiles.isEmpty && content.isEmpty && matchedCountries.isEmpty {
                ContentUnavailableView(
                    "No results",
                    systemImage: "text.magnifyingglass",
                    description: Text("Try another country, person, or keyword.")
                )
            } else {
                List {
                    if !matchedCountries.isEmpty {
                        Section("Countries") {
                            ForEach(matchedCountries) { country in
                                countryRow(country)
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

                    if !content.isEmpty {
                        Section("Content") {
                            ForEach(content) { post in
                                contentRow(post)
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

    private func countryRow(_ country: Country) -> some View {
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

    private func contentRow(_ post: CountryPost) -> some View {
        Button {
            appState.openPost(post)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                contentThumbnail(post)

                VStack(alignment: .leading, spacing: 6) {
                    Text(post.authorDisplayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.ink)

                    if let headline = post.displayHeadline {
                        Text(headline)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(2)
                    }

                    let excerpt = post.displayExcerpt
                    if !excerpt.isEmpty {
                        Text(excerpt)
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(2)
                    }

                    HStack(spacing: 8) {
                        if let country = post.countryName ?? post.countryCode?.uppercased() {
                            Text(country)
                                .font(.caption2)
                                .foregroundStyle(Theme.inkMuted)
                        }
                        Text(RelativeTime.format(post.createdAt))
                            .font(.caption2)
                            .foregroundStyle(Theme.inkMuted)
                        if post.hasVideo {
                            Label("Video", systemImage: "play.rectangle.fill")
                                .font(.caption2)
                                .foregroundStyle(Theme.inkMuted)
                        } else if post.hasImage {
                            Label("Photo", systemImage: "photo")
                                .font(.caption2)
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func contentThumbnail(_ post: CountryPost) -> some View {
        let size: CGFloat = 56
        if let url = post.feedImageURL, post.hasMedia {
            CachedAsyncImage(url: url, maxPixelSize: size * 2, contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.accentSoft)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: post.hasVideo ? "play.rectangle" : "text.alignleft")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentBright)
                }
        }
    }

    private func profileRow(_ profile: Profile) -> some View {
        HStack(spacing: 12) {
            Button {
                appState.openPublicProfile(username: profile.username, userID: profile.userID)
            } label: {
                HStack(spacing: 12) {
                    AvatarView(url: profile.avatarURL, seed: profile.userID, size: 40)
                    VStack(alignment: .leading) {
                        Text(profile.displayName ?? profile.username ?? "User")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        if let username = profile.username {
                            Text("@\(username)")
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                        } else if let country = profile.countryName {
                            Text(country)
                                .font(.caption)
                                .foregroundStyle(Theme.inkMuted)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                appState.openPlayChannel(
                    authorID: profile.userID,
                    username: profile.username
                )
            } label: {
                Image(systemName: "globe.americas")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentBright)
                    .frame(width: 32, height: 32)
                    .background(Theme.accentSoft, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(MatteryaCopy.matteryaHubs) channel")
        }
    }

    private func countryFlag(_ iso: String) -> String {
        let code = iso.uppercased()
        guard code.count == 2 else { return "🌍" }
        let base: UInt32 = 127397
        let scalars = code.unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }
        return String(String.UnicodeScalarView(scalars))
    }

    private func openCountry(_ country: Country) {
        appState.selectCountry(country)
        appState.selectedTab = .globe
        appState.navigationPath.removeAll()
        appState.navigate(to: .countryFeed(country))
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

        let generation = searchGeneration + 1
        searchGeneration = generation
        isSearching = true
        searchError = nil
        defer {
            if searchGeneration == generation {
                isSearching = false
            }
        }

        var loadedProfiles: [Profile] = []
        var loadedContent: [CountryPost] = []
        var errors: [String] = []

        async let peopleTask: Void = {
            do {
                loadedProfiles = try await ProfileService.shared.searchProfiles(
                    trimmed,
                    limit: MatteryaSearchEngine.peopleLimit
                )
            } catch {
                errors.append(error.localizedDescription)
            }
        }()

        async let contentTask: Void = {
            do {
                loadedContent = try await PostsService.shared.searchPosts(
                    trimmed,
                    limit: MatteryaSearchEngine.contentLimit
                )
            } catch {
                errors.append(error.localizedDescription)
            }
        }()

        _ = await (peopleTask, contentTask)
        guard searchGeneration == generation else { return }

        profiles = loadedProfiles
        content = loadedContent

        if profiles.isEmpty && content.isEmpty && matchedCountries.isEmpty, !errors.isEmpty {
            searchError = errors.first
        }
    }
}