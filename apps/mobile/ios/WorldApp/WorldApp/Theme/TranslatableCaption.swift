import NaturalLanguage
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
/// - Already-English text: no Translate control (Show original still appears after a swap).
/// - Set `showsTranslateControl` false when a parent owns one shared post-level button.
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
    /// When false, only renders text (parent supplies a shared Translate control).
    var showsTranslateControl: Bool = true

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

    private var showsControl: Bool {
        guard showsTranslateControl, translationAvailable else { return false }
        if showingTranslated || isTranslating { return true }
        return !CaptionLanguage.isLikelyEnglish(trimmed)
    }

    var body: some View {
        Group {
            if trimmed.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    captionContent

                    if showsControl {
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
        TranslateControlButton(
            showingTranslated: showingTranslated,
            isTranslating: isTranslating,
            buttonTint: buttonTint
        ) {
            handleTranslateTap()
        }
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

// MARK: - Shared post-level Translate (one button for title + body)

/// One Translate control for an entire post’s visible title + body.
struct PostSharedTranslateBar: View {
    let title: String
    let bodyText: String
    var buttonTint: Color = Theme.accentBright

    @Binding var translatedTitle: String?
    @Binding var translatedBody: String?
    @Binding var showingTranslated: Bool

    @State private var isTranslating = false
    @State private var showSystemSheet = false
    @State private var englishSessionTrigger = 0

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedBody: String {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var combinedForSheet: String {
        [trimmedTitle, trimmedBody].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private var translationAvailable: Bool {
        if #available(iOS 17.4, *) { return true }
        return false
    }

    private var needsTranslate: Bool {
        let parts = [trimmedTitle, trimmedBody].filter { !$0.isEmpty }
        guard !parts.isEmpty else { return false }
        // Hide when every visible part is already English.
        return parts.contains { !CaptionLanguage.isLikelyEnglish($0) }
    }

    private var showsControl: Bool {
        guard translationAvailable else { return false }
        if showingTranslated || isTranslating { return true }
        return needsTranslate
    }

    var body: some View {
        Group {
            if showsControl {
                TranslateControlButton(
                    showingTranslated: showingTranslated,
                    isTranslating: isTranslating,
                    buttonTint: buttonTint
                ) {
                    handleTap()
                }
                .modifier(MultiTranslationHooks(
                    title: trimmedTitle,
                    bodyText: trimmedBody,
                    combinedForSheet: combinedForSheet,
                    showSystemSheet: $showSystemSheet,
                    englishSessionTrigger: englishSessionTrigger,
                    onTranslated: { titleOut, bodyOut in
                        translatedTitle = titleOut
                        translatedBody = bodyOut
                        showingTranslated = true
                        isTranslating = false
                    },
                    onFailed: {
                        isTranslating = false
                    }
                ))
            }
        }
        .onChange(of: title) { _, _ in resetIfSourcesChanged() }
        .onChange(of: bodyText) { _, _ in resetIfSourcesChanged() }
    }

    private func handleTap() {
        if showingTranslated {
            showingTranslated = false
            return
        }
        if translatedTitle != nil || translatedBody != nil {
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

    private func resetIfSourcesChanged() {
        translatedTitle = nil
        translatedBody = nil
        showingTranslated = false
        isTranslating = false
        showSystemSheet = false
        englishSessionTrigger = 0
    }
}

struct TranslateControlButton: View {
    let showingTranslated: Bool
    let isTranslating: Bool
    var buttonTint: Color = Theme.accentBright
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
}

// MARK: - Language gate

enum CaptionLanguage {
    /// True when NaturalLanguage is confident the text is English.
    /// Short / ambiguous strings stay eligible for Translate (false).
    static func isLikelyEnglish(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return false }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)

        guard recognizer.dominantLanguage == .english else { return false }
        let englishScore = recognizer.languageHypotheses(withMaximum: 3)[.english] ?? 0
        return englishScore >= 0.72
    }
}

// MARK: - Availability bridges (keep iOS 18 types off the iOS 17-deployed struct)

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

private struct MultiTranslationHooks: ViewModifier {
    let title: String
    let bodyText: String
    let combinedForSheet: String
    @Binding var showSystemSheet: Bool
    let englishSessionTrigger: Int
    let onTranslated: (_ title: String?, _ body: String?) -> Void
    let onFailed: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .modifier(
                    InlineEnglishMultiTranslation(
                        title: title,
                        bodyText: bodyText,
                        trigger: englishSessionTrigger,
                        onTranslated: onTranslated,
                        onFailed: onFailed
                    )
                )
                .modifier(
                    SystemTranslationSheet(
                        sourceText: combinedForSheet,
                        showSystemSheet: $showSystemSheet,
                        onTranslated: { replaced in
                            applyCombinedReplace(replaced)
                        }
                    )
                )
        } else if #available(iOS 17.4, *) {
            content
                .modifier(
                    SystemTranslationSheet(
                        sourceText: combinedForSheet,
                        showSystemSheet: $showSystemSheet,
                        onTranslated: { replaced in
                            applyCombinedReplace(replaced)
                        }
                    )
                )
        } else {
            content
        }
    }

    private func applyCombinedReplace(_ replaced: String) {
        let out = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else {
            onFailed()
            return
        }
        let hasTitle = !title.isEmpty
        let hasBody = !bodyText.isEmpty
        if hasTitle, hasBody, let range = out.range(of: "\n\n") {
            let t = String(out[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let b = String(out[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            onTranslated(t.isEmpty ? nil : t, b.isEmpty ? nil : b)
        } else if hasTitle, !hasBody {
            onTranslated(out, nil)
        } else if hasBody, !hasTitle {
            onTranslated(nil, out)
        } else {
            onTranslated(hasTitle ? out : nil, hasBody ? out : nil)
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

@available(iOS 18.0, *)
private struct InlineEnglishMultiTranslation: ViewModifier {
    let title: String
    let bodyText: String
    let trigger: Int
    let onTranslated: (_ title: String?, _ body: String?) -> Void
    let onFailed: () -> Void

    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { @MainActor session in
                do {
                    var titleOut: String?
                    var bodyOut: String?
                    if !title.isEmpty {
                        let response = try await session.translate(title)
                        let out = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                        titleOut = out.isEmpty ? nil : out
                    }
                    if !bodyText.isEmpty {
                        let response = try await session.translate(bodyText)
                        let out = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                        bodyOut = out.isEmpty ? nil : out
                    }
                    if titleOut == nil, bodyOut == nil {
                        onFailed()
                    } else {
                        onTranslated(titleOut, bodyOut)
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

@available(iOS 18.0, *)
private struct InlineEnglishMultiTranslation: ViewModifier {
    let title: String
    let bodyText: String
    let trigger: Int
    let onTranslated: (_ title: String?, _ body: String?) -> Void
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
