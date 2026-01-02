import { CountryType } from './modules/countries/countries.type.js';

export const typeDefs = `#graphql
  ${CountryType}

  type Query {
    countries: [Country!]!
    countryByIso(iso: String!): Country
  }
`;
