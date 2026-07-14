import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export type CountryCentroid = {
  iso2: string;
  lat: number;
  lng: number;
  spreadLat: number;
  spreadLng: number;
};

export type GlobePresenceDot = {
  lat: number;
  lng: number;
  count: number;
};

export type GlobePresenceDotsResult = {
  dots: GlobePresenceDot[];
  totalOnline: number;
  precision: number;
  maxPoints: number;
  computedAt: string;
};

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const COUNTRIES_MAP_PATHS = [
  path.resolve(__dirname, '../../../../../mobile/ios/WorldApp/WorldApp/Resources/countries_map.json'),
  path.resolve(process.cwd(), '../mobile/ios/WorldApp/WorldApp/Resources/countries_map.json'),
  path.resolve(process.cwd(), 'src/data/countries_map.json'),
];

let centroidsCache: Map<string, CountryCentroid> | null = null;

function normalizeLng(lng: number): number {
  if (!Number.isFinite(lng)) return 0;
  let x = lng;
  while (x > 180) x -= 360;
  while (x < -180) x += 360;
  return x;
}

function spreadFromRings(rings: number[][][]): { spreadLat: number; spreadLng: number } {
  let minLng = 180;
  let maxLng = -180;
  let minLat = 90;
  let maxLat = -90;

  for (const ring of rings) {
    for (const pt of ring) {
      if (!Array.isArray(pt) || pt.length < 2) continue;
      const lng = Number(pt[0]);
      const lat = Number(pt[1]);
      if (!Number.isFinite(lng) || !Number.isFinite(lat)) continue;
      minLng = Math.min(minLng, lng);
      maxLng = Math.max(maxLng, lng);
      minLat = Math.min(minLat, lat);
      maxLat = Math.max(maxLat, lat);
    }
  }

  return {
    spreadLat: Math.max(1.2, (maxLat - minLat) * 0.82),
    spreadLng: Math.max(1.2, (maxLng - minLng) * 0.82),
  };
}

export function loadCountryCentroids(): Map<string, CountryCentroid> {
  if (centroidsCache) return centroidsCache;

  const filePath = COUNTRIES_MAP_PATHS.find((candidate) => fs.existsSync(candidate));
  if (!filePath) {
    centroidsCache = new Map();
    return centroidsCache;
  }

  const raw = JSON.parse(fs.readFileSync(filePath, 'utf8')) as Array<{
    iso2?: string;
    lat?: number;
    lng?: number;
    rings?: number[][][];
  }>;

  const map = new Map<string, CountryCentroid>();
  for (const row of raw) {
    const iso2 = String(row.iso2 ?? '').trim().toUpperCase();
    const lat = Number(row.lat);
    const lng = Number(row.lng);
    if (!iso2 || !Number.isFinite(lat) || !Number.isFinite(lng)) continue;
    const spread = spreadFromRings(Array.isArray(row.rings) ? row.rings : []);
    map.set(iso2, {
      iso2,
      lat,
      lng: normalizeLng(lng),
      spreadLat: spread.spreadLat,
      spreadLng: spread.spreadLng,
    });
  }

  centroidsCache = map;
  return map;
}

function hash32(input: string): number {
  let h = 2166136261;
  for (let i = 0; i < input.length; i += 1) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return Math.abs(h);
}

function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function slotPosition(centroid: CountryCentroid, slot: number): { lat: number; lng: number } {
  const rnd = mulberry32(hash32(`${centroid.iso2}:${slot}`));
  return {
    lat: centroid.lat + (rnd() - 0.5) * centroid.spreadLat,
    lng: normalizeLng(centroid.lng + (rnd() - 0.5) * centroid.spreadLng),
  };
}

export function cellSizeForPrecision(precision: number): number {
  const sizes = [18, 8, 3, 1.1, 0.35];
  const idx = Math.max(0, Math.min(sizes.length - 1, Math.floor(precision) - 1));
  return sizes[idx] ?? 3;
}

export function clampGlobePresenceArgs(precision: number, maxPoints: number): {
  precision: number;
  maxPoints: number;
  cellSize: number;
} {
  const safePrecision = Math.max(1, Math.min(5, Math.floor(precision) || 3));
  const safeMaxPoints = Math.max(128, Math.min(8192, Math.floor(maxPoints) || 4096));
  return {
    precision: safePrecision,
    maxPoints: safeMaxPoints,
    cellSize: cellSizeForPrecision(safePrecision),
  };
}

export function mergePresenceSlots(
  rows: Array<{ cc: string; slot: number; n: number }>,
  centroids: Map<string, CountryCentroid>,
  cellSize: number,
  maxPoints: number
): GlobePresenceDot[] {
  const grid = new Map<string, GlobePresenceDot>();

  for (const row of rows) {
    const centroid = centroids.get(row.cc);
    if (!centroid || row.n <= 0) continue;

    const pos = slotPosition(centroid, row.slot);
    const cellLat = Math.floor(pos.lat / cellSize) * cellSize + cellSize / 2;
    const cellLng = Math.floor(pos.lng / cellSize) * cellSize + cellSize / 2;
    const key = `${cellLat.toFixed(4)}:${cellLng.toFixed(4)}`;

    const existing = grid.get(key);
    if (existing) {
      existing.count += row.n;
      continue;
    }
    grid.set(key, { lat: cellLat, lng: normalizeLng(cellLng), count: row.n });
  }

  return [...grid.values()]
    .sort((a, b) => b.count - a.count)
    .slice(0, maxPoints);
}