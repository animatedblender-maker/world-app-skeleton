import SwiftUI

struct PhotorealGlobeView: View {
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
            Color.black.ignoresSafeArea()

            if !globeReady {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading Earth…")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
                PhotorealGlobeSceneRepresentable(
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
        _ = PhotorealGlobeBuilder.prepare()
        globeReady = true
    }

    private func loadCountries() async {
        if apiCountries.isEmpty {
            apiCountries = (try? await ProfileService.shared.countries()) ?? []
        }
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
        onSelectCountry(country)
    }
}