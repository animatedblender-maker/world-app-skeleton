import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { AuthService } from '../core/services/auth.service';
import { LocationService } from '../core/services/location.service';
import { MediaService } from '../core/services/media.service';
import { ProfileService, type Profile } from '../core/services/profile.service';
import { resolveAvatarUrl } from '../core/utils/media-url.util';

/** Pixel port of iOS EditProfileView — paper cards, ink primary CTA. */
@Component({
  selector: 'app-edit-profile-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="shell">
      <header class="nav">
        <button type="button" class="nav-btn" (click)="cancel()" aria-label="Back">←</button>
        <div class="nav-title">Edit Profile</div>
        <span class="nav-spacer"></span>
      </header>

      <main class="body" *ngIf="ready; else loadingTpl">
        <section class="block">
          <div class="block-label">Avatar</div>
          <div class="avatar-row">
            <div class="avatar">
              <img *ngIf="avatarPreview" [src]="avatarPreview" alt="" />
              <span *ngIf="!avatarPreview">{{ initials }}</span>
            </div>
            <div class="avatar-actions">
              <label class="secondary-fill" [class.disabled]="busy || uploadingAvatar">
                {{ uploadingAvatar ? 'Uploading…' : 'Change avatar' }}
                <input
                  type="file"
                  accept="image/*"
                  (change)="onAvatar($event)"
                  [disabled]="busy || uploadingAvatar"
                  hidden
                />
              </label>
              <p class="hint">
                {{ uploadingAvatar ? 'Please wait — photo is uploading…' : 'Pick a photo from your library.' }}
              </p>
            </div>
          </div>
        </section>

        <section class="block">
          <div class="block-label">Identity</div>
          <label class="field">
            <span>Display name</span>
            <input [(ngModel)]="displayName" name="displayName" autocomplete="nickname" />
          </label>
          <label class="field">
            <span>Username</span>
            <input
              [(ngModel)]="username"
              name="username"
              autocomplete="username"
              autocapitalize="off"
              autocorrect="off"
            />
          </label>
          <label class="field">
            <span>Date of birth</span>
            <input type="date" [(ngModel)]="birthdate" name="birthdate" [attr.max]="todayISO" />
            <small>Private — only you can see this.</small>
          </label>
        </section>

        <section class="block">
          <div class="block-label">Location</div>
          <div class="loc" *ngIf="detecting">Detecting your location…</div>
          <ng-container *ngIf="!detecting && hasDetectedLocation">
            <div class="info-row"><span>Country</span><span>{{ countryName }}</span></div>
            <div class="info-row" *ngIf="cityName"><span>City</span><span>{{ cityName }}</span></div>
            <p class="hint">Location is detected automatically and can’t be edited.</p>
          </ng-container>
          <p class="hint" *ngIf="!detecting && !hasDetectedLocation">
            {{ locationStatus || 'Tap below to detect your location from this device.' }}
          </p>
          <button
            type="button"
            class="secondary-fill full"
            (click)="detectLocation()"
            [disabled]="detecting || busy || uploadingAvatar"
          >
            {{ detecting ? 'Detecting…' : 'Detect location again' }}
          </button>
        </section>

        <section class="block">
          <div class="block-label">Bio</div>
          <label class="field">
            <span>Bio</span>
            <textarea [(ngModel)]="bio" name="bio" rows="4" maxlength="280"></textarea>
          </label>
        </section>

        <p class="error" *ngIf="error">{{ error }}</p>
        <p class="ok" *ngIf="success">{{ success }}</p>

        <button
          type="button"
          class="primary-fill"
          (click)="save()"
          [disabled]="busy || uploadingAvatar || !canSave"
        >
          {{ busy ? 'Saving…' : 'Save profile' }}
        </button>
        <button type="button" class="secondary-fill full" (click)="cancel()" [disabled]="busy || uploadingAvatar">
          Cancel
        </button>
      </main>

      <ng-template #loadingTpl>
        <div class="state">Loading…</div>
      </ng-template>
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
        padding-bottom: 40px;
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
      .block {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .block-label {
        font-size: 12px;
        font-weight: 650;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        color: var(--m-ink-muted, #948b82);
        padding: 0 4px;
      }
      .avatar-row {
        display: flex;
        gap: 16px;
        align-items: center;
      }
      .avatar {
        width: 72px;
        height: 72px;
        border-radius: 999px;
        overflow: hidden;
        background: var(--m-canvas-deep, #edeae5);
        border: 0.5px solid var(--m-border, #ddd8d1);
        display: grid;
        place-items: center;
        font-weight: 700;
        flex-shrink: 0;
      }
      .avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .avatar-actions {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 8px;
      }
      .field {
        display: grid;
        gap: 6px;
      }
      .field span {
        font-size: 12px;
        font-weight: 650;
        color: var(--m-ink-muted, #948b82);
      }
      .field input,
      .field textarea {
        border: 0.5px solid var(--m-border, #ddd8d1);
        border-radius: var(--m-control-radius, 8px);
        padding: 12px;
        background: var(--m-matte-deep, #f0ede8);
        color: var(--m-ink, #2c2825);
        font: inherit;
        font-size: 15px;
        outline: none;
        resize: vertical;
      }
      .field input:focus,
      .field textarea:focus {
        border-color: var(--m-ink, #2c2825);
        box-shadow: 0 0 0 3px color-mix(in srgb, var(--m-ink, #2c2825) 12%, transparent);
      }
      .field small {
        font-size: 11px;
        color: var(--m-ink-muted, #948b82);
      }
      .info-row {
        display: flex;
        justify-content: space-between;
        gap: 12px;
        padding: 14px 16px;
        background: var(--m-surface, #fefdfb);
        border: 0.5px solid color-mix(in srgb, var(--m-border, #ddd8d1) 85%, transparent);
        border-radius: 14px;
        font-size: 15px;
      }
      .info-row span:last-child {
        color: var(--m-ink-muted, #948b82);
        text-align: right;
      }
      .hint {
        margin: 0;
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        line-height: 1.4;
      }
      .loc {
        font-size: 14px;
        color: var(--m-ink-muted, #948b82);
      }
      .primary-fill,
      .secondary-fill {
        display: block;
        width: 100%;
        box-sizing: border-box;
        text-align: center;
        border-radius: var(--m-control-radius, 8px);
        font-size: 15px;
        font-weight: 650;
        cursor: pointer;
      }
      .primary-fill {
        border: 0;
        padding: 14px 16px;
        background: var(--m-ink, #2c2825);
        color: var(--m-paper, #f8f6f2);
      }
      .primary-fill:disabled {
        opacity: 0.55;
        cursor: not-allowed;
      }
      .secondary-fill {
        border: 0.5px solid var(--m-border, #ddd8d1);
        padding: 12px 14px;
        background: var(--m-matte, #f6f3ef);
        color: var(--m-ink, #2c2825);
      }
      .secondary-fill.full {
        width: 100%;
      }
      .secondary-fill.disabled,
      .secondary-fill:disabled {
        opacity: 0.55;
        cursor: not-allowed;
      }
      .error {
        margin: 0;
        color: var(--m-danger, #ea000b);
        font-size: 13px;
      }
      .ok {
        margin: 0;
        color: var(--m-success, #00b050);
        font-size: 13px;
      }
      .state {
        padding: 48px 16px;
        text-align: center;
        color: var(--m-ink-muted, #948b82);
      }
    `,
  ],
})
export class EditProfilePageComponent implements OnInit {
  ready = false;
  busy = false;
  uploadingAvatar = false;
  detecting = false;
  error = '';
  success = '';
  locationStatus = '';

  displayName = '';
  username = '';
  bio = '';
  birthdate = EditProfilePageComponent.defaultBirthdateISO();
  readonly todayISO = new Date().toISOString().slice(0, 10);
  countryName = '';
  countryCode = '';
  cityName = '';
  avatarUrl: string | null = null;
  avatarPreviewUrl: string | null = null;
  private profile: Profile | null = null;

  constructor(
    private auth: AuthService,
    private profiles: ProfileService,
    private media: MediaService,
    private location: LocationService,
    private router: Router,
    private cdr: ChangeDetectorRef
  ) {}

  get avatarPreview(): string | null {
    if (this.avatarPreviewUrl) return this.avatarPreviewUrl;
    if (!this.avatarUrl) return null;
    return resolveAvatarUrl(this.avatarUrl, this.username || this.profile?.user_id) || this.avatarUrl;
  }

  get initials(): string {
    const n = this.displayName || this.username || 'ME';
    return n.slice(0, 2).toUpperCase();
  }

  get hasDetectedLocation(): boolean {
    const country = this.countryName.trim();
    return !!country && country !== 'Unknown';
  }

  get canSave(): boolean {
    return !!this.displayName.trim();
  }

  private static defaultBirthdateISO(): string {
    const d = new Date();
    d.setUTCFullYear(d.getUTCFullYear() - 18);
    return d.toISOString().slice(0, 10);
  }

  async ngOnInit(): Promise<void> {
    try {
      const user = await this.auth.getUser();
      if (!user?.id) {
        void this.router.navigate(['/auth']);
        return;
      }
      const { meProfile } = await this.profiles.meProfile();
      this.profile = meProfile;
      if (!meProfile) {
        void this.router.navigate(['/profile-setup']);
        return;
      }
      this.displayName = meProfile.display_name || '';
      this.username = meProfile.username || '';
      this.bio = String(meProfile.bio || '')
        .replace(/__living_channel__\|[^\n]*/g, '')
        .trim();
      this.countryName = meProfile.country_name || '';
      this.countryCode = meProfile.country_code || '';
      this.cityName = meProfile.city_name || '';
      this.avatarUrl = meProfile.avatar_url || null;
      if (meProfile.birthdate && String(meProfile.birthdate).trim().length >= 10) {
        this.birthdate = String(meProfile.birthdate).trim().slice(0, 10);
      }
      this.ready = true;
    } catch (e: any) {
      this.error = e?.message || 'Could not load profile.';
      this.ready = true;
    }
    this.paint();
  }

  async onAvatar(e: Event): Promise<void> {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    this.error = '';
    this.success = '';
    if (this.avatarPreviewUrl) {
      try {
        URL.revokeObjectURL(this.avatarPreviewUrl);
      } catch {
        // ignore
      }
    }
    this.avatarPreviewUrl = URL.createObjectURL(file);
    this.uploadingAvatar = true;
    this.paint();
    try {
      const res = await this.media.uploadAvatar(file);
      this.avatarUrl = res.path || res.url;
    } catch (err: any) {
      this.error = err?.message || 'Avatar upload failed.';
      this.avatarPreviewUrl = null;
    } finally {
      this.uploadingAvatar = false;
      input.value = '';
      this.paint();
    }
  }

  async detectLocation(): Promise<void> {
    this.detecting = true;
    this.locationStatus = '';
    this.error = '';
    this.paint();
    try {
      const loc = await this.location.detectViaGpsThenServer(9000);
      if (loc?.countryCode && loc.countryName) {
        this.countryCode = loc.countryCode;
        this.countryName = loc.countryName;
        this.cityName = loc.cityName ?? '';
        this.locationStatus = `Detected: ${loc.countryName}`;
      } else {
        this.locationStatus =
          'Location unavailable. Enable Location for Matterya in Settings, then try again.';
      }
    } catch (e: any) {
      this.locationStatus = e?.message || 'Location unavailable.';
    } finally {
      this.detecting = false;
      this.paint();
    }
  }

  async save(): Promise<void> {
    if (!this.canSave || this.busy) return;
    this.busy = true;
    this.error = '';
    this.success = '';
    this.paint();
    try {
      const birth = (this.birthdate || '').trim();
      const input: Record<string, unknown> = {
        display_name: this.displayName.trim(),
        username: this.username.trim() || undefined,
        bio: this.bio.trim() || null,
        avatar_url: this.avatarUrl,
        country_name: this.countryName.trim() || undefined,
        country_code: this.countryCode.trim() || undefined,
        city_name: this.cityName.trim() || null,
      };
      if (/^\d{4}-\d{2}-\d{2}$/.test(birth)) {
        input['birthdate'] = birth;
      }
      await this.profiles.updateProfile(input as any);
      this.success = 'Profile saved.';
      void this.router.navigate(['/profile']);
    } catch (e: any) {
      this.error = e?.message || 'Could not save profile.';
    } finally {
      this.busy = false;
      this.paint();
    }
  }

  cancel(): void {
    void this.router.navigate(['/profile']);
  }

  private paint(): void {
    try {
      this.cdr.detectChanges();
    } catch {
      // destroyed
    }
  }
}
