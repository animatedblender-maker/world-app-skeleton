import { Component, ChangeDetectorRef, NgZone } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../core/services/auth.service';

@Component({
  selector: 'app-auth-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
  <div class="auth-bg">
    <div class="auth-frame">
      <div class="scanlines"></div>
      <div class="grid"></div>

      <div class="auth-card">
        <div class="auth-brand">
          <img class="brand-logo" src="/logo.png" alt="matterya logo" />
          <div class="brand-text">
            <div class="brand-title">MATTERYA</div>
            <div class="brand-sub">Authenticate to synchronize your node.</div>
          </div>
        </div>

        <div class="tabs">
          <button
            type="button"
            class="tab"
            [class.active]="tab==='login'"
            (click)="tab='login'; clearMsgs()">
            LOGIN
          </button>

          <button
            type="button"
            class="tab"
            [class.active]="tab==='register'"
            (click)="tab='register'; clearMsgs()">
            REGISTER
          </button>
        </div>

        <form class="form" (ngSubmit)="submit()">
          <label class="field">
            <span>IDENTIFIER (EMAIL)</span>
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
            <span>ACCESS KEY (PASSWORD)</span>
            <input
              type="password"
              [(ngModel)]="password"
              name="password"
              [attr.autocomplete]="tab==='register' ? 'new-password' : 'current-password'"
              placeholder="••••••••"
              minlength="6"
              required
            />
          </label>

          <div class="error" *ngIf="errorMsg">{{ errorMsg }}</div>

          <!-- ✅ Email already used -->
          <div class="hint" *ngIf="accountExists">
            Email already used.
            <div class="actions">
              <button type="button" class="link" (click)="forgotPassword()">Forgot password</button>
            </div>
            <div class="hint" *ngIf="resetMsg" style="margin-top:8px;">{{ resetMsg }}</div>
          </div>

          <!-- ✅ Wrong password -->
          <div class="hint" *ngIf="wrongPassword && !accountExists">
            Wrong password.
            <div class="actions">
              <button type="button" class="link" (click)="forgotPassword()">Forgot password</button>
            </div>
            <div class="hint" *ngIf="resetMsg" style="margin-top:8px;">{{ resetMsg }}</div>
          </div>

          <!-- ✅ Needs email confirmation -->
          <div class="hint" *ngIf="needsEmailConfirm && !accountExists && !wrongPassword">
            Check your inbox to confirm your email, then come back and login.
            <div class="actions">
              <button type="button" class="link" (click)="forgotPassword()">Forgot password</button>
            </div>
            <div class="hint" *ngIf="resetMsg" style="margin-top:8px;">{{ resetMsg }}</div>
          </div>

          <button class="cta" type="submit" [disabled]="busy">
            {{ busy ? 'LINKING…' : (tab==='login' ? 'LOGIN' : 'CREATE ACCOUNT') }}
          </button>

          <div class="hint" *ngIf="tab==='register'">
            If email confirmation is enabled, check your inbox to confirm.
          </div>
        </form>
      </div>
    </div>
  </div>
  `,
  styles: [`
    :host { display:block; height:100vh; }
    .auth-bg{
      height:100vh; display:grid; place-items:center;
      background:
        radial-gradient(1200px 800px at 50% 30%, rgba(0,255,209,0.14), transparent 60%),
        radial-gradient(900px 700px at 60% 70%, rgba(140,0,255,0.12), transparent 55%),
        rgba(6,8,14,0.92);
    }
    .auth-frame{ position:relative; width:min(520px,92vw); padding:20px; }
    .scanlines{
      pointer-events:none; position:absolute; inset:0; border-radius:26px;
      background:repeating-linear-gradient(to bottom, rgba(255,255,255,0.05) 0px, rgba(255,255,255,0.05) 1px, rgba(0,0,0,0) 3px, rgba(0,0,0,0) 6px);
      opacity:0.35; mix-blend-mode:overlay; animation:scan 7s linear infinite;
    }
    @keyframes scan{ from{transform:translateY(0)} to{transform:translateY(18px)} }
    .grid{
      pointer-events:none; position:absolute; inset:0; border-radius:26px;
      background-image:linear-gradient(rgba(0,255,209,0.10) 1px, transparent 1px), linear-gradient(90deg, rgba(0,255,209,0.08) 1px, transparent 1px);
      background-size:36px 36px; opacity:0.25;
      mask-image:radial-gradient(circle at 50% 45%, black 40%, transparent 75%);
    }
    .auth-card{
      position:relative; border-radius:26px; padding:18px;
      background:rgba(10,12,20,0.58); backdrop-filter:blur(14px);
      box-shadow:0 30px 90px rgba(0,0,0,0.45), 0 0 0 1px rgba(0,255,209,0.20), 0 0 50px rgba(0,255,209,0.12);
      overflow:hidden;
    }
    .auth-card::before{
      content:""; position:absolute; inset:-2px; border-radius:28px;
      background:conic-gradient(from 180deg, rgba(0,255,209,0), rgba(0,255,209,0.65), rgba(140,0,255,0.55), rgba(0,255,209,0));
      filter:blur(10px); opacity:0.45;
    }
    .auth-card>*{ position:relative; z-index:1; }
    .auth-brand{ display:flex; gap:12px; align-items:center; margin-bottom:12px; }
    .brand-logo{
      width:30px;
      height:30px;
      border-radius:8px;
      object-fit:contain;
      background:rgba(0,0,0,0.25);
      box-shadow:0 0 18px rgba(0,255,209,0.35);
      padding:4px;
    }
    .brand-title{ color:rgba(255,255,255,0.92); letter-spacing:0.18em; font-weight:800; font-size:14px; }
    .brand-sub{ color:rgba(255,255,255,0.68); font-size:12px; margin-top:2px; }
    .tabs{ display:grid; grid-template-columns:1fr 1fr; gap:10px; margin:10px 0 14px; }
    .tab{
      border:0; border-radius:16px; padding:12px; cursor:pointer;
      background:rgba(255,255,255,0.06); color:rgba(255,255,255,0.78);
      font-weight:800; letter-spacing:0.12em;
    }
    .tab.active{
      background:rgba(0,255,209,0.14); color:rgba(255,255,255,0.95);
      box-shadow:0 0 0 1px rgba(0,255,209,0.25) inset, 0 0 28px rgba(0,255,209,0.10);
    }
    .form{ display:grid; gap:12px; }
    .field{ display:grid; gap:7px; }
    .field span{ font-size:11px; letter-spacing:0.14em; color:rgba(255,255,255,0.62); }
    .field input{
      border:1px solid rgba(255,255,255,0.12); border-radius:16px; padding:12px;
      background:rgba(0,0,0,0.28); color:rgba(255,255,255,0.92); outline:none;
    }
    .field input:focus{ border-color:rgba(0,255,209,0.35); box-shadow:0 0 0 3px rgba(0,255,209,0.10); }
    .cta{
      border:0; border-radius:16px; padding:13px 14px; cursor:pointer;
      background:linear-gradient(90deg, rgba(0,255,209,0.85), rgba(140,0,255,0.75));
      color:rgba(6,8,14,0.96); font-weight:900; letter-spacing:0.18em;
      box-shadow:0 18px 50px rgba(0,255,209,0.18);
    }
    .cta:disabled{ opacity:0.6; cursor:not-allowed; }
    .error{
      color:rgba(255,120,120,0.95); background:rgba(255,80,80,0.10);
      border:1px solid rgba(255,80,80,0.18); padding:10px 12px; border-radius:16px; font-size:12px;
    }
    .hint{ color:rgba(255,255,255,0.60); font-size:12px; line-height:1.4; }
    .actions{ display:flex; gap:12px; margin-top:6px; flex-wrap:wrap; }
    .link{
      background:transparent; border:0; padding:0; cursor:pointer;
      color:rgba(0,255,209,0.92);
      font-size:12px; letter-spacing:0.08em; font-weight:800;
      text-decoration:underline;
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

  constructor(
    private auth: AuthService,
    private router: Router,
    private cdr: ChangeDetectorRef,
    private zone: NgZone
  ) {}

  private forceUi(): void {
    this.zone.run(() => this.cdr.detectChanges());
  }

  clearMsgs(): void {
    this.errorMsg = '';
    this.accountExists = false;
    this.needsEmailConfirm = false;
    this.wrongPassword = false;
    this.resetMsg = '';
  }

  private normalizeError(e: any): string {
    // Supabase errors can be objects with: message, error_description, code, status, etc.
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

    // Covers common Supabase variants:
    // "User already registered"
    // "A user with this email address has already been registered"
    // "email already in use"
    // codes: user_already_exists, email_exists, etc.
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
    this.busy = true;
    this.forceUi();

    try {
      const email = this.email.trim();
      const pass = this.password;

      if (this.tab === 'login') {
        await this.auth.login(email, pass);
        await this.router.navigateByUrl('/');
        return;
      }

      // REGISTER
      const r = await this.auth.register(email, pass);

      if (r.isExistingEmail) {
        this.accountExists = true;
        this.errorMsg = 'Email already used.';
        this.tab = 'login';
        return;
      }

      if (r.needsEmailConfirm) {
        this.needsEmailConfirm = true;
        this.tab = 'login';
        return;
      }

      await this.router.navigateByUrl('/');
    } catch (e: any) {
      const msg = this.normalizeError(e);

      // REGISTER: email already used
      if (this.tab === 'register' && this.isEmailExistsError(msg)) {
        this.accountExists = true;
        this.errorMsg = 'Email already used.';
        this.tab = 'login';
      }
      // LOGIN: wrong password
      else if (this.tab === 'login' && this.isWrongPasswordError(msg)) {
        this.wrongPassword = true;
        this.errorMsg = 'Wrong password.';
      } else {
        this.errorMsg = msg;
      }
    } finally {
      this.busy = false;
      this.forceUi();
    }
  }
}
