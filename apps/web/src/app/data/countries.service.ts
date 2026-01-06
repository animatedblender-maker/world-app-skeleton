import { Injectable } from '@angular/core';

type LatLng = { lat: number; lng: number };

function normalizeName(s: string): string {
  return (s || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .replace(/[’']/g, '')
    .replace(/[^a-z0-9 ]/g, '');
}

function normalizeIso2(v: any): string | null {
  const s = String(v ?? '').trim().toUpperCase();
  if (/^[A-Z]{2}$/.test(s)) return s;
  return null;
}

function simpleCentroid(geometry: any): LatLng | null {
  const points: Array<[number, number]> = [];
  const pushRing = (ring: any) => {
    if (!Array.isArray(ring)) return;
    for (const pt of ring) if (Array.isArray(pt) && pt.length >= 2) points.push([pt[0], pt[1]]);
  };

  const type = geometry?.type;
  const coords = geometry?.coordinates;
  if (!type || !Array.isArray(coords)) return null;

  if (type === 'Polygon') for (const ring of coords) pushRing(ring);
  else if (type === 'MultiPolygon') for (const poly of coords) for (const ring of poly || []) pushRing(ring);

  if (!points.length) return null;

  let sx = 0, sy = 0;
  for (const [lng, lat] of points) { sx += lng; sy += lat; }
  return { lng: sx / points.length, lat: sy / points.length };
}

function bboxOfGeometry(geometry: any): { minLat: number; maxLat: number; minLng: number; maxLng: number } | null {
  const points: Array<[number, number]> = [];
  const pushRing = (ring: any) => {
    if (!Array.isArray(ring)) return;
    for (const pt of ring) if (Array.isArray(pt) && pt.length >= 2) points.push([pt[0], pt[1]]);
  };

  const type = geometry?.type;
  const coords = geometry?.coordinates;
  if (!type || !Array.isArray(coords)) return null;

  if (type === 'Polygon') for (const ring of coords) pushRing(ring);
  else if (type === 'MultiPolygon') for (const poly of coords) for (const ring of poly || []) pushRing(ring);

  if (!points.length) return null;

  let minLng = Infinity, maxLng = -Infinity, minLat = Infinity, maxLat = -Infinity;
  for (const [lng, lat] of points) {
    if (lng < minLng) minLng = lng;
    if (lng > maxLng) maxLng = lng;
    if (lat < minLat) minLat = lat;
    if (lat > maxLat) maxLat = lat;
  }
  return { minLat, maxLat, minLng, maxLng };
}

// Point in polygon (ray casting) for one ring
function pipRing(lat: number, lng: number, ring: Array<[number, number]>): boolean {
  // ring points are [lng, lat]
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = ring[i][0], yi = ring[i][1];
    const xj = ring[j][0], yj = ring[j][1];

    const intersect =
      (yi > lat) !== (yj > lat) &&
      lng < ((xj - xi) * (lat - yi)) / (yj - yi + 1e-12) + xi;

    if (intersect) inside = !inside;
  }
  return inside;
}

// Polygon with holes: inside outer AND not inside any hole
function pipPolygon(lat: number, lng: number, rings: Array<Array<[number, number]>>): boolean {
  if (!rings.length) return false;
  if (!pipRing(lat, lng, rings[0])) return false;
  for (let i = 1; i < rings.length; i++) {
    if (pipRing(lat, lng, rings[i])) return false;
  }
  return true;
}

export type CountryModel = {
  id: number;
  name: string;
  norm: string;
  center: LatLng;
  labelSize: number;
  flyAltitude: number;
  code: string | null;

  // ✅ added for bounded points
  pointPool: LatLng[];
  __pip?: {
    type: 'Polygon' | 'MultiPolygon';
    // For Polygon => [rings]
    // For MultiPolygon => [[rings], [rings], ...]
    poly: Array<Array<[number, number]>> | Array<Array<Array<[number, number]>>>;
  };
};

export type CountriesLoadResult = {
  features: any[];
  countries: CountryModel[];
};

@Injectable({ providedIn: 'root' })
export class CountriesService {
  async loadCountries(): Promise<CountriesLoadResult> {
    const geo = await this.fetchCountriesGeoJson();
    const rawFeatures: any[] = Array.isArray(geo?.features) ? geo.features : [];

    const features = rawFeatures
      .filter((f) => f?.geometry?.type === 'Polygon' || f?.geometry?.type === 'MultiPolygon')
      .filter((f) => (f?.properties?.NAME || f?.properties?.ADMIN) && f?.properties?.ISO_A2 !== 'AQ');

    features.forEach((f, idx) => (f.__id = idx + 1));

    const countries: CountryModel[] = features
      .map((f) => {
        const p = f.properties || {};
        const name = p.NAME || p.ADMIN || 'Unknown';

        const center = simpleCentroid(f.geometry) || { lat: 0, lng: 0 };
        const bbox = bboxOfGeometry(f.geometry) || { minLat: -10, maxLat: 10, minLng: -10, maxLng: 10 };

        const code = normalizeIso2(p.ISO_A2 ?? p.iso_a2 ?? p.ISO2);

        const model: CountryModel = {
          id: f.__id,
          name,
          norm: normalizeName(name),
          center,
          labelSize: 0.5,
          flyAltitude: 1.2,
          code,
          pointPool: [],
          __pip: this.buildPipIndex(f.geometry),
        };

        model.pointPool = this.buildPointPool(model, bbox, 420); // ✅ pool size

        return model;
      })
      .sort((a, b) => a.name.localeCompare(b.name));

    return { features, countries };
  }

  // ✅ used by PresenceService
  pickPoolPoint(country: CountryModel, seed: number): LatLng {
    const pool = country.pointPool || [];
    if (!pool.length) return { lat: country.center.lat, lng: country.center.lng };
    const idx = Math.abs(seed) % pool.length;
    return pool[idx];
  }

  // ✅ used by PresenceService
  containsPoint(country: CountryModel, lat: number, lng: number): boolean {
    const idx = country.__pip;
    if (!idx) return false;

    if (idx.type === 'Polygon') {
      return pipPolygon(lat, lng, idx.poly as Array<Array<[number, number]>>);
    } else {
      const polys = idx.poly as Array<Array<Array<[number, number]>>>;
      for (const rings of polys) {
        if (pipPolygon(lat, lng, rings)) return true;
      }
      return false;
    }
  }

  private buildPipIndex(geometry: any): CountryModel['__pip'] {
    const type = geometry?.type;
    const coords = geometry?.coordinates;

    if (type === 'Polygon' && Array.isArray(coords)) {
      const rings = coords.map((ring: any) => (Array.isArray(ring) ? ring.map((p: any) => [p[0], p[1]] as [number, number]) : []));
      return { type: 'Polygon', poly: rings };
    }

    if (type === 'MultiPolygon' && Array.isArray(coords)) {
      const polys = coords.map((poly: any) =>
        (poly || []).map((ring: any) =>
          (ring || []).map((p: any) => [p[0], p[1]] as [number, number])
        )
      );
      return { type: 'MultiPolygon', poly: polys };
    }

    return undefined;
  }

  private buildPointPool(country: CountryModel, bbox: { minLat: number; maxLat: number; minLng: number; maxLng: number }, target = 300): LatLng[] {
    const out: LatLng[] = [];
    const maxTries = target * 40;

    let tries = 0;
    while (out.length < target && tries < maxTries) {
      tries++;

      // random point in bbox
      const lat = bbox.minLat + Math.random() * (bbox.maxLat - bbox.minLat);
      const lng = bbox.minLng + Math.random() * (bbox.maxLng - bbox.minLng);

      if (this.containsPoint(country, lat, lng)) out.push({ lat, lng });
    }

    // fallback if a tiny island country
    if (!out.length) out.push({ lat: country.center.lat, lng: country.center.lng });

    return out;
  }

  private async fetchCountriesGeoJson(): Promise<any> {
    // IMPORTANT:
    // In your Angular.json you only copy from "public" to build root.
    // So the runtime URL is "/countries50m.geojson" (NOT /assets/...)
    const tryUrls = ['/countries50m.geojson', '/countries.geojson'];

    let lastErr: any = null;
    for (const url of tryUrls) {
      try {
        const r = await fetch(url, { cache: 'force-cache' });
        if (!r.ok) throw new Error(`${url} HTTP ${r.status}`);
        return await r.json();
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr || new Error('GeoJSON fetch failed');
  }
}
