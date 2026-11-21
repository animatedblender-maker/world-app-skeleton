import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { AuthService } from '../core/services/auth.service';
import {
  PASSWORD_REQUIREMENTS_HINT,
  validateStrongPassword,
} from '../core/utils/password-policy';

@Component({
  selector: 'app-reset-password-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
  <div class="auth-bg">
    <div class="auth-card">
      <div class="brand-title">Matterya</div>
      <div class="page-title">Reset your password</div>
      <div class="sub" *ngIf="token">Enter a new password for your Matterya account.</div>
      <div class="sub" *ngIf="!token">
        This page needs a valid reset link from your Matterya email (no-reply@matterya.com).
      </div>

      <ng-container *ngIf="token">
        <form class="form" (ngSubmit)="save()">
          <label class="field">
            <span>New password</span>
            <input
              [(ngModel)]="password"
              name="password"
              type="password"
              autocomplete="new-password"
              minlength="8"
              placeholder="••••••••"
              required
            />
            <span class="field-hint">{{ passwordHint }}</span>
          </label>

          <label class="field">
            <span>Confirm new password</span>
            <input
              [(ngModel)]="password2"
              name="password2"
              type="password"
              autocomplete="new-password"
              minlength="8"
              placeholder="••••••••"
              required
            />
          </label>

          <div class="error" *ngIf="msg && !savedOk">{{ msg }}</div>
          <div class="hint ok" *ngIf="msg && savedOk">{{ msg }}</div>

          <button class="cta" type="submit" [disabled]="busy">
            {{ busy ? 'Saving…' : 'Save password' }}
          </button>
        </form>
      </ng-container>

      <div class="error" *ngIf="!token && msg">{{ msg }}</div>

      <div class="switch-row">
        <button type="button" class="link" (click)="goLogin()">Back to log in</button>
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
      gap: 16px;
    }
    .brand-title{
      text-align:center;
      font-family: 'Iowan Old Style', 'Palatino Linotype', Palatino, Georgia, serif;
      font-size: 42px;
      font-weight: 600;
      letter-spacing: 0.02em;
      color: var(--m-ink, #2c2825);
      margin-bottom: 4px;
    }
    .page-title{
      text-align:center;
      font-size: 18px;
      font-weight: 650;
      color: var(--m-ink, #2c2825);
    }
    .sub{
      text-align:center;
      color: var(--m-ink-muted, #948b82);
      font-size: 14px;
      line-height: 1.45;
      margin-bottom: 4px;
    }
    .form{ display:grid; gap:14px; margin-top: 6px; }
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
      border-color: var(--m-accent, #2c2825);
      box-shadow: 0 0 0 3px rgba(44, 40, 37, 0.12);
    }
    .field-hint{
      font-size: 11px;
      font-weight: 500;
      text-transform: none;
      letter-spacing: 0;
      color: var(--m-ink-muted, #948b82);
      line-height: 1.35;
    }
    .cta{
      border:0;
      border-radius: var(--m-control-radius, 8px);
      padding: 14px 16px;
      cursor:pointer;
      background: var(--m-ink, #2c2825);
      color: var(--m-paper, #f8f6f2);
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
    .hint.ok{
      color: var(--m-ink, #2c2825);
      background: rgba(44, 40, 37, 0.06);
      border: 0.5px solid var(--m-border, #ddd8d1);
      padding:10px 12px;
      border-radius:10px;
    }
    .switch-row{
      display:flex;
      justify-content:center;
      margin-top: 8px;
    }
    .link{
      border:0;
      background:transparent;
      color: var(--m-ink, #2c2825);
      font-weight: 650;
      font-size: 14px;
      cursor:pointer;
      text-decoration: underline;
      text-underline-offset: 3px;
      padding: 4px 0;
    }
  `],
})
export class ResetPasswordPageComponent implements OnInit {
  password = '';
  password2 = '';
  busy = false;
  msg = '';
  savedOk = false;
  token = '';
  readonly passwordHint = PASSWORD_REQUIREMENTS_HINT;

  constructor(
    private auth: AuthService,
    private router: Router,
    private route: ActivatedRoute
  ) {}

  ngOnInit(): void {
    this.token = String(this.route.snapshot.queryParamMap.get('token') ?? '').trim();
    if (!this.token) {
      this.msg =
        'Open the Reset my password button in the email from no-reply@matterya.com, or request a new link from the login screen.';
    }
  }

  goLogin(): void {
    void this.router.navigateByUrl('/auth');
  }

  async save(): Promise<void> {
    this.msg = '';
    this.savedOk = false;
    this.busy = true;

    try {
      const p1 = this.password;
      const p2 = this.password2;

      const strength = validateStrongPassword(p1);
      if (!strength.ok) throw new Error(strength.message);
      if (p1 !== p2) throw new Error('Passwords do not match.');
      if (!this.token) throw new Error('Missing password reset link.');

      await this.auth.resetPasswordWithToken(this.token, p1);
      this.savedOk = true;
      this.msg = 'Password updated. You can log in now.';
      await this.router.navigateByUrl('/auth');
    } catch (e: any) {
      this.msg = e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  }
}
