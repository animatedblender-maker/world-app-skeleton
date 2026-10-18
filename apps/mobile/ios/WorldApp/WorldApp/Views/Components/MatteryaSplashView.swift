import SwiftUI

/// Branded Matterya splash — the word itself is the loading bar.
/// Letters glow left → right until fill completes, then the shell can open.
struct MatteryaSplashView: View {
    /// When true, letters animate a fill glow (loading). When false, show full glow (static hold).
    var showsProgress: Bool = true
    var message: String? = nil
    /// Fired once the letter fill reaches the end (only when `showsProgress`).
    var onFillComplete: (() -> Void)? = nil

    @State private var fillProgress: CGFloat = 0
    @State private var shimmerPhase: CGFloat = 0
    @State private var didNotifyComplete = false

    private let word = Array("Matterya")
    /// Minimum time for a full left→right letter fill.
    private let fillDuration: TimeInterval = 1.45

    var body: some View {
        ZStack {
            Theme.paper
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer(minLength: 0)

                HStack(spacing: 1) {
                    ForEach(Array(word.enumerated()), id: \.offset) { index, character in
                        glowingLetter(character, index: index)
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
        .onAppear {
            if showsProgress {
                startLetterFill()
            } else {
                fillProgress = 1
            }
        }
    }

    @ViewBuilder
    private func glowingLetter(_ character: Character, index: Int) -> some View {
        let amount = letterAmount(index: index)
        let lit = amount > 0.02
        // Soft pulse on lit letters so the word feels alive while loading.
        let pulse = lit
            ? 0.55 + 0.45 * abs(sin((shimmerPhase + CGFloat(index) * 0.35) * .pi))
            : 0

        Text(String(character))
            .font(.system(size: 36, weight: .semibold, design: .serif))
            .tracking(0.6)
            .foregroundStyle(
                lit
                    ? Theme.ink.opacity(0.55 + 0.45 * amount)
                    : Theme.ink.opacity(0.18)
            )
            .shadow(
                color: Theme.accentBright.opacity(0.55 * amount * pulse),
                radius: 4 + 10 * amount * pulse,
                y: 0
            )
            .shadow(
                color: Theme.accent.opacity(0.35 * amount),
                radius: 2 + 4 * amount,
                y: 0
            )
            .scaleEffect(1 + 0.03 * amount * pulse)
    }

    /// 0…1 how lit letter `index` is, based on overall fill (loading-bar across glyphs).
    private func letterAmount(index: Int) -> CGFloat {
        let count = CGFloat(max(word.count, 1))
        let start = CGFloat(index) / count
        let end = CGFloat(index + 1) / count
        if fillProgress <= start { return 0 }
        if fillProgress >= end { return 1 }
        return (fillProgress - start) / (end - start)
    }

    private func startLetterFill() {
        fillProgress = 0
        didNotifyComplete = false

        withAnimation(.easeInOut(duration: fillDuration)) {
            fillProgress = 1
        }

        // Continuous soft shimmer while letters are lighting / holding at full.
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            shimmerPhase = 1
        }

        Task { @MainActor in
            let nanos = UInt64(fillDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !didNotifyComplete else { return }
            didNotifyComplete = true
            onFillComplete?()
        }
    }
}

#Preview("Loading") {
    MatteryaSplashView(showsProgress: true)
}

#Preview("Hold") {
    MatteryaSplashView(showsProgress: false)
}
