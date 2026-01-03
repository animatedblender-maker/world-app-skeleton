import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from  '../../app/core/services/auth.service'

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
          <div class="brand-mark"></div>
          <div class="brand-text">
            <div class="brand-title">WORLD APP</div>
            <div class="brand-sub">Authenticate to synchronize your node.</div>
          </div>
        </div>

        <div class="tabs">
          <button
            type="button"
            class="tab"
            [class.active]="tab==='login'"
            (click)="tab='login'">
            LOGIN
          </button>

          <button
            type="button"
            class="tab"
            [class.active]="tab==='register'"
            (click)="tab='register'">
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
    .brand-mark{ width:14px; height:14px; border-radius:50%; background:rgba(0,255,209,0.95); box-shadow:0 0 18px rgba(0,255,209,0.65); }
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
  `],
})
export class AuthPageComponent {
  tab: 'login' | 'register' = 'login';
  email = '';
  password = '';
  busy = false;
  errorMsg = '';

  constructor(private auth: AuthService, private router: Router) {}

  async submit(): Promise<void> {
    this.errorMsg = '';
    this.busy = true;

    try {
      const email = this.email.trim();
      const pass = this.password;

      if (this.tab === 'login') {
        await this.auth.login(email, pass);
      } else {
        await this.auth.register(email, pass);
      }

      // After auth, we will decide profile completeness on Home/ProfileSetup route.
      await this.router.navigateByUrl('/');
    } catch (e: any) {
      this.errorMsg = e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  }
}
