import { Injectable } from '@angular/core';

import { CountriesService, type CountryModel } from '../../data/countries.service';
import type { Profile } from './profile.service';

const FIRST_NAMES = [
  'Amir', 'Layla', 'Noah', 'Emma', 'Omar', 'Maya', 'Liam', 'Ava', 'Eli', 'Zara',
  'Yara', 'Adam', 'Nora', 'Sami', 'Lina', 'Hadi', 'Sara', 'Leo', 'Mila', 'Aria',
  'Jade', 'Rami', 'Nina', 'Theo', 'Iris', 'Kian', 'Lara', 'Raya', 'Jonah', 'Esra',
  'Mina', 'Ayan', 'Maya', 'Niko', 'Rina', 'Zane', 'Ari', 'Tara', 'Miro', 'Zoe',
];

const LAST_NAMES = [
  'Hassan', 'Smith', 'Garcia', 'Khan', 'Lee', 'Patel', 'Kim', 'Silva', 'Nguyen', 'Lopez',
  'Baker', 'Jones', 'Ali', 'Brown', 'Miller', 'Sato', 'Ivanov', 'Singh', 'Chen', 'Davis',
  'Martinez', 'Ahmed', 'Clark', 'Wilson', 'Taylor', 'Anders', 'Morgan', 'Carter', 'Wright', 'Reed',
];

const CITY_NAMES = [
  'Cairo', 'Alexandria', 'Lagos', 'Nairobi', 'Accra', 'Casablanca', 'Rabat', 'Tunis', 'Algiers', 'Tripoli',
  'Istanbul', 'Dubai', 'Doha', 'Riyadh', 'Amman', 'Beirut', 'Tehran', 'Karachi', 'Delhi', 'Mumbai',
  'Tokyo', 'Osaka', 'Seoul', 'Shanghai', 'Beijing', 'Bangkok', 'Hanoi', 'Jakarta', 'Manila', 'Sydney',
  'Paris', 'Berlin', 'Rome', 'Madrid', 'London', 'Dublin', 'Lisbon', 'Vienna', 'Prague', 'Athens',
  'New York', 'Los Angeles', 'Toronto', 'Mexico City', 'Sao Paulo', 'Buenos Aires', 'Lima', 'Bogota', 'Santiago', 'Auckland',
];

const BIO_SNIPPETS = [
  'Exploring new cities.',
  'Collecting stories.',
  'Here for the culture.',
  'Chasing sunsets.',
  'Always learning.',
  'Small steps, big maps.',
  'Coffee and long walks.',
  'Sharing local moments.',
  'Wandering with intent.',
  'Notes from the road.',
];

const DICEBEAR_BASE = 'https://api.dicebear.com/7.x/identicon/svg?seed=';
const NAMES_DATA_URL = 'names-by-country.json';

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

function normalizeHandle(value: string): string {
  return String(value || '')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '')
    .slice(0, 18);
}

function clamp(v: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, v));
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
  private namesByCountry: Record<string, { first?: string[]; last?: string[] }> = {};
  private namesLoaded = false;
  private namesPromise: Promise<void> | null = null;

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

      await this.loadNamesByCountry();

      const rng = mulberry32(913457);
      const now = Date.now();
      const maxAgeMs = 1000 * 60 * 60 * 24 * 365 * 2;
      const usedDisplayNames = new Set<string>();

      this.profiles = [];
      this.profilesById.clear();
      this.profilesByUsername.clear();
      this.searchIndex = [];

      for (let i = 0; i < this.COUNT; i++) {
        const country = this.countries[Math.floor(rng() * this.countries.length)];
        const city = CITY_NAMES[Math.floor(rng() * CITY_NAMES.length)];

        const { first, last } = this.pickNamePair(country?.code ?? null, rng);

        const base = normalizeHandle(`${first}.${last}`) || 'user';
        const suffix = String(i + 1).padStart(5, '0');
        const username = `${base}${suffix}`;
        const userId = `fake-${suffix}`;
        const displayName = this.ensureUniqueDisplayName(first, last, country?.code ?? null, rng, usedDisplayNames);
        const createdAt = new Date(now - Math.floor(rng() * maxAgeMs)).toISOString();

        const profile: Profile = {
          user_id: userId,
          email: null,
          display_name: displayName,
          username,
          avatar_url: `${DICEBEAR_BASE}${encodeURIComponent(username)}`,
          country_name: country?.name || 'Unknown',
          country_code: country?.code ?? null,
          city_name: city,
          bio: BIO_SNIPPETS[Math.floor(rng() * BIO_SNIPPETS.length)],
          created_at: createdAt,
          updated_at: createdAt,
        };

        this.profiles.push(profile);
        this.profilesById.set(userId, profile);
        this.profilesByUsername.set(username.toLowerCase(), profile);
        this.searchIndex.push({
          profile,
          username: username.toLowerCase(),
          display: displayName.toLowerCase(),
        });
      }

      this.initialized = true;
    })();

    return this.initPromise;
  }

  private ensureUniqueDisplayName(
    first: string,
    last: string,
    countryCode: string | null,
    rng: () => number,
    used: Set<string>
  ): string {
    let display = `${first} ${last}`.trim();
    let tries = 0;
    while (used.has(display) && tries < 6) {
      const pick = this.pickNamePair(countryCode, rng);
      display = `${pick.first} ${pick.last}`.trim();
      tries += 1;
    }
    if (used.has(display)) {
      const extraLast = this.pickLastName(countryCode, rng);
      if (extraLast && extraLast !== last) {
        display = `${first} ${last} ${extraLast}`.trim();
      }
    }
    used.add(display);
    return display;
  }

  private pickNamePair(countryCode: string | null, rng: () => number): { first: string; last: string } {
    return {
      first: this.pickFirstName(countryCode, rng),
      last: this.pickLastName(countryCode, rng),
    };
  }

  private pickFirstName(countryCode: string | null, rng: () => number): string {
    const list = this.getNameList(countryCode, 'first');
    if (list.length) return list[Math.floor(rng() * list.length)];
    return FIRST_NAMES[Math.floor(rng() * FIRST_NAMES.length)];
  }

  private pickLastName(countryCode: string | null, rng: () => number): string {
    const list = this.getNameList(countryCode, 'last');
    if (list.length) return list[Math.floor(rng() * list.length)];
    return LAST_NAMES[Math.floor(rng() * LAST_NAMES.length)];
  }

  private getNameList(countryCode: string | null, key: 'first' | 'last'): string[] {
    const code = String(countryCode ?? '').trim().toUpperCase();
    const byCountry = (code && this.namesByCountry[code]?.[key]) || [];
    if (byCountry && byCountry.length) return byCountry;
    const global = this.namesByCountry['GLOBAL']?.[key] || [];
    if (global && global.length) return global;
    return [];
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
    return this.profilesById.get(userId) ?? null;
  }

  async getProfileByUsername(username: string): Promise<Profile | null> {
    await this.ensureInitialized();
    const key = String(username || '').trim().toLowerCase();
    if (!key) return null;
    return this.profilesByUsername.get(key) ?? null;
  }

  async searchProfiles(query: string, limit = 6): Promise<Profile[]> {
    await this.ensureInitialized();
    const q = String(query || '').trim().toLowerCase();
    if (!q) return [];

    const results: Array<{ score: number; profile: Profile; username: string }> = [];
    for (const entry of this.searchIndex) {
      let score = -1;
      if (entry.username.startsWith(q)) score = 0;
      else if (entry.display.startsWith(q)) score = 1;
      else if (entry.username.includes(q) || entry.display.includes(q)) score = 2;
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
