import SwiftUI

/// Target countries for an ad campaign: Worldwide, or typed suggestions that become removable tags.
struct AdsCountryTargetField: View {
    /// ISO-3166 alpha-2 codes. Empty = worldwide (server treats `[]` as all countries).
    @Binding var selectedCodes: [String]
    @State private var query = ""
    /// True while the advertiser is picking countries (even before the first tag).
    @State private var forceScoped = false
    @FocusState private var searchFocused: Bool

    private var catalog: [CountryOption] { Self.sharedCatalog }
    private var isScoped: Bool { forceScoped || !selectedCodes.isEmpty }

    private var suggestions: [CountryOption] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 1 else { return [] }
        let selected = Set(selectedCodes.map { $0.uppercased() })
        let upper = q.uppercased()
        let lower = q.lowercased()
        return catalog
            .filter { option in
                guard !selected.contains(option.code) else { return false }
                if option.code.hasPrefix(upper) { return true }
                if option.name.lowercased().hasPrefix(lower) { return true }
                if option.name.lowercased().contains(lower) { return true }
                return option.aliases.contains { $0.hasPrefix(lower) || $0 == lower }
            }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Target countries")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)

            HStack(spacing: 8) {
                scopeChip(title: "Worldwide", selected: !isScoped) {
                    forceScoped = false
                    selectedCodes = []
                    query = ""
                    searchFocused = false
                }
                scopeChip(title: "Specific countries", selected: isScoped) {
                    forceScoped = true
                    searchFocused = true
                }
            }

            if !isScoped {
                Text("Serves in every country. Switch to Specific countries to narrow.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if !selectedCodes.isEmpty {
                    AdsWrappingHStack(spacing: 8, lineSpacing: 8) {
                        ForEach(selectedCodes, id: \.self) { code in
                            countryTag(code: code)
                        }
                    }
                } else {
                    Text("Type below and tap a suggestion — it becomes a tag.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkMuted)
                }

                TextField("Type a country (e.g. Germany or DE)", text: $query)
                    .foregroundStyle(Theme.ink)
                    .tint(Theme.ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($searchFocused)
                    .submitLabel(.done)
                    .onSubmit { commitExactOrFirstSuggestion() }
                    .padding(12)
                    .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.controlRadius)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )

                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions) { option in
                            Button {
                                add(option.code)
                            } label: {
                                HStack {
                                    Text(option.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.ink)
                                    Spacer(minLength: 8)
                                    Text(option.code)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.inkMuted)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if option.id != suggestions.last?.id {
                                Divider().overlay(Theme.border.opacity(0.6))
                            }
                        }
                    }
                    .background(Theme.canvasMuted, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.controlRadius)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )
                }
            }
        }
        .onAppear {
            forceScoped = !selectedCodes.isEmpty
        }
        .onChange(of: selectedCodes) { _, codes in
            if !codes.isEmpty {
                forceScoped = true
            } else if query.isEmpty && !searchFocused {
                // Parent reset / edit of a worldwide campaign.
                forceScoped = false
            }
        }
    }

    private func scopeChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(selected ? Theme.ink : Theme.inkSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    selected ? Theme.matte.opacity(0.92) : Theme.buttonMuted,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func countryTag(code: String) -> some View {
        let label = catalog.first(where: { $0.code == code.uppercased() })?.name ?? code
        return Button {
            remove(code)
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.caption.weight(.semibold))
                Text(code.uppercased())
                    .font(.caption2.weight(.bold))
                    .opacity(0.7)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.matte.opacity(0.9), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(label)")
    }

    private func add(_ code: String) {
        let normalized = code.uppercased()
        guard normalized.count == 2 else { return }
        if !selectedCodes.contains(where: { $0.uppercased() == normalized }) {
            selectedCodes.append(normalized)
        }
        query = ""
        searchFocused = true
    }

    private func remove(_ code: String) {
        selectedCodes.removeAll { $0.uppercased() == code.uppercased() }
    }

    private func commitExactOrFirstSuggestion() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if let exact = catalog.first(where: {
            $0.code == q.uppercased() || $0.name.caseInsensitiveCompare(q) == .orderedSame
        }) {
            add(exact.code)
            return
        }
        if let first = suggestions.first {
            add(first.code)
        }
    }
}

// MARK: - Catalog

private struct CountryOption: Identifiable, Hashable {
    var id: String { code }
    let code: String
    let name: String
    let aliases: [String]
}

extension AdsCountryTargetField {
    fileprivate static let sharedCatalog: [CountryOption] = {
        var options: [CountryOption] = Locale.isoRegionCodes.compactMap { code in
            guard code.count == 2,
                  let name = Locale.current.localizedString(forRegionCode: code),
                  !name.isEmpty
            else { return nil }
            return CountryOption(code: code.uppercased(), name: name, aliases: [])
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Common aliases the API also accepts (typed shortcuts).
        let aliasMap: [String: [String]] = [
            "DE": ["germany", "deutschland"],
            "US": ["usa", "america", "united states"],
            "GB": ["uk", "united kingdom", "england", "britain"],
            "EG": ["egypt"],
            "AL": ["albania"],
            "XK": ["kosovo"],
        ]
        options = options.map { option in
            guard let extra = aliasMap[option.code] else { return option }
            return CountryOption(code: option.code, name: option.name, aliases: extra)
        }
        if !options.contains(where: { $0.code == "XK" }) {
            options.append(CountryOption(code: "XK", name: "Kosovo", aliases: ["kosovo"]))
            options.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return options
    }()
}

// MARK: - Wrapping layout

/// Simple left-to-right wrap for country tags.
struct AdsWrappingHStack: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            maxX = max(maxX, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
