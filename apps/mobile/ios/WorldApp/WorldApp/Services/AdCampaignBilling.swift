import Foundation
import StoreKit

/// Pay-at-create IAP for Matterya Ads (consumable — not a subscription / paid tier).
/// Free create: `animatedblender@gmail.com` only (server also enforces).
/// Everyone else pays once via StoreKit when they tap Create.
@MainActor
@Observable
final class AdCampaignBilling {
    static let shared = AdCampaignBilling()

    static let productID = "com.matterya.worldapp.ads.campaign_create"
    private static let freeEmails: Set<String> = ["animatedblender@gmail.com"]

    private(set) var product: Product?
    private(set) var freeCreate = false
    private(set) var creditsAvailable = 0
    private(set) var isBusy = false
    private(set) var lastError: String?

    var displayPrice: String {
        product?.displayPrice ?? "—"
    }

    var needsPurchaseToCreate: Bool {
        !freeCreate && creditsAvailable < 1
    }

    private init() {}

    func refresh() async {
        lastError = nil
        await refreshEntitlementFromServer()
        await loadProduct()
    }

    /// Ensures the signed-in account may create one campaign (free or after purchase).
    func ensureCreateAllowance() async throws {
        await refreshEntitlementFromServer()
        if freeCreate || creditsAvailable > 0 { return }

        try await purchaseCreateCredit()
        await refreshEntitlementFromServer()
        guard freeCreate || creditsAvailable > 0 else {
            throw AdBillingError.purchaseRequired
        }
    }

    func purchaseCreateCredit() async throws {
        guard !freeCreate else { return }
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        if product == nil {
            await loadProduct()
        }
        guard let product else {
            throw AdBillingError.productUnavailable
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            let jws = verification.jwsRepresentation
            _ = try await AdsService.shared.redeemAdCampaignPurchase(
                productID: Self.productID,
                transactionID: String(transaction.id),
                originalTransactionID: String(transaction.originalID),
                jws: jws
            )
            await transaction.finish()
            await refreshEntitlementFromServer()
        case .userCancelled:
            throw AdBillingError.cancelled
        case .pending:
            throw AdBillingError.pending
        @unknown default:
            throw AdBillingError.productUnavailable
        }
    }

    // MARK: - Private

    private var isFreeAccount: Bool {
        let email = AuthService.shared.currentUser?.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return Self.freeEmails.contains(email)
    }

    private func refreshEntitlementFromServer() async {
        do {
            let entitlement = try await AdsService.shared.adCreateEntitlement()
            freeCreate = entitlement.freeCreate || isFreeAccount
            creditsAvailable = entitlement.creditsAvailable
        } catch {
            // Fall back to local free-email check if entitlement query fails.
            freeCreate = isFreeAccount
            #if DEBUG
            print("[AdsBilling] entitlement refresh failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
            if product == nil {
                lastError = "Ads create product is not available in App Store Connect yet."
            }
        } catch {
            lastError = error.localizedDescription
            #if DEBUG
            print("[AdsBilling] product load failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw AdBillingError.unverified
        case .verified(let safe):
            return safe
        }
    }
}

enum AdBillingError: LocalizedError {
    case productUnavailable
    case purchaseRequired
    case cancelled
    case pending
    case unverified

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            "Ad create purchase is not available right now. Try again later."
        case .purchaseRequired:
            "Purchase required to create an ad campaign."
        case .cancelled:
            "Purchase cancelled."
        case .pending:
            "Purchase is pending approval."
        case .unverified:
            "Could not verify the App Store purchase."
        }
    }
}

struct AdCreateEntitlementModel: Sendable {
    let freeCreate: Bool
    let creditsAvailable: Int
    let productID: String
}
