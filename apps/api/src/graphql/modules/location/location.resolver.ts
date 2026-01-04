import { LocationService } from './location.service.js';

type Context = { user: any | null };

const svc = new LocationService();

export const locationResolvers = {
  Query: {
    detectLocation: async (_: any, args: { lat: number; lng: number }, _ctx: Context) => {
      // No auth required for detection; it only returns country/city.
      // (We can require auth later if you want.)
      const { lat, lng } = args;
      return await svc.reverseGeocode(lat, lng);
    },
  },
};
