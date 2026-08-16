import SwiftUI
import UIKit

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
                    Text(trimmed)
                        .font(font)
                        .foregroundStyle(color)
                        .lineSpacing(lineSpacing)
                        .lineLimit(expanded ? nil : collapsedLineLimit)
                        .multilineTextAlignment(.leading)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
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
                        .foregroundStyle(Theme.accentBright)
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

        // Obviously short one-liners — never show See more.
        let newlines = trimmed.reduce(0) { $0 + ($1.isNewline ? 1 : 0) }
        if newlines == 0, trimmed.count <= 100 {
            isTruncated = false
            return
        }

        // Need a real width to know if wrapping exceeds the line limit.
        guard layoutWidth > 8 else {
            // Before layout: only multi-paragraph / very long copy may need expand.
            isTruncated = newlines + 1 > collapsedLineLimit || trimmed.count > 180
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
        let fullRect = (trimmed as NSString).boundingRect(
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
