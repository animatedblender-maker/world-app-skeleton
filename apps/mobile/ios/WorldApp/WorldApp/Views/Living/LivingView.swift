import SwiftUI

/// Matterya Hubs tab — organized video (long-form + sparks).
struct LivingView: View {
    @Environment(AppState.self) private var appState

    /// When presented as a full-screen cover, Hubs hosts its own share sheet.
    var hostsShareSheet = false

    var body: some View {
        Group {
            if hostsShareSheet {
                YouTubeAppView()
                    .sharePostSheet(appState: appState)
            } else {
                YouTubeAppView()
            }
        }
    }
}