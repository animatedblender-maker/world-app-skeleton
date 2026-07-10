import Foundation

private enum AdsGraphQLFields {
    static let campaign = """
    id advertiser_user_id name status placement target_country_codes
    budget_cents daily_budget_cents start_at end_at created_at updated_at
    impression_count click_count
    creatives {
      id campaign_id title body media_kind media_url click_url cta_label duration_seconds
      created_at updated_at
    }
    """

    static let creative = """
    id campaign_id title body media_kind media_url click_url cta_label duration_seconds
    created_at updated_at
    """
}

struct AdCampaignInput {
    let name: String
    let placement: String
    let status: String?
    let targetCountryCodes: [String]?
    let budgetCents: Int?
    let dailyBudgetCents: Int?
    let startAt: String?
    let endAt: String?

    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "placement": placement,
        ]
        if let status { dict["status"] = status }
        if let targetCountryCodes { dict["target_country_codes"] = targetCountryCodes }
        if let budgetCents { dict["budget_cents"] = budgetCents }
        if let dailyBudgetCents { dict["daily_budget_cents"] = dailyBudgetCents }
        if let startAt { dict["start_at"] = startAt }
        if let endAt { dict["end_at"] = endAt }
        return dict
    }
}

struct AdCreativeInput {
    let title: String?
    let body: String?
    let mediaKind: String?
    let mediaURL: String
    let clickURL: String?
    let ctaLabel: String?
    let durationSeconds: Int?

    var dictionary: [String: Any] {
        var dict: [String: Any] = ["media_url": mediaURL]
        if let title { dict["title"] = title }
        if let body { dict["body"] = body }
        if let mediaKind { dict["media_kind"] = mediaKind }
        if let clickURL { dict["click_url"] = clickURL }
        if let ctaLabel { dict["cta_label"] = ctaLabel }
        if let durationSeconds { dict["duration_seconds"] = durationSeconds }
        return dict
    }
}

@MainActor
final class AdsService {
    static let shared = AdsService()

    private let gql = GraphQLService.shared
    private init() {}

