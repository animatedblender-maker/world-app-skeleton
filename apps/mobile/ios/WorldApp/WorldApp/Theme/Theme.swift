import SwiftUI
import UIKit

/// Status bar (notch clock / battery / Wi‑Fi) for dark surfaces.
enum MatteryaStatusBar {
    /// Force light (off-white) status-bar glyphs on dark overlays (Sparks, side menu).
    /// Pair with root `preferredColorScheme(.dark)` — window override alone can lose to a
    /// hard-coded app-root `.light` preference.
    @MainActor
    static func setLightContent(_ enabled: Bool) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let style: UIUserInterfaceStyle = enabled ? .dark : .unspecified
        for window in scene.windows {
            window.overrideUserInterfaceStyle = style
            window.rootViewController?.setNeedsStatusBarAppearanceUpdate()
            propagateStatusBarUpdate(from: window.rootViewController)
        }
    }

    /// Sparks full-screen alias — same light glyphs as `setLightContent`.
    @MainActor
    static func setSparksLightContent(_ enabled: Bool) {
        setLightContent(enabled)
    }

    @MainActor
    private static func propagateStatusBarUpdate(from root: UIViewController?) {
        guard let root else { return }
        root.setNeedsStatusBarAppearanceUpdate()
        for child in root.children {
            propagateStatusBarUpdate(from: child)
        }
        if let presented = root.presentedViewController {
            propagateStatusBarUpdate(from: presented)
        }
    }
}

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
    /// Off-white matte highlight — never metallic gold or shiny bronze.
    static let matte = Color(red: 0.965, green: 0.953, blue: 0.937)
    /// Soft matte fill for chips / selected controls (flat paper, no sheen).
    static let matteDeep = Color(red: 0.941, green: 0.929, blue: 0.910)
    /// Warm ink accent for text/icons on paper (flat — not gold).
    static let accent = ink
    /// Former gold/bronze bright → matte off-white (fills, tints, checkmarks).
    static let accentBright = matte
    static let border = Color(red: 0.867, green: 0.847, blue: 0.820)
    static let divider = Color(red: 0.886, green: 0.871, blue: 0.847)
    static let landFill = Color(red: 0.910, green: 0.894, blue: 0.863)
    static let landSelected = Color(red: 0.878, green: 0.839, blue: 0.776)
    static let oceanWash = Color(red: 0.820, green: 0.878, blue: 0.922)
    /// Full-screen Sparks accents on dark video — matte off-white, never gold.
    static let reelsAccent = matte
    static let danger = Color(red: 0.918, green: 0.000, blue: 0.043)
    static let like = Color(red: 0.918, green: 0.000, blue: 0.043)
    static let commentBubble = Color(red: 0.941, green: 0.949, blue: 0.961)
    static let facebookBlue = Color(red: 0.094, green: 0.467, blue: 0.949)
    /// Filled/active icon tint — same matte off-white family.
    static let iconFill = matte
    static let success = Color(red: 0.000, green: 0.690, blue: 0.314)
    static let buttonMuted = matteDeep
    static let globeGlass = Color.white.opacity(0.94)
    static let globeScrimTop = Color.white.opacity(0.82)
    static let globeScrimBottom = Color.white.opacity(0.55)
    /// Story ring — flat paper tones (no gold / IG rainbow).
    static let storyRing = LinearGradient(
        colors: [
            matte,
            matteDeep,
            Color(red: 0.910, green: 0.894, blue: 0.863),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 8
    static let pagePadding: CGFloat = 16
    /// Outer feed chrome (rarely used — prefer full-width cards + `pagePadding` on text).
    static let feedGutter: CGFloat = 14
    /// Readable side inset for post body text on full-width feed cards.
    static let feedTextInset: CGFloat = 16
    static let cardPadding: CGFloat = 12
    static let tabBarHeight: CGFloat = 49
}

// MARK: - Premium motion (YouTube / IG / FB snappy feel — short easeOut, no hangy springs)

/// App-wide motion tokens. Prefer these over ad-hoc `interactiveSpring` (which can hang mid-path).
enum MatteryaMotion {
    /// Page / tab morph — lands immediately.
    static let snappy = Animation.easeOut(duration: 0.12)
    /// YouTube mini settle after finger-up (snappy spring, not a hangy bounce).
    static let minimize = Animation.spring(response: 0.22, dampingFraction: 0.92)
    /// Sheets, comments, share overlays.
    static let sheet = Animation.easeOut(duration: 0.16)
    /// YouTube maximize from mini → full watch (snappy — was hanging at ~0.34s + tab work).
    static let expand = Animation.spring(response: 0.22, dampingFraction: 0.92)
    /// Fullscreen present / dismiss (legacy alias).
    static let fullscreen = Animation.spring(response: 0.28, dampingFraction: 0.94)
    /// Micro UI (mute chip, glyph, heart pop settle).
    static let micro = Animation.easeOut(duration: 0.10)
    /// Like burst — short punch, not a bouncy spring that feels laggy.
    static let like = Animation.easeOut(duration: 0.14)
    /// Scroll-to-top / list chrome.
    static let scroll = Animation.easeOut(duration: 0.18)
    /// Feed upload shadow insert.
    static let insert = Animation.easeOut(duration: 0.16)

    // MARK: YouTube-parity hubs geometry (stage ↔ FS ↔ mini)

    /// Continuous morph settle — finger-up stage/FS/mini (tight, no hang).
    static let ytMorph = Animation.spring(response: 0.28, dampingFraction: 0.94)
    /// Maximize from mini → watch stage.
    static let ytExpand = Animation.spring(response: 0.24, dampingFraction: 0.93)
    /// Device tilt / content rotation while FS (short ease, no bounce).
    static let ytRotate = Animation.easeInOut(duration: 0.20)

    /// UIKit: faster than system default for feed-like lists.
    static var collectionDeceleration: UIScrollView.DecelerationRate { .fast }
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
    static let continueWatching = "Continue watching"
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

    /// Other people's profile hub CTA — "John's hub" from first name (channel owners only).
    static func personsHubTitle(displayName: String?, username: String?) -> String {
        let raw = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let firstFromName = raw.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
        let handle = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = firstFromName ?? (handle.isEmpty ? nil : handle)
        guard let name, !name.isEmpty else { return "Their hub" }
        if name.lowercased().hasSuffix("s") {
            return "\(name)' hub"
        }
        return "\(name)'s hub"
    }
    static let verifiedHubsChannel = "Verified \(hubsBrand) channel"
    static let longFormOnHubs = "Long-form on \(hubsBrand)"
    static let sparksOnHubs = "Short vertical video on \(hubsBrand)"
    static let hubsPublishHint = "Follow creators or publish on \(hubsBrand)."
    static let hubsLoadError = "Couldn't load \(hubsBrand) right now. Pull to refresh or check your connection."
    static let hubsNoChannelVideos = "This creator hub has no videos on \(hubsBrand) yet."
    static let hubsVideoUnavailable = "This video isn't available on \(hubsBrand)."
    static let postToYourFeed = "Post to the main feed"
    static let shareToYourFeed = "Share to the main feed"
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

    // MARK: Masquerade (Anonymous mode)

    private static let masqueradeBrand = "Matterya\(nbsp)Masquerade"

    /// Short product name (tabs, short labels).
    static let anonymous = "Masquerade"
    /// Header wordmark — same pattern as Matterya Hubs.
    static let matteryaMasquerade = masqueradeBrand
    /// Kept as the mode chip under the title where a chip is useful.
    static let anonymousModeChip = "Anonymous mode"
    static let anonymousTagline = "Leave your identity outside."
    static let anonymousWildeQuote =
        "“Give him a mask, and he will tell you the truth.”"
    static let anonymousWildeAttribution = "— Oscar Wilde, 1891"
    static let anonymousPrivacyBoundary =
        "Your Masquerade name is public inside Spaces. Other members can’t see your Matterya profile. Matterya may link identities for safety and legal compliance."
    static let anonymousUnder18Title = "Adults only"
    static let anonymousUnder18Body =
        "Masquerade is only available to people 18 and older. No posts, Spaces, or search are shown until age eligibility is confirmed."
    static let anonymousMissingBirthdateTitle = "Birthday needed"
    static let anonymousMissingBirthdateBody =
        "Add your birthday in Matterya profile settings before entering Masquerade."
    static let anonymousAgeGateHint = "Return to Matterya from the tab bar anytime."
    static let anonymousAttestTitle = "Confirm you’re 18+"
    static let anonymousAttestBody =
        "Before entering Masquerade, confirm you are at least 18 years old. Private Space content stays hidden until you do."
    static let anonymousAttestFinePrint =
        "False confirmation may result in account restrictions. Age assurance may be re-checked over time."
    static let anonymousClaimTitle = "Choose your Masquerade name"
    static let anonymousClaimBody =
        "You’ll get one persistent username for all Spaces. It’s separate from your Matterya profile."
    static let anonymousClaimIrreversible =
        "Usernames can’t be changed later. Pick carefully."
    static let anonymousClaimGeneratedOnly =
        "v1 usernames are generated for you — custom real-name handles aren’t allowed."
    static let anonymousNoSpaces = "No Spaces yet"
    static let anonymousNoSpacesBody = "Create a free Space or pull to refresh when more appear."
    static let anonymousNoJoinedSpaces = "No joined Spaces"
    static let anonymousNoJoinedSpacesBody = "Join a free Space to see it here."
    static let anonymousPaidComingSoonTitle = "Paid Spaces coming soon"
    static let anonymousPaidComingSoonBody =
        "Paid memberships aren’t live yet. You can browse labels, but joining paid Spaces stays disabled."
    static let anonymousPaidJoinDisabled =
        "Paid join isn’t available yet. Billing will unlock this Space later."
    static let anonymousSpaceMissing = "Space unavailable"
    static let anonymousSpaceMissingBody = "This Space may be private, removed, or temporarily unavailable."
    static let anonymousSpaceEmptyPosts =
        "No posts yet. Seed a thoughtful first conversation."
    static let anonymousFeedEmptyTitle = "Nothing in your feed"
    static let anonymousFeedEmptyBody =
        "Pull to refresh — free Spaces show up here automatically."
    static let anonymousFeedWakeTitle = "Still waking up"
    static let anonymousFeedWakeBody =
        "Masquerade timed out on the first try. Pull to refresh — posts are already live."
    static let anonymousNoComments = "No comments yet — start the thread."
    static let anonymousComposerPrivacyNudge =
        "Don’t share real names, contact info, or anything that links to your Matterya profile."
    static let anonymousMeHint =
        "This identity is only for Masquerade. Your ordinary Matterya avatar and name never appear here."
    static let anonymousExportPlaceholder = "Masquerade data export will open a request flow soon."
    static let anonymousDeletePlaceholder = "Masquerade deletion requests will open a support flow soon."
    static let anonymousSearchTitle = "Search Masquerade"
    static let anonymousSearchHint = "Find Spaces and text posts you’ve already been shown."
    static let anonymousSearchEmptyTitle = "No matches"
    static let anonymousSearchEmptyBody = "Try another keyword. Private Spaces won’t appear in search."
    static let anonymousNotificationsTitle = "No Masquerade notifications yet"
    static let anonymousNotificationsBody =
        "Replies, mentions, and Space updates land only here — never mixed with Matterya notifications or Inbox."
    static let anonymousMessagesInboxTitle = "Inbox is empty"
    static let anonymousMessagesInboxBody =
        "Messages with people (and official Matterya) show up here. Notifications stay under the bell."
    static let anonymousInboxPrivacyNote =
        "Lock-screen and push copy won’t reveal Space titles to unauthorized recipients."
    static let anonymousModPlaceholderBody =
        "Moderator queue, removals, and sanctions will appear here. Platform policy still outranks Space rules."
    static let anonymousSuspendedTitle = "Masquerade suspended"
    static let anonymousSuspendedBody =
        "Your Masquerade access is restricted. Contact support if you believe this is a mistake."
    static let anonymousOfflineTitle = "Masquerade isn’t live yet"
    static let anonymousOfflineBody =
        "The Masquerade API isn’t reachable on this build. After the server migration and Manual Deploy, pull to try again."
    static let anonymousCreateMenuTitle = "Create in Masquerade"
    static let anonymousCreateSpace = "Create a Space"
    static let anonymousCreatePost = "New post in a Space"
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
            // minWidth:0 lets long titles wrap inside edge-to-edge cards (no horizontal blowout).
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .matteryaPrimaryFill(pressed: configuration.isPressed)
    }
}

