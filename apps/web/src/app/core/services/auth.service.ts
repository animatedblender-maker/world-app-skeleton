import { Injectable } from '@angular/core';
import { BehaviorSubject, Observable } from 'rxjs';
import { createClient, type SupabaseClient, type Session } from '@supabase/supabase-js';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from '../../config/supabase.config';

export type AuthUser = { id: string; email: string };

@Injectable({ providedIn: 'root' })
export class AuthService {
  private supabase: SupabaseClient;
  private user$ = new BehaviorSubject<AuthUser | null>(null);

  constructor() {
    this.supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

    // restore session -> set token + user
    this.initFromSession();

    // keep token/user synced on any auth change
    this.supabase.auth.onAuthStateChange((_event, session) => {
      this.applySession(session);
    });
  }

  currentUser(): Observable<AuthUser | null> {
    return this.user$.asObservable();
  }

  getAccessToken(): string | null {
    return localStorage.getItem('world_token');
  }

  async register(email: string, password: string): Promise<AuthUser> {
    const { data, error } = await this.supabase.auth.signUp({ email, password });
    if (error) throw error;

    // Supabase may require email confirmation depending on settings.
    // If email confirmation is ON, session can be null here.
    this.applySession(data.session ?? null);

    const user = data.user;
    if (!user) throw new Error('No user returned from Supabase register');

    const u = { id: user.id, email: user.email ?? email };
    this.user$.next(u);

    return u;
  }

  async login(email: string, password: string): Promise<AuthUser> {
    const { data, error } = await this.supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;

    this.applySession(data.session);

    const user = data.user;
    const u = { id: user.id, email: user.email ?? email };
    this.user$.next(u);

    return u;
  }

  async logout(): Promise<void> {
    await this.supabase.auth.signOut();
    this.applySession(null);
  }

  private async initFromSession() {
    const { data, error } = await this.supabase.auth.getSession();
    if (error) {
      console.error('❌ Supabase getSession error:', error);
      this.applySession(null);
      return;
    }
    this.applySession(data.session ?? null);
  }

  private applySession(session: Session | null) {
    if (session?.access_token) {
      localStorage.setItem('world_token', session.access_token);
    } else {
      localStorage.removeItem('world_token');
    }

    const user = session?.user;
    if (user) {
      this.user$.next({ id: user.id, email: user.email ?? '' });
    } else {
      this.user$.next(null);
    }
  }
}
