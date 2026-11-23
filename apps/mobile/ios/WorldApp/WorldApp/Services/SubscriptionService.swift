import Foundation

/// Matterya is free — StoreKit / paid entitlements are not live yet.
///
/// `isPremium` must stay **false** while ads are on. Hardcoding `true`
/// skipped every Hubs pre-roll and every Sparks standalone ad card.
@MainActor
@Observable
final class SubscriptionService {
    static let shared = SubscriptionService()

    /// Paid “remove ads” entitlement. Always false until subscriptions ship.
    var isPremium: Bool { false }

    private init() {}

    func loadProducts() async {}

    func refreshEntitlements() async {}

    func restorePurchases() async -> String? { nil }
}