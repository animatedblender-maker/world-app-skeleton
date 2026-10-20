import SwiftUI
import UIKit

/// Branded Matterya splash — glow loop runs on Core Animation (render server),
/// so AppState / bootstrap / RootView mount cannot freeze the sweep.
struct MatteryaSplashView: View {
    var showsProgress: Bool = true
    var message: String? = nil

    var body: some View {
        ZStack {
            Color(uiColor: MatteryaSplashGlowUIView.paperUIColor)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer(minLength: 0)

                MatteryaSplashGlowRepresentable(animating: showsProgress)
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
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
        // Isolate from parent animation / layout thrash while shell mounts under us.
        .transaction { $0.animation = nil }
    }
}

// MARK: - SwiftUI bridge

private struct MatteryaSplashGlowRepresentable: UIViewRepresentable {
    var animating: Bool

    func makeUIView(context: Context) -> MatteryaSplashGlowUIView {
        let view = MatteryaSplashGlowUIView()
        view.setAnimating(animating)
        return view
    }

    func updateUIView(_ uiView: MatteryaSplashGlowUIView, context: Context) {
        uiView.setAnimating(animating)
    }
}

// MARK: - Core Animation glow (independent of SwiftUI / AppState)

/// Each letter is base ink + a bright overlay. Overlay opacity / shadow / scale are
/// repeating `CAAnimation`s — they keep sweeping on the render server while the
/// main thread hydrates AppState and mounts RootView.
final class MatteryaSplashGlowUIView: UIView {
    static let paperUIColor = UIColor(red: 0.973, green: 0.965, blue: 0.949, alpha: 1)
    private static let ink = UIColor(red: 0.173, green: 0.157, blue: 0.145, alpha: 1)
    /// Off-white matte glow — never metallic gold.
    private static let accentBright = UIColor(red: 0.965, green: 0.953, blue: 0.937, alpha: 1)

    private let word = Array("Matterya")
    private let loopDuration: CFTimeInterval = 0.95
    private let gapDuration: CFTimeInterval = 0.18
    private var letterHosts: [LetterHost] = []
    private var isAnimating = false
    private let stack = UIStackView()
    /// Shared timeline so remounts stay in phase.
    private var loopAnchor: CFTimeInterval = 0

    private struct LetterHost {
        let container: UIView
        let base: UILabel
        let bright: UILabel
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let font = UIFont.systemFont(ofSize: 36, weight: .semibold).withDesign(.serif)
            ?? UIFont.systemFont(ofSize: 36, weight: .semibold)

        for ch in word {
            let container = UIView()
            container.backgroundColor = .clear

            let base = UILabel()
            base.text = String(ch)
            base.font = font
            base.textColor = Self.ink.withAlphaComponent(0.42)
            base.translatesAutoresizingMaskIntoConstraints = false

            let bright = UILabel()
            bright.text = String(ch)
            bright.font = font
            bright.textColor = Self.ink
            bright.alpha = 0
            bright.layer.shadowColor = Self.accentBright.cgColor
            bright.layer.shadowOpacity = 0
            bright.layer.shadowRadius = 2
            bright.layer.shadowOffset = .zero
            bright.layer.masksToBounds = false
            bright.translatesAutoresizingMaskIntoConstraints = false

            container.addSubview(base)
            container.addSubview(bright)
            NSLayoutConstraint.activate([
                base.topAnchor.constraint(equalTo: container.topAnchor),
                base.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                base.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                base.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                bright.topAnchor.constraint(equalTo: container.topAnchor),
                bright.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                bright.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                bright.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])

            stack.addArrangedSubview(container)
            letterHosts.append(LetterHost(container: container, base: base, bright: bright))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAnimating(_ animating: Bool) {
        if animating == isAnimating,
           animating,
           letterHosts.first?.bright.layer.animation(forKey: "glowOpacity") != nil {
            return
        }
        isAnimating = animating
        if animating {
            startLoop()
        } else {
            stopLoop(peakIndex: word.count / 2)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, isAnimating {
            startLoop()
        }
    }

    private func startLoop() {
        let cycle = loopDuration + gapDuration
        let count = max(word.count, 1)
        if loopAnchor == 0 {
            loopAnchor = CACurrentMediaTime()
        }
        let begin = loopAnchor

        for (index, host) in letterHosts.enumerated() {
            let layer = host.bright.layer
            layer.removeAnimation(forKey: "glowOpacity")
            layer.removeAnimation(forKey: "glowShadow")
            layer.removeAnimation(forKey: "glowRadius")
            layer.removeAnimation(forKey: "glowScale")

            let letterCenter = (Double(index) + 0.5) / Double(count)
            let peakTime = letterCenter * loopDuration
            let band = 0.16 * loopDuration
            let riseStart = max(0, peakTime - band)
            let riseEnd = peakTime
            let fallEnd = min(loopDuration, peakTime + band)
            let keyTimes: [NSNumber] = [
                0,
                NSNumber(value: riseStart / cycle),
                NSNumber(value: riseEnd / cycle),
                NSNumber(value: fallEnd / cycle),
                1,
            ]

            func keyframe(path: String, values: [Any]) -> CAKeyframeAnimation {
                let anim = CAKeyframeAnimation(keyPath: path)
                anim.values = values
                anim.keyTimes = keyTimes
                anim.duration = cycle
                anim.repeatCount = .infinity
                anim.calculationMode = .linear
                anim.isRemovedOnCompletion = false
                anim.fillMode = .forwards
                anim.beginTime = begin
                return anim
            }

            host.bright.alpha = 0
            layer.shadowOpacity = 0
            layer.shadowRadius = 2
            layer.transform = CATransform3DIdentity

            layer.add(keyframe(path: "opacity", values: [0, 0, 1, 0, 0]), forKey: "glowOpacity")
            layer.add(keyframe(path: "shadowOpacity", values: [0, 0, 0.75, 0, 0]), forKey: "glowShadow")
            layer.add(keyframe(path: "shadowRadius", values: [2, 2, 14, 2, 2]), forKey: "glowRadius")
            layer.add(keyframe(path: "transform.scale", values: [1, 1, 1.04, 1, 1]), forKey: "glowScale")
        }
    }

    private func stopLoop(peakIndex: Int) {
        for (index, host) in letterHosts.enumerated() {
            host.bright.layer.removeAllAnimations()
            let on = index == peakIndex
            host.bright.alpha = on ? 1 : 0
            host.bright.layer.shadowOpacity = on ? 0.55 : 0
            host.bright.layer.shadowRadius = on ? 10 : 2
            host.bright.layer.transform = on
                ? CATransform3DMakeScale(1.04, 1.04, 1)
                : CATransform3DIdentity
        }
    }
}

private extension UIFont {
    func withDesign(_ design: UIFontDescriptor.SystemDesign) -> UIFont? {
        guard let descriptor = fontDescriptor.withDesign(design) else { return nil }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

#Preview("Loop") {
    MatteryaSplashView(showsProgress: true)
}
