import Foundation

/// Matterya is free — subscription plumbing is disabled for now.
@MainActor
@Observable
final class SubscriptionService {
    static let shared = SubscriptionService()

    var isPremium: Bool { true }

    private init() {}

    func loadProducts() async {}

    func refreshEntitlements() async {}

    func restorePurchases() async -> String? { nil }
}