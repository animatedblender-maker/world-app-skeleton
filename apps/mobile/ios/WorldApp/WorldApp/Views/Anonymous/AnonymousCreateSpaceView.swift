import SwiftUI

struct AnonymousCreateSpaceView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var store = AnonymousStore.shared

    @State private var step = 0
    @State private var title = ""
    @State private var slug = ""
    @State private var description = ""
    @State private var category = "General"
    @State private var rulesText = "Be respectful.\nNo doxxing or real-name outing.\nNo illegal content."
    @State private var visibility = AnonymousSpaceVisibility.adultPublic
    @State private var admission = AnonymousSpaceAdmission.free
    @State private var isPublishing = false

    private let categories = ["General", "Support", "Creative", "Tech", "Culture", "Games", "Other"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepHeader
                ScrollView {
                    stepBody
                        .padding(Theme.pagePadding)
                }
                footer
            }
            .screenBackground()
            .navigationTitle("Create Space")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.ink)
                }
            }
        }
    }

    private var stepHeader: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { idx in
                Capsule()
                    .fill(idx <= step ? Theme.ink : Theme.border)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case 0: metadataStep
        case 1: rulesStep
        case 2: visibilityStep
        default: reviewStep
        }
    }

    private var metadataStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            fieldLabel("Title")
            matteryaField(text: $title, placeholder: "Space title")
                .onChange(of: title) { _, value in
                    if slug.isEmpty || slug == slugify(String(title.dropLast())) {
                        slug = slugify(value)
                    }
                }

            fieldLabel("Slug")
            matteryaField(text: $slug, placeholder: "space_slug")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            fieldLabel("Description")
            matteryaEditor(text: $description, placeholder: "What is this Space about?")

            fieldLabel("Category")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { item in
                        Button {
                            category = item
                        } label: {
                            Text(item)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(category == item ? Theme.surface : Theme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(category == item ? Theme.ink : Theme.matteDeep))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var rulesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Space rules")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("One rule per line. Platform policy always outranks Space rules.")
                .font(.caption)
                .foregroundStyle(Theme.inkMuted)
            matteryaEditor(text: $rulesText, placeholder: "Rules…", minHeight: 180)
        }
    }

    private var visibilityStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Visibility")
                .font(.headline)
                .foregroundStyle(Theme.ink)

            ForEach([
                (AnonymousSpaceVisibility.adultPublic, "Adult public", "Discoverable to eligible adults"),
                (AnonymousSpaceVisibility.restricted, "Restricted", "Listed; participation may be limited"),
                (AnonymousSpaceVisibility.privateSpace, "Private", "Limited metadata; members only"),
            ], id: \.0) { value, title, subtitle in
                Button {
                    visibility = value
                } label: {
                    choiceRow(title: title, subtitle: subtitle, selected: visibility == value)
                }
                .buttonStyle(.plain)
            }

            Text("Admission")
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .padding(.top, 8)

            Button {
                admission = .free
            } label: {
                choiceRow(title: "Free", subtitle: "Anyone eligible can join", selected: admission == .free)
            }
            .buttonStyle(.plain)

            Button {
                admission = .paid
            } label: {
                choiceRow(
                    title: "Paid",
                    subtitle: MatteryaCopy.anonymousPaidComingSoonBody,
                    selected: admission == .paid,
                    badge: "Coming soon"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            reviewRow("Title", title)
            reviewRow("Slug", "a/\(slug)")
            reviewRow("Category", category)
            reviewRow("Visibility", visibility.rawValue.replacingOccurrences(of: "_", with: " "))
            reviewRow("Admission", admission == .free ? "Free" : "Paid (not available yet)")
            if !description.isEmpty {
                reviewRow("Description", description)
            }
            Text("Rules")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
            Text(rulesText)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    withAnimation(MatteryaMotion.snappy) { step -= 1 }
                } label: {
                    Text("Back").elegantButton(outlined: true)
                }
                .buttonStyle(.plain)
            }
            Button {
                if step < 3 {
                    guard validateCurrentStep() else { return }
                    withAnimation(MatteryaMotion.snappy) { step += 1 }
                } else {
                    Task { await publish() }
                }
            } label: {
                Text(step < 3 ? "Continue" : (isPublishing ? "Publishing…" : "Publish"))
                    .elegantButton()
                    .opacity(isPublishing ? 0.55 : 1)
            }
            .buttonStyle(.plain)
            .disabled(isPublishing)
        }
        .padding(Theme.pagePadding)
        .background(Theme.surface.opacity(0.96))
        .overlay(alignment: .top) { Theme.divider.frame(height: 0.5) }
    }

    private func validateCurrentStep() -> Bool {
        switch step {
        case 0:
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let s = slug.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count >= 3, s.count >= 3 else {
                appState.showToast("Title and slug need at least 3 characters.", style: .error)
                return false
            }
            return true
        case 2:
            if admission != .free {
                appState.showToast(MatteryaCopy.anonymousPaidComingSoonBody, style: .info)
                admission = .free
            }
            return true
        default:
            return true
        }
    }

    private func publish() async {
        guard admission == .free else {
            appState.showToast(AnonymousError.paidDisabled.errorDescription ?? "", style: .info)
            return
        }
        isPublishing = true
        defer { isPublishing = false }
        let rules = rulesText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let input = AnonymousCreateSpaceInput(
            slug: slugify(slug),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            tags: [],
            rules: rules,
            visibility: visibility.rawValue,
            admission: AnonymousSpaceAdmission.free.rawValue
        )
        if let space = await store.createSpace(input) {
            appState.showToast("Created a/\(space.slug)", style: .success)
            dismiss()
        } else if let err = store.consumeError() {
            appState.showToast(err, style: .error)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.inkMuted)
            .textCase(.uppercase)
    }

    private func matteryaField(text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .stroke(Theme.border, lineWidth: 0.5)
            )
            .foregroundStyle(Theme.ink)
    }

    private func matteryaEditor(text: Binding<String>, placeholder: String, minHeight: CGFloat = 110) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
            TextEditor(text: text)
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .padding(8)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private func choiceRow(title: String, subtitle: String, selected: Bool, badge: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.matteDeep, in: Capsule())
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(selected ? Theme.matteDeep : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.border, lineWidth: 0.5)
        )
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkMuted)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
        }
    }

    private func slugify(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let allowed = lowered.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "_"
        }
        var out = String(allowed)
        while out.contains("__") { out = out.replacingOccurrences(of: "__", with: "_") }
        return String(out.trimmingCharacters(in: CharacterSet(charactersIn: "_")).prefix(24))
    }
}
