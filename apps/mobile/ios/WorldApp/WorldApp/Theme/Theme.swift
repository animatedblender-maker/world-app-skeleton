import SwiftUI

enum Theme {
    static let paper = Color(red: 0.973, green: 0.965, blue: 0.949)
    static let canvas = paper
    static let canvasMuted = Color(red: 0.949, green: 0.941, blue: 0.925)
    static let canvasDeep = Color(red: 0.929, green: 0.918, blue: 0.898)
    static let surface = Color(red: 0.996, green: 0.992, blue: 0.984)
    static let surfaceMuted = canvasMuted
    static let accentSoft = accent.opacity(0.10)
    static let ink = Color(red: 0.173, green: 0.157, blue: 0.145)
    static let inkSecondary = Color(red: 0.420, green: 0.392, blue: 0.365)
    static let inkMuted = Color(red: 0.580, green: 0.545, blue: 0.510)
    static let accent = Color(red: 0.420, green: 0.345, blue: 0.255)
    static let accentBright = Color(red: 0.482, green: 0.388, blue: 0.278)
    static let border = Color(red: 0.867, green: 0.847, blue: 0.820)
    static let divider = Color(red: 0.886, green: 0.871, blue: 0.847)
    static let landFill = Color(red: 0.910, green: 0.894, blue: 0.863)
    static let landSelected = Color(red: 0.878, green: 0.839, blue: 0.776)
    static let oceanWash = Color(red: 0.820, green: 0.878, blue: 0.922)
    static let danger = Color(red: 0.918, green: 0.000, blue: 0.043)
    static let like = Color(red: 0.918, green: 0.000, blue: 0.043)
    static let commentBubble = Color(red: 0.941, green: 0.949, blue: 0.961)
    static let facebookBlue = Color(red: 0.094, green: 0.467, blue: 0.949)
    static let success = Color(red: 0.000, green: 0.690, blue: 0.314)
    static let buttonMuted = Color(red: 0.941, green: 0.941, blue: 0.941)
    static let globeGlass = Color.white.opacity(0.94)
    static let globeScrimTop = Color.white.opacity(0.82)
    static let globeScrimBottom = Color.white.opacity(0.55)
    static let storyRing = LinearGradient(
        colors: [
            Color(red: 0.985, green: 0.753, blue: 0.176),
            Color(red: 0.918, green: 0.235, blue: 0.412),
            Color(red: 0.525, green: 0.224, blue: 0.796),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 8
    static let pagePadding: CGFloat = 16
    static let cardPadding: CGFloat = 12
    static let tabBarHeight: CGFloat = 49
}

extension View {
    func screenBackground() -> some View {
        background {
            PaperBackground()
        }
    }

    func premiumCard(inset: CGFloat = Theme.cardPadding) -> some View {
        self.padding(inset)
            .background(Theme.surface)
    }

    func glassSurface(cornerRadius: CGFloat = Theme.controlRadius) -> some View {
        padding(12)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.globeGlass)
                    .shadow(color: Theme.ink.opacity(0.06), radius: 10, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
    }

    func feedDivider() -> some View {
        overlay(alignment: .bottom) {
            Theme.divider.frame(height: 0.5)
        }
    }

    func sectionLabel() -> some View {
        font(.caption.weight(.semibold))
            .foregroundStyle(Theme.inkMuted)
            .textCase(.uppercase)
    }

    func pillTab(isSelected: Bool) -> some View {
        font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Theme.ink : Theme.inkMuted)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .fill(Theme.ink)
                        .frame(height: 1)
                        .offset(y: 10)
                }
            }
    }

    func instagramButton() -> some View {
        font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Theme.buttonMuted, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
    }

    func elegantButton(outlined: Bool = false) -> some View {
        font(.subheadline.weight(.medium))
            .foregroundStyle(outlined ? Theme.ink : Theme.surface)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if outlined {
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .stroke(Theme.border, lineWidth: 0.5)
                } else {
                    RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .fill(Theme.ink)
                }
            }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .instagramButton()
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct PremiumTextField: View {
    let title: String
    @Binding var text: String
    var isSecure = false
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
            Group {
                if isSecure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                        .keyboardType(keyboard)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(12)
            .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
        }
    }
}