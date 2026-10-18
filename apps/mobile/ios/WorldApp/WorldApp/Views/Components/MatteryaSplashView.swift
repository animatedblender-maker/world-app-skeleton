import SwiftUI

/// Branded Matterya splash — the word glows in a continuous loop until the shell opens.
struct MatteryaSplashView: View {
    /// When true, run the looping letter glow. When false, hold a soft mid glow.
    var showsProgress: Bool = true
    var message: String? = nil

    private let word = Array("Matterya")
    /// One full left→right pass duration (then repeats seamlessly).
    private let loopDuration: TimeInterval = 1.25

    var body: some View {
        ZStack {
            Theme.paper
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer(minLength: 0)

                Group {
                    if showsProgress {
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                            let phase = loopPhase(at: context.date)
                            letterRow(wavePhase: phase)
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
                        .transition(.opacity)
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
            // Base opacity matches LaunchWordmark so cold open never “pops in” late.
            .foregroundStyle(Theme.ink.opacity(0.55 + 0.45 * amount))
            .shadow(
                color: Theme.accentBright.opacity(0.70 * amount),
                radius: 3 + 14 * amount,
                y: 0
            )
            .shadow(
                color: Theme.accent.opacity(0.45 * amount),
                radius: 1.5 + 6 * amount,
                y: 0
            )
            .scaleEffect(1 + 0.045 * amount)
    }

    /// Brightest under the traveling wave peak; soft falloff so the word reads as a looping bar.
    private func letterGlow(index: Int, wavePhase: CGFloat) -> CGFloat {
        let count = CGFloat(max(word.count, 1))
        let letterCenter = (CGFloat(index) + 0.5) / count
        var delta = abs(letterCenter - wavePhase)
        delta = min(delta, 1 - delta)
        let band: CGFloat = 0.28
        let raw = max(0, 1 - delta / band)
        // Floor keeps every letter readable from frame 0 (matches static launch wordmark).
        return 0.35 + 0.65 * (raw * raw * (3 - 2 * raw))
    }

    private func loopPhase(at date: Date) -> CGFloat {
        let t = date.timeIntervalSinceReferenceDate
        let wrapped = t.truncatingRemainder(dividingBy: loopDuration)
        return CGFloat(wrapped / loopDuration)
    }
}

#Preview("Loop") {
    MatteryaSplashView(showsProgress: true)
}

#Preview("Hold") {
    MatteryaSplashView(showsProgress: false)
}
