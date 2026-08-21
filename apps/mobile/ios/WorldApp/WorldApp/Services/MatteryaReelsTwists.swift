import SwiftUI
import UIKit

enum CountryFlag {
    static func emoji(for iso: String?) -> String {
        guard let iso else { return "🌍" }
        let code = iso.uppercased()
        guard code.count == 2, code.unicodeScalars.allSatisfy(\.isASCII) else { return "🌍" }
        let base: UInt32 = 127397
        let scalars = code.unicodeScalars.compactMap { UnicodeScalar(base + $0.value) }
        guard scalars.count == 2 else { return "🌍" }
        return String(String.UnicodeScalarView(scalars))
    }
}

enum MatteryaCountryBridge {
    static func country(from post: CountryPost) -> Country? {
        guard let code = post.countryCode?.uppercased(), !code.isEmpty else { return nil }
        let name = post.countryName ?? code
        return Country(id: code, name: name, iso: code, continent: nil, centerLat: nil, centerLng: nil)
    }

    static func isHomeCountry(post: CountryPost, viewerCountryCode: String?) -> Bool {
        guard let viewer = viewerCountryCode?.uppercased(),
              let postCode = post.countryCode?.uppercased(),
              !viewer.isEmpty, !postCode.isEmpty
        else { return false }
        return viewer == postCode
    }
}

struct ReelsWorldHopMoment: Equatable {
    let countryCode: String
    let countryName: String
    let cityName: String?
    let isHomeCountry: Bool
}

enum ReelsTwistHaptics {
    /// No-op — country hop while scrolling must stay silent (user request).
    static func worldHop() {}

    /// Soft tap only for intentional globe shuffle button (not scroll).
    static func globeShuffle() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.4)
    }

    static func pullDismiss() {
        // Silent — pull-to-dismiss shouldn't buzz either.
    }
}

/// Full-screen Sparks stage gravity (Facebook / IG Reels style).
///
/// • Portrait / square → always **fill** (covers notch; slight side crop is OK).
/// • Landscape → **fill** only if crop is small; else **fit** (letterbox, no hard crop-zoom).
/// • Unknown → **fill** (most Sparks are vertical; stage stays full-bleed under the island).
enum SparksStageLayout {
    /// For landscape only: max crop on the tight axis when filling.
    static let maxLandscapeCropFraction: CGFloat = 0.12

    static func shouldFillWithoutCrop(videoSize: CGSize, stageSize: CGSize) -> Bool {
        // Unknown size: caller decides optimistic default (ShortForm → fit, TikTok → fill).
        guard videoSize.width > 2, videoSize.height > 2 else { return true }
        guard stageSize.width > 2, stageSize.height > 2 else { return true }

        // True portrait (taller than wide) — fill the stage (TikTok / Reels).
        // Require clear portrait so 4:3 / 16:9 ShortForm never zoom-crops the dock.
        if videoSize.height > videoSize.width * 1.05 {
            return true
        }

        // Landscape / square / 4:3: fill only when crop is tiny.
        let scaleFit = min(stageSize.width / videoSize.width, stageSize.height / videoSize.height)
        let scaleFill = max(stageSize.width / videoSize.width, stageSize.height / videoSize.height)
        guard scaleFill > 0.0001 else { return false }
        let visibleFraction = scaleFit / scaleFill
        return visibleFraction >= (1 - maxLandscapeCropFraction)
    }

    static var defaultStageSize: CGSize {
        physicalScreenSize
    }

    /// Physical screen — Sparks pages are always full-screen; never size video to a settling layout.
    static var physicalScreenSize: CGSize {
        if let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }) {
            let s = scene.screen.bounds.size
            if s.width > 2, s.height > 2 { return s }
        }
        return UIScreen.main.bounds.size
    }

    static var physicalScreenBounds: CGRect {
        CGRect(origin: .zero, size: physicalScreenSize)
    }

    /// True when a view is already full-page (not mid-layout zero/partial bounds).
    static func isStableFullStage(_ bounds: CGRect) -> Bool {
        let screen = physicalScreenSize
        return bounds.width >= screen.width - 2
            && bounds.height >= screen.height * 0.85
    }

    /// Prefer real bounds; if the host is still 0×0 / tiny, use the screen so the
    /// first painted AVPlayerLayer frame is already full-screen (no grow-in blink).
    static func stageFrame(forHostBounds bounds: CGRect) -> CGRect {
        if isStableFullStage(bounds) {
            return CGRect(origin: .zero, size: bounds.size)
        }
        return physicalScreenBounds
    }
}

