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

function bboxOfGeometry(geometry: any): { dLat: number; dLng: number } | null {
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

  let minLng = Infinity,
    maxLng = -Infinity,
    minLat = Infinity,
    maxLat = -Infinity;

  for (const [lng, lat] of points) {
    if (lng < minLng) minLng = lng;
    if (lng > maxLng) maxLng = lng;
    if (lat < minLat) minLat = lat;
    if (lat > maxLat) maxLat = lat;
  }

  return { dLat: Math.max(0.1, maxLat - minLat), dLng: Math.max(0.1, maxLng - minLng) };
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

export type CountryModel = {
  id: number;
  name: string;
  norm: string;
  center: LatLng;
  labelSize: number;
  flyAltitude: number;
  code: string | null;
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
        const bbox = bboxOfGeometry(f.geometry) || { dLat: 10, dLng: 10 };

        return {
          id: f.__id,
          name,
          norm: normalizeName(name),
          center,
          labelSize: computeLabelSizeFromBBox(bbox.dLat, bbox.dLng),
          flyAltitude: computeAltitudeFromBBox(bbox.dLat, bbox.dLng),
          code: p.ISO_A2 || p.iso_a2 || p.ISO2 || p.ADM0_A3 || p.ISO_A3 || null,
        };
      })
      .sort((a, b) => a.name.localeCompare(b.name));

    return { features, countries };
  }

  private async fetchCountriesGeoJson(): Promise<any> {
    const tryUrls = ['/countries50m.geojson', '/public/countries50m.geojson'];

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
