import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { AuthService } from '../core/services/auth.service';
import { ProfileService, type Profile } from '../core/services/profile.service';

@Component({
  selector: 'app-account-settings-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="wrap">
      <header class="head">
        <button type="button" class="back" (click)="goBack()">← Back</button>
        <h1>Account settings</h1>
      </header>

      <section class="card" *ngIf="profile">
        <div class="row">
          <span class="label">Name</span>
          <span>{{ profile.display_name || profile.username || 'Member' }}</span>
        </div>
        <div class="row" *ngIf="profile.username">
          <span class="label">Username</span>
          <span>@{{ profile.username }}</span>
        </div>
        <div class="row" *ngIf="profile.email">
          <span class="label">Email</span>
          <span>{{ profile.email }}</span>
        </div>
      </section>

      <section class="card danger-zone">
        <h2>Account control</h2>
        <p class="hint">
          Deactivate hides your profile and pauses activity. You can sign in again anytime to
          reactivate. Delete permanently removes your account.
        </p>

        <button
          type="button"
          class="btn secondary"
          [disabled]="busy"
          (click)="confirmDeactivate = true"
        >
          Deactivate account
        </button>

        <button
          type="button"
          class="btn destructive"
          [disabled]="busy"
          (click)="openDelete()"
        >
          Delete account
        </button>

        <p class="error" *ngIf="error">{{ error }}</p>
        <p class="ok" *ngIf="message">{{ message }}</p>
      </section>

      <!-- Deactivate confirm -->
      <div class="modal" *ngIf="confirmDeactivate" (click)="confirmDeactivate = false">
        <div class="dialog" (click)="$event.stopPropagation()">
          <h3>Deactivate your account?</h3>
          <p>Your profile will be hidden and you will be signed out. Sign in again anytime to reactivate.</p>
          <div class="dialog-actions">
            <button type="button" class="btn ghost" (click)="confirmDeactivate = false" [disabled]="busy">
              Cancel
            </button>
            <button type="button" class="btn destructive" (click)="deactivate()" [disabled]="busy">
              {{ busy ? 'Working…' : 'Deactivate' }}
            </button>
          </div>
        </div>
      </div>

      <!-- Delete confirm -->
      <div class="modal" *ngIf="confirmDelete" (click)="confirmDelete = false">
        <div class="dialog" (click)="$event.stopPropagation()">
          <h3>Delete your account permanently?</h3>
          <p>
            This cannot be undone. Type <strong>DELETE</strong>
            <span *ngIf="profile?.username"> or <strong>{{ profile?.username }}</strong></span>
            to confirm.
          </p>
          <input
            type="text"
            [(ngModel)]="deleteConfirmation"
            placeholder="DELETE or username"
            autocomplete="off"
            autocapitalize="off"
          />
          <div class="dialog-actions">
            <button type="button" class="btn ghost" (click)="confirmDelete = false" [disabled]="busy">
              Cancel
            </button>
            <button
              type="button"
              class="btn destructive"
              (click)="deleteAccount()"
              [disabled]="busy || !deleteConfirmation.trim()"
            >
              {{ busy ? 'Deleting…' : 'Delete forever' }}
            </button>
          </div>
        </div>
      </div>
    </div>
  `,
  styles: [
    `
      :host {
        display: block;
        min-height: 100vh;
        background: #f6f4ef;
        color: #1c1917;
      }
      .wrap {
        max-width: 560px;
        margin: 0 auto;
        padding: 24px 16px 80px;
      }
      .head {
        display: flex;
        flex-direction: column;
        gap: 8px;
        margin-bottom: 20px;
      }
      .head h1 {
        margin: 0;
        font-size: 1.5rem;
        font-weight: 700;
      }
      .back {
        border: 0;
        background: transparent;
        color: #57534e;
        font-size: 0.95rem;
        cursor: pointer;
        align-self: flex-start;
        padding: 0;
      }
      .card {
        background: #fff;
        border: 1px solid #e7e5e4;
        border-radius: 16px;
        padding: 18px;
        margin-bottom: 16px;
      }
      .row {
        display: flex;
        justify-content: space-between;
        gap: 12px;
        padding: 8px 0;
        border-bottom: 1px solid #f5f5f4;
        font-size: 0.95rem;
      }
      .row:last-child {
        border-bottom: 0;
      }
      .label {
        color: #78716c;
      }
      .danger-zone h2 {
        margin: 0 0 8px;
        font-size: 1.05rem;
      }
      .hint {
        margin: 0 0 16px;
        color: #78716c;
        font-size: 0.9rem;
        line-height: 1.45;
      }
      .btn {
        display: block;
        width: 100%;
        border-radius: 12px;
        border: 1px solid transparent;
        padding: 12px 14px;
        font-weight: 600;
        font-size: 0.95rem;
        cursor: pointer;
        margin-bottom: 10px;
      }
      .btn:disabled {
        opacity: 0.55;
        cursor: not-allowed;
      }
      .btn.secondary {
        background: #f5f5f4;
        border-color: #e7e5e4;
        color: #1c1917;
      }
      .btn.destructive {
        background: #dc2626;
        color: #fff;
      }
      .btn.ghost {
        background: transparent;
        border-color: #e7e5e4;
        color: #44403c;
      }
      .error {
        color: #b91c1c;
        font-size: 0.88rem;
        margin: 8px 0 0;
      }
      .ok {
        color: #15803d;
        font-size: 0.88rem;
        margin: 8px 0 0;
      }
      .modal {
        position: fixed;
        inset: 0;
        background: rgba(0, 0, 0, 0.45);
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 16px;
        z-index: 1000;
      }
      .dialog {
        background: #fff;
        border-radius: 16px;
        padding: 20px;
        width: min(420px, 100%);
        box-shadow: 0 20px 50px rgba(0, 0, 0, 0.2);
      }
      .dialog h3 {
        margin: 0 0 10px;
        font-size: 1.1rem;
      }
      .dialog p {
        margin: 0 0 14px;
        color: #57534e;
        font-size: 0.92rem;
        line-height: 1.45;
      }
      .dialog input {
        width: 100%;
        box-sizing: border-box;
        border: 1px solid #d6d3d1;
        border-radius: 10px;
        padding: 10px 12px;
        margin-bottom: 14px;
        font-size: 0.95rem;
      }
      .dialog-actions {
        display: flex;
        gap: 10px;
      }
      .dialog-actions .btn {
        margin: 0;
        flex: 1;
      }
    `,
  ],
})
export class AccountSettingsPageComponent implements OnInit {
  profile: Profile | null = null;
  busy = false;
  error = '';
  message = '';
  confirmDeactivate = false;
  confirmDelete = false;
  deleteConfirmation = '';

  constructor(
    private profiles: ProfileService,
    private auth: AuthService,
    private router: Router,
    private cdr: ChangeDetectorRef
  ) {}

  async ngOnInit(): Promise<void> {
    try {
      const user = await this.auth.getUser();
      if (!user?.id) {
        void this.router.navigate(['/auth']);
        return;
      }
      const { meProfile } = await this.profiles.meProfile();
      this.profile = meProfile;
      if (meProfile?.account_status === 'deactivated') {
        // Signing in again should reactivate; do it proactively here if they land on settings.
        try {
          await this.profiles.reactivateAccount();
          const refreshed = await this.profiles.meProfile();
          this.profile = refreshed.meProfile;
          this.message = 'Your account was reactivated.';
        } catch {
          // ignore
        }
      }
    } catch {
      this.error = 'Could not load account.';
    }
    this.cdr.detectChanges();
  }

  goBack(): void {
    void this.router.navigate(['/profile']);
  }

  openDelete(): void {
    this.deleteConfirmation = '';
    this.error = '';
    this.confirmDelete = true;
  }

  async deactivate(): Promise<void> {
    this.busy = true;
    this.error = '';
    this.message = '';
    try {
      const res = await this.profiles.deactivateAccount();
      this.message = res.deactivateAccount.message || 'Account deactivated.';
      this.confirmDeactivate = false;
      await this.auth.logout();
      void this.router.navigate(['/auth']);
    } catch (e: any) {
      this.error = e?.message ?? 'Could not deactivate account.';
    } finally {
      this.busy = false;
      this.cdr.detectChanges();
    }
  }

  async deleteAccount(): Promise<void> {
    const confirmation = this.deleteConfirmation.trim();
    if (!confirmation) {
      this.error = 'Type DELETE or your username to confirm.';
      return;
    }
    this.busy = true;
    this.error = '';
    this.message = '';
    try {
      const res = await this.profiles.deleteAccount(confirmation);
      this.message = res.deleteAccount.message || 'Account deleted.';
      this.confirmDelete = false;
      try {
        await this.auth.logout();
      } catch {
        // session may already be invalid after auth user delete
      }
      void this.router.navigate(['/auth']);
    } catch (e: any) {
      this.error = e?.message ?? 'Could not delete account.';
    } finally {
      this.busy = false;
      this.cdr.detectChanges();
    }
  }
}