enum MatteryaPullDownDismiss {
    /// YouTube-style: full collapse over this pull distance.
    static let dismissDistance: CGFloat = 220
    /// Strong fling predicted end → commit mini (YouTube velocity).
    static let predictedDismissDistance: CGFloat = 320
    /// Pull distance that maps to collapse progress 1.0.
    static let chromeFadeDistance: CGFloat = 220
    /// Release below this progress (and weak velocity) → snap back to expanded.
    static let releaseSnapBackProgress: CGFloat = 0.32
    static let releaseSnapBackTranslation: CGFloat = 70
    /// Predicted end Y above this commits mini even if progress is mid-way.
    static let flingCommitPredicted: CGFloat = 200

    static func shouldDismiss(_ value: DragGesture.Value) -> Bool {
        value.translation.height > dismissDistance
            || value.predictedEndTranslation.height > predictedDismissDistance
    }

    /// YouTube mini-player commit rules:
    /// - progress ≥ ~1/3 → mini
    /// - strong downward fling → mini
    /// - otherwise spring back to expanded
    static func shouldMinimizeOnRelease(
        _ value: DragGesture.Value,
        dragOffset: CGFloat = 0,
        pullProgress: CGFloat = 0
    ) -> Bool {
        let progress = max(
            pullProgress,
            Self.pullProgress(forVertical: value.translation.height)
        )
        let y = max(0, value.translation.height)
        let predicted = value.predictedEndTranslation.height
        // Velocity-style: finger already “thrown” past the mid zone.
        if predicted > flingCommitPredicted { return true }
        if shouldDismiss(value) { return true }
        // Position threshold (YouTube ~30–40% of the collapse track).
        if progress >= releaseSnapBackProgress { return true }
        if y >= releaseSnapBackTranslation && predicted > 90 { return true }
        return false
    }

    /// 0…1 slider from raw downward translation (moving up lowers the value).
    static func pullProgress(forVertical translationY: CGFloat) -> CGFloat {
        let y = max(0, translationY)
        return min(1, y / chromeFadeDistance)
    }

    /// 0…1 from rubber-banded visual offset (fallback).
    static func pullProgress(forOffset offset: CGFloat) -> CGFloat {
        pullProgress(forVertical: offset)
    }

    static func applyChanged(
        _ value: DragGesture.Value,
        offset: inout CGFloat,
        isDragging: inout Bool
    ) {
        let vertical = value.translation.height
        let horizontal = abs(value.translation.width)

        // Once engaged, keep tracking 1:1 with the finger (slider).
        // Moving up reduces offset so chrome reappears in lockstep.
        if isDragging {
            if vertical <= 0 {
                isDragging = false
                offset = 0
                return
            }
            // Stay engaged while mostly vertical; cancel only on clear horizontal pan.
            if horizontal > vertical * 1.35, vertical < 24 {
                isDragging = false
                offset = 0
                return
            }
            let y = max(0, vertical)
            // Mild rubber-band only far past dismiss — fade uses raw Y via pullProgress.
            if y > 280 {
                let extra = y - 280
                offset = 280 + extra * 0.35
            } else {
                offset = y
            }
            return
        }

        // Engage early so the grab feels glued to the finger (horizontal pans still ignored).
        guard vertical > 6, vertical > horizontal * 0.7 else { return }
        isDragging = true
        offset = vertical
    }

    static func applyEnded(
        _ value: DragGesture.Value,
        offset: inout CGFloat,
        isDragging: inout Bool,
        dismiss: () -> Void
    ) {
        isDragging = false
        if shouldDismiss(value) {
            ReelsTwistHaptics.pullDismiss()
            dismiss()
            return
        }
        withAnimation(MatteryaMotion.micro) {
            offset = 0
        }
    }
}

extension View {
    /// Pull-down motion. Set `fadesContent: false` on the video so only chrome fades.
    func matteryaPullDownDismissTransform(offset: CGFloat, fadesContent: Bool = true) -> some View {
        let progress = min(max(offset, 0) / 320, 1)
        return self
            .offset(y: offset)
            .scaleEffect(1 - progress * 0.06, anchor: .top)
            .opacity(fadesContent ? Double(1 - progress * 0.35) : 1)
    }

    func matteryaPullDownToDismiss(
        offset: Binding<CGFloat>,
        isDragging: Binding<Bool>,
        onDismiss: @escaping () -> Void
    ) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 14, coordinateSpace: .local)
                .onChanged { value in
                    var dragOffset = offset.wrappedValue
                    var dragging = isDragging.wrappedValue
                    MatteryaPullDownDismiss.applyChanged(
                        value,
                        offset: &dragOffset,
                        isDragging: &dragging
                    )
                    offset.wrappedValue = dragOffset
                    isDragging.wrappedValue = dragging
                }
                .onEnded { value in
                    var dragOffset = offset.wrappedValue
                    var dragging = isDragging.wrappedValue
                    MatteryaPullDownDismiss.applyEnded(
                        value,
                        offset: &dragOffset,
                        isDragging: &dragging,
                        dismiss: onDismiss
                    )
                    offset.wrappedValue = dragOffset
                    isDragging.wrappedValue = dragging
                }
        )
    }
}

struct ReelsPassport: Equatable {
    private(set) var visitedCodes: [String] = []

    mutating func visit(_ code: String?) {
        guard let code = code?.uppercased(), !code.isEmpty else { return }
        if !visitedCodes.contains(code) {
            visitedCodes.append(code)
        }
    }

    var placeCount: Int { visitedCodes.count }

    var label: String {
        switch placeCount {
        case 0: MatteryaCopy.matteryaSparks
        case 1: "1 place"
        default: "\(placeCount) places"
        }
    }
}

struct ReelsWorldHopBanner: View {
    let moment: ReelsWorldHopMoment

    var body: some View {
        HStack(spacing: 10) {
            // Country name only — no flag emoji in Sparks.
            Image(systemName: moment.isHomeCountry ? "house.fill" : "globe.americas.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.reelsAccent)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(moment.isHomeCountry ? "Back home" : "World hop")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.82))
                Text(moment.countryName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.ink.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
    }
}

/// Compact shelf UI that sits below the Dynamic Island during full-screen Reels.
struct ReelsIslandStrip: View {
    let post: CountryPost?
    let passport: ReelsPassport

    var body: some View {
        HStack(spacing: 6) {
            // Country name only — no flag.
            Text(locationLabel)
                .font(.caption.weight(.bold))
                .lineLimit(1)
            if passport.placeCount > 1 {
                Text("· \(passport.placeCount)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
        .foregroundStyle(.white.opacity(0.94))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Theme.ink.opacity(0.58), in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(islandAccessibilityLabel)
    }

    /// Shared-from country name only (no city, no flag).
    private var locationLabel: String {
        guard let post else { return MatteryaCopy.matteryaSparks }
        if let name = post.countryName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return post.countryCode?.uppercased() ?? MatteryaCopy.sparks
    }

    private var islandAccessibilityLabel: String {
        if passport.placeCount > 1 {
            return "\(locationLabel), \(passport.placeCount) places visited"
        }
        return locationLabel
    }
}

struct ReelsChromeButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Simple off-white mark — no circle chrome (Sparks close).
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ReelsCountryChip: View {
    let post: CountryPost
    let isHomeCountry: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption2.weight(.bold))
                Text(chipLabel)
                    .font(.caption2.weight(.semibold))
                if isHomeCountry {
                    Text("Home")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.accentBright)
                }
            }
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.canvasMuted, in: Capsule())
            .overlay(Capsule().stroke(Theme.border.opacity(0.6), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shared from \(chipLabel)")
    }

    private var chipLabel: String {
        if let name = post.countryName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return post.countryCode?.uppercased() ?? "Explore"
    }
}