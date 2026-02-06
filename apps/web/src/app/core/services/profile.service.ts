import { Injectable } from '@angular/core';
import { GqlService } from './gql.service';
import { FakeDataService } from './fake-data.service';

export type LatLng = { lat: number; lng: number };

export type Country = {
  id: string;
  name: string;
  iso: string;
  continent?: string | null;
  center?: LatLng | null;
};

export type Profile = {
  user_id: string;
  email?: string | null;
  display_name?: string | null;
  username?: string | null;
  avatar_url?: string | null;
  country_name: string;
  country_code?: string | null;
  city_name?: string | null;
  bio?: string | null;
  followers_count?: number | null;
  following_count?: number | null;
  created_at: string;
  updated_at: string;
};

const COUNTRIES_QUERY = `
query Countries {
  countries {
    countries {
      id
      name
      iso
      continent
      center { lat lng }
    }
  }
}
`;

const ME_PROFILE = `
query MeProfile {
  meProfile {
    user_id
    email
    display_name
    username
    avatar_url
    country_name
    country_code
    city_name
    bio
    created_at
    updated_at
  }
}
`;

const UPDATE_PROFILE = `
mutation UpdateProfile($input: UpdateProfileInput!) {
  updateProfile(input: $input) {
    user_id
    email
    display_name
    username
    avatar_url
    country_name
    country_code
    city_name
    bio
    created_at
    updated_at
  }
}
`;

const PROFILE_BY_USERNAME = `
query ProfileByUsername($username: String!) {
  profileByUsername(username: $username) {
    user_id
    email
    display_name
    username
    avatar_url
    country_name
    country_code
    city_name
    bio
    created_at
    updated_at
  }
}
`;

const PROFILE_BY_ID = `
query ProfileById($user_id: ID!) {
  profileById(user_id: $user_id) {
    user_id
    email
    display_name
    username
    avatar_url
    country_name
    country_code
    city_name
    bio
    created_at
    updated_at
  }
}
`;

const SEARCH_PROFILES = `
query SearchProfiles($query: String!, $limit: Int) {
  searchProfiles(query: $query, limit: $limit) {
    user_id
    email
    display_name
    username
    avatar_url
    country_name
    country_code
    city_name
    bio
    created_at
    updated_at
  }
}
`;

@Injectable({ providedIn: 'root' })
export class ProfileService {
  constructor(
    private gql: GqlService,
    private fakeData: FakeDataService
  ) {}

  async countries() {
    return this.gql.request<{ countries: { countries: Country[] } }>(COUNTRIES_QUERY);
  }

  async meProfile() {
    return this.gql.request<{ meProfile: Profile | null }>(ME_PROFILE);
  }

  async updateProfile(input: {
    display_name?: string;
    username?: string;
    avatar_url?: string | null; // ✅ allow null
    country_name?: string;
    country_code?: string | null;
    city_name?: string | null;
    bio?: string | null;
  }) {
    return this.gql.request<{ updateProfile: Profile }>(UPDATE_PROFILE, { input });
  }

  async profileByUsername(username: string) {
    const trimmed = String(username || '').trim().replace(/^@/, '');
    if (!trimmed) {
      return { profileByUsername: null };
    }
    try {
      const real = await this.gql.request<{ profileByUsername: Profile | null }>(
        PROFILE_BY_USERNAME,
        { username: trimmed }
      );
      if (real?.profileByUsername) return real;
    } catch {
      // fall back to fake profiles if API fails
    }
    const fake = await this.fakeData.getProfileByUsername(trimmed);
    if (fake) return { profileByUsername: fake };
    return { profileByUsername: null };
  }

  async profileById(userId: string) {
    const trimmed = String(userId || '').trim();
    if (!trimmed) return { profileById: null };
    try {
      const real = await this.gql.request<{ profileById: Profile | null }>(PROFILE_BY_ID, {
        user_id: trimmed,
      });
      if (real?.profileById) return real;
    } catch {
      // fall back to fake profiles if API fails
    }
    const fake = await this.fakeData.getProfileById(trimmed);
    if (fake) return { profileById: fake };
    return { profileById: null };
  }

  isComplete(p: Profile | null) {
    if (!p) return false;
    // Treat profiles with a display name + country name as complete even if code is missing.
    return !!p.display_name && !!p.country_name && p.country_name !== 'Unknown';
  }

  async searchProfiles(query: string, limit = 6) {
    const trimmed = String(query || '').trim();
    if (!trimmed) return { searchProfiles: [] };

    const [realResult, fakeResult] = await Promise.allSettled([
      this.gql.request<{ searchProfiles: Profile[] }>(SEARCH_PROFILES, {
        query: trimmed,
        limit,
      }),
      this.fakeData.searchProfiles(trimmed, limit),
    ]);

    const realProfiles =
      realResult.status === 'fulfilled' ? realResult.value.searchProfiles ?? [] : [];
    const fakeProfiles = fakeResult.status === 'fulfilled' ? fakeResult.value : [];

    return { searchProfiles: this.mergeProfiles(realProfiles, fakeProfiles, limit) };
  }

  private mergeProfiles(real: Profile[], fake: Profile[], limit: number): Profile[] {
    const next: Profile[] = [];
    const seen = new Set<string>();

    const push = (profile: Profile) => {
      const key = profile.user_id || profile.username || '';
      if (!key || seen.has(key)) return;
      seen.add(key);
      next.push(profile);
    };

    real.forEach(push);
    fake.forEach(push);

    return next.slice(0, Math.max(1, limit));
  }
}
