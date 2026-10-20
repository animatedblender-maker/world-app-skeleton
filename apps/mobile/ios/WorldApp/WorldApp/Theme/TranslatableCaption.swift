import SwiftUI
import UIKit
#if canImport(Translation)
import Translation
#endif

/// Caption / written-body text with a small **Translate** control (→ English first).
///
/// - iOS 18+: on-device `TranslationSession` into English, swaps text inline.
/// - iOS 17.4–17.x: system translation sheet; Replace swaps text inline.
/// - Earlier OS: text only (no button).
struct TranslatableCaption: View {
    let text: String
    var collapsedLineLimit: Int = 4
    var font: Font = .body
    var color: Color = Theme.inkSecondary
    var lineSpacing: CGFloat = 4
    var moreTitle: String = "See more"
    var lessTitle: String = "See less"
    var uiTextStyle: UIFont.TextStyle = .body
    /// When set, renders a plain `Text` with this line limit (Sparks / Reels dock).
    var plainLineLimit: Int? = nil
    var buttonTint: Color = Theme.accentBright
    /// Skip expand/collapse chrome (always plain Text + Translate).
    var expandable: Bool = true

    @State private var translated: String?
    @State private var showingTranslated = false
    @State private var showSystemSheet = false
    @State private var isTranslating = false
    /// Bumped to kick off an iOS 18 inline English translation.
    @State private var englishSessionTrigger = 0

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayText: String {
        if showingTranslated, let translated, !translated.isEmpty {
            return translated
        }
        return trimmed
    }

    private var translationAvailable: Bool {
        if #available(iOS 17.4, *) { return true }
        return false
    }

    var body: some View {
        Group {
            if trimmed.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    captionContent

                    if translationAvailable {
                        translateControl
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .onChange(of: text) { _, _ in
                    resetTranslation()
                }
                .modifier(TranslationAvailabilityHooks(
                    sourceText: trimmed,
                    showSystemSheet: $showSystemSheet,
                    englishSessionTrigger: englishSessionTrigger,
                    onTranslated: { result in
                        translated = result
                        showingTranslated = true
                        isTranslating = false
                    },
                    onFailed: {
                        isTranslating = false
                    }
                ))
            }
        }
    }

    @ViewBuilder
    private var captionContent: some View {
        if let plainLineLimit {
            Text(displayText)
                .font(font)
                .foregroundStyle(color)
                .lineSpacing(lineSpacing)
                .lineLimit(plainLineLimit)
                .multilineTextAlignment(.leading)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        } else if expandable {
            ExpandableBodyText(
                text: displayText,
                collapsedLineLimit: collapsedLineLimit,
                font: font,
                color: color,
                lineSpacing: lineSpacing,
                moreTitle: moreTitle,
                lessTitle: lessTitle,
                uiTextStyle: uiTextStyle
            )
        } else {
            Text(displayText)
                .font(font)
                .foregroundStyle(color)
                .lineSpacing(lineSpacing)
                .multilineTextAlignment(.leading)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
    }

    private var translateControl: some View {
        Button {
            handleTranslateTap()
        } label: {
            HStack(spacing: 4) {
                if isTranslating {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(buttonTint)
                } else {
                    Image(systemName: "translate")
                        .font(.caption2.weight(.semibold))
                }
                Text(showingTranslated ? "Show original" : "Translate")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(buttonTint)
        }
        .buttonStyle(.plain)
        .disabled(isTranslating)
        .accessibilityLabel(showingTranslated ? "Show original text" : "Translate to English")
    }

    private func handleTranslateTap() {
        if showingTranslated {
            showingTranslated = false
            return
        }
        if let translated, !translated.isEmpty {
            showingTranslated = true
            return
        }

        if #available(iOS 18.0, *) {
            isTranslating = true
            englishSessionTrigger &+= 1
            return
        }
        if #available(iOS 17.4, *) {
            showSystemSheet = true
            return
        }
    }

    private func resetTranslation() {
        translated = nil
        showingTranslated = false
        isTranslating = false
        showSystemSheet = false
        englishSessionTrigger = 0
    }
}

// MARK: - Availability bridges (keep iOS 18 types off the iOS 17-deployed struct)

/// Routes to the right Translation API without putting `TranslationSession` on
/// types that compile against the iOS 17 deployment target.
private struct TranslationAvailabilityHooks: ViewModifier {
    let sourceText: String
    @Binding var showSystemSheet: Bool
    let englishSessionTrigger: Int
    let onTranslated: (String) -> Void
    let onFailed: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .modifier(
                    InlineEnglishTranslation(
                        sourceText: sourceText,
                        trigger: englishSessionTrigger,
                        onTranslated: onTranslated,
                        onFailed: onFailed
                    )
                )
                .modifier(
                    SystemTranslationSheet(
                        sourceText: sourceText,
                        showSystemSheet: $showSystemSheet,
                        onTranslated: onTranslated
                    )
                )
        } else if #available(iOS 17.4, *) {
            content
                .modifier(
                    SystemTranslationSheet(
                        sourceText: sourceText,
                        showSystemSheet: $showSystemSheet,
                        onTranslated: onTranslated
                    )
                )
        } else {
            content
        }
    }
}

#if canImport(Translation)
@available(iOS 18.0, *)
private struct InlineEnglishTranslation: ViewModifier {
    let sourceText: String
    let trigger: Int
    let onTranslated: (String) -> Void
    let onFailed: () -> Void

    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { @MainActor session in
                do {
                    let response = try await session.translate(sourceText)
                    let out = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if out.isEmpty {
                        onFailed()
                    } else {
                        onTranslated(out)
                    }
                } catch {
                    onFailed()
                }
            }
            .onChange(of: trigger) { _, newValue in
                guard newValue > 0 else { return }
                let next = TranslationSession.Configuration(
                    source: nil,
                    target: Locale.Language(identifier: "en")
                )
                if configuration == nil {
                    configuration = next
                } else {
                    configuration?.invalidate()
                    configuration = next
                }
            }
    }
}

@available(iOS 17.4, *)
private struct SystemTranslationSheet: ViewModifier {
    let sourceText: String
    @Binding var showSystemSheet: Bool
    let onTranslated: (String) -> Void

    func body(content: Content) -> some View {
        content
            .translationPresentation(isPresented: $showSystemSheet, text: sourceText) { replaced in
                let out = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
                if !out.isEmpty {
                    onTranslated(out)
                }
            }
    }
}
#else
@available(iOS 18.0, *)
private struct InlineEnglishTranslation: ViewModifier {
    let sourceText: String
    let trigger: Int
    let onTranslated: (String) -> Void
    let onFailed: () -> Void

    func body(content: Content) -> some View { content }
}

@available(iOS 17.4, *)
private struct SystemTranslationSheet: ViewModifier {
    let sourceText: String
    @Binding var showSystemSheet: Bool
    let onTranslated: (String) -> Void

    func body(content: Content) -> some View { content }
}
#endif
