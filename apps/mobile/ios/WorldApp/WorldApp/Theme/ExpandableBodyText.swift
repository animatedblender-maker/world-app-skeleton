import SwiftUI
import UIKit

/// Lightweight inline markup for posts and messages:
/// - `# heading` (line-leading `# ` → larger bold header; marker not shown)
/// - `**bold**`
/// - `*italic*`
/// Composer rich-text controls can come later; storage stays plain text with markers.
enum MatteryaMarkdown {
    struct Segment: Equatable {
        let text: String
        let bold: Bool
        let italic: Bool
        let heading: Bool
    }

    /// Parse line-leading `# ` headers, then `**bold**`, then `*italic*`.
    static func segments(_ string: String) -> [Segment] {
        var out: [Segment] = []
        let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
        for (idx, lineSub) in lines.enumerated() {
            let line = String(lineSub)
            if idx > 0 {
                out.append(Segment(text: "\n", bold: false, italic: false, heading: false))
            }
            let trimmedLeading = line.drop(while: { $0 == " " || $0 == "\t" })
            if trimmedLeading.hasPrefix("# ") {
                let title = String(trimmedLeading.dropFirst(2))
                if title.isEmpty {
                    out.append(Segment(text: "", bold: false, italic: false, heading: false))
                } else {
                    // Headers are always bold; still allow nested ** / * inside.
                    for seg in inlineSegments(title) {
                        out.append(
                            Segment(
                                text: seg.text,
                                bold: true,
                                italic: seg.italic,
                                heading: true
                            )
                        )
                    }
                }
            } else {
                out.append(contentsOf: inlineSegments(line))
            }
        }
        return out
    }

    private static func inlineSegments(_ string: String) -> [Segment] {
        var out: [Segment] = []
        for boldRun in boldRuns(string) {
            if boldRun.bold {
                out.append(Segment(text: boldRun.text, bold: true, italic: false, heading: false))
            } else {
                out.append(contentsOf: italicRuns(boldRun.text))
            }
        }
        return out
    }

    private struct BoldRun {
        let text: String
        let bold: Bool
    }

    private static func boldRuns(_ string: String) -> [BoldRun] {
        var out: [BoldRun] = []
        var remaining = Substring(string)
        while let open = remaining.range(of: "**") {
            let before = String(remaining[..<open.lowerBound])
            if !before.isEmpty {
                out.append(BoldRun(text: before, bold: false))
            }
            remaining = remaining[open.upperBound...]
            if let close = remaining.range(of: "**") {
                let mid = String(remaining[..<close.lowerBound])
                if mid.isEmpty {
                    out.append(BoldRun(text: "****", bold: false))
                } else {
                    out.append(BoldRun(text: mid, bold: true))
                }
                remaining = remaining[close.upperBound...]
            } else {
                out.append(BoldRun(text: "**" + remaining, bold: false))
                remaining = ""
                break
            }
        }
        if !remaining.isEmpty {
            out.append(BoldRun(text: String(remaining), bold: false))
        }
        return out
    }

    /// Split plain text on paired single `*…*` (not `**`).
    private static func italicRuns(_ string: String) -> [Segment] {
        var out: [Segment] = []
        var i = string.startIndex
        while i < string.endIndex {
            guard let open = string[i...].firstIndex(of: "*") else {
                out.append(Segment(text: String(string[i...]), bold: false, italic: false, heading: false))
                break
            }
            if open > i {
                out.append(Segment(text: String(string[i..<open]), bold: false, italic: false, heading: false))
            }
            let afterOpen = string.index(after: open)
            if afterOpen < string.endIndex, string[afterOpen] == "*" {
                out.append(Segment(text: "**", bold: false, italic: false, heading: false))
                i = string.index(after: afterOpen)
                continue
            }
            if let close = string[afterOpen...].firstIndex(of: "*") {
                let afterClose = string.index(after: close)
                if afterClose < string.endIndex, string[afterClose] == "*" {
                    out.append(Segment(text: "*", bold: false, italic: false, heading: false))
                    i = afterOpen
                    continue
                }
                let mid = String(string[afterOpen..<close])
                if mid.isEmpty {
                    out.append(Segment(text: "**", bold: false, italic: false, heading: false))
                } else {
                    out.append(Segment(text: mid, bold: false, italic: true, heading: false))
                }
                i = afterClose
            } else {
                out.append(Segment(text: String(string[open...]), bold: false, italic: false, heading: false))
                break
            }
        }
        return out
    }

    /// Markers stripped — for inbox previews and truncation measurement.
    static func plain(_ string: String) -> String {
        segments(string).map(\.text).joined()
    }

