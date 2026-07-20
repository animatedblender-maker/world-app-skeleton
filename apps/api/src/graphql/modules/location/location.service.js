export class LocationService {
    /** Prefer GPS reverse-geocode; fall back to the caller's IP (not the server IP). */
    async detect(opts = {}) {
        const lat = opts.lat;
        const lng = opts.lng;
        if (typeof lat === 'number' &&
            typeof lng === 'number' &&
            Number.isFinite(lat) &&
            Number.isFinite(lng)) {
            const nom = await this.fromNominatim(lat, lng);
            if (nom)
                return nom;
        }
        const ip = await this.fromClientIp(opts.clientIp);
        if (ip)
            return ip;
        return {
            countryCode: '',
            countryName: 'Unknown',
            cityName: null,
            source: 'fallback',
        };
    }
    async reverseGeocode(lat, lng) {
        return this.detect({ lat, lng });
    }
    async fromNominatim(lat, lng) {
        try {
            const baseUrl = process.env.NOMINATIM_URL ?? 'https://nominatim.openstreetmap.org/reverse';
            const url = new URL(baseUrl);
            url.searchParams.set('format', 'jsonv2');
            url.searchParams.set('lat', String(lat));
            url.searchParams.set('lon', String(lng));
            const ua = process.env.NOMINATIM_UA ?? 'world-app/1.0 (server-side)';
            const controller = new AbortController();
            const timeoutMs = Number(process.env.NOMINATIM_TIMEOUT_MS ?? 4000);
            const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
            try {
                const res = await fetch(url.toString(), {
                    method: 'GET',
                    headers: {
                        Accept: 'application/json',
                        'User-Agent': ua,
                    },
                    signal: controller.signal,
                });
                if (!res.ok)
                    return null;
                const json = await res.json();
                const addr = json?.address ?? {};
                const countryCode = String(addr.country_code ?? '').toUpperCase();
                const countryName = String(addr.country ?? '');
                const cityName = addr.city ??
                    addr.town ??
                    addr.village ??
                    addr.municipality ??
                    addr.county ??
                    null;
                if (!countryCode || !countryName)
                    return null;
                return { countryCode, countryName, cityName, source: 'gps' };
            }
            finally {
                clearTimeout(timeoutId);
            }
        }
        catch {
            return null;
        }
    }
    async fromClientIp(clientIp) {
        const ip = this.normalizeIp(clientIp);
        const fromIpApi = await this.fromIpApi(ip);
        if (fromIpApi)
            return fromIpApi;
        return this.fromIpApiCo(ip);
    }
    normalizeIp(raw) {
        if (!raw)
            return null;
        let ip = String(raw).split(',')[0]?.trim() || '';
        if (ip.startsWith('::ffff:'))
            ip = ip.slice(7);
        if (!ip || ip === '::1' || ip === '127.0.0.1' || ip.startsWith('10.') || ip.startsWith('192.168.')) {
            return null;
        }
        return ip;
    }
    async fromIpApi(ip) {
        try {
            const path = ip
                ? `http://ip-api.com/json/${encodeURIComponent(ip)}?fields=status,country,countryCode,city`
                : `http://ip-api.com/json/?fields=status,country,countryCode,city`;
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 3500);
            try {
                const res = await fetch(path, { signal: controller.signal });
                if (!res.ok)
                    return null;
                const json = await res.json();
                if (json?.status !== 'success')
                    return null;
                const countryCode = String(json?.countryCode ?? '').toUpperCase();
                const countryName = String(json?.country ?? '');
                const cityName = json?.city ?? null;
                if (!countryCode || !countryName)
                    return null;
                return { countryCode, countryName, cityName, source: 'ip' };
            }
            finally {
                clearTimeout(timeoutId);
            }
        }
        catch {
            return null;
        }
    }
    async fromIpApiCo(ip) {
        try {
            const path = ip
                ? `https://ipapi.co/${encodeURIComponent(ip)}/json/`
                : 'https://ipapi.co/json/';
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 3500);
            try {
                const res = await fetch(path, {
                    headers: {
                        Accept: 'application/json',
                        'User-Agent': 'world-app/1.0 (server-side)',
                    },
                    signal: controller.signal,
                });
                if (!res.ok)
                    return null;
                const json = await res.json();
                if (json?.error)
                    return null;
                const countryCode = String(json?.country_code ?? '').toUpperCase();
                const countryName = String(json?.country_name ?? '');
                const cityName = json?.city ?? null;
                if (!countryCode || !countryName)
                    return null;
                return { countryCode, countryName, cityName, source: 'ip' };
            }
            finally {
                clearTimeout(timeoutId);
            }
        }
        catch {
            return null;
        }
    }
}