/// Matterya settings / menu row — paper card, not UIKit grouped List chrome.
struct MatteryaSettingsRowButtonStyle: ButtonStyle {
    var destructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .matteryaSettingsCard(
                destructive: destructive,
                pressed: configuration.isPressed
            )
    }
}

extension View {
    /// Bake Matterya paper chrome into the label itself — survives NavigationLink / PhotosPicker
    /// (those ignore ButtonStyle and fall back to Apple blue/bordered).
    func matteryaSettingsCard(destructive: Bool = false, pressed: Bool = false) -> some View {
        font(.body.weight(.medium))
            .foregroundStyle(destructive ? Theme.danger : Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(pressed ? Theme.matteDeep : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.border.opacity(0.85), lineWidth: 0.5)
            )
    }

    /// Solid Matterya control fill (ink pill) — primary actions.
    func matteryaPrimaryFill(pressed: Bool = false) -> some View {
        font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.paper)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(Theme.ink.opacity(pressed ? 0.82 : 1))
            )
    }

    /// Matte outlined Matterya control — secondary actions.
    func matteryaSecondaryFill(pressed: Bool = false) -> some View {
        font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(pressed ? Theme.matteDeep : Theme.matte)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
    }

    /// Profile / settings text pill — no SF Symbols, flat paper.
    func matteryaTextPill(
        pressed: Bool = false,
        emphasized: Bool = false,
        compact: Bool = false
    ) -> some View {
        font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
            .foregroundStyle(emphasized ? Theme.paper : Theme.ink)
            .multilineTextAlignment(.center)
            .frame(maxWidth: compact ? nil : .infinity)
            .padding(.horizontal, compact ? 14 : 14)
            .padding(.vertical, compact ? 8 : 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(
                        emphasized
                            ? Theme.ink.opacity(pressed ? 0.82 : 1)
                            : (pressed ? Theme.matteDeep : Theme.matte)
                    )
            )
            .overlay {
                if !emphasized {
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .stroke(Theme.border, lineWidth: 0.5)
                }
            }
    }
}

/// Text-first Matterya pill — profile Edit / Settings / Hubs channel.
struct MatteryaTextPillButtonStyle: ButtonStyle {
    var emphasized: Bool = false
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .matteryaTextPill(
                pressed: configuration.isPressed,
                emphasized: emphasized,
                compact: compact
            )
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .instagramButton()
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Outlined / secondary Matterya control — matte paper, ink label (not Apple bordered).
struct MatteryaSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .matteryaSecondaryFill(pressed: configuration.isPressed)
    }
}

/// Flat Matterya switch — replaces system Toggle chrome in Settings.
struct MatteryaSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(MatteryaMotion.micro) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn ? Theme.ink : Theme.matteDeep)
                    .frame(width: 48, height: 28)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Theme.border.opacity(isOn ? 0 : 0.9), lineWidth: 0.5)
                    )
                Circle()
                    .fill(Theme.paper)
                    .frame(width: 22, height: 22)
                    .padding(3)
                    .shadow(color: Theme.ink.opacity(0.12), radius: 1, y: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
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