    /// SwiftUI `Text` with heading / bold / italic runs.
    /// Font is applied per segment so `.bold()` / heading size survive (a trailing
    /// `.font(.body)` on the combined `Text` would wipe weight).
    static func text(_ string: String, baseFont: Font = .body) -> Text {
        let segs = segments(string)
        guard segs.contains(where: { $0.bold || $0.italic || $0.heading }) else {
            return Text(string).font(baseFont)
        }
        return segs.reduce(Text("")) { partial, seg in
            let font: Font = {
                if seg.heading {
                    return .title3.weight(.bold)
                }
                if seg.bold, seg.italic {
                    return baseFont.bold().italic()
                }
                if seg.bold {
                    return baseFont.bold()
                }
                if seg.italic {
                    return baseFont.italic()
                }
                return baseFont
            }()
            return partial + Text(seg.text).font(font)
        }
    }
}

/// Post/message body that renders `#` headers, `**bold**`, and `*italic*` markers.
struct MatteryaRichText: View {
    let text: String
    var font: Font = .body
    var color: Color = Theme.ink
    var lineSpacing: CGFloat = 0
    var lineLimit: Int? = nil
    var multilineTextAlignment: TextAlignment = .leading

    var body: some View {
        MatteryaMarkdown.text(text, baseFont: font)
            .foregroundStyle(color)
            .lineSpacing(lineSpacing)
            .lineLimit(lineLimit)
            .multilineTextAlignment(multilineTextAlignment)
    }
}

/// Collapsed body text with See more / See less — only when text is actually truncated.
struct ExpandableBodyText: View {
    let text: String
    var collapsedLineLimit: Int = 3
    var font: Font = .body
    var color: Color = Theme.inkSecondary
    var lineSpacing: CGFloat = 4
    var moreTitle: String = "See more"
    var lessTitle: String = "See less"
    var uiTextStyle: UIFont.TextStyle = .body
    /// See more / See less tint (paper on Sparks dock; ink on Feed cards).
    var buttonTint: Color = Theme.ink
    /// When set, expanded state uses this line cap (grows the box; avoids nested scroll in Sparks pager).
    var expandedLineLimit: Int? = nil

    @State private var expanded = false
    /// True only when full text needs more lines than `collapsedLineLimit` at the live width.
    @State private var isTruncated = false
    @State private var layoutWidth: CGFloat = 0

    var body: some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Group {
            if trimmed.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    MatteryaMarkdown.text(trimmed, baseFont: font)
                        .foregroundStyle(color)
                        .lineSpacing(lineSpacing)
                        .lineLimit(expanded ? expandedLineLimit : collapsedLineLimit)
                        .multilineTextAlignment(.leading)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { noteWidth(geo.size.width, text: trimmed) }
                                    .onChange(of: geo.size.width) { _, w in
                                        noteWidth(w, text: trimmed)
                                    }
                            }
                        )

                    // Only when collapsed text is actually cut off — never a no-op control.
                    if isTruncated || expanded {
                        Button(expanded ? lessTitle : moreTitle) {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                expanded.toggle()
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(buttonTint)
                        .buttonStyle(.plain)
                        .accessibilityHint(
                            expanded
                                ? "Collapse description"
                                : "Expand full description"
                        )
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .onChange(of: text) { _, _ in
                    expanded = false
                    recomputeTruncation(for: text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .onChange(of: collapsedLineLimit) { _, _ in
                    recomputeTruncation(for: trimmed)
                }
            }
        }
    }

    private func noteWidth(_ width: CGFloat, text: String) {
        let w = max(0, width)
        if abs(w - layoutWidth) > 0.5 {
            layoutWidth = w
        }
        recomputeTruncation(for: text)
    }

    private func recomputeTruncation(for trimmed: String) {
        guard !trimmed.isEmpty else {
            isTruncated = false
            return
        }

        // Measure without markup markers so truncation matches rendered width.
        let plain = MatteryaMarkdown.plain(trimmed)
        let newlines = plain.reduce(0) { $0 + ($1.isNewline ? 1 : 0) }
        // Skip measure only when copy clearly fits the collapsed limit (tight for 2-line Sparks).
        let safeCharBudget = max(24, collapsedLineLimit * 36)
        if newlines == 0, plain.count <= safeCharBudget {
            isTruncated = false
            return
        }

        // Need a real width to know if wrapping exceeds the line limit.
        guard layoutWidth > 8 else {
            // Before layout: only multi-paragraph / very long copy may need expand.
            isTruncated = newlines + 1 > collapsedLineLimit || plain.count > safeCharBudget + 40
            return
        }

        let uiFont = UIFont.preferredFont(forTextStyle: uiTextStyle)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let attrs: [NSAttributedString.Key: Any] = [
            .font: uiFont,
            .paragraphStyle: paragraph,
        ]
        let constraint = CGSize(width: layoutWidth, height: .greatestFiniteMagnitude)
        let fullRect = (plain as NSString).boundingRect(
            with: constraint,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        let lineHeight = max(uiFont.lineHeight, 1) + lineSpacing
        let maxCollapsed = lineHeight * CGFloat(collapsedLineLimit)
        // Small slack so fractional layout never leaves a dead “See more”.
        isTruncated = ceil(fullRect.height) > ceil(maxCollapsed) + 2
    }
}
