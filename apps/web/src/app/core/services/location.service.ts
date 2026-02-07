import { Injectable } from '@angular/core';
import { GqlService } from './gql.service';

export type DetectedLocation = {
  countryCode: string;
  countryName: string;
  cityName?: string | null;
  source: 'gps' | 'ip' | string;
};

const DETECT_LOCATION = `
mutation DetectLocation($lat: Float!, $lng: Float!) {
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

  // ✅ THIS is what profile-setup.page.ts calls
  async detectViaGpsThenServer(timeoutMs = 8000): Promise<DetectedLocation | null> {
    const cached = this.getCachedLocation();
    const coords = await this.getBrowserCoords(timeoutMs);
    if (!coords) return cached;

    try {
      const res = await this.gql.request<{ detectLocation: DetectedLocation }>(
        DETECT_LOCATION,
        { lat: coords.lat, lng: coords.lng }
      );

      if (res.detectLocation?.countryCode && res.detectLocation?.countryName) {
        this.setCachedLocation(res.detectLocation);
      }
      return res.detectLocation ?? cached;
    } catch {
      return cached;
    }
  }

  // Internal helper
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
      if (!parsed?.countryCode || !parsed?.countryName) return null;
      return parsed;
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
