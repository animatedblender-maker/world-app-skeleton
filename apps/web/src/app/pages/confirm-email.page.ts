import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { environment } from '../../envirnoments/envirnoment';

@Component({
  selector: 'app-confirm-email-page',
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <div class="wrap">
      <div class="card">
        <div class="brand">Matterya</div>
        <h1>{{ title }}</h1>
        <p class="sub" *ngIf="message">{{ message }}</p>

        <div class="spinner" *ngIf="busy">Confirming your email…</div>

        <div class="actions" *ngIf="!busy">
          <a class="cta" routerLink="/auth">{{ success ? 'Log in' : 'Back to sign in' }}</a>
          <button
            type="button"
            class="ghost"
            *ngIf="!success && email"
            [disabled]="resending"
            (click)="resend()"
          >
            {{ resending ? 'Sending…' : 'Resend confirmation email' }}
          </button>
        </div>

        <p class="hint" *ngIf="resendMsg">{{ resendMsg }}</p>
      </div>
    </div>
  `,
  styles: [
    `
      :host {
        display: block;
        min-height: 100vh;
      }
      .wrap {
        min-height: 100vh;
        display: grid;
        place-items: center;
        padding: 24px 16px;
        background: radial-gradient(900px 500px at 50% 0%, rgba(15, 118, 110, 0.12), transparent 55%),
          #f6f4ef;
        color: #1c1917;
      }
      .card {
        width: min(440px, 100%);
        background: #fff;
        border: 1px solid #e7e5e4;
        border-radius: 20px;
        padding: 32px 28px;
        box-shadow: 0 20px 50px rgba(28, 25, 23, 0.08);
        text-align: center;
      }
      .brand {
        font-size: 1.35rem;
        font-weight: 700;
        letter-spacing: -0.02em;
        margin-bottom: 12px;
      }
      h1 {
        margin: 0 0 10px;
        font-size: 1.35rem;
        font-weight: 700;
      }
      .sub {
        margin: 0 0 20px;
        color: #57534e;
        font-size: 0.95rem;
        line-height: 1.5;
      }
      .spinner {
        color: #0f766e;
        font-weight: 600;
        margin: 16px 0;
      }
      .actions {
        display: flex;
        flex-direction: column;
        gap: 10px;
        margin-top: 8px;
      }
      .cta {
        display: block;
        text-decoration: none;
        background: #0f766e;
        color: #fff;
        font-weight: 700;
        padding: 12px 16px;
        border-radius: 12px;
      }
      .ghost {
        border: 1px solid #e7e5e4;
        background: #fafaf9;
        color: #44403c;
        font-weight: 600;
        padding: 11px 14px;
        border-radius: 12px;
        cursor: pointer;
      }
      .ghost:disabled {
        opacity: 0.6;
        cursor: not-allowed;
      }
      .hint {
        margin-top: 14px;
        font-size: 0.85rem;
        color: #78716c;
      }
    `,
  ],
})
export class ConfirmEmailPageComponent implements OnInit {
  busy = true;
  success = false;
  title = 'Confirm your email';
  message = '';
  email = '';
  resending = false;
  resendMsg = '';

  private apiBase = (environment as any).apiBaseUrl || 'https://api.matterya.com';

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private cdr: ChangeDetectorRef
  ) {}

  async ngOnInit(): Promise<void> {
    const qp = this.route.snapshot.queryParamMap;
    const preOk = qp.get('ok') === '1';
    const preError = qp.get('error');
    const preEmail = qp.get('email') || '';
    const token = (qp.get('token') || '').trim();

    if (preOk) {
      this.busy = false;
      this.success = true;
      this.email = preEmail;
      this.title = 'Email confirmed';
      this.message = preEmail
        ? `${preEmail} is verified. You can log in to Matterya.`
        : 'Your email is verified. You can log in to Matterya.';
      this.cdr.detectChanges();
      return;
    }

    if (preError && !token) {
      this.busy = false;
      this.success = false;
      this.title = 'Confirmation failed';
      this.message = preError;
      this.cdr.detectChanges();
      return;
    }

    if (!token) {
      this.busy = false;
      this.success = false;
      this.title = 'Missing confirmation link';
      this.message =
        'Open the link from your Matterya confirmation email, or request a new one from Sign Up.';
      this.cdr.detectChanges();
      return;
    }

    try {
      const res = await fetch(`${this.apiBase}/auth/confirm-email`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', accept: 'application/json' },
        body: JSON.stringify({ token }),
      });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(json?.message || json?.error || 'Confirmation failed.');
      }
      this.success = true;
      this.email = json?.email || '';
      this.title = json?.alreadyConfirmed ? 'Already confirmed' : 'Email confirmed';
      this.message = this.email
        ? `${this.email} is verified. You can log in to Matterya.`
        : 'Your email is verified. You can log in to Matterya.';
      // Clean token out of the URL bar
      void this.router.navigate([], {
        relativeTo: this.route,
        queryParams: { ok: '1', email: this.email || null },
        replaceUrl: true,
      });
    } catch (e: any) {
      this.success = false;
      this.title = 'Confirmation failed';
      this.message = e?.message ?? 'This link is invalid or expired.';
    } finally {
      this.busy = false;
      this.cdr.detectChanges();
    }
  }

  async resend(): Promise<void> {
    if (!this.email) return;
    this.resending = true;
    this.resendMsg = '';
    try {
      const res = await fetch(`${this.apiBase}/auth/resend-confirmation`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ email: this.email }),
      });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(json?.message || 'Could not resend.');
      this.resendMsg = json?.message || 'Check your inbox for a new Matterya email.';
    } catch (e: any) {
      this.resendMsg = e?.message ?? 'Could not resend.';
    } finally {
      this.resending = false;
      this.cdr.detectChanges();
    }
  }
}
