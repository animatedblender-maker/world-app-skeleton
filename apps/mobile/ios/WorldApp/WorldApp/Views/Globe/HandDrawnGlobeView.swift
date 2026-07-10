import SwiftUI

struct HandDrawnGlobeView: View {
    @Environment(AppState.self) private var appState

    let onSelectCountry: (Country) -> Void

    @State private var entries: [CountryMapEntry] = []
    @State private var apiCountries: [Country] = []
    @State private var globeReady = false

    private var selectedISO: String? {
        appState.selectedCountry?.iso.uppercased()
    }

    var body: some View {
        ZStack {
            PaperBackground()

            if !globeReady {
                VStack(spacing: 12) {
                    ProgressView().tint(Theme.accent)
                    Text("Painting the world…")
                        .font(.system(.caption, design: .serif))
                        .foregroundStyle(Theme.inkMuted)
                }
            } else {
                HandDrawnGlobeSceneRepresentable(
                    entries: entries,
                    selectedISO: selectedISO,
                    onSelectEntry: selectEntry
                )
                .ignoresSafeArea()
            }
        }
        .task {
            if entries.isEmpty {
                entries = CountryMapData.load()
            }
            if !entries.isEmpty {
                await prepareGlobe()
            }
            await loadCountries()
        }
    }

    private func prepareGlobe() async {
        let loaded = entries
        await Task.detached(priority: .userInitiated) {
            _ = CartoonGlobeTexture.image(for: loaded, selectedISO: nil)
        }.value
        globeReady = true
    }

    private func loadCountries() async {
        apiCountries = (try? await ProfileService.shared.countries()) ?? []
    }

    private func selectEntry(_ entry: CountryMapEntry) {
        let match = apiCountries.first {
            $0.iso.uppercased() == entry.iso2.uppercased()
                || $0.iso.uppercased() == entry.iso3.uppercased()
                || $0.name.caseInsensitiveCompare(entry.name) == .orderedSame
        }
        let country = match ?? Country(
            id: entry.iso2,
            name: entry.name,
            iso: entry.iso2.uppercased(),
            continent: nil,
            centerLat: entry.lat,
            centerLng: entry.lng
        )
        appState.selectCountry(country)
        onSelectCountry(country)
    }
}