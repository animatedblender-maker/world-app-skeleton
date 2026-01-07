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
    for (const pt of ring) {
      if (Array.isArray(pt) && pt.length >= 2) points.push([pt[0], pt[1]]);
    }
  };

  const type = geometry?.type;
  const coords = geometry?.coordinates;
  if (!type || !Array.isArray(coords)) return null;

  if (type === 'Polygon') {
    for (const ring of coords) pushRing(ring);
  } else if (type === 'MultiPolygon') {
    for (const poly of coords) {
      if (!Array.isArray(poly)) continue;
      for (const ring of poly) pushRing(ring);
    }
  }

  if (!points.length) return null;

  let sx = 0;
  let sy = 0;
  for (const [lng, lat] of points) {
    sx += lng;
    sy += lat;
  }
  return { lng: sx / points.length, lat: sy / points.length };
}

function bboxOfGeometry(geometry: any): { minLat: number; maxLat: number; minLng: number; maxLng: number } | null {
  const points: Array<[number, number]> = [];

  const pushRing = (ring: any) => {
    if (!Array.isArray(ring)) return;
    for (const pt of ring) {
      if (Array.isArray(pt) && pt.length >= 2) points.push([pt[0], pt[1]]);
    }
  };

  const type = geometry?.type;
  const coords = geometry?.coordinates;
  if (!type || !Array.isArray(coords)) return null;

  if (type === 'Polygon') {
    for (const ring of coords) pushRing(ring);
  } else if (type === 'MultiPolygon') {
    for (const poly of coords) {
      if (!Array.isArray(poly)) continue;
      for (const ring of poly) pushRing(ring);
    }
  }

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

function computeLabelSizeFromBBox(dLat: number, dLng: number): number {
  const areaish = Math.max(0.1, dLat * dLng);
  const size = 0.25 + Math.log10(areaish + 1) * 0.25;
  return Math.max(0.22, Math.min(1.1, size));
}

function computeAltitudeFromBBox(dLat: number, dLng: number): number {
  const span = Math.max(dLat, dLng);
  const alt = 0.7 + Math.min(2.2, span / 22);
  return Math.max(0.9, Math.min(2.25, alt));
}

// ---------- Point in polygon (with holes) ----------
function pointInRing(lng: number, lat: number, ring: any[]): boolean {
  // Ray casting algorithm; ring = [ [lng,lat], ... ]
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = ring[i][0], yi = ring[i][1];
    const xj = ring[j][0], yj = ring[j][1];

    const intersect =
      yi > lat !== yj > lat &&
      lng < ((xj - xi) * (lat - yi)) / ((yj - yi) || 1e-12) + xi;

    if (intersect) inside = !inside;
  }
  return inside;
}

function pointInPolygonCoords(lng: number, lat: number, polyRings: any[]): boolean {
  if (!Array.isArray(polyRings) || !polyRings.length) return false;

  const outer = polyRings[0];
  if (!Array.isArray(outer) || outer.length < 3) return false;

  if (!pointInRing(lng, lat, outer)) return false;

  // holes
  for (let i = 1; i < polyRings.length; i++) {
    const hole = polyRings[i];
    if (Array.isArray(hole) && hole.length >= 3) {
      if (pointInRing(lng, lat, hole)) return false;
    }
  }
  return true;
}

function geometryContains(geometry: any, lng: number, lat: number): boolean {
  const type = geometry?.type;
  const coords = geometry?.coordinates;
  if (!type || !Array.isArray(coords)) return false;

  if (type === 'Polygon') {
    return pointInPolygonCoords(lng, lat, coords);
  }
  if (type === 'MultiPolygon') {
    for (const poly of coords) {
      if (pointInPolygonCoords(lng, lat, poly)) return true;
    }
    return false;
  }
  return false;
}

// deterministic RNG from seed
function mulberry32(seed: number) {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function hashStr(s: string): number {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return Math.abs(h);
}

function buildPointPool(feature: any, count: number): LatLng[] {
  const geometry = feature?.geometry;
  const bbox = bboxOfGeometry(geometry);
  const center = simpleCentroid(geometry) || { lat: 0, lng: 0 };
  if (!bbox) return [center];

  const { minLat, maxLat, minLng, maxLng } = bbox;
  const dLat = Math.max(0.1, maxLat - minLat);
  const dLng = Math.max(0.1, maxLng - minLng);

  // Heuristic: fewer points for tiny countries, more for large ones
  const target = Math.max(40, Math.min(count, Math.floor(50 + (dLat * dLng) * 1.5)));

  const seed = hashStr((feature?.properties?.ISO_A2 ?? feature?.properties?.NAME ?? '') + '|' + feature?.__id);
  const rnd = mulberry32(seed);

  const pool: LatLng[] = [];
  const maxTries = target * 50;

  let tries = 0;
  while (pool.length < target && tries < maxTries) {
    tries++;
    const lng = minLng + rnd() * (maxLng - minLng);
    const lat = minLat + rnd() * (maxLat - minLat);

    if (geometryContains(geometry, lng, lat)) {
      pool.push({ lat, lng });
    }
  }

  // Hard fallback (never return empty)
  if (!pool.length) pool.push(center);
  return pool;
}

export type CountryModel = {
  id: number;
  name: string;
  norm: string;
  center: LatLng;
  labelSize: number;
  flyAltitude: number;
  code: string | null; // ISO2 only (DE/US/EG) or null
  pointPool: LatLng[]; // ✅ guaranteed inside borders (incl holes)
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
        const bbox = bboxOfGeometry(f.geometry);
        const dLat = bbox ? Math.max(0.1, bbox.maxLat - bbox.minLat) : 10;
        const dLng = bbox ? Math.max(0.1, bbox.maxLng - bbox.minLng) : 10;

        const code = normalizeIso2(p.ISO_A2 ?? p.iso_a2 ?? p.ISO2);

        // ✅ build strict in-bounds pool
        const pointPool = buildPointPool(f, 240);

        return {
          id: f.__id,
          name,
          norm: normalizeName(name),
          center,
          labelSize: computeLabelSizeFromBBox(dLat, dLng),
          flyAltitude: computeAltitudeFromBBox(dLat, dLng),
          code,
          pointPool,
        };
      })
      .sort((a, b) => a.name.localeCompare(b.name));

    return { features, countries };
  }

  private getGeoJsonCandidates(): string[] {
    const baseHref = document.querySelector('base')?.getAttribute('href') ?? '/';
    const resolvedBase = new URL(baseHref, window.location.origin).toString();
    const paths = [
      'countries50m.geojson',
      'public/countries50m.geojson',
      'assets/countries50m.geojson',
      'assets/countries.geojson',
    ];
    return paths.map((path) => new URL(path, resolvedBase).toString());
  }

  private async fetchCountriesGeoJson(): Promise<any> {
    const tryUrls = this.getGeoJsonCandidates();
    let lastErr: any = null;
    for (const url of tryUrls) {
      try {
        const r = await fetch(url);
        if (!r.ok) throw new Error(`${url} HTTP ${r.status}`);
        return await r.json();
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr || new Error('GeoJSON fetch failed');
  }
}
