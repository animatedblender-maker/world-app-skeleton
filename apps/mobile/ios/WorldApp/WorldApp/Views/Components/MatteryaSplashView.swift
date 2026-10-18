import SwiftUI

/// Branded Matterya splash — a single glow peak sweeps left→right, then repeats.
/// (No circular wrap — that lit the first and last letters at once and felt stuck.)
struct MatteryaSplashView: View {
    var showsProgress: Bool = true
    var message: String? = nil

    private let word = Array("Matterya")
    /// One clean left→right pass (snappy, not sluggish).
    private let loopDuration: TimeInterval = 0.95
    /// Quiet beat between passes so ends never glow together.
    private let gapDuration: TimeInterval = 0.18

    var body: some View {
        ZStack {
            Theme.paper
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer(minLength: 0)

                Group {
                    if showsProgress {
                        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                            letterRow(wavePhase: loopPhase(at: context.date))
                        }
                    } else {
                        letterRow(wavePhase: 0.5)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Matterya")

                if let message, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkMuted)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
        }
    }

    private func letterRow(wavePhase: CGFloat) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(word.enumerated()), id: \.offset) { index, character in
                glowingLetter(character, index: index, wavePhase: wavePhase)
            }
        }
    }

    private func glowingLetter(_ character: Character, index: Int, wavePhase: CGFloat) -> some View {
        let amount = letterGlow(index: index, wavePhase: wavePhase)

        return Text(String(character))
            .font(.system(size: 36, weight: .semibold, design: .serif))
            .tracking(0.6)
            .foregroundStyle(Theme.ink.opacity(0.42 + 0.58 * amount))
            .shadow(
                color: Theme.accentBright.opacity(0.75 * amount),
                radius: 2 + 12 * amount,
                y: 0
            )
            .shadow(
                color: Theme.accent.opacity(0.40 * amount),
                radius: 1 + 5 * amount,
                y: 0
            )
            .scaleEffect(1 + 0.04 * amount)
    }

    /// Linear distance only — peak travels 0→1; during the gap phase is nil-ish (all soft).
    private func letterGlow(index: Int, wavePhase: CGFloat) -> CGFloat {
        // gap: wavePhase < 0 → all letters at base glow
        guard wavePhase >= 0 else { return 0.15 }
        let count = CGFloat(max(word.count, 1))
        let letterCenter = (CGFloat(index) + 0.5) / count
        let delta = abs(letterCenter - wavePhase)
        let band: CGFloat = 0.16
        let raw = max(0, 1 - delta / band)
        return 0.15 + 0.85 * (raw * raw * (3 - 2 * raw))
    }

    /// Returns 0…1 during the sweep, or -1 during the quiet gap (no wrap glow).
    private func loopPhase(at date: Date) -> CGFloat {
        let cycle = loopDuration + gapDuration
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
        if t >= loopDuration { return -1 }
        return CGFloat(t / loopDuration)
    }
}

#Preview("Loop") {
    MatteryaSplashView(showsProgress: true)
}
