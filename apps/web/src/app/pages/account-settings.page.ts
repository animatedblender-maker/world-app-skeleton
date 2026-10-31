import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { AuthService } from '../core/services/auth.service';
import { ProfileService, type Profile } from '../core/services/profile.service';

/** Pixel port of iOS SettingsView — Matterya paper rows + ink toggles (not stock form chrome). */
@Component({
  selector: 'app-account-settings-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="shell">
      <header class="nav">
        <button type="button" class="nav-btn" (click)="goBack()" aria-label="Back">←</button>
        <div class="nav-title">Settings</div>
        <span class="nav-spacer"></span>
      </header>

      <main class="body">
        <section class="section" *ngIf="profile">
          <div class="section-title">Account</div>
          <div class="info-row">
            <span>Name</span>
            <span>{{ profile.display_name || profile.username || 'Member' }}</span>
          </div>
          <div class="info-row" *ngIf="profile.username">
            <span>Username</span>
            <span>@{{ profile.username }}</span>
          </div>
          <div class="info-row" *ngIf="profile.country_name && profile.country_name !== 'Unknown'">
            <span>Home country</span>
            <span>{{ profile.country_name }}</span>
          </div>
          <button type="button" class="action-row" (click)="openEdit()">
            <span>Edit profile</span>
            <span class="chev">›</span>
          </button>
          <button type="button" class="action-row destructive" (click)="logout()">
            <span>Log out</span>
          </button>
        </section>

        <section class="section">
          <div class="section-title">Account control</div>
          <button type="button" class="action-row multi" [disabled]="busy" (click)="openDeactivate()">
            <span class="multi-copy">
              <span class="multi-title">Deactivate account</span>
              <span class="multi-sub"
                >Hide your profile and pause activity. You can sign in again anytime to reactivate.</span
              >
            </span>
            <span class="chev">›</span>
          </button>
          <button type="button" class="action-row multi destructive" [disabled]="busy" (click)="openDelete()">
            <span class="multi-copy">
              <span class="multi-title">Delete account</span>
              <span class="multi-sub"
                >Permanently delete your account, profile, and posts. This cannot be undone.</span
              >
            </span>
            <span class="chev">›</span>
          </button>
          <p class="footer">
            Deactivate is temporary. Delete removes your Matterya identity and content for good.
          </p>
          <p class="error" *ngIf="error">{{ error }}</p>
          <p class="ok" *ngIf="message">{{ message }}</p>
        </section>

        <section class="section">
          <div class="section-title">Notifications</div>
          <div class="card-row">
            <span>Notifications</span>
            <button
              type="button"
              class="m-switch"
              [class.on]="pushEnabled"
              [attr.aria-pressed]="pushEnabled"
              (click)="togglePush()"
            >
              <span class="knob"></span>
            </button>
          </div>
          <p class="footer">
            Used for messages, calls, and activity. Browser permission controls delivery.
          </p>
          <p class="hint" *ngIf="notificationsHint">{{ notificationsHint }}</p>
        </section>

        <section class="section">
          <div class="section-title">Privacy</div>
          <button type="button" class="action-row" (click)="openPrivacy()">
            <span>Data &amp; privacy</span>
            <span class="chev">›</span>
          </button>
        </section>

        <section class="section">
          <div class="section-title">Support</div>
          <div class="info-row"><span>App</span><span>Matterya</span></div>
          <div class="info-row"><span>Version</span><span>{{ appVersion }}</span></div>
          <a class="action-row" href="https://matterya.com" target="_blank" rel="noopener">
            <span>Help center</span>
            <span class="chev">›</span>
          </a>
        </section>
      </main>

      <div class="modal" *ngIf="confirmDeactivate" (click)="confirmDeactivate = false">
        <div class="dialog" (click)="$event.stopPropagation()">
          <h3>Deactivate your account?</h3>
          <p>Your profile will be hidden and you will be signed out. Sign in again anytime to reactivate.</p>
          <div class="dialog-actions">
            <button type="button" class="ghost" (click)="confirmDeactivate = false" [disabled]="busy">Cancel</button>
            <button type="button" class="danger" (click)="deactivate()" [disabled]="busy">
              {{ busy ? 'Working…' : 'Deactivate' }}
            </button>
          </div>
        </div>
      </div>

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
            <button type="button" class="ghost" (click)="confirmDelete = false" [disabled]="busy">Cancel</button>
            <button
              type="button"
              class="danger"
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
        min-height: 100%;
        background: var(--m-paper, #f8f6f2);
        color: var(--m-ink, #2c2825);
      }
      .shell {
        min-height: 100vh;
        max-width: 680px;
        margin: 0 auto;
        padding-bottom: 48px;
      }
      .nav {
        display: grid;
        grid-template-columns: 44px 1fr 44px;
        align-items: center;
        height: calc(44px + env(safe-area-inset-top));
        padding: env(safe-area-inset-top) 8px 0;
        background: var(--m-canvas, #f8f6f2);
        border-bottom: 0.5px solid var(--m-divider, #e2ded8);
        position: sticky;
        top: 0;
        z-index: 10;
      }
      .nav-title {
        text-align: center;
        font-size: 16px;
        font-weight: 650;
      }
      .nav-btn {
        border: 0;
        background: transparent;
        width: 44px;
        height: 44px;
        font-size: 18px;
        color: var(--m-ink, #2c2825);
        cursor: pointer;
      }
      .body {
        padding: 18px var(--m-page-padding, 16px);
        display: flex;
        flex-direction: column;
        gap: 22px;
      }
      .section {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }
      .section-title {
        font-size: 12px;
        font-weight: 650;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--m-ink-muted, #948b82);
        padding: 0 4px;
      }
      .info-row,
      .action-row,
      .card-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        padding: 14px 16px;
        background: var(--m-surface, #fefdfb);
        border: 0.5px solid color-mix(in srgb, var(--m-border, #ddd8d1) 85%, transparent);
        border-radius: 14px;
        font-size: 15px;
        font-weight: 500;
        color: var(--m-ink, #2c2825);
        text-decoration: none;
      }
      .info-row span:last-child {
        color: var(--m-ink-muted, #948b82);
        font-weight: 400;
        text-align: right;
      }
      .action-row {
        width: 100%;
        box-sizing: border-box;
        cursor: pointer;
        text-align: left;
        font: inherit;
      }
      .action-row:disabled {
        opacity: 0.55;
        cursor: not-allowed;
      }
      .action-row.destructive,
      .action-row.destructive .multi-title {
        color: var(--m-danger, #ea000b);
      }
      .action-row.multi {
        align-items: flex-start;
      }
      .multi-copy {
        display: flex;
        flex-direction: column;
        gap: 4px;
        min-width: 0;
      }
      .multi-title {
        font-weight: 500;
      }
      .multi-sub {
        font-size: 12px;
        font-weight: 400;
        color: var(--m-ink-muted, #948b82);
        line-height: 1.4;
      }
      .chev {
        color: var(--m-ink-muted, #948b82);
        font-size: 18px;
        line-height: 1;
      }
      .footer,
      .hint {
        margin: 0;
        padding: 0 4px;
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        line-height: 1.4;
      }
      .error {
        margin: 0;
        padding: 0 4px;
        color: var(--m-danger, #ea000b);
        font-size: 13px;
      }
      .ok {
        margin: 0;
        padding: 0 4px;
        color: var(--m-success, #00b050);
        font-size: 13px;
      }
      .m-switch {
        position: relative;
        width: 48px;
        height: 28px;
        border-radius: 999px;
        border: 0.5px solid var(--m-border, #ddd8d1);
        background: var(--m-matte-deep, #f0ede8);
        padding: 0;
        cursor: pointer;
        flex-shrink: 0;
      }
      .m-switch.on {
        background: var(--m-ink, #2c2825);
        border-color: transparent;
      }
      .m-switch .knob {
        position: absolute;
        top: 3px;
        left: 3px;
        width: 22px;
        height: 22px;
        border-radius: 50%;
        background: var(--m-paper, #f8f6f2);
        box-shadow: 0 1px 2px color-mix(in srgb, var(--m-ink, #2c2825) 12%, transparent);
        transition: transform 0.15s ease;
      }
      .m-switch.on .knob {
        transform: translateX(20px);
      }
      .modal {
        position: fixed;
        inset: 0;
        background: rgba(0, 0, 0, 0.35);
        display: grid;
        place-items: center;
        padding: 16px;
        z-index: 1000;
      }
      .dialog {
        width: min(420px, 100%);
        background: var(--m-surface, #fefdfb);
        border-radius: 16px;
        padding: 20px;
        box-shadow: 0 20px 50px rgba(0, 0, 0, 0.2);
      }
      .dialog h3 {
        margin: 0 0 10px;
        font-size: 18px;
      }
      .dialog p {
        margin: 0 0 14px;
        color: var(--m-ink-secondary, #6b645d);
        font-size: 14px;
        line-height: 1.45;
      }
      .dialog input {
        width: 100%;
        box-sizing: border-box;
        border: 0.5px solid var(--m-border, #ddd8d1);
        border-radius: 10px;
        padding: 10px 12px;
        margin-bottom: 14px;
        background: var(--m-matte-deep, #f0ede8);
        color: var(--m-ink, #2c2825);
        font-size: 15px;
      }
      .dialog-actions {
        display: flex;
        gap: 10px;
      }
      .dialog-actions button {
        flex: 1;
        border-radius: var(--m-control-radius, 8px);
        padding: 12px 14px;
        font-weight: 650;
        font-size: 14px;
        cursor: pointer;
      }
      .ghost {
        border: 0.5px solid var(--m-border, #ddd8d1);
        background: var(--m-matte, #f6f3ef);
        color: var(--m-ink, #2c2825);
      }
      .danger {
        border: 0;
        background: var(--m-danger, #ea000b);
        color: var(--m-paper, #f8f6f2);
      }
      .danger:disabled,
      .ghost:disabled {
        opacity: 0.55;
        cursor: not-allowed;
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
  pushEnabled = false;
  notificationsHint = '';
  appVersion = '1.0';

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
        try {
          await this.profiles.reactivateAccount();
          const refreshed = await this.profiles.meProfile();
          this.profile = refreshed.meProfile;
          this.message = 'Your account was reactivated.';
        } catch {
          // ignore
        }
      }
      this.pushEnabled =
        typeof Notification !== 'undefined' && Notification.permission === 'granted';
    } catch {
      this.error = 'Could not load account.';
    }
    this.cdr.detectChanges();
  }

  goBack(): void {
    void this.router.navigate(['/profile']);
  }

  openEdit(): void {
    void this.router.navigate(['/edit-profile']);
  }

  openPrivacy(): void {
    void this.router.navigate(['/privacy']);
  }

  async logout(): Promise<void> {
    try {
      await this.auth.logout();
    } catch {
      // ignore
    }
    void this.router.navigate(['/auth']);
  }

  openDeactivate(): void {
    this.error = '';
    this.confirmDeactivate = true;
  }

  openDelete(): void {
    this.deleteConfirmation = '';
    this.error = '';
    this.confirmDelete = true;
  }

  async togglePush(): Promise<void> {
    if (typeof Notification === 'undefined') {
      this.notificationsHint = 'Notifications aren’t available in this browser.';
      this.paint();
      return;
    }
    if (this.pushEnabled) {
      this.pushEnabled = false;
      this.notificationsHint = 'Turn delivery back on in your browser site settings if you change your mind.';
      this.paint();
      return;
    }
    try {
      const permission = await Notification.requestPermission();
      this.pushEnabled = permission === 'granted';
      this.notificationsHint = this.pushEnabled
        ? 'Notifications are on for messages, calls, and activity.'
        : 'Permission was not granted.';
    } catch {
      this.notificationsHint = 'Could not request notification permission.';
    }
    this.paint();
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
      this.paint();
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
        // session may already be invalid
      }
      void this.router.navigate(['/auth']);
    } catch (e: any) {
      this.error = e?.message ?? 'Could not delete account.';
    } finally {
      this.busy = false;
      this.paint();
    }
  }

  private paint(): void {
    try {
      this.cdr.detectChanges();
    } catch {
      // destroyed
    }
  }
}