    func myCampaigns() async throws -> [AdCampaign] {
        struct Response: Decodable { let myAdCampaigns: [GraphQLAdCampaign] }
        let query = """
        query {
          myAdCampaigns {
            \(AdsGraphQLFields.campaign)
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(query: query)
        return result.myAdCampaigns.map(\.toModel)
    }

    func createCampaign(input: AdCampaignInput) async throws -> AdCampaign {
        struct Response: Decodable { let createAdCampaign: GraphQLAdCampaign }
        let mutation = """
        mutation($input: AdCampaignInput!) {
          createAdCampaign(input: $input) {
            \(AdsGraphQLFields.campaign)
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["input": input.dictionary],
        )
        return result.createAdCampaign.toModel
    }

    func updateCampaign(campaignID: String, input: AdCampaignInput) async throws -> AdCampaign {
        struct Response: Decodable { let updateAdCampaign: GraphQLAdCampaign }
        let mutation = """
        mutation($campaignId: ID!, $input: AdCampaignInput!) {
          updateAdCampaign(campaign_id: $campaignId, input: $input) {
            \(AdsGraphQLFields.campaign)
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["campaignId": campaignID, "input": input.dictionary],
        )
        return result.updateAdCampaign.toModel
    }

    func createCreative(campaignID: String, input: AdCreativeInput) async throws -> AdCreative {
        struct Response: Decodable { let createAdCreative: GraphQLAdCreative }
        let mutation = """
        mutation($campaignId: ID!, $input: AdCreativeInput!) {
          createAdCreative(campaign_id: $campaignId, input: $input) {
            \(AdsGraphQLFields.creative)
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["campaignId": campaignID, "input": input.dictionary],
        )
        return result.createAdCreative.toModel
    }

    func updateCreative(creativeID: String, input: AdCreativeInput) async throws -> AdCreative {
        struct Response: Decodable { let updateAdCreative: GraphQLAdCreative }
        let mutation = """
        mutation($creativeId: ID!, $input: AdCreativeInput!) {
          updateAdCreative(creative_id: $creativeId, input: $input) {
            \(AdsGraphQLFields.creative)
          }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["creativeId": creativeID, "input": input.dictionary],
        )
        return result.updateAdCreative.toModel
    }

    func deleteCampaign(campaignID: String) async throws -> Bool {
        struct Response: Decodable { let deleteAdCampaign: Bool }
        let mutation = """
        mutation($campaignId: ID!) {
          deleteAdCampaign(campaign_id: $campaignId)
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["campaignId": campaignID],
        )
        return result.deleteAdCampaign
    }

    func serveVideoAd(
        placement: String,
        countryCode: String? = nil,
        contentCountryCode: String? = nil,
        postID: String? = nil
    ) async throws -> AdSlot? {
        struct Response: Decodable { let serveVideoAd: GraphQLAdSlot? }
        let query = """
        query ServeVideoAd(
          $placement: String!
          $country_code: String
          $content_country_code: String
          $post_id: ID
        ) {
          serveVideoAd(
            placement: $placement
            country_code: $country_code
            content_country_code: $content_country_code
            post_id: $post_id
          ) {
            impression_token
            skip_after_seconds
            campaign {
              \(AdsGraphQLFields.campaign)
            }
            creative {
              \(AdsGraphQLFields.creative)
            }
          }
        }
        """
        var variables: [String: Any] = ["placement": placement]
        if let countryCode { variables["country_code"] = countryCode }
        if let contentCountryCode { variables["content_country_code"] = contentCountryCode }
        if let postID { variables["post_id"] = postID }

        let result: Response = try await gql.authenticatedRequest(query: query, variables: variables)
        return result.serveVideoAd?.toModel
    }

    func logImpression(impressionToken: String) async throws -> Bool {
        struct LogResult: Decodable { let ok: Bool }
        struct Response: Decodable { let logAdImpression: LogResult }
        let mutation = """
        mutation($token: String!) {
          logAdImpression(impression_token: $token) { ok }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["token": impressionToken],
        )
        return result.logAdImpression.ok
    }

    func logClick(impressionToken: String) async throws -> Bool {
        struct LogResult: Decodable { let ok: Bool }
        struct Response: Decodable { let logAdClick: LogResult }
        let mutation = """
        mutation($token: String!) {
          logAdClick(impression_token: $token) { ok }
        }
        """
        let result: Response = try await gql.authenticatedRequest(
            query: mutation,
            variables: ["token": impressionToken],
        )
        return result.logAdClick.ok
    }
}

private struct GraphQLAdSlot: Decodable {
    let impressionToken: String
    let skipAfterSeconds: Int
    let campaign: GraphQLAdCampaign
    let creative: GraphQLAdCreative

    enum CodingKeys: String, CodingKey {
        case campaign, creative
        case impressionToken = "impression_token"
        case skipAfterSeconds = "skip_after_seconds"
    }

    var toModel: AdSlot {
        AdSlot(
            impressionToken: impressionToken,
            skipAfterSeconds: skipAfterSeconds,
            campaign: campaign.toModel,
            creative: creative.toModel
        )
    }
}

private struct GraphQLAdCampaign: Decodable {
    let id: String
    let name: String
    let status: String
    let placement: String
    let targetCountryCodes: [String]
    let budgetCents: Int
    let dailyBudgetCents: Int
    let startAt: String?
    let endAt: String?
    let impressionCount: Int
    let clickCount: Int
    let creatives: [GraphQLAdCreative]

    enum CodingKeys: String, CodingKey {
        case id, name, status, placement, creatives
        case targetCountryCodes = "target_country_codes"
        case budgetCents = "budget_cents"
        case dailyBudgetCents = "daily_budget_cents"
        case startAt = "start_at"
        case endAt = "end_at"
        case impressionCount = "impression_count"
        case clickCount = "click_count"
    }

    var toModel: AdCampaign {
        AdCampaign(
            id: id,
            name: name,
            status: status,
            placement: placement,
            targetCountryCodes: targetCountryCodes,
            budgetCents: budgetCents,
            dailyBudgetCents: dailyBudgetCents,
            startAt: startAt,
            endAt: endAt,
            impressionCount: impressionCount,
            clickCount: clickCount,
            creatives: creatives.map(\.toModel)
        )
    }
}

private struct GraphQLAdCreative: Decodable {
    let id: String
    let campaignID: String
    let title: String?
    let body: String?
    let mediaKind: String
    let mediaURL: String
    let clickURL: String?
    let ctaLabel: String?
    let durationSeconds: Int

    enum CodingKeys: String, CodingKey {
        case id, title, body
        case campaignID = "campaign_id"
        case mediaKind = "media_kind"
        case mediaURL = "media_url"
        case clickURL = "click_url"
        case ctaLabel = "cta_label"
        case durationSeconds = "duration_seconds"
    }

    var toModel: AdCreative {
        AdCreative(
            id: id,
            campaignID: campaignID,
            title: title,
            body: body,
            mediaKind: mediaKind,
            mediaURL: mediaURL,
            clickURL: clickURL,
            ctaLabel: ctaLabel,
            durationSeconds: durationSeconds
        )
    }
}