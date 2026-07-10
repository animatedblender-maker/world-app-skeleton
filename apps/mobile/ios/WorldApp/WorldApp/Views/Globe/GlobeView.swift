import SwiftUI

struct GlobeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            PhotorealGlobeView { country in
                appState.selectCountry(country)
                appState.navigate(to: .countryFeed(country))
            }

            VStack(spacing: 0) {
                MatteryaTopBar(showsSearch: true) {
                    appState.searchPrefersCountries = true
                    appState.navigate(to: .search)
                }
                Spacer(minLength: 0)
            }

            NotificationsOverlay()
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}