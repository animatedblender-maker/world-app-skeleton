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
    static func worldHop() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.75)
        }
    }

    static func globeShuffle() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.9)
    }

    static func pullDismiss() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.85)
    }
}

enum MatteryaPullDownDismiss {
    static let dismissDistance: CGFloat = 160
    static let predictedDismissDistance: CGFloat = 300

    static func shouldDismiss(_ value: DragGesture.Value) -> Bool {
        value.translation.height > dismissDistance
            || value.predictedEndTranslation.height > predictedDismissDistance
    }

    static func applyChanged(
        _ value: DragGesture.Value,
        offset: inout CGFloat,
        isDragging: inout Bool
    ) {
        let vertical = value.translation.height
        let horizontal = abs(value.translation.width)
        guard vertical > 28, vertical > horizontal * 0.85 else {
            if isDragging, vertical <= 4 {
                isDragging = false
                offset = 0
            }
            return
        }
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
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            offset = 0
        }
    }
}

extension View {
    func matteryaPullDownDismissTransform(offset: CGFloat) -> some View {
        let progress = min(max(offset, 0) / 320, 1)
        return self
            .offset(y: offset)
            .scaleEffect(1 - progress * 0.06, anchor: .top)
            .opacity(Double(1 - progress * 0.35))
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
            Text(CountryFlag.emoji(for: moment.countryCode))
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(moment.isHomeCountry ? "Back home" : "World hop")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.82))
                Text(locationLine)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
            Image(systemName: moment.isHomeCountry ? "house.fill" : "globe.americas.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.reelsAccent)
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

    private var locationLine: String {
        if let city = moment.cityName?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            return "\(city), \(moment.countryName)"
        }
        return moment.countryName
    }
}

/// Compact shelf UI that sits below the Dynamic Island during full-screen Reels.
struct ReelsIslandStrip: View {
    let post: CountryPost?
    let passport: ReelsPassport

    var body: some View {
        HStack(spacing: 6) {
            Text(CountryFlag.emoji(for: post?.countryCode))
                .font(.caption)
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

    private var locationLabel: String {
        guard let post else { return MatteryaCopy.matteryaSparks }
        if let city = post.cityName?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            return city
        }
        return post.countryName ?? post.countryCode?.uppercased() ?? MatteryaCopy.sparks
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
            Image(systemName: systemName)
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Theme.ink.opacity(0.52), in: Circle())
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
            HStack(spacing: 6) {
                Text(CountryFlag.emoji(for: post.countryCode))
                    .font(.caption)
                Text(chipLabel)
                    .font(.caption.weight(.semibold))
                if isHomeCountry {
                    Text("Home")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.reelsAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accentSoft, in: Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .opacity(0.7)
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var chipLabel: String {
        if let city = post.cityName?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            return city
        }
        return post.countryName ?? post.countryCode?.uppercased() ?? "Explore"
    }
}