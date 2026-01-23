import { Injectable } from '@angular/core';

import { CountriesService, type CountryModel } from '../../data/countries.service';
import type { Profile } from './profile.service';

const DICEBEAR_BASE = 'https://api.dicebear.com/7.x/identicon/svg?seed=';
const FAKE_USERS_URL = 'fake_users_60k_real_names/fake_users_60k.jsonl';
const NAMES_DATA_URL = 'names-by-country.json';

type FakeUserRow = {
  user_id: string;
  first_name?: string | null;
  last_name?: string | null;
  username?: string | null;
  handle?: string | null;
  city?: string | null;
  country?: string | null;
  country_code?: string | null;
  bio?: string | null;
};

type LatLng = { lat: number; lng: number };
type CountryGeo = {
  center: LatLng;
  points: LatLng[];
  minLat: number;
  maxLat: number;
  minLng: number;
  maxLng: number;
};

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

function hashSeed(value: string): number {
  let h = 2166136261;
  for (let i = 0; i < value.length; i++) {
    h ^= value.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

function normalizeHandle(value: string): string {
  return String(value || '')
    .toLowerCase()
    .replace(/[^a-z0-9._]/g, '')
    .replace(/^@+/, '')
    .slice(0, 24);
}

function clamp(v: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, v));
}

function parseJsonl<T>(text: string, limit?: number): T[] {
  const out: T[] = [];
  const lines = text.split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      out.push(JSON.parse(trimmed) as T);
    } catch {
      // Skip bad lines.
    }
    if (limit && out.length >= limit) break;
  }
  return out;
}

@Injectable({ providedIn: 'root' })
export class FakeDataService {
  private readonly COUNT = 30000;

  private initialized = false;
  private initPromise: Promise<void> | null = null;

  private profiles: Profile[] = [];
  private profilesById = new Map<string, Profile>();
  private profilesByUsername = new Map<string, Profile>();
  private searchIndex: Array<{ profile: Profile; username: string; display: string }> = [];

  private countries: CountryModel[] = [];

  private fakeUsersLoaded = false;
  private fakeUsersPromise: Promise<void> | null = null;
  private fakeUsers: FakeUserRow[] = [];
  private fakeUsersById = new Map<string, FakeUserRow>();
  private cityPoolByCountry = new Map<string, string[]>();
  private fallbackCityPoolByCountry = new Map<string, string[]>();
  private cityPrimaryCountry = new Map<string, string>();
  private generatedCityPoolByCountry = new Map<string, string[]>();
  private countryGeoByCode = new Map<string, CountryGeo>();

  private namesLoaded = false;
  private namesPromise: Promise<void> | null = null;
  private namesByCountry: Record<string, { first?: string[]; last?: string[] }> = {};

  constructor(private countriesService: CountriesService) {}

  async ensureInitialized(countries?: CountryModel[]): Promise<void> {
    if (this.initialized) return;
    if (this.initPromise) return this.initPromise;

    this.initPromise = (async () => {
      const supplied = (countries || []).filter((c) => !!c.code);
      if (supplied.length) {
        this.countries = supplied;
      } else {
        const loaded = await this.countriesService.loadCountries();
        this.countries = (loaded.countries || []).filter((c) => !!c.code);
      }
      if (!this.countries.length) {
        this.countries = [
          {
            id: 0,
            name: 'World',
            norm: 'world',
            center: { lat: 0, lng: 0 },
            labelSize: 0.6,
            flyAltitude: 1,
            code: 'WW',
            pointPool: [{ lat: 0, lng: 0 }],
          },
        ];
      }

      this.buildCountryGeoIndex();
      await this.loadFakeUsers();
      await this.loadNamesByCountry();
      this.buildCityPools();

      const now = Date.now();
      const maxAgeMs = 1000 * 60 * 60 * 24 * 365 * 2;
      const usedDisplayNames = new Set<string>();

      this.profiles = [];
      this.profilesById.clear();
      this.profilesByUsername.clear();
      this.searchIndex = [];

      const source = this.fakeUsers.length ? this.fakeUsers : [];
      const limit = clamp(this.COUNT, 1, source.length || 1);

      for (let i = 0; i < limit; i++) {
        const row = source[i] || { user_id: `user_${String(i + 1).padStart(6, '0')}` };
        const userId = String(row.user_id || '').trim() || `user_${String(i + 1).padStart(6, '0')}`;

        const rng = mulberry32(hashSeed(userId));
        const createdAt = new Date(now - Math.floor(rng() * maxAgeMs)).toISOString();

        const countryCode = this.resolveCountryCode(row.country_code, row.country);
        const username = this.buildUsername(row, userId, countryCode);
        const displayName = this.buildDisplayName(row, userId, username, countryCode, usedDisplayNames);
        const countryName = this.resolveCountryName(row.country, countryCode);
        const cityName = this.pickCityName(row, countryCode, userId);
        const bio = this.normalizeBio(row.bio, row.city, cityName);

        const followSeed = mulberry32(hashSeed(`${userId}|follow`));
        const followers = Math.floor(Math.pow(followSeed(), 2) * 20000);
        const following = Math.floor(Math.pow(followSeed(), 2) * 3200);

        const profile: Profile = {
          user_id: userId,
          email: null,
          display_name: displayName,
          username,
          avatar_url: `${DICEBEAR_BASE}${encodeURIComponent(username || userId)}`,
          country_name: countryName || 'Unknown',
          country_code: countryCode,
          city_name: cityName,
          bio,
          followers_count: followers,
          following_count: following,
          created_at: createdAt,
          updated_at: createdAt,
        };

        this.profiles.push(profile);
        this.profilesById.set(userId, profile);
        if (username) {
          this.profilesByUsername.set(username.toLowerCase(), profile);
        }
        const handle = normalizeHandle(row.handle || '');
        if (handle) {
          this.profilesByUsername.set(handle.toLowerCase(), profile);
        }
        this.searchIndex.push({
          profile,
          username: (username || '').toLowerCase(),
          display: (displayName || '').toLowerCase(),
        });
      }

      this.initialized = true;
    })();

    return this.initPromise;
  }

