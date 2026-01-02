import { countriesResolvers } from './modules/countries/countries.resolver.js';

export const resolvers = {
  Query: {
    ...countriesResolvers.Query
  }
};
