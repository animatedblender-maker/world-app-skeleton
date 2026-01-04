import { Injectable } from '@angular/core';
import { GqlService } from './gql.service';

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

@Injectable({ providedIn: 'root' })
export class ProfileService {
  constructor(private gql: GqlService) {}

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

  isComplete(p: Profile | null) {
    if (!p) return false;
    return !!p.display_name && !!p.country_code && p.country_name !== 'Unknown';
  }
}
