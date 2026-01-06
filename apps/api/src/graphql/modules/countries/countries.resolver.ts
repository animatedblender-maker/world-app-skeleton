// apps/api/src/graphql/modules/countries/countries.resolver.ts
import fs from 'node:fs';
import path from 'node:path';

type GeoJSON = {
  type: 'FeatureCollection';
  features: any[];
};

type Country = {
  id: number;
  name: string;
  iso: string;
  continent: string;
  lat: number;
  lng: number;
  center: { lat: number; lng: number };
};

const GEOJSON_PATH = path.join(process.cwd(), 'src', 'data', 'countries50m.geojson');

let cachedCountries: Country[] | null = null;

function normalizeIso(v: any): string {
  const s = String(v || '').trim().toUpperCase();
  return s.length === 2 ? s : 'XX';
}

function pickName(props: any): string {
  return String(
    props?.NAME ||
      props?.ADMIN ||
      props?.NAME_EN ||
      props?.FORMAL_EN ||
      'Unknown'
  );
}

function pickContinent(props: any): string {
  const raw =
    props?.CONTINENT ??
    props?.continent ??
    props?.REGION_UN ??
    props?.REGION_WB ??
    props?.SUBREGION ??
    props?.region ??
    'Unknown';

  const s = String(raw || '').trim();
  if (!s) return 'Unknown';

  if (s.includes('North America')) return 'North America';
  if (s.includes('South America')) return 'South America';
  if (s.includes('Europe')) return 'Europe';
  if (s.includes('Africa')) return 'Africa';
  if (s.includes('Asia')) return 'Asia';
  if (s.includes('Oceania') || s.includes('Australia')) return 'Oceania';
  if (s.includes('Antarctica')) return 'Antarctica';

  return s;
}

function pushRing(points: Array<[number, number]>, ring: any) {
  if (!Array.isArray(ring)) return;
  for (const pt of ring) {
    if (Array.isArray(pt) && pt.length >= 2) {
      const lng = Number(pt[0]);
      const lat = Number(pt[1]);
      if (Number.isFinite(lng) && Number.isFinite(lat)) points.push([lng, lat]);
    }
  }
}

function centroidOfGeometry(geometry: any): { lat: number; lng: number } | null {
  const points: Array<[number, number]> = [];
  const type = geometry?.type;
  const coords = geometry?.coordinates;
  if (!type || !Array.isArray(coords)) return null;

  if (type === 'Polygon') {
    for (const ring of coords) pushRing(points, ring);
  } else if (type === 'MultiPolygon') {
    for (const poly of coords) {
      if (!Array.isArray(poly)) continue;
      for (const ring of poly) pushRing(points, ring);
    }
  } else {
    return null;
  }

  if (!points.length) return null;

  let sumLng = 0;
  let sumLat = 0;
  for (const [lng, lat] of points) {
    sumLng += lng;
    sumLat += lat;
  }

  return { lng: sumLng / points.length, lat: sumLat / points.length };
}

function loadCountriesFromGeoJSON(): Country[] {
  if (cachedCountries) return cachedCountries;

  if (!fs.existsSync(GEOJSON_PATH)) {
    throw new Error(
      `GeoJSON not found at ${GEOJSON_PATH}
→ copy apps/web/public/countries50m.geojson
→ to   apps/api/src/data/countries50m.geojson`
    );
  }

  const raw = fs.readFileSync(GEOJSON_PATH, 'utf-8');
  const json = JSON.parse(raw) as GeoJSON;
  const features = Array.isArray(json.features) ? json.features : [];

  const result: Country[] = [];

  for (const feature of features) {
    const props = feature?.properties || {};
    const geom = feature?.geometry;

    const iso = normalizeIso(props?.ISO_A2 || props?.iso_a2 || props?.ISO2);
    if (iso === 'AQ') continue;

    const name = pickName(props);
    if (!name || name === 'Unknown') continue;

    const center = centroidOfGeometry(geom);
    if (!center) continue;

    result.push({
      id: result.length + 1,
      name,
      iso,
      continent: pickContinent(props),
      lat: center.lat,
      lng: center.lng,
      center: { lat: center.lat, lng: center.lng },
    });
  }

  result.sort((a, b) => a.name.localeCompare(b.name));
  result.forEach((c, i) => (c.id = i + 1));

  cachedCountries = result;
  return result;
}

export const countriesResolvers = {
  Query: {
    countries: () => ({ countries: loadCountriesFromGeoJSON() }),

    countryByIso: (_: any, args: { iso: string }) => {
      const want = normalizeIso(args.iso);
      return loadCountriesFromGeoJSON().find((c) => c.iso === want) || null;
    },
  },
};