  private buildUsername(row: FakeUserRow, userId: string, countryCode: string | null): string {
    const fromRow = normalizeHandle(row.username || row.handle || '');
    if (fromRow) return fromRow;
    const first = this.pickNamePart(row.first_name, countryCode, 'first', hashSeed(`${userId}|first`));
    const last = this.pickNamePart(row.last_name, countryCode, 'last', hashSeed(`${userId}|last`));
    const base = normalizeHandle(`${first}.${last}`) || normalizeHandle(userId);
    return base || normalizeHandle(userId);
  }

  private buildDisplayName(
    row: FakeUserRow,
    userId: string,
    username: string,
    countryCode: string | null,
    used: Set<string>
  ): string {
    const first = this.pickNamePart(row.first_name, countryCode, 'first', hashSeed(`${userId}|first`));
    const last = this.pickNamePart(row.last_name, countryCode, 'last', hashSeed(`${userId}|last`));
    let display = `${first} ${last}`.trim();
    if (!display) display = username || userId;

    let attempt = 0;
    while (used.has(display) && attempt < 4) {
      display = `${display} ${String(attempt + 1)}`.trim();
      attempt += 1;
    }
    used.add(display);
    return display;
  }

  private normalizeCountryCode(value?: string | null): string | null {
    const cc = String(value || '').trim().toUpperCase();
    return cc || null;
  }

  private normalizeCountryName(value?: string | null): string {
    return String(value || '')
      .trim()
      .toLowerCase()
      .replace(/\s+/g, ' ');
  }

  private buildCountryGeoIndex(): void {
    this.countryGeoByCode.clear();
    for (const country of this.countries) {
      const code = String(country.code || '').trim().toUpperCase();
      if (!code) continue;
      const points = Array.isArray(country.pointPool) ? country.pointPool : [];
      if (!points.length) continue;
      let minLat = Infinity;
      let maxLat = -Infinity;
      let minLng = Infinity;
      let maxLng = -Infinity;
      for (const point of points) {
        if (!point) continue;
        minLat = Math.min(minLat, point.lat);
        maxLat = Math.max(maxLat, point.lat);
        minLng = Math.min(minLng, point.lng);
        maxLng = Math.max(maxLng, point.lng);
      }
      if (!Number.isFinite(minLat) || !Number.isFinite(minLng)) continue;
      this.countryGeoByCode.set(code, {
        center: country.center,
        points,
        minLat,
        maxLat,
        minLng,
        maxLng,
      });
    }
  }

  private resolveCountryCode(code?: string | null, name?: string | null): string | null {
    const direct = this.normalizeCountryCode(code);
    if (direct) return direct;
    const normalized = this.normalizeCountryName(name);
    if (!normalized) return null;
    const match = this.countries.find(
      (country) => this.normalizeCountryName(country.name) === normalized
    );
    return match?.code ?? null;
  }

