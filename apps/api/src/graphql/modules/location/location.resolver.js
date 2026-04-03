import { LocationService } from './location.service.js';
const svc = new LocationService();
export const locationResolvers = {
    Query: {
        detectLocation: async (_, args, _ctx) => {
            // No auth required for detection; it only returns country/city.
            // (We can require auth later if you want.)
            const { lat, lng } = args;
            return await svc.reverseGeocode(lat, lng);
        },
    },
};
