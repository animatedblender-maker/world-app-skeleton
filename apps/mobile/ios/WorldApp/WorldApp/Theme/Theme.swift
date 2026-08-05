import SwiftUI
import UIKit

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
    /// Full-screen Sparks accents on dark video — same warm ink as the rest of Matterya.
    static let reelsAccent = accentBright
    static let danger = Color(red: 0.918, green: 0.000, blue: 0.043)
    static let like = Color(red: 0.918, green: 0.000, blue: 0.043)
    static let commentBubble = Color(red: 0.941, green: 0.949, blue: 0.961)
    static let facebookBlue = Color(red: 0.094, green: 0.467, blue: 0.949)
    /// Filled/active icon tint — warm off-white, never blue.
    static let iconFill = Color(red: 0.965, green: 0.953, blue: 0.937)
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
    static let feedGutter: CGFloat = 14
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

/// User-facing names for short vertical videos (not "Reels").
enum MatteryaCopy {
    /// Keeps the product name on one line in headers and chips.
    private static let nbsp = "\u{00A0}"
    private static let hubsBrand = "Matterya\(nbsp)Hubs"

    static let sparks = "Sparks"
    static let spark = "Spark"
    static let matteryaSparks = "Matterya\(nbsp)Sparks"
    static let sparksForYou = "Sparks for you"
    static let newSpark = "New spark"
    static let newVideo = "New video"
    static let publishSpark = "Publish spark"
    static let publishVideo = "Publish video"
    static let savedSparks = "Saved sparks"
    static let browseSparks = "Browse Sparks"
    static let watchAllSparks = "Watch all"
    static let sparksFromCountry = "Sparks from"
    static let noSparksYet = "No sparks yet"
    static let noSparksForCountry = "No sparks for"
    static let saveSparksHint = "Save sparks while watching or publish your own."
    static let savedSparksSubtitle = "Sparks you bookmarked"
    static let publishSparkHint = "Vertical video works best"
    static let publishVideoHint = "Shows in feed and \(hubsBrand)"
    static let matteryaHubs = hubsBrand
    static let newOnHubs = "New on \(hubsBrand)"
    static let watchOnHubs = "Watch on \(hubsBrand)"
    static let publishedOnHubs = "Published on \(hubsBrand)"
    static let openingHubs = "Opening \(hubsBrand)…"
    static let loadingHubs = "Loading \(hubsBrand)…"
    static let hubsUnavailable = "\(hubsBrand) unavailable"
    static let exploreHubs = "Explore \(hubsBrand)"
    static let searchHubs = "Search \(hubsBrand)"
    static let searchHubsHint = "Find videos and creators on \(hubsBrand)"
    static let moreOnHubs = "More on \(hubsBrand)"
    static let yourChannelOnHubs = "Your channel on \(hubsBrand)"
    static let verifiedHubsChannel = "Verified \(hubsBrand) channel"
    static let longFormOnHubs = "Long-form on \(hubsBrand)"
    static let sparksOnHubs = "Short vertical video on \(hubsBrand)"
    static let hubsPublishHint = "Try another category, follow creators, or publish on \(hubsBrand)."
    static let hubsLoadError = "Couldn't load \(hubsBrand) right now. Pull to refresh or check your connection."
    static let hubsNoChannelVideos = "This creator hub has no videos on \(hubsBrand) yet."
    static let hubsVideoUnavailable = "This video isn't available on \(hubsBrand)."
    static let postToYourFeed = "Post to your country feed"
    static let shareToYourFeed = "Share to your country feed"
    static let browsingForeignFeed = "Browsing another country"
    static let shareFromForeignHint = "Tap share on any post to add it to your home feed. You can only write posts in your own country."
    static let homeCountryOnlyPost = "You can only publish in your home country."
    static let follow = "Follow"
    static let following = "Following"
    static let followers = "followers"
    static let creator = "Creator"
    static let creators = "Creators"
    static let viewCreatorHub = "View creator hub"
    static let shareCreatorHub = "Share creator hub"
    static let aboutThisHub = "About this hub"
    static let featuredCreators = "Featured creators"
}

extension View {
    /// Prevents awkward wraps in short Matterya Hubs labels.
    func matteryaBrandLine(minScale: CGFloat = 0.88) -> some View {
        lineLimit(1)
            .minimumScaleFactor(minScale)
            .allowsTightening(true)
    }

    func postHeadlineStyle(lineLimit: Int = 4) -> some View {
        font(.system(.title3, design: .serif))
            .fontWeight(.regular)
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.leading)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.9)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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

extension View {
    /// Sheets and full-screen covers do not reliably inherit `@Observable` environment values.
    func withAppState(_ appState: AppState) -> some View {
        environment(appState)
    }

    /// Dismiss the software keyboard (comments, messages, composers).
    func dismissKeyboard() {
        Keyboard.dismiss()
    }

    /// Tap empty / non-keyboard space to put the keyboard down.
    /// Does not block buttons or scroll gestures (simultaneous + content shape).
    func dismissKeyboardOnTap() -> some View {
        contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded { _ in
                    Keyboard.dismiss()
                }
            )
    }
}

enum Keyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    /// Install once on the key window: any touch outside the keyboard collapses it.
    /// `cancelsTouchesInView = false` so buttons, lists, and fields keep working.
    @MainActor
    static func installDismissOnOutsideTap() {
        KeyboardDismissTapInstaller.shared.installIfNeeded()
    }
}

/// Window-level tap that resigns first responder without stealing other touches.
@MainActor
private final class KeyboardDismissTapInstaller: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissTapInstaller()

    private var isInstalled = false

    func installIfNeeded() {
        guard !isInstalled else { return }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first
        else { return }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tap.requiresExclusiveTouchType = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        isInstalled = true
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        Keyboard.dismiss()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        var view = touch.view
        while let current = view {
            // Don't dismiss when the user is aiming at a field (would open then snap shut).
            if current is UITextField || current is UITextView {
                return false
            }
            let name = NSStringFromClass(type(of: current))
            if name.contains("UIKeyboard")
                || name.contains("Keyboard")
                || name.contains("UISearchBar")
                || name.contains("TextField")
                || name.contains("TextView")
                || name.contains("TextInput")
            {
                return false
            }
            view = current.superview
        }
        return true
    }
}