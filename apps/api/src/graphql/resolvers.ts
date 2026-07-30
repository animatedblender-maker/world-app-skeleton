// apps/api/src/graphql/resolvers.ts
import { countriesResolvers } from './modules/countries/countries.resolver.js';
import { profilesResolvers } from './modules/profiles/profiles.resolver.js';
import { presenceResolvers } from './modules/presence/presence.resolver.js';
import { postsResolvers } from './modules/posts/posts.resolver.js';
import { followsResolvers } from './modules/follows/follows.resolver.js';
import { notificationsResolvers } from './modules/notifications/notifications.resolver.js';
import { messagesResolvers } from './modules/messages/messages.resolver.js';
import { insightsResolvers } from './modules/insights/insights.resolver.js';
import { countryFeedResolvers } from './modules/country-feed/country-feed.resolver.js';
import { adsResolvers } from './modules/ads/ads.resolver.js';
import { newsResolvers } from './modules/news/news.resolver.js';
import { streamingResolvers } from './modules/streaming/streaming.resolver.js';
import { locationResolvers } from './modules/location/location.resolver.js';

export const resolvers = {
  Query: {
    ...(countriesResolvers.Query ?? {}),
    ...(profilesResolvers.Query ?? {}),
    ...(presenceResolvers.Query ?? {}),
    ...(postsResolvers.Query ?? {}),
    ...(followsResolvers.Query ?? {}),
    ...(notificationsResolvers.Query ?? {}),
    ...(messagesResolvers.Query ?? {}),
    ...(insightsResolvers.Query ?? {}),
    ...(countryFeedResolvers.Query ?? {}),
    ...(adsResolvers.Query ?? {}),
    ...(newsResolvers.Query ?? {}),
    ...(streamingResolvers.Query ?? {}),
    ...(locationResolvers.Query ?? {}),
  },

  Mutation: {
    ...(locationResolvers.Mutation ?? {}),
    ...(profilesResolvers.Mutation ?? {}),
    ...(presenceResolvers.Mutation ?? {}),
    ...(postsResolvers.Mutation ?? {}),
    ...(followsResolvers.Mutation ?? {}),
    ...(notificationsResolvers.Mutation ?? {}),
    ...(messagesResolvers.Mutation ?? {}),
    ...(adsResolvers.Mutation ?? {}),
    ...(newsResolvers.Mutation ?? {}),
    ...(streamingResolvers.Mutation ?? {}),
  },
};
