import { LocationService } from './location.service.js';

const svc = new LocationService();

function clientIpFromReq(req) {
    if (!req)
        return null;
    const xf = req.headers?.['x-forwarded-for'] ?? req.headers?.['X-Forwarded-For'];
    if (typeof xf === 'string' && xf.trim())
        return xf.split(',')[0].trim();
    if (Array.isArray(xf) && xf[0])
        return String(xf[0]).split(',')[0].trim();
    const realIp = req.headers?.['x-real-ip'] ?? req.headers?.['cf-connecting-ip'];
    if (typeof realIp === 'string' && realIp.trim())
        return realIp.trim();
    const socketIp = req.socket?.remoteAddress ?? req.ip ?? null;
    return socketIp ? String(socketIp) : null;
}

export const locationResolvers = {
    Mutation: {
        detectLocation: async (_, args, ctx) => {
            return await svc.detect({
                lat: args?.lat,
                lng: args?.lng,
                clientIp: clientIpFromReq(ctx?.req),
            });
        },
    },
    Query: {
        detectLocation: async (_, args, ctx) => {
            return await svc.detect({
                lat: args?.lat,
                lng: args?.lng,
                clientIp: clientIpFromReq(ctx?.req),
            });
        },
    },
};
