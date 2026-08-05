import { Component, ChangeDetectorRef, NgZone } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../core/services/auth.service';
import { ProfileService } from '../core/services/profile.service';
import {
  validatePasswordPresent,
  validateStrongPassword,
} from '../core/utils/password-policy';

@Component({
  selector: 'app-auth-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
  <div class="auth-bg">
    <div class="auth-card">
      <div class="brand-title">Matterya</div>

      <form class="form" (ngSubmit)="submit()">
        <label class="field">
          <span>Email</span>
          <input
            type="email"
            [(ngModel)]="email"
            name="email"
            autocomplete="email"
            placeholder="you@example.com"
            required
          />
        </label>

        <label class="field">
          <span>Password</span>
          <input
            type="password"
            [(ngModel)]="password"
            name="password"
            [attr.autocomplete]="tab==='register' ? 'new-password' : 'current-password'"
            placeholder="••••••••"
            [attr.minlength]="tab === 'register' ? 8 : null"
            required
          />
        </label>

        <div class="error" *ngIf="errorMsg">{{ errorMsg }}</div>

        <div class="hint" *ngIf="accountExists">
          Email already used.
          <div class="actions">
            <button type="button" class="link" (click)="forgotPassword()">Forgot password</button>
          </div>
          <div class="hint" *ngIf="resetMsg" style="margin-top:8px;">{{ resetMsg }}</div>
        </div>

        <div class="hint" *ngIf="wrongPassword && !accountExists">
          Wrong password.
          <div class="actions">
            <button type="button" class="link" (click)="forgotPassword()">Forgot password</button>
          </div>
          <div class="hint" *ngIf="resetMsg" style="margin-top:8px;">{{ resetMsg }}</div>
        </div>

        <div class="hint" *ngIf="needsEmailConfirm && !accountExists && !wrongPassword">
          <div class="actions">
            <button type="button" class="link" (click)="resendConfirm()" [disabled]="busy">
              Resend confirmation email
            </button>
            <button type="button" class="link" (click)="forgotPassword()">Forgot password</button>
          </div>
          <div class="hint" *ngIf="resetMsg" style="margin-top:8px;">{{ resetMsg }}</div>
        </div>

        <button class="cta" type="submit" [disabled]="busy">
          {{ busy ? 'Please wait…' : (tab==='login' ? 'Log In' : 'Sign Up') }}
        </button>
      </form>

      <div class="switch-row">
        <span>{{ tab === 'login' ? "Don't have an account?" : 'Have an account?' }}</span>
        <button type="button" class="link" (click)="tab = tab === 'login' ? 'register' : 'login'; clearMsgs()">
          {{ tab === 'login' ? 'Sign up' : 'Log in' }}
        </button>
      </div>
    </div>

    <div class="popup-backdrop" *ngIf="successPopup">
      <div class="popup-card">
        <div class="popup-title">Check your email</div>
        <div class="popup-body">{{ successPopup }}</div>
      </div>
    </div>
  </div>
  `,
  styles: [`
    :host { display:block; height:100vh; }
    .auth-bg{
      min-height:100vh;
      display:grid;
      place-items:center;
      padding: 32px 16px;
      background: var(--m-paper, #f8f6f2);
      color: var(--m-ink, #2c2825);
    }
    .auth-card{
      width:min(420px, 92vw);
      display:grid;
      gap: 22px;
    }
    .brand-title{
      text-align:center;
      font-family: 'Iowan Old Style', 'Palatino Linotype', Palatino, Georgia, serif;
      font-size: 42px;
      font-weight: 600;
      letter-spacing: 0.02em;
      color: var(--m-ink, #2c2825);
      margin-bottom: 8px;
    }
    .form{ display:grid; gap:14px; }
    .field{ display:grid; gap:7px; }
    .field span{
      font-size:12px;
      font-weight: 600;
      color: var(--m-ink-muted, #948b82);
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }
    .field input{
      border: 0.5px solid var(--m-border, #ddd8d1);
      border-radius: 10px;
      padding: 12px 14px;
      background: var(--m-surface, #fefdfb);
      color: var(--m-ink, #2c2825);
      outline:none;
      font-size: 16px;
    }
    .field input:focus{
      border-color: var(--m-accent, #6b5841);
      box-shadow: 0 0 0 3px rgba(107, 88, 65, 0.12);
    }
    .cta{
      border:0;
      border-radius: 10px;
      padding: 12px 14px;
      cursor:pointer;
      background: var(--m-ink, #2c2825);
      color: var(--m-surface, #fefdfb);
      font-weight: 650;
      font-size: 15px;
    }
    .cta:disabled{ opacity:0.55; cursor:not-allowed; }
    .error{
      color: var(--m-danger, #ea000b);
      background: rgba(234, 0, 11, 0.06);
      border: 0.5px solid rgba(234, 0, 11, 0.18);
      padding:10px 12px;
      border-radius:10px;
      font-size:13px;
    }
    .hint{ color: var(--m-ink-muted, #948b82); font-size:13px; line-height:1.4; }
    .popup-backdrop{
      position: fixed;
      inset: 0;
      background: rgba(0,0,0,0.35);
      display: grid;
      place-items: center;
      z-index: 1000;
      padding: 20px;
    }
    .popup-card{
      width: min(340px, 100%);
      background: #fff;
      border-radius: 16px;
      padding: 22px 20px;
      box-shadow: 0 20px 50px rgba(0,0,0,0.2);
      text-align: center;
    }
    .popup-title{
      font-weight: 700;
      font-size: 1.05rem;
      margin-bottom: 8px;
    }
    .popup-body{
      color: var(--m-ink-muted, #948b82);
      font-size: 0.92rem;
      line-height: 1.45;
    }
    .hint.center{ text-align:center; }
    .actions{ display:flex; gap:12px; margin-top:6px; flex-wrap:wrap; }
    .switch-row{
      display:flex;
      gap: 6px;
      justify-content:center;
      align-items:center;
      flex-wrap: wrap;
      padding-top: 8px;
      border-top: 0.5px solid var(--m-divider, #e2ded8);
      color: var(--m-ink-muted, #948b82);
      font-size: 14px;
    }
    .link{
      background:transparent;
      border:0;
      padding:0;
      cursor:pointer;
      color: var(--m-accent, #6b5841);
      font-size:14px;
      font-weight:650;
    }
    .link:hover{ opacity:0.85; }
  `],
})
export class AuthPageComponent {
  tab: 'login' | 'register' = 'login';
  email = '';
  password = '';

  busy = false;
  errorMsg = '';

  accountExists = false;
  needsEmailConfirm = false;
  wrongPassword = false;
  resetMsg = '';
  successPopup = '';
  private successTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(
    private auth: AuthService,
    private profiles: ProfileService,
    private router: Router,
    private cdr: ChangeDetectorRef,
    private zone: NgZone
  ) {}

  private forceUi(): void {
    this.zone.run(() => this.cdr.detectChanges());
  }

  /** Soft-deactivated accounts come back on successful sign-in. */
  private async reactivateIfNeeded(): Promise<void> {
    try {
      const { meProfile } = await this.profiles.meProfile();
      if (meProfile?.account_status === 'deleted') {
        await this.auth.logout();
        throw new Error('This account was permanently deleted.');
      }
      if (meProfile?.account_status === 'deactivated') {
        await this.profiles.reactivateAccount();
      }
    } catch (e: any) {
      const msg = String(e?.message ?? e ?? '');
      if (msg.includes('permanently deleted') || msg.includes('ACCOUNT_DELETED')) {
        throw e;
      }
      // Non-fatal if profile columns are not migrated yet.
    }
  }

  clearMsgs(): void {
    this.errorMsg = '';
    this.accountExists = false;
    this.needsEmailConfirm = false;
    this.wrongPassword = false;
    this.resetMsg = '';
  }

  private normalizeError(e: any): string {
    const msg =
      e?.message ??
      e?.error_description ??
      e?.error?.message ??
      e?.error?.error_description ??
      e?.data?.message ??
      e?.data?.error_description ??
      '';

    if (msg && typeof msg === 'string') return msg;

    try {
      return JSON.stringify(e);
    } catch {
      return String(e);
    }
  }

  private isEmailExistsError(msg: string): boolean {
    const m = (msg || '').toLowerCase();

    return (
      m.includes('already registered') ||
      m.includes('already exists') ||
      m.includes('already in use') ||
      m.includes('email already') ||
      m.includes('user_already_exists') ||
      m.includes('email_exists') ||
      m.includes('duplicate') ||
      m.includes('exists')
    );
  }

  private isWrongPasswordError(msg: string): boolean {
    const m = (msg || '').toLowerCase();
    return (
      m.includes('invalid login credentials') ||
      m.includes('wrong password') ||
      m.includes('invalid password') ||
      m.includes('invalid credentials')
    );
  }

  async forgotPassword(): Promise<void> {
    this.resetMsg = '';
    this.forceUi();

    try {
      const email = this.email.trim();
      if (!email) {
        this.resetMsg = 'Type your email first.';
        this.forceUi();
        return;
      }

      await this.auth.resetPassword(email);
      this.resetMsg = 'Reset email sent. Check your inbox.';
    } catch (e: any) {
      this.resetMsg = this.normalizeError(e);
    } finally {
      this.forceUi();
    }
  }

  async submit(): Promise<void> {
    this.clearMsgs();

    const email = this.email.trim();
    const pass = this.password;

    if (!email) {
      this.errorMsg = 'Email is required. Enter your email address.';
      this.forceUi();
      return;
    }
    if (!this.isValidEmail(email)) {
      this.errorMsg = 'Enter a valid email address (for example you@example.com).';
      this.forceUi();
      return;
    }
    if (this.tab === 'login') {
      const present = validatePasswordPresent(pass);
      if (!present.ok) {
        this.errorMsg = present.message;
        this.forceUi();
        return;
      }
    } else {
      const strength = validateStrongPassword(pass);
      if (!strength.ok) {
        this.errorMsg = strength.message;
        this.forceUi();
        return;
      }
    }

    this.busy = true;
    this.forceUi();

    try {
      if (this.tab === 'login') {
        await this.auth.login(email, pass);
        await this.reactivateIfNeeded();
        await this.router.navigateByUrl('/feed');
        return;
      }

      const r = await this.auth.register(email, pass);

      if (r.isExistingEmail) {
        this.accountExists = true;
        this.errorMsg = 'This email is already registered. Log in or reset your password.';
        this.tab = 'login';
        return;
      }

      if (r.needsEmailConfirm) {
        this.needsEmailConfirm = true;
        this.tab = 'login';
        this.showSuccessPopup(
          'We sent you a confirmation email. Open the link to activate your account, then log in.'
        );
        return;
      }

      await this.router.navigateByUrl('/feed');
    } catch (e: any) {
      const msg = this.normalizeError(e);

      if (this.tab === 'register' && this.isEmailExistsError(msg)) {
        this.accountExists = true;
        this.errorMsg = 'This email is already registered. Log in or reset your password.';
        this.tab = 'login';
      } else if (this.tab === 'login' && this.isEmailNotConfirmedError(msg)) {
        this.needsEmailConfirm = true;
        this.errorMsg = 'Confirm your email first — check your Matterya confirmation message.';
      } else if (this.tab === 'login' && this.isWrongPasswordError(msg)) {
        this.wrongPassword = true;
        this.errorMsg = 'Wrong password.';
      } else {
        // Always show validation / server errors in red.
        this.errorMsg = msg || 'Something went wrong. Try again.';
      }
    } finally {
      this.busy = false;
      this.forceUi();
    }
  }

  private showSuccessPopup(message: string): void {
    this.successPopup = message;
    if (this.successTimer) clearTimeout(this.successTimer);
    this.successTimer = setTimeout(() => {
      this.successPopup = '';
      this.successTimer = null;
      this.forceUi();
    }, 5000);
    this.forceUi();
  }

  private isValidEmail(value: string): boolean {
    return /^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$/i.test(value);
  }

  async resendConfirm(): Promise<void> {
    this.resetMsg = '';
    this.errorMsg = '';
    this.forceUi();
    try {
      const email = this.email.trim();
      if (!email) {
        this.errorMsg = 'Email is required. Enter your email address.';
        this.forceUi();
        return;
      }
      if (!this.isValidEmail(email)) {
        this.errorMsg = 'Enter a valid email address (for example you@example.com).';
        this.forceUi();
        return;
      }
      const msg = await this.auth.resendConfirmation(email);
      this.showSuccessPopup(msg || 'We sent you a confirmation email.');
    } catch (e: any) {
      this.errorMsg = this.normalizeError(e);
    } finally {
      this.forceUi();
    }
  }

  private isEmailNotConfirmedError(msg: string): boolean {
    const m = (msg || '').toLowerCase();
    return (
      m.includes('email not confirmed') ||
      m.includes('not confirmed') ||
      m.includes('confirm your email') ||
      m.includes('email_not_confirmed')
    );
  }
}
