import SwiftUI

struct GlobeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            // Presence-only globe — countries are not tappable; all posts live on main feed.
            AppleMapGlobeView(
                resetGlobe: true,
                allowsCountrySelection: false,
                onSelectCountry: { _ in }
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                MatteryaTopBar(showsSearch: true) {
                    appState.searchPrefersCountries = false
                    appState.navigate(to: .search)
                }
                Spacer(minLength: 0)
            }

        }
        .toolbar(.hidden, for: .navigationBar)
    }
}