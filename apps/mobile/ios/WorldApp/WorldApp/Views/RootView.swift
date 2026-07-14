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
            } else if !appState.isSessionReady {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(Theme.accent)
                    Text("Loading Matterya…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .screenBackground()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.isAuthenticated)
        .animation(.easeInOut(duration: 0.25), value: appState.needsProfileSetup)
        .fullScreenCover(isPresented: Binding(
            get: { callManager.showFullCallUI },
            set: { presented in
                if presented {
                    callManager.expandCall()
                } else if callManager.isActive || callManager.isConnecting {
                    callManager.minimizeCall()
                } else {
                    callManager.showUI = false
                }
            }
        )) {
            CallOverlayView(callManager: callManager)
                .withAppState(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .socialNotificationsDidChange)) { _ in
            Task { await appState.refreshNotifications() }
        }
        .overlay(alignment: .bottom) {
            CreateMenuOverlay()
        }
        .overlay(alignment: .bottom) {
            if callManager.showCompactCallBar {
                CallMiniBar(callManager: callManager)
                    .padding(.horizontal, 12)
                    .padding(.bottom, Theme.tabBarHeight + 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(250)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: callManager.showCompactCallBar)
        .overlay(alignment: .top) {
            if let toast = appState.toastMessage {
                ToastBanner(message: toast, style: appState.toastStyle)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(300)
            }
        }
        .animation(.easeOut(duration: 0.2), value: appState.toastMessage)
        .onReceive(NotificationCenter.default.publisher(for: .pushDeepLinkRequested)) { notification in
            let info = notification.userInfo ?? [:]
            let type = (info["type"] as? String) ?? ""
            let conversationID = info["conversationId"] as? String
            let postID = info["postId"] as? String
            let username = info["username"] as? String
            appState.handlePushNavigation(
                type: type,
                conversationID: conversationID,
                postID: postID,
                username: username
            )
        }
        .sheet(item: Binding(
            get: { appState.sharePostSheet },
            set: { appState.sharePostSheet = $0 }
        )) { post in
            SharePostSheet(post: post)
                .withAppState(appState)
        }
    }
}