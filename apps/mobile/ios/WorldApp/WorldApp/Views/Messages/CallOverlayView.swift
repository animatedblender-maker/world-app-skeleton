import LiveKit
import SwiftUI

struct CallOverlayView: View {
    @Environment(AppState.self) private var appState
    @Bindable var callManager: CallSessionManager

    @State private var dragOffset: CGFloat = 0

    private var canDragToMinimize: Bool {
        callManager.isActive || callManager.isConnecting
    }

    var body: some View {
        ZStack {
            background

            if callManager.callKind == .video {
                videoLayout
            } else {
                audioLayout
            }

            VStack(spacing: 0) {
                if canDragToMinimize {
                    callDragHandle
                }
                topChrome
                Spacer(minLength: 0)
                bottomChrome
            }
        }
        .offset(y: dragOffset)
        .scaleEffect(callDismissScale, anchor: .top)
        .opacity(callDismissOpacity)
        .simultaneousGesture(callDragGesture)
        .ignoresSafeArea()
        .accessibilityHint(canDragToMinimize ? "Swipe down anywhere to minimize the call" : "")
        .onChange(of: callManager.showFullCallUI) { _, isPresented in
            if isPresented {
                dragOffset = 0
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.25), value: callManager.showUI)
        .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.86), value: dragOffset)
    }

    private var callDismissScale: CGFloat {
        guard canDragToMinimize else { return 1 }
        return max(0.88, 1 - (dragOffset / 900))
    }

    private var callDismissOpacity: Double {
        guard canDragToMinimize else { return 1 }
        return max(0.55, 1 - Double(dragOffset / 420))
    }

    private var callDragHandle: some View {
        Capsule()
            .fill(Color.white.opacity(0.42))
            .frame(width: 42, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var callDragGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                guard canDragToMinimize else { return }
                guard value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width)
                else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                guard canDragToMinimize else { return }
                let shouldMinimize = value.translation.height > 110
                    || value.predictedEndTranslation.height > 180
                if shouldMinimize {
                    dragOffset = 0
                    callManager.minimizeCall()
                } else {
                    withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86)) {
                        dragOffset = 0
                    }
                }
            }
    }

    @ViewBuilder
    private var background: some View {
        if callManager.callKind == .video, callManager.remoteVideoTrack != nil {
            Color.black.ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.16),
                    Color(red: 0.03, green: 0.04, blue: 0.08),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var videoLayout: some View {
        ZStack(alignment: .topTrailing) {
            if let track = callManager.remoteVideoTrack {
                LiveKitVideoView(track: track)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 18) {
                    AvatarView(
                        url: callManager.peerAvatarURL,
                        seed: callManager.peerName,
                        size: 128
                    )
                    Text(callManager.statusText)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                }
            }

            if let localTrack = callManager.localVideoTrack, !callManager.isCameraOff {
                LiveKitVideoView(track: localTrack)
                    .frame(width: 112, height: 156)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    }
                    .padding(.top, 72)
                    .padding(.trailing, 18)
            }
        }
    }

    private var audioLayout: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                if callManager.isIncoming || callManager.outgoingPhase == .ringing {
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 2)
                        .frame(width: 188, height: 188)
                        .scaleEffect(callManager.isIncoming ? 1.08 : 1.04)
                        .opacity(0.8)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: callManager.showUI)
                }

                AvatarView(
                    url: callManager.peerAvatarURL,
                    seed: callManager.peerName,
                    size: 156
                )
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.22), lineWidth: 2)
                }
            }

            VStack(spacing: 8) {
                Text(callManager.peerName)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(callManager.statusText)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)

                if callManager.isActive {
                    Text(callManager.timerLabel)
                        .font(.system(.title3, design: .monospaced).weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 28)

            Spacer()
            Spacer()
        }
    }

    private var topChrome: some View {
        VStack(spacing: 6) {
            if callManager.callKind == .video {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(callManager.peerName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(callManager.statusText)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                    if callManager.isActive {
                        Text(callManager.timerLabel)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }

            if let error = callManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background {
            if callManager.callKind == .video {
                LinearGradient(
                    colors: [Color.black.opacity(0.62), Color.black.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
            }
        }
    }

    private var bottomChrome: some View {
        VStack(spacing: 18) {
            if callManager.isIncoming {
                HStack(spacing: 54) {
                    roundCallButton(
                        title: "Decline",
                        systemImage: "phone.down.fill",
                        tint: Theme.danger,
                        size: 74
                    ) {
                        callManager.declineCall()
                    }

                    roundCallButton(
                        title: "Accept",
                        systemImage: "phone.fill",
                        tint: Theme.success,
                        size: 74
                    ) {
                        let conversationID = callManager.conversationID
                        Task {
                            await callManager.acceptCall()
                            if let conversationID {
                                appState.openConversation(id: conversationID)
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 22) {
                    roundCallButton(
                        title: callManager.isMuted ? "Unmute" : "Mute",
                        systemImage: callManager.isMuted ? "mic.slash.fill" : "mic.fill",
                        tint: Color.white.opacity(0.18),
                        size: 64
                    ) {
                        callManager.toggleMute()
                    }

                    if callManager.callKind == .video {
                        roundCallButton(
                            title: callManager.isCameraOff ? "Camera" : "Camera off",
                            systemImage: callManager.isCameraOff ? "video.slash.fill" : "video.fill",
                            tint: Color.white.opacity(0.18),
                            size: 64
                        ) {
                            callManager.toggleCamera()
                        }
                    }

                    roundCallButton(
                        title: "End",
                        systemImage: "phone.down.fill",
                        tint: Theme.danger,
                        size: 74
                    ) {
                        callManager.endCall()
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(callManager.callKind == .video ? 0.72 : 0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func roundCallButton(
        title: String,
        systemImage: String,
        tint: Color,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(tint, in: Circle())
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct LiveKitVideoView: UIViewRepresentable {
    let track: VideoTrack

    func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        view.track = track
        view.layoutMode = .fill
        return view
    }

    func updateUIView(_ uiView: VideoView, context: Context) {
        uiView.track = track
        uiView.layoutMode = .fill
    }
}

struct CallMiniBar: View {
    @Bindable var callManager: CallSessionManager

    var body: some View {
        HStack(spacing: 12) {
            Button {
                callManager.expandCall()
            } label: {
                HStack(spacing: 12) {
                    AvatarView(
                        url: callManager.peerAvatarURL,
                        seed: callManager.peerName,
                        size: 40
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(callManager.peerName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(Theme.success)
                                .frame(width: 8, height: 8)
                            if callManager.isActive {
                                Text(callManager.timerLabel)
                                    .font(.system(.caption, design: .monospaced).weight(.medium))
                                    .foregroundStyle(Theme.inkSecondary)
                            } else {
                                Text(callManager.statusText)
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                callManager.endCall()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.danger, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("End call")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        }
    }
}