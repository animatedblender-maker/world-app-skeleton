import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            // Order matters: never show Auth when a persisted session exists.
            // Returning users hydrate isAuthenticated + isSessionReady in AppState.init.
            if appState.isAuthenticated, appState.needsProfileSetup {
                ProfileSetupView()
            } else if appState.isAuthenticated, appState.isSessionReady {
                authenticatedShell
            } else if appState.isAuthenticated {
                // Rare: session known but shell not marked ready yet (e.g. mid-login).
                sessionRestoringSplash
            } else {
                // Logged out or brand-new install only.
                AuthView()
            }
        }
        // Animate real login/logout only — not cold-launch restore (already correct state).
        .animation(.easeInOut(duration: 0.22), value: appState.isAuthenticated)
        .animation(.easeInOut(duration: 0.22), value: appState.needsProfileSetup)
        .animation(.easeInOut(duration: 0.18), value: appState.isSessionReady)
        .onChange(of: appState.isSessionReady) { _, ready in
            if ready { appState.flushPendingPushRoute() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .socialNotificationsDidChange)) { _ in
            Task { await appState.refreshNotifications() }
        }
        .overlay(alignment: .bottom) {
            if appState.isAuthenticated {
                CreateMenuOverlay()
            }
        }
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
    }

    /// Brief splash only while a known session finishes marking the shell ready.
    private var sessionRestoringSplash: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Theme.accent)
            Text("Loading Matterya…")
                .font(.subheadline)
                .foregroundStyle(Theme.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }

    /// Call stack only exists once signed in — keeps login typing responsive.
    @ViewBuilder
    private var authenticatedShell: some View {
        @Bindable var callManager = CallSessionManager.shared
        MainTabView()
            .onAppear {
                appState.flushPendingPushRoute()
            }
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
    }
}
