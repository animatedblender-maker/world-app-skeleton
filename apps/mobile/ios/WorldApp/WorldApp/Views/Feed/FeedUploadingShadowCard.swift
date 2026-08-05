import SwiftUI

/// Animated “shadow” of a post card while a video is uploading — pins at the top of the feed.
struct FeedUploadingShadowCard: View {
    let draft: FeedUploadPlaceholder

    @State private var shimmerPhase: CGFloat = -1
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            mediaShadow
            if !draft.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(draft.caption)
                    .font(.body)
                    .foregroundStyle(Theme.inkSecondary.opacity(0.85))
                    .lineLimit(3)
                    .padding(.horizontal, Theme.feedGutter)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            }
            progressFooter
        }
        .background(Theme.canvas)
        .overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
        .padding(.bottom, 10)
        .opacity(draft.failedMessage == nil ? 1 : 0.92)
        .onAppear {
            withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.2
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(draft.failedMessage == nil ? "Uploading video" : "Upload failed")
        .accessibilityValue(draft.progressText)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(Theme.canvasMuted)
                .frame(width: 36, height: 36)
                .overlay {
                    Circle()
                        .stroke(Theme.border, lineWidth: 0.5)
                }
                .shimmer(phase: shimmerPhase)

            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.canvasMuted)
                    .frame(width: 108, height: 12)
                    .shimmer(phase: shimmerPhase)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Theme.canvasMuted.opacity(0.75))
                    .frame(width: 64, height: 9)
                    .shimmer(phase: shimmerPhase)
            }

            Spacer(minLength: 0)

            if draft.isHub {
                Text("Hubs")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.accentBright.opacity(0.85))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.accentSoft, in: Capsule())
            }
        }
        .padding(.horizontal, Theme.feedGutter)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var mediaShadow: some View {
        ZStack {
            // Soft card silhouette — feels like the real 16:9 frame arriving.
            Rectangle()
                .fill(Theme.canvasDeep.opacity(pulse ? 0.92 : 0.78))
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.14),
                            Color.white.opacity(0.0),
                        ],
                        startPoint: UnitPoint(x: shimmerPhase - 0.35, y: 0.2),
                        endPoint: UnitPoint(x: shimmerPhase + 0.15, y: 0.9)
                    )
                }

            if let preview = draft.previewImage {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .opacity(0.42)
                    .blur(radius: 1.2)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 10) {
                Image(systemName: draft.failedMessage == nil ? "arrow.up.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(draft.failedMessage == nil ? Theme.surface.opacity(0.95) : Theme.danger)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                    .scaleEffect(pulse && draft.failedMessage == nil ? 1.06 : 1.0)

                Text(draft.progressText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.surface.opacity(0.92))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.38), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipped()
    }

    private var progressFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.canvasMuted)
                    Capsule()
                        .fill(draft.failedMessage == nil ? Theme.accentBright : Theme.danger)
                        .frame(width: max(8, geo.size.width * CGFloat(min(1, max(0.04, draft.progress)))))
                        .animation(.easeOut(duration: 0.25), value: draft.progress)
                }
            }
            .frame(height: 4)

            HStack(spacing: 6) {
                if draft.failedMessage == nil {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.inkMuted)
                }
                Text(draft.failedMessage == nil ? "Your video is on its way to the feed…" : "Couldn't publish — try again.")
                    .font(.caption2)
                    .foregroundStyle(Theme.inkMuted)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Theme.feedGutter)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }
}

private extension View {
    func shimmer(phase: CGFloat) -> some View {
        overlay {
            LinearGradient(
                colors: [
                    Color.white.opacity(0),
                    Color.white.opacity(0.35),
                    Color.white.opacity(0),
                ],
                startPoint: UnitPoint(x: phase - 0.4, y: 0.5),
                endPoint: UnitPoint(x: phase + 0.1, y: 0.5)
            )
            .blendMode(.plusLighter)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
