import { Injectable } from '@angular/core';
import { supabase } from '../../supabase/supabase.client';
import type { User } from '@supabase/supabase-js';

@Injectable({ providedIn: 'root' })
export class AuthService {
  async login(email: string, password: string): Promise<void> {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
  }

  async register(email: string, password: string): Promise<void> {
    const { error } = await supabase.auth.signUp({ email, password });
    if (error) throw error;
  }

  async logout(): Promise<void> {
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
  }

  // ✅ Guard will use this
  async getUser(): Promise<User | null> {
    const { data, error } = await supabase.auth.getUser();
    if (error) return null;
    return data.user ?? null;
  }

  // ✅ GraphQL service will use this
  async getAccessToken(): Promise<string | null> {
    const { data } = await supabase.auth.getSession();
    return data.session?.access_token ?? null;
  }
}
