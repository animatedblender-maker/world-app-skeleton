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
        Capsule(style: .continuous)
            .fill(isVideoCall ? Theme.matte.opacity(0.55) : Theme.inkMuted.opacity(0.45))
            .frame(width: 42, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var isVideoCall: Bool { callManager.callKind == .video }

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
        if isVideoCall, callManager.remoteVideoTrack != nil {
            Color.black.ignoresSafeArea()
        } else if isVideoCall {
            // Waiting for remote video — flat ink, no glow gradient.
            Theme.ink.ignoresSafeArea()
        } else {
            // Audio: flat Matterya paper (minimal).
            Theme.canvas.ignoresSafeArea()
        }
    }

    private var videoLayout: some View {
        ZStack(alignment: .topTrailing) {
            if let track = callManager.remoteVideoTrack {
                LiveKitVideoView(track: track, mirrorMode: .off)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    AvatarView(
                        url: callManager.peerAvatarURL,
                        seed: callManager.peerName,
                        size: 112
                    )
                    .overlay {
                        Circle()
                            .stroke(Theme.matte.opacity(0.35), lineWidth: 1)
                    }
                    Text(callManager.statusText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.matte.opacity(0.85))
                }
            }

            if let localTrack = callManager.localVideoTrack, !callManager.isCameraOff {
                LiveKitVideoView(track: localTrack, mirrorMode: .mirror)
                    .frame(width: 104, height: 144)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.matte.opacity(0.35), lineWidth: 0.5)
                    }
                    .padding(.top, 72)
                    .padding(.trailing, 16)
            }
        }
    }

    private var audioLayout: some View {
        VStack(spacing: 20) {
            Spacer()

            AvatarView(
                url: callManager.peerAvatarURL,
                seed: callManager.peerName,
                size: 128
            )
            .overlay {
                Circle()
                    .stroke(Theme.border, lineWidth: 0.5)
            }

            VStack(spacing: 8) {
                Text(callManager.peerName)
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)

                Text(callManager.statusText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)

                if callManager.isActive {
                    Text(callManager.timerLabel)
                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 28)

            Spacer()
            Spacer()
        }
    }

    private var topChrome: some View {
        VStack(spacing: 6) {
            if isVideoCall {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(callManager.peerName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Theme.matte)
                        Text(callManager.statusText)
                            .font(.subheadline)
                            .foregroundStyle(Theme.matte.opacity(0.75))
                    }
                    Spacer()
                    if callManager.isActive {
                        Text(callManager.timerLabel)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundStyle(Theme.matte.opacity(0.85))
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
        .padding(.bottom, 10)
        .background {
            if isVideoCall {
                Theme.ink.opacity(0.55)
                    .ignoresSafeArea(edges: .top)
            }
        }
    }

    private var bottomChrome: some View {
        VStack(spacing: 16) {
            if callManager.isIncoming {
                HStack(spacing: 40) {
                    roundCallButton(
                        title: "Decline",
                        systemImage: "phone.down.fill",
                        fill: Theme.danger,
                        glyph: Theme.paper,
                        size: 68
                    ) {
                        callManager.declineCall()
                    }

                    roundCallButton(
                        title: "Accept",
                        systemImage: "phone.fill",
                        fill: Theme.ink,
                        glyph: Theme.paper,
                        size: 68
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
                HStack(spacing: 16) {
                    roundCallButton(
                        title: callManager.isMuted ? "Unmute" : "Mute",
                        systemImage: callManager.isMuted ? "mic.slash.fill" : "mic.fill",
                        fill: secondaryFill,
                        glyph: secondaryGlyph,
                        size: 56
                    ) {
                        callManager.toggleMute()
                    }

                    roundCallButton(
                        title: callManager.isSpeakerOn ? "Speaker" : "Earpiece",
                        systemImage: callManager.isSpeakerOn
                            ? "speaker.wave.2.fill"
                            : "speaker.wave.1.fill",
                        fill: callManager.isSpeakerOn ? Theme.ink : secondaryFill,
                        glyph: callManager.isSpeakerOn ? Theme.paper : secondaryGlyph,
                        size: 56
                    ) {
                        callManager.toggleSpeaker()
                    }

                    if isVideoCall {
                        roundCallButton(
                            title: callManager.isCameraOff ? "Camera" : "Camera off",
                            systemImage: callManager.isCameraOff ? "video.slash.fill" : "video.fill",
                            fill: secondaryFill,
                            glyph: secondaryGlyph,
                            size: 56
                        ) {
                            callManager.toggleCamera()
                        }
                    }

                    roundCallButton(
                        title: "End",
                        systemImage: "phone.down.fill",
                        fill: Theme.danger,
                        glyph: Theme.paper,
                        size: 60
                    ) {
                        callManager.endCall()
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
        .background {
            if isVideoCall {
                Theme.ink.opacity(0.72)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                Theme.surface
                    .overlay(alignment: .top) {
                        Theme.border.frame(height: 0.5)
                    }
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private var secondaryFill: Color {
        isVideoCall ? Theme.matte.opacity(0.18) : Theme.matteDeep
    }

    private var secondaryGlyph: Color {
        isVideoCall ? Theme.matte : Theme.ink
    }

    private var labelColor: Color {
        isVideoCall ? Theme.matte.opacity(0.88) : Theme.inkSecondary
    }

    private func roundCallButton(
        title: String,
        systemImage: String,
        fill: Color,
        glyph: Color,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(glyph)
                    .frame(width: size, height: size)
                    .background(fill, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Theme.border.opacity(isVideoCall ? 0 : 0.85), lineWidth: 0.5)
                    }
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(labelColor)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct LiveKitVideoView: UIViewRepresentable {
    let track: VideoTrack
    var mirrorMode: VideoView.MirrorMode = .auto

    func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        view.track = track
        view.layoutMode = .fill
        view.mirrorMode = mirrorMode
        return view
    }

    func updateUIView(_ uiView: VideoView, context: Context) {
        uiView.track = track
        uiView.layoutMode = .fill
        uiView.mirrorMode = mirrorMode
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border.opacity(0.85), lineWidth: 0.5)
        }
    }
}