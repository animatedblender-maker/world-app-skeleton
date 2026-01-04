import { Injectable } from '@angular/core';
import { supabase } from '../../supabase/supabase.client';
import type { User } from '@supabase/supabase-js';

@Injectable({ providedIn: 'root' })
export class AuthService {
  async login(email: string, password: string): Promise<void> {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
  }

  /**
   * Register that returns info to drive UI:
   * - isExistingEmail: email already registered
   * - needsEmailConfirm: signUp succeeded but session is null (email confirmation enabled)
   *
   * NOTE:
   * Supabase sometimes does NOT throw an error for existing emails.
   * Instead it returns a user with identities = [] and session = null.
   */
  async register(
    email: string,
    password: string
  ): Promise<{ isExistingEmail: boolean; needsEmailConfirm: boolean }> {
    const { data, error } = await supabase.auth.signUp({ email, password });

    // Case 1: explicit error
    if (error) {
      const msg = (error as any)?.message ?? String(error);

      if (/already|registered|exists|EMAIL_EXISTS|user_already_exists|email_exists/i.test(msg)) {
        return { isExistingEmail: true, needsEmailConfirm: false };
      }

      throw error;
    }

    /**
     * Case 2: "email already used" but NO error:
     * Supabase returns:
     * - data.user exists
     * - data.user.identities is []
     * - data.session is null
     */
    const identities = (data.user as any)?.identities;
    if (data.user && Array.isArray(identities) && identities.length === 0) {
      return { isExistingEmail: true, needsEmailConfirm: false };
    }

    // Case 3: normal new signup
    const needsEmailConfirm = !data.session;
    return { isExistingEmail: false, needsEmailConfirm };
  }

  async logout(): Promise<void> {
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
  }

  async getUser(): Promise<User | null> {
    const { data, error } = await supabase.auth.getUser();
    if (error) return null;
    return data.user ?? null;
  }

  async getAccessToken(): Promise<string | null> {
    const { data } = await supabase.auth.getSession();
    return data.session?.access_token ?? null;
  }

  /**
   * Sends reset password email. Make sure Supabase Auth "Site URL" + redirect URLs
   * include your app route: http://localhost:4200/reset-password
   */
  async resetPassword(email: string): Promise<void> {
    const redirectTo = `${window.location.origin}/reset-password`;

    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo,
    });

    if (error) throw error;
  }

  /**
   * On reset-password page load:
   * Exchange the recovery "code" in URL for a session.
   * Returns true if session is ready.
   */
  async prepareResetSession(): Promise<{ ok: boolean; reason?: string }> {
    try {
      const current = await supabase.auth.getSession();
      if (current.data.session) return { ok: true };

      const url = window.location.href;
      const hasCode = /[?&]code=/.test(url);

      if (hasCode) {
        const { data, error } = await supabase.auth.exchangeCodeForSession(url);
        if (error) {
          const msg = (error as any)?.message ?? String(error);
          return { ok: false, reason: msg };
        }
        if (data.session) return { ok: true };
      }

      return { ok: false, reason: 'Reset session not ready.' };
    } catch (e: any) {
      const msg = e?.message ?? String(e);
      return { ok: false, reason: msg };
    }
  }

  /**
   * Update password for the current authenticated session.
   */
  async updatePassword(newPassword: string): Promise<void> {
    const { error } = await supabase.auth.updateUser({ password: newPassword });

    if (error) {
      const msg = (error as any)?.message ?? String(error);

      if (/issued in the future|clock|skew/i.test(msg)) {
        throw new Error(
          'Your device clock looks incorrect. Please enable automatic time + time zone in Windows, sync the clock, then reopen the reset link.'
        );
      }

      throw error;
    }
  }
}
