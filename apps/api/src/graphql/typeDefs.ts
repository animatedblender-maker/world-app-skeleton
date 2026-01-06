// apps/api/src/graphql/typeDefs.ts
export const typeDefs = `#graphql
  type LatLng {
    lat: Float!
    lng: Float!
  }

  type Country {
    id: ID!
    name: String!
    iso: String!
    continent: String!
    lat: Float!
    lng: Float!
    center: LatLng!
  }

  # ✅ Match your frontend query shape:
  # query { countries { countries { ... } } }
  type CountriesResult {
    countries: [Country!]!
  }

  type Profile {
    user_id: ID!
    email: String
    display_name: String
    username: String
    avatar_url: String
    country_name: String!
    country_code: String
    city_name: String
    bio: String
    created_at: String
    updated_at: String
  }

  # ✅ This is what Query.me returns (not Profile)
  type MeUser {
    id: ID!
    email: String
    role: String
  }

  type DetectedLocation {
    countryCode: String!
    countryName: String!
    cityName: String
    source: String!
  }

  input UpdateProfileInput {
    display_name: String
    username: String
    avatar_url: String
    country_name: String
    country_code: String
    city_name: String
    bio: String
  }

  # ----------------------------
  # Presence / Stats (NEW)
  # ----------------------------

  type GlobalStats {
    totalUsers: Int!
    onlineNow: Int!
    ttlSeconds: Int!
    computedAt: String!
  }

  type CountryStats {
    iso: String!
    name: String
    totalUsers: Int!
    onlineNow: Int!
    ttlSeconds: Int!
    computedAt: String!
  }

  type HeartbeatResult {
    ok: Boolean!
    ttlSeconds: Int!
    lastSeen: String!
  }

  type Query {
    # Countries
    countries: CountriesResult!
    countryByIso(iso: String!): Country

    # Auth info
    me: MeUser
    privatePing: String

    # Profile
    meProfile: Profile

    # Presence stats
    globalStats: GlobalStats!
    countryStats(iso: String!): CountryStats!
  }

  type Mutation {
    detectLocation(lat: Float!, lng: Float!): DetectedLocation!
    updateProfile(input: UpdateProfileInput!): Profile!

    # Presence mutations
    heartbeat(iso: String): HeartbeatResult!
    setOffline: Boolean!
  }
`;
