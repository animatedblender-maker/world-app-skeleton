import { createClient } from '@supabase/supabase-js';

type ProfileRow = {
  user_id: string;
  email: string | null;
  display_name: string | null;
  username: string | null;
  avatar_url: string | null;
  country_name: string;
  country_code: string | null;
  city_name: string | null;
  bio: string | null;
  created_at: string;
  updated_at: string;
};

type UpdateProfileInput = {
  display_name?: string | null;
  username?: string | null;
  avatar_url?: string | null;
  country_name?: string | null;
  country_code?: string | null;
  city_name?: string | null;
  bio?: string | null;
};

export class ProfilesService {
  private supabaseAdmin = createClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!
  );

  private assertEnv() {
    if (!process.env.SUPABASE_URL) throw new Error('SUPABASE_URL missing');
    if (!process.env.SUPABASE_SERVICE_ROLE_KEY) throw new Error('SUPABASE_SERVICE_ROLE_KEY missing');
  }

  async getMeProfile(userId: string): Promise<ProfileRow | null> {
    this.assertEnv();

    const { data, error } = await this.supabaseAdmin
      .from('profiles')
      .select('*')
      .eq('user_id', userId)
      .maybeSingle();

    if (error) throw error;
    return (data as ProfileRow) ?? null;
  }

  async updateProfile(userId: string, input: UpdateProfileInput): Promise<ProfileRow> {
    this.assertEnv();

    // If profile row doesn't exist (older users), create minimal row first.
    const existing = await this.getMeProfile(userId);
    if (!existing) {
      const { error: insErr } = await this.supabaseAdmin
        .from('profiles')
        .insert({ user_id: userId, country_name: 'Unknown' });

      if (insErr) throw insErr;
    }

    const patch: Record<string, any> = {};
    for (const [k, v] of Object.entries(input)) {
      if (v !== undefined) patch[k] = v;
    }

    const { data, error } = await this.supabaseAdmin
      .from('profiles')
      .update(patch)
      .eq('user_id', userId)
      .select('*')
      .single();

    if (error) throw error;
    return data as ProfileRow;
  }
}
