export type DetectedLocation = {
  countryCode: string;
  countryName: string;
  cityName?: string | null;
  source: 'gps' | 'ip';
};

export class LocationService {
  async reverseGeocode(lat: number, lng: number): Promise<DetectedLocation> {
    // 1) Try Nominatim reverse (server-side, no CORS)
    const nom = await this.fromNominatim(lat, lng);
    if (nom) return nom;

    // 2) Fallback: IP-based (server IP, not user IP) – last resort
    const ip = await this.fromIp();
    if (ip) return ip;

    throw new Error('LOCATION_DETECT_FAILED');
  }

  private async fromNominatim(lat: number, lng: number): Promise<DetectedLocation | null> {
    try {
      const url =
        `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${encodeURIComponent(lat)}&lon=${encodeURIComponent(lng)}`;

      const res = await fetch(url, {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
          // Nominatim likes a UA/Referer; Node fetch sometimes needs this to behave nicely.
          'User-Agent': 'world-app-dev/1.0 (server-side)',
        },
      });

      if (!res.ok) return null;

      const json: any = await res.json();
      const addr = json?.address ?? {};

      const countryCode = String(addr.country_code ?? '').toUpperCase();
      const countryName = String(addr.country ?? '');
      const cityName =
        addr.city ??
        addr.town ??
        addr.village ??
        addr.municipality ??
        addr.county ??
        null;

      if (!countryCode || !countryName) return null;

      return { countryCode, countryName, cityName, source: 'gps' };
    } catch {
      return null;
    }
  }

  private async fromIp(): Promise<DetectedLocation | null> {
    try {
      const res = await fetch('https://ipapi.co/json/', {
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'world-app-dev/1.0 (server-side)',
        },
      });
      if (!res.ok) return null;

      const json: any = await res.json();
      const countryCode = String(json?.country_code ?? '').toUpperCase();
      const countryName = String(json?.country_name ?? '');
      const cityName = json?.city ?? null;

      if (!countryCode || !countryName) return null;
      return { countryCode, countryName, cityName, source: 'ip' };
    } catch {
      return null;
    }
  }
}
