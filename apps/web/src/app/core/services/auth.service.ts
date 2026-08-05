import { Injectable } from '@angular/core';
import { supabase } from '../../supabase/supabase.client';
import type { User } from '@supabase/supabase-js';
import { environment } from '../../../envirnoments/envirnoment';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private apiBase = (environment as any).apiBaseUrl || 'https://api.matterya.com';

  async login(email: string, password: string): Promise<void> {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
  }

  /**
   * Matterya-owned signup: API creates an unconfirmed Auth user and emails a
   * branded confirmation link to https://matterya.com/confirm-email?token=…
   * (not Supabase's default confirm page).
   */
  async register(
    email: string,
    password: string
  ): Promise<{ isExistingEmail: boolean; needsEmailConfirm: boolean; message?: string }> {
    const res = await fetch(`${this.apiBase}/auth/signup`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify({ email: email.trim(), password }),
    });
    const json = await res.json().catch(() => ({}));

    if (!res.ok) {
      if (json?.isExistingEmail || json?.error === 'EMAIL_EXISTS') {
        return { isExistingEmail: true, needsEmailConfirm: false };
      }
      throw new Error(json?.message || json?.error || `Signup failed (HTTP ${res.status}).`);
    }

    return {
      isExistingEmail: false,
      needsEmailConfirm: true,
      message:
        'We sent a confirmation email from Matterya. Open the link to activate your account, then log in.',
    };
  }

  async resendConfirmation(email: string): Promise<string> {
    const res = await fetch(`${this.apiBase}/auth/resend-confirmation`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify({ email: email.trim() }),
    });
    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      throw new Error(json?.message || 'Could not resend confirmation email.');
    }
    return json?.message || 'If that email needs confirmation, we sent a new Matterya link.';
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

  async resetPassword(email: string): Promise<void> {
    const redirectTo = `${window.location.origin}/reset-password`;

    const { error } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo,
    });

    if (error) throw error;
  }

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
