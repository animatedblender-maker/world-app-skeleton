import { Injectable } from '@angular/core';
import { GqlService } from './gql.service';

export type DetectedLocation = {
  countryCode: string;
  countryName: string;
  cityName?: string | null;
  source: 'gps' | 'ip' | string;
};

const DETECT_LOCATION = `
mutation DetectLocation($lat: Float, $lng: Float) {
  detectLocation(lat: $lat, lng: $lng) {
    countryCode
    countryName
    cityName
    source
  }
}
`;

@Injectable({ providedIn: 'root' })
export class LocationService {
  constructor(private gql: GqlService) {}

  /**
   * Auto-detect country for profile setup / posting home:
   * 1) browser GPS → server reverse-geocode
   * 2) server IP geo (caller's IP via API)
   * 3) client-side IP APIs (when server cannot see real client IP)
   * 4) last cached location
   */
  async detectViaGpsThenServer(timeoutMs = 8000): Promise<DetectedLocation | null> {
    const cached = this.getCachedLocation();

    const coords = await this.getBrowserCoords(timeoutMs);
    if (coords) {
      try {
        const res = await this.gql.request<{ detectLocation: DetectedLocation }>(DETECT_LOCATION, {
          lat: coords.lat,
          lng: coords.lng,
        });
        const loc = this.normalize(res.detectLocation);
        if (loc) {
          this.setCachedLocation(loc);
          return loc;
        }
      } catch {
        // fall through
      }
    }

    // Server-side IP from request headers (works in production behind a proxy).
    try {
      const res = await this.gql.request<{ detectLocation: DetectedLocation }>(DETECT_LOCATION, {
        lat: null,
        lng: null,
      });
      const loc = this.normalize(res.detectLocation);
      if (loc) {
        this.setCachedLocation(loc);
        return loc;
      }
    } catch {
      // fall through
    }

    // Browser-side IP geo (user's real public IP even when API is remote).
    const fromBrowserIp = await this.detectViaBrowserIp();
    if (fromBrowserIp) {
      this.setCachedLocation(fromBrowserIp);
      return fromBrowserIp;
    }

    return cached;
  }

  private normalize(raw: DetectedLocation | null | undefined): DetectedLocation | null {
    if (!raw) return null;
    const countryCode = String(raw.countryCode || '').trim().toUpperCase();
    const countryName = String(raw.countryName || '').trim();
    if (!countryCode || !countryName || countryName === 'Unknown' || countryCode === 'XX') {
      return null;
    }
    return {
      countryCode,
      countryName,
      cityName: raw.cityName ?? null,
      source: raw.source || 'ip',
    };
  }

  private async detectViaBrowserIp(): Promise<DetectedLocation | null> {
    const endpoints = [
      {
        url: 'https://ipapi.co/json/',
        map: (j: any): DetectedLocation | null => {
          const countryCode = String(j?.country_code ?? '').toUpperCase();
          const countryName = String(j?.country_name ?? '');
          if (!countryCode || !countryName || j?.error) return null;
          return {
            countryCode,
            countryName,
            cityName: j?.city ?? null,
            source: 'ip',
          };
        },
      },
      {
        url: 'https://ipwho.is/',
        map: (j: any): DetectedLocation | null => {
          if (j?.success === false) return null;
          const countryCode = String(j?.country_code ?? '').toUpperCase();
          const countryName = String(j?.country ?? '');
          if (!countryCode || !countryName) return null;
          return {
            countryCode,
            countryName,
            cityName: j?.city ?? null,
            source: 'ip',
          };
        },
      },
    ];

    for (const ep of endpoints) {
      try {
        const controller = new AbortController();
        const t = window.setTimeout(() => controller.abort(), 4000);
        const res = await fetch(ep.url, {
          signal: controller.signal,
          headers: { Accept: 'application/json' },
        });
        clearTimeout(t);
        if (!res.ok) continue;
        const json = await res.json();
        const loc = ep.map(json);
        if (loc) return loc;
      } catch {
        // try next
      }
    }
    return null;
  }

  private getBrowserCoords(
    timeoutMs: number
  ): Promise<{ lat: number; lng: number } | null> {
    return new Promise((resolve) => {
      if (!('geolocation' in navigator)) return resolve(null);

      let finished = false;
      const finish = (v: { lat: number; lng: number } | null) => {
        if (finished) return;
        finished = true;
        resolve(v);
      };

      const timer = window.setTimeout(() => finish(null), timeoutMs);

      navigator.geolocation.getCurrentPosition(
        (pos) => {
          clearTimeout(timer);
          finish({
            lat: pos.coords.latitude,
            lng: pos.coords.longitude,
          });
        },
        () => {
          clearTimeout(timer);
          finish(null);
        },
        {
          enableHighAccuracy: false,
          timeout: timeoutMs,
          maximumAge: 60_000,
        }
      );
    });
  }

  getCachedLocation(): DetectedLocation | null {
    try {
      const raw = localStorage.getItem('matterya:lastLocation');
      if (!raw) return null;
      const parsed = JSON.parse(raw) as DetectedLocation;
      return this.normalize(parsed);
    } catch {
      return null;
    }
  }

  cacheLocation(loc: DetectedLocation): void {
    if (!loc?.countryCode || !loc?.countryName) return;
    this.setCachedLocation(loc);
  }

  private setCachedLocation(loc: DetectedLocation): void {
    try {
      localStorage.setItem('matterya:lastLocation', JSON.stringify(loc));
    } catch {}
  }
}
