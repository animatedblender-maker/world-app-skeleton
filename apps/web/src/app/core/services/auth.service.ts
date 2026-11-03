import { Injectable } from '@angular/core';
import { supabase } from '../../supabase/supabase.client';
import type { User } from '@supabase/supabase-js';
import { environment } from '../../../envirnoments/envirnoment';
import {
  validatePasswordPresent,
  validateStrongPassword,
} from '../utils/password-policy';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private apiBase = (environment as any).apiBaseUrl || 'https://api.matterya.com';

  async login(email: string, password: string): Promise<void> {
    const emailTrim = (email ?? '').trim();
    if (!emailTrim) throw new Error('Email is required. Enter your email address.');
    const present = validatePasswordPresent(password);
    if (!present.ok) throw new Error(present.message);
    const { error } = await supabase.auth.signInWithPassword({
      email: emailTrim,
      password,
    });
    if (error) throw error;
  }

  /**
   * Matterya-owned signup: API creates an unconfirmed Auth user and emails a
   * branded confirmation link to https://matterya.com/confirm-email?token=…
   * (not Supabase's default confirm page).
   */
  async register(
    email: string,
    password: string,
    birthdate: string
  ): Promise<{ isExistingEmail: boolean; needsEmailConfirm: boolean; message?: string }> {
    const emailTrim = (email ?? '').trim();
    if (!emailTrim) throw new Error('Email is required. Enter your email address.');
    const strength = validateStrongPassword(password);
    if (!strength.ok) throw new Error(strength.message);
    const birthTrim = (birthdate ?? '').trim();
    if (!birthTrim) throw new Error('Birthdate is required. Enter your date of birth.');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(birthTrim)) {
      throw new Error('Birthdate must be YYYY-MM-DD.');
    }

    const res = await fetch(`${this.apiBase}/auth/signup`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify({ email: emailTrim, password, birthdate: birthTrim }),
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

  /**
   * Matterya-owned forgot password — API emails a branded link from
   * no-reply@matterya.com (never Supabase Auth recovery mail).
   */
  async resetPassword(email: string): Promise<string> {
    const emailTrim = (email ?? '').trim();
    if (!emailTrim) throw new Error('Email is required. Enter your email address.');
    const res = await fetch(`${this.apiBase}/auth/forgot-password`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify({ email: emailTrim }),
    });
    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      throw new Error(json?.message || 'Could not send password reset email.');
    }
    return (
      json?.message ||
      'If an account exists for that email, we sent a Matterya password reset link from no-reply@matterya.com.'
    );
  }

  /**
   * Complete a Matterya reset link (`/reset-password?token=…`).
   * Sets the password via API admin — no Supabase recovery session.
   */
  async resetPasswordWithToken(token: string, newPassword: string): Promise<void> {
    const strength = validateStrongPassword(newPassword);
    if (!strength.ok) throw new Error(strength.message);
    const clean = (token ?? '').trim();
    if (!clean) throw new Error('Missing password reset link. Open the link from your email again.');

    const res = await fetch(`${this.apiBase}/auth/reset-password`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify({ token: clean, password: newPassword }),
    });
    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      throw new Error(json?.message || 'Could not reset password.');
    }
  }
}
