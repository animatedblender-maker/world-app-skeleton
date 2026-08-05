import SwiftUI
import UIKit

/// Collapsed body text with See more / See less for feed and hub descriptions.
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
    @State private var isTruncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineSpacing(lineSpacing)
                .lineLimit(expanded ? nil : collapsedLineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ExpandableTextHeightKey.self,
                            value: geo.size.height
                        )
                    }
                )

            if isTruncated || expanded {
                Button(expanded ? lessTitle : moreTitle) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        expanded.toggle()
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accentBright)
                .buttonStyle(.plain)
            }
        }
        .background(
            // Measure full height vs collapsed to know if "See more" is needed.
            Text(text)
                .font(font)
                .lineSpacing(lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .background(
                    GeometryReader { full in
                        Color.clear
                            .onAppear { updateTruncation(fullHeight: full.size.height) }
                            .onChange(of: text) { _, _ in
                                updateTruncation(fullHeight: full.size.height)
                            }
                    }
                )
        )
    }

    private func updateTruncation(fullHeight: CGFloat) {
        // Approximate collapsed height from UIFont metrics.
        let uiFont = UIFont.preferredFont(forTextStyle: uiTextStyle)
        let lineHeight = uiFont.lineHeight + lineSpacing
        let collapsedHeight = lineHeight * CGFloat(collapsedLineLimit) + 4
        isTruncated = fullHeight > collapsedHeight + 2
    }
}

private struct ExpandableTextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
