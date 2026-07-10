import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Bindable private var callManager = CallSessionManager.shared

    var body: some View {
        Group {
            if !appState.isAuthenticated {
                AuthView()
            } else if appState.needsProfileSetup {
                ProfileSetupView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.isAuthenticated)
        .animation(.easeInOut(duration: 0.25), value: appState.needsProfileSetup)
        .fullScreenCover(isPresented: Binding(
            get: { callManager.showUI },
            set: { callManager.showUI = $0 }
        )) {
            CallOverlayView(callManager: callManager)
                .environment(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .socialNotificationsDidChange)) { _ in
            Task { await appState.refreshNotifications() }
        }
        .onChange(of: callManager.conversationID) { _, conversationID in
            if callManager.isIncoming, let conversationID {
                appState.pendingConversationID = conversationID
            }
        }
    }
}