import SwiftUI
import UIKit

/// Caption / written-body text.
///
/// Translate UI + Apple TranslationSession are **off** for now (`AppConfig.enableTranslate`)
/// to keep Feed / Sparks / comments lighter. Call-site API kept so restore is one flag flip
/// plus restoring the Translation hooks from git history.
struct TranslatableCaption: View {
    let text: String
    var collapsedLineLimit: Int = 4
    var font: Font = .body
    var color: Color = Theme.inkSecondary
    var lineSpacing: CGFloat = 4
    var moreTitle: String = "See more"
    var lessTitle: String = "See less"
    var uiTextStyle: UIFont.TextStyle = .body
    /// When set **and** `expandable` is false, renders a plain `Text` with this line limit.
    var plainLineLimit: Int? = nil
    var buttonTint: Color = Theme.accentBright
    /// Skip expand/collapse chrome (always plain Text).
    var expandable: Bool = true
    /// Expanded line cap for Sparks dock (grows the frosted box; nil = unlimited).
    var expandedLineLimit: Int? = nil
    /// Ignored while Translate is disabled — kept for call-site compatibility.
    var showsTranslateControl: Bool = true

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if trimmed.isEmpty {
                EmptyView()
            } else if !expandable, let plainLineLimit {
                MatteryaRichText(
                    text: trimmed,
                    font: font,
                    color: color,
                    lineSpacing: lineSpacing,
                    lineLimit: plainLineLimit
                )
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            } else if expandable {
                ExpandableBodyText(
                    text: trimmed,
                    collapsedLineLimit: collapsedLineLimit,
                    font: font,
                    color: color,
                    lineSpacing: lineSpacing,
                    moreTitle: moreTitle,
                    lessTitle: lessTitle,
                    uiTextStyle: uiTextStyle,
                    buttonTint: buttonTint,
                    expandedLineLimit: expandedLineLimit
                )
            } else {
                MatteryaRichText(
                    text: trimmed,
                    font: font,
                    color: color,
                    lineSpacing: lineSpacing
                )
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Shared post-level Translate (stub — feature off)

/// Former one-button Translate for title + body. Empty while `AppConfig.enableTranslate` is false.
struct PostSharedTranslateBar: View {
    let title: String
    let bodyText: String
    var buttonTint: Color = Theme.accentBright

    @Binding var translatedTitle: String?
    @Binding var translatedBody: String?
    @Binding var showingTranslated: Bool

    var body: some View {
        EmptyView()
    }
}
