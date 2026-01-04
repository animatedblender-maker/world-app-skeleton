import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../core/services/auth.service';

@Component({
  selector: 'app-reset-password-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
  <div class="wrap">
    <div class="card">
      <div class="title">Reset your password</div>
      <div class="sub">Enter a new password for your account.</div>

      <div class="field">
        <label>New password</label>
        <input [(ngModel)]="password" type="password" minlength="6" placeholder="••••••••" />
      </div>

      <div class="field">
        <label>Confirm new password</label>
        <input [(ngModel)]="password2" type="password" minlength="6" placeholder="••••••••" />
      </div>

      <div class="row">
        <button class="btn" (click)="save()" [disabled]="busy">
          {{ busy ? 'Saving…' : 'Save' }}
        </button>
        <div class="msg" *ngIf="msg">{{ msg }}</div>
      </div>
    </div>
  </div>
  `,
  styles: [`
    :host { display:block; height:100vh; }
    .wrap{
      height:100vh; display:grid; place-items:center;
      background: radial-gradient(1200px 800px at 50% 30%, rgba(0,255,209,0.10), transparent 60%),
                  rgba(6,8,14,0.95);
      color: rgba(255,255,255,0.92);
    }
    .card{
      width:min(560px,92vw);
      border-radius:24px;
      padding:18px;
      background: rgba(10,12,20,0.60);
      border: 1px solid rgba(0,255,209,0.20);
      box-shadow: 0 30px 90px rgba(0,0,0,0.45);
      backdrop-filter: blur(12px);
    }
    .title{ font-weight:900; letter-spacing:0.08em; }
    .sub{ margin-top:6px; opacity:.7; font-size:13px; }
    .field{ margin-top:14px; display:grid; gap:8px; }
    label{ font-size:12px; opacity:.7; letter-spacing:0.12em; }
    input{
      padding:12px; border-radius:16px;
      border:1px solid rgba(255,255,255,0.12);
      background: rgba(0,0,0,0.28);
      color: rgba(255,255,255,0.92);
      outline:none;
    }
    .row{ margin-top:16px; display:flex; gap:12px; align-items:center; }
    .btn{
      border:0; border-radius:16px; padding:12px 14px; cursor:pointer;
      background: linear-gradient(90deg, rgba(0,255,209,0.85), rgba(140,0,255,0.75));
      color: rgba(6,8,14,0.96); font-weight:900; letter-spacing:0.12em;
    }
    .btn:disabled{ opacity:.6; cursor:not-allowed; }
    .msg{ font-size:13px; opacity:.85; }
  `],
})
export class ResetPasswordPageComponent {
  password = '';
  password2 = '';
  busy = false;
  msg = '';

  constructor(private auth: AuthService, private router: Router) {}

  async save(): Promise<void> {
    this.msg = '';
    this.busy = true;

    try {
      const p1 = this.password.trim();
      const p2 = this.password2.trim();

      if (p1.length < 6) throw new Error('Password must be at least 6 characters.');
      if (p1 !== p2) throw new Error('Passwords do not match.');

      await this.auth.updatePassword(p1);
      this.msg = 'Password updated. You can login now.';
      await this.router.navigateByUrl('/auth');
    } catch (e: any) {
      this.msg = e?.message ?? String(e);
    } finally {
      this.busy = false;
    }
  }
}