  private resolveCountryName(value?: string | null, code?: string | null): string | null {
    const direct = (value || '').trim();
    const normalizedDirect = this.normalizeCountryName(direct);
    const normalizedCode = String(code || '').trim().toUpperCase();
    if (normalizedCode) {
      const match = this.countries.find((c) => String(c.code || '').toUpperCase() === normalizedCode);
      if (!match) return direct || null;
      if (normalizedDirect && this.normalizeCountryName(match.name) === normalizedDirect) {
        return direct;
      }
      return match.name || direct || null;
    }
    return direct || null;
  }

  private pickNamePart(
    value: string | null | undefined,
    countryCode: string | null,
    key: 'first' | 'last',
    seed?: number
  ): string {
    const list = this.getNameList(countryCode, key);
    if (list.length) {
      if (Number.isFinite(seed)) {
        const rng = mulberry32(seed as number);
        return list[Math.floor(rng() * list.length)];
      }
      return list[0];
    }
    const direct = (value || '').trim();
    if (direct) return direct;
    return '';
  }

  private getNameList(countryCode: string | null, key: 'first' | 'last'): string[] {
    const code = String(countryCode ?? '').trim().toUpperCase();
    const byCountry = (code && this.namesByCountry[code]?.[key]) || [];
    if (byCountry && byCountry.length) return byCountry;
    const global = this.namesByCountry['GLOBAL']?.[key] || [];
    if (global && global.length) return global;
    return [];
  }

  private buildCityPools(): void {
    const countsByCountry = new Map<string, Map<string, number>>();
    const countsByCity = new Map<string, Map<string, number>>();
    for (const row of this.fakeUsers) {
      const cc = this.resolveCountryCode(row.country_code, row.country);
      const city = this.normalizeCityName(row.city);
      if (!cc || !city || !this.isSaneCityName(city)) continue;
      const bucket = countsByCountry.get(cc) ?? new Map<string, number>();
      bucket.set(city, (bucket.get(city) ?? 0) + 1);
      countsByCountry.set(cc, bucket);

      const cityBucket = countsByCity.get(city) ?? new Map<string, number>();
      cityBucket.set(cc, (cityBucket.get(cc) ?? 0) + 1);
      countsByCity.set(city, cityBucket);
    }

    this.cityPoolByCountry.clear();
    this.fallbackCityPoolByCountry.clear();
    this.cityPrimaryCountry.clear();
    this.generatedCityPoolByCountry.clear();

    const primaryByCountry = new Map<string, Array<{ city: string; count: number }>>();
    for (const [city, cityMap] of countsByCity.entries()) {
      const sorted = Array.from(cityMap.entries()).sort((a, b) => b[1] - a[1]);
      const [primaryCountry, primaryCount] = sorted[0];
      const total = sorted.reduce((sum, entry) => sum + entry[1], 0);
      const ratio = total ? primaryCount / total : 0;
      this.cityPrimaryCountry.set(city, primaryCountry);
      if (total >= 3 && ratio >= 0.7) {
        const list = primaryByCountry.get(primaryCountry) ?? [];
        list.push({ city, count: primaryCount });
        primaryByCountry.set(primaryCountry, list);
      }
    }

    const maxCities = 240;
    for (const [cc, cityList] of primaryByCountry.entries()) {
      const ordered = cityList
        .sort((a, b) => b.count - a.count)
        .slice(0, maxCities)
        .map((entry) => entry.city);
      this.cityPoolByCountry.set(cc, ordered);
    }

    for (const [cc, cityMap] of countsByCountry.entries()) {
      const ordered = Array.from(cityMap.entries())
        .sort((a, b) => b[1] - a[1])
        .slice(0, maxCities)
        .map(([city]) => city);
      this.fallbackCityPoolByCountry.set(cc, ordered);
    }

    for (const country of this.countries) {
      const cc = String(country.code || '').trim().toUpperCase();
      if (!cc) continue;
      const generated = this.generateMapCityPool(cc);
      if (generated.length) this.generatedCityPoolByCountry.set(cc, generated);
    }
  }

  private pickCityName(row: FakeUserRow, countryCode: string | null, userId: string): string | null {
    const cc = String(countryCode || '').trim().toUpperCase();
    const direct = this.normalizeCityName(row.city);
    const mapPool = cc ? this.generatedCityPoolByCountry.get(cc) ?? [] : [];
    const pool = cc
      ? mapPool.length
        ? mapPool
        : this.cityPoolByCountry.get(cc) ??
          this.fallbackCityPoolByCountry.get(cc) ??
          []
      : [];
    if (!pool.length) return null;
    const rng = mulberry32(hashSeed(`${userId}|city`));
    return pool[Math.floor(rng() * pool.length)] ?? null;
  }

  private normalizeCityName(value?: string | null): string {
    return String(value || '').trim().replace(/\s+/g, ' ');
  }

  private isSaneCityName(value: string): boolean {
    if (!value) return false;
    const cleaned = value.trim();
    if (!cleaned || cleaned.length > 48) return false;
    const allowed = cleaned.match(/[A-Za-z0-9 .,'-]/g)?.length ?? 0;
    return allowed / cleaned.length >= 0.7;
  }

  private generateMapCityPool(countryCode: string): string[] {
    const geo = this.countryGeoByCode.get(countryCode);
    if (!geo || !geo.points.length) return [];
    const rng = mulberry32(hashSeed(`${countryCode}|geo`));
    const labels = new Set<string>();
    const attempts = Math.min(geo.points.length * 2, 480);
    for (let i = 0; i < attempts; i += 1) {
      const idx = Math.floor(rng() * geo.points.length);
      const point = geo.points[idx];
      if (!point) continue;
      labels.add(this.pickRegionLabel(geo, point));
      if (labels.size >= 12) break;
    }
    return Array.from(labels);
  }

  private pickRegionLabel(geo: CountryGeo, point: LatLng): string {
    const latSpan = Math.max(0.1, geo.maxLat - geo.minLat);
    const lngSpan = Math.max(0.1, geo.maxLng - geo.minLng);
    const relLat = (point.lat - geo.center.lat) / latSpan;
    const relLng = (point.lng - geo.center.lng) / lngSpan;
    const threshold = 0.18;
    let vertical = '';
    let horizontal = '';
    if (relLat > threshold) vertical = 'North';
    else if (relLat < -threshold) vertical = 'South';
    if (relLng > threshold) horizontal = 'East';
    else if (relLng < -threshold) horizontal = 'West';
    if (!vertical && !horizontal) return 'Central';
    if (vertical && horizontal) {
      const key = `${vertical}-${horizontal}`;
      const combo: Record<string, string> = {
        'North-East': 'Northeast',
        'North-West': 'Northwest',
        'South-East': 'Southeast',
        'South-West': 'Southwest',
      };
      return combo[key] ?? `${vertical}${horizontal}`;
    }
    return vertical || horizontal;
  }

  private normalizeBio(
    value?: string | null,
    originalCity?: string | null,
    chosenCity?: string | null
  ): string | null {
    const trimmed = String(value || '').trim();
    if (!trimmed) return null;
    let result = trimmed;
    const sourceCity = this.normalizeCityName(originalCity);
    const targetCity = this.normalizeCityName(chosenCity);
    if (sourceCity) {
      const escaped = sourceCity.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const pattern = new RegExp(escaped, 'gi');
      if (pattern.test(result)) {
        result = result.replace(pattern, targetCity || '').replace(/\s{2,}/g, ' ').trim();
      }
    }
    result = result.replace(/\s*(?:\u2022|\u00b7|[|.-])\s*$/g, '').trim();
    return result || null;
  }

  private async loadFakeUsers(): Promise<void> {
    if (this.fakeUsersLoaded) return;
    if (this.fakeUsersPromise) return this.fakeUsersPromise;

    this.fakeUsersPromise = (async () => {
      if (typeof window === 'undefined' || typeof document === 'undefined') {
        this.fakeUsers = [];
        this.fakeUsersLoaded = true;
        return;
      }
      try {
        const baseHref = document.querySelector('base')?.getAttribute('href') ?? '/';
        const resolvedBase = new URL(baseHref, window.location.origin).toString();
        const url = new URL(FAKE_USERS_URL, resolvedBase).toString();
        const res = await fetch(url);
        if (!res.ok) throw new Error(`Failed to load fake users: ${res.status}`);
        const text = await res.text();
        this.fakeUsers = parseJsonl<FakeUserRow>(text, this.COUNT);
        this.fakeUsersById.clear();
        for (const row of this.fakeUsers) {
          if (!row?.user_id) continue;
          this.fakeUsersById.set(row.user_id, row);
        }
        this.buildCityPools();
      } catch {
        this.fakeUsers = [];
        this.fakeUsersById.clear();
        this.cityPoolByCountry.clear();
        this.fallbackCityPoolByCountry.clear();
        this.cityPrimaryCountry.clear();
        this.generatedCityPoolByCountry.clear();
      } finally {
        this.fakeUsersLoaded = true;
      }
    })();

    return this.fakeUsersPromise;
  }

  private async loadNamesByCountry(): Promise<void> {
    if (this.namesLoaded) return;
    if (this.namesPromise) return this.namesPromise;

    this.namesPromise = (async () => {
      if (typeof window === 'undefined' || typeof document === 'undefined') {
        this.namesByCountry = {};
        this.namesLoaded = true;
        return;
      }
      try {
        const baseHref = document.querySelector('base')?.getAttribute('href') ?? '/';
        const resolvedBase = new URL(baseHref, window.location.origin).toString();
        const url = new URL(NAMES_DATA_URL, resolvedBase).toString();
        const res = await fetch(url);
        if (!res.ok) throw new Error(`Failed to load names data: ${res.status}`);
        const data = await res.json();
        this.namesByCountry = (data && typeof data === 'object') ? data : {};
      } catch {
        this.namesByCountry = {};
      } finally {
        this.namesLoaded = true;
      }
    })();

    return this.namesPromise;
  }

  async getProfiles(countries?: CountryModel[]): Promise<Profile[]> {
    await this.ensureInitialized(countries);
    return this.profiles;
  }

  async getProfileById(userId: string): Promise<Profile | null> {
    await this.ensureInitialized();
    const existing = this.profilesById.get(userId);
    if (existing) return existing;
    const row = this.fakeUsersById.get(userId);
    if (!row) return null;

    const countryCode = this.resolveCountryCode(row.country_code, row.country);
    const username = this.buildUsername(row, userId, countryCode);
    const displayName = this.buildDisplayName(row, userId, username, countryCode, new Set());
    const countryName = this.resolveCountryName(row.country, countryCode);
    const cityName = this.pickCityName(row, countryCode, userId);
    const createdAt = new Date().toISOString();
    const bio = this.normalizeBio(row.bio, row.city, cityName);

    const followSeed = mulberry32(hashSeed(`${userId}|follow`));
    const profile: Profile = {
      user_id: userId,
      email: null,
      display_name: displayName,
      username,
      avatar_url: `${DICEBEAR_BASE}${encodeURIComponent(username || userId)}`,
      country_name: countryName || 'Unknown',
      country_code: countryCode,
      city_name: cityName,
      bio,
      followers_count: Math.floor(Math.pow(followSeed(), 2) * 20000),
      following_count: Math.floor(Math.pow(followSeed(), 2) * 3200),
      created_at: createdAt,
      updated_at: createdAt,
    };

    this.profilesById.set(userId, profile);
    if (username) {
      this.profilesByUsername.set(username.toLowerCase(), profile);
    }
    this.searchIndex.push({
      profile,
      username: (username || '').toLowerCase(),
      display: (displayName || '').toLowerCase(),
    });
    this.profiles.push(profile);
    return profile;
  }

  async ensureProfilesById(userIds: Iterable<string>): Promise<void> {
    await this.ensureInitialized();
    for (const userId of userIds) {
      if (!userId) continue;
      if (this.profilesById.has(userId)) continue;
      const row = this.fakeUsersById.get(userId);
      if (!row) continue;
      await this.getProfileById(userId);
    }
  }

  async getProfileByUsername(username: string): Promise<Profile | null> {
    await this.ensureInitialized();
    const key = normalizeHandle(username);
    if (!key) return null;
    return this.profilesByUsername.get(key) ?? null;
  }

  async getFollowCounts(userId: string): Promise<{ followers: number; following: number } | null> {
    await this.ensureInitialized();
    const profile = this.profilesById.get(userId);
    if (!profile) return null;
    return {
      followers: profile.followers_count ?? 0,
      following: profile.following_count ?? 0,
    };
  }

  async searchProfiles(query: string, limit = 6): Promise<Profile[]> {
    await this.ensureInitialized();
    const raw = String(query || '').trim().toLowerCase();
    const handle = normalizeHandle(query);
    if (!raw && !handle) return [];

    const results: Array<{ score: number; profile: Profile; username: string }> = [];
    for (const entry of this.searchIndex) {
      let score = -1;
      if (handle && entry.username.startsWith(handle)) score = 0;
      else if (raw && entry.display.startsWith(raw)) score = 1;
      else if (
        (handle && entry.username.includes(handle)) ||
        (raw && entry.display.includes(raw))
      ) {
        score = 2;
      }
      if (score === -1) continue;
      results.push({ score, profile: entry.profile, username: entry.username });
    }

    results.sort((a, b) => (a.score - b.score) || a.username.localeCompare(b.username));

    const picked: Profile[] = [];
    for (const item of results) {
      picked.push(item.profile);
      if (picked.length >= clamp(limit, 1, 50)) break;
    }
    return picked;
  }
}
