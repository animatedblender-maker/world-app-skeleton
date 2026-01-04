export const typeDefs = `#graphql
  type Country {
    id: ID!
    name: String!
    iso: String!
    continent: String!
    lat: Float!
    lng: Float!
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

  type Query {
    countries: [Country!]!
    countryByIso(iso: String!): Country
    meProfile: Profile
  }

  type Mutation {
    detectLocation(lat: Float!, lng: Float!): DetectedLocation!
    updateProfile(input: UpdateProfileInput!): Profile!
  }
`;
