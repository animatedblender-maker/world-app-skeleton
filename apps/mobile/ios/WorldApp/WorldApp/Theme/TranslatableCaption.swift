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
#if canImport(Translation)
    @State private var configuration: TranslationSession.Configuration?
#endif

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
#if canImport(Translation)
                .modifier(TranslationHooks(
                    sourceText: trimmed,
                    configuration: $configuration,
                    showSystemSheet: $showSystemSheet,
                    onTranslated: { result in
                        translated = result
                        showingTranslated = true
                        isTranslating = false
                    },
                    onFailed: {
                        isTranslating = false
                    }
                ))
#endif
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

#if canImport(Translation)
        if #available(iOS 18.0, *) {
            isTranslating = true
            // Auto-detect source → English.
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
            return
        }
        if #available(iOS 17.4, *) {
            showSystemSheet = true
            return
        }
#endif
    }

    private func resetTranslation() {
        translated = nil
        showingTranslated = false
        isTranslating = false
        showSystemSheet = false
#if canImport(Translation)
        configuration = nil
#endif
    }
}

#if canImport(Translation)
/// Attaches iOS 18 `translationTask` + iOS 17.4 `translationPresentation` without
/// polluting the main view's availability checks.
private struct TranslationHooks: ViewModifier {
    let sourceText: String
    @Binding var configuration: TranslationSession.Configuration?
    @Binding var showSystemSheet: Bool
    let onTranslated: (String) -> Void
    let onFailed: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
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
                .translationPresentation(isPresented: $showSystemSheet, text: sourceText) { replaced in
                    let out = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !out.isEmpty {
                        onTranslated(out)
                    }
                }
        } else if #available(iOS 17.4, *) {
            content
                .translationPresentation(isPresented: $showSystemSheet, text: sourceText) { replaced in
                    let out = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !out.isEmpty {
                        onTranslated(out)
                    }
                }
        } else {
            content
        }
    }
}
#endif
