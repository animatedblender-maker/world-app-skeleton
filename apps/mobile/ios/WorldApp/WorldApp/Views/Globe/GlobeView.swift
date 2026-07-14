import SwiftUI

struct GlobeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            AppleMapGlobeView(resetGlobe: appState.selectedCountry == nil) { country in
                appState.selectCountry(country)
                appState.navigate(to: .countryFeed(country))
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                MatteryaTopBar(showsSearch: true) {
                    appState.searchPrefersCountries = true
                    appState.navigate(to: .search)
                }
                Spacer(minLength: 0)
            }

        }
        .toolbar(.hidden, for: .navigationBar)
    }
}