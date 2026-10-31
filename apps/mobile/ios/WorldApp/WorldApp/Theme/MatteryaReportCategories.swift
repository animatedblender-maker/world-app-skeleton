import Foundation
import SwiftUI

/// Canonical Matterya report categories — shared across Feed, Sparks, Hubs, comments, messages.
/// Adult material is **Mature content** (never Reddit-style "NSFW").
enum MatteryaReportCategories {
    struct Item: Identifiable, Hashable {
        let slug: String
        let label: String
        var id: String { slug }
    }

    static let all: [Item] = [
        .init(slug: "spam", label: "Spam"),
        .init(slug: "harassment", label: "Harassment"),
        .init(slug: "hate", label: "Hate"),
        .init(slug: "mature", label: "Mature content"),
        .init(slug: "csam", label: "CSAM"),
        .init(slug: "violence", label: "Violence"),
        .init(slug: "terrorism", label: "Terrorism"),
        .init(slug: "self_harm", label: "Self-harm"),
        .init(slug: "servitude", label: "Servitude / domestic helpers"),
        .init(slug: "solicitation", label: "Adult solicitation"),
        .init(slug: "misinfo", label: "Misinformation"),
        .init(slug: "scam", label: "Scam"),
        .init(slug: "doxxing", label: "Doxxing / privacy"),
        .init(slug: "other", label: "Other"),
    ]

    /// Labels for confirmationDialog ForEach (API accepts label or slug).
    static var labels: [String] { all.map(\.label) }

    static func slug(forLabel label: String) -> String {
        let t = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let hit = all.first(where: { $0.label.lowercased() == t || $0.slug == t }) {
            return hit.slug
        }
        // Legacy aliases from older clients
        if t.contains("nsfw") || t.contains("sexual") || t.contains("adult") { return "mature" }
        if t.contains("spam") { return "spam" }
        if t.contains("harass") { return "harassment" }
        if t.contains("misinfo") { return "misinfo" }
        if t.contains("terror") || t.contains("extremist") { return "terrorism" }
        if t.contains("csam") || t.contains("grooming") || t.contains("child sexual") { return "csam" }
        if t.contains("solicit") || t.contains("escort") { return "solicitation" }
        if t.contains("servitude") || t.contains("domestic helper") || t.contains("forced labor") || t.contains("traffick") { return "servitude" }
        if t.contains("illegal") || t.contains("harm") { return "other" }
        return "other"
    }
}

extension View {
    /// Shared Matterya report reasons — includes Mature content (not NSFW).
    func matteryaReportDialog(
        _ title: String,
        isPresented: Binding<Bool>,
        onReason: @escaping (String) -> Void
    ) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            ForEach(MatteryaReportCategories.all) { item in
                Button(item.label, role: .destructive) {
                    onReason(item.label)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
