import { Component, OnInit, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { AuthService } from '../core/services/auth.service';
import { GraphqlService } from '../core/services/graphql.service';
import { MediaService } from '../core/services/media.service';
import { LocationService } from '../core/services/location.service';

@Component({
  selector: 'app-profile-setup-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
  <div class="wrap">
    <div class="card">
      <div class="topbar">
        <button class="back" type="button" (click)="goBack()">Back</button>
      </div>
      <div class="title">Create your profile</div>
      <div class="sub">Your country is detected automatically. Just add who you are.</div>

      <div class="field">
        <label>Screen name</label>
        <input [(ngModel)]="displayName" placeholder="e.g. Amr" autocomplete="nickname" />
      </div>

      <div class="field">
        <label>Avatar (optional)</label>
        <div class="row">
          <label class="btn2" style="cursor:pointer;">
            Choose image
            <input type="file" accept="image/*" (change)="onAvatar($event)" style="display:none;" />
          </label>
          <div class="avatar-preview" *ngIf="avatarPreviewUrl || avatarUrl">
            <img [src]="avatarPreviewUrl || avatarUrl" alt="" />
          </div>
          <small class="muted" *ngIf="avatarUrl && !avatarPreviewUrl">Selected ✅</small>
        </div>
      </div>

      <div class="field">
        <label>Bio (optional)</label>
        <textarea
          [(ngModel)]="bio"
          rows="3"
          placeholder="Tell the world a little about you…"
          maxlength="280"
        ></textarea>
      </div>

      <div class="loc-status" *ngIf="detecting || countryName">
        <span class="dot" [class.ok]="!!countryCode && !detecting" [class.busy]="detecting"></span>
        <span *ngIf="detecting">Detecting your location…</span>
        <span *ngIf="!detecting && countryName">
          Home country: <b>{{ countryName }}</b><span *ngIf="cityName"> · {{ cityName }}</span>
        </span>
      </div>

      <div class="row" style="margin-top:16px;">
        <button class="btn" (click)="save()" [disabled]="busy || detecting || !canSave">
          {{ busy ? 'Saving…' : detecting ? 'Detecting location…' : 'Save & Continue' }}
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
      width:min(720px,92vw);
      border-radius:24px;
      padding:18px;
      background: rgba(10,12,20,0.60);
      border: 1px solid rgba(0,255,209,0.20);
      box-shadow: 0 30px 90px rgba(0,0,0,0.45);
      backdrop-filter: blur(12px);
    }
    .title{ font-weight:900; letter-spacing:0.08em; font-size:18px; }
    .sub{ margin-top:6px; opacity:.7; font-size:13px; }
    .topbar{
      display:flex;
      justify-content:flex-end;
      margin-bottom:8px;
    }
    .back{
      border:1px solid rgba(255,255,255,0.12);
      background: rgba(8,10,18,0.75);
      color: rgba(255,255,255,0.85);
      padding:8px 12px;
      border-radius:12px;
      cursor:pointer;
      font-weight:800;
      letter-spacing:0.08em;
      font-size:11px;
    }
    .field{ margin-top:14px; display:grid; gap:8px; }
    label{ font-size:12px; opacity:.75; letter-spacing:0.12em; }
    input,textarea{
      padding:12px; border-radius:16px;
      border:1px solid rgba(255,255,255,0.12);
      background: rgba(0,0,0,0.28);
      color: rgba(255,255,255,0.92);
      outline:none;
      font: inherit;
      resize: vertical;
    }
    .loc-status{
      margin-top:14px;
      display:flex;
      align-items:center;
      gap:8px;
      font-size:13px;
      opacity:.85;
    }
    .loc-status .dot{
      width:8px; height:8px; border-radius:999px;
      background: rgba(255,255,255,0.35);
      flex-shrink:0;
    }
    .loc-status .dot.ok{ background: #22c55e; box-shadow: 0 0 0 3px rgba(34,197,94,0.2); }
    .loc-status .dot.busy{
      background: #00ffd1;
      animation: pulse 1s ease infinite;
    }
    @keyframes pulse {
      0%,100% { opacity: 1; }
      50% { opacity: 0.35; }
    }
    .row{ display:flex; gap:12px; align-items:center; flex-wrap:wrap; }
    .avatar-preview{
      width:44px; height:44px; border-radius:999px; overflow:hidden;
      border:1px solid rgba(255,255,255,0.15);
    }
    .avatar-preview img{ width:100%; height:100%; object-fit:cover; display:block; }
    .muted{ opacity:.65; font-weight:600; font-size:12px; }
    .btn{
      border:0; border-radius:16px; padding:12px 14px; cursor:pointer;
      background: linear-gradient(90deg, rgba(0,255,209,0.85), rgba(140,0,255,0.75));
      color: rgba(6,8,14,0.96); font-weight:900; letter-spacing:0.12em;
    }
    .btn:disabled{ opacity:.6; cursor:not-allowed; }
    .btn2{
      border:1px solid rgba(255,255,255,0.14);
      background: rgba(255,255,255,0.06);
      color: rgba(255,255,255,0.90);
      padding:10px 12px;
      border-radius:14px;
      cursor:pointer;
      font-weight:900;
      letter-spacing:0.08em;
      font-size:12px;
    }
    .msg{ font-size:13px; opacity:.95; white-space:pre-wrap; color:#fca5a5; }
  `],
})
export class ProfileSetupPageComponent implements OnInit {
  displayName = '';
  bio = '';
  avatarUrl: string | null = null;
  avatarPreviewUrl: string | null = null;

  detecting = false;
  countryName = '';
  countryCode = '';
  cityName = '';

  busy = false;
  msg = '';

  constructor(
    private auth: AuthService,
    private gql: GraphqlService,
    private media: MediaService,
    private location: LocationService,
    private router: Router,
    private cdr: ChangeDetectorRef
  ) {}

  get canSave(): boolean {
    return !!this.displayName.trim() && !!this.countryCode && !!this.countryName;
  }

  async ngOnInit(): Promise<void> {
    const user = await this.auth.getUser();
    if (!user) {
      await this.router.navigateByUrl('/auth');
      return;
    }

    this.displayName = user.email?.split('@')[0] ?? 'User';
    this.cdr.detectChanges();

    // Location is automatic — no manual country picker on this screen.
    queueMicrotask(() => void this.detectLocation());
  }

  async onAvatar(e: Event): Promise<void> {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;

    this.msg = '';
    if (this.avatarPreviewUrl) {
      try {
        URL.revokeObjectURL(this.avatarPreviewUrl);
      } catch {}
    }
    this.avatarPreviewUrl = URL.createObjectURL(file);

    try {
      const res = await this.media.uploadAvatar(file);
      this.avatarUrl = res.path;
    } catch (err: any) {
      this.msg = `Avatar upload failed: ${err?.message ?? err}`;
      this.avatarPreviewUrl = null;
    } finally {
      input.value = '';
      this.cdr.detectChanges();
    }
  }

  private async detectLocation(): Promise<void> {
    this.detecting = true;
    this.msg = '';
    this.cdr.detectChanges();

    try {
      const loc = await this.location.detectViaGpsThenServer(9000);
      if (loc?.countryCode && loc.countryName) {
        this.countryCode = loc.countryCode;
        this.countryName = loc.countryName;
        this.cityName = loc.cityName ?? '';
      } else {
        this.msg =
          'Could not detect your location automatically. Check network permission and try again, or refresh the page.';
      }
    } catch (e: any) {
      this.msg = e?.message ?? String(e);
    } finally {
      this.detecting = false;
      this.cdr.detectChanges();
    }
  }

  async save(): Promise<void> {
    this.msg = '';
    this.busy = true;

    try {
      const dn = this.displayName.trim();
      if (!dn) throw new Error('Screen name is required.');

      // One more detect attempt if still missing (e.g. slow network).
      if (!this.countryCode || !this.countryName) {
        const loc = await this.location.detectViaGpsThenServer(9000);
        if (loc?.countryCode && loc.countryName) {
          this.countryCode = loc.countryCode;
          this.countryName = loc.countryName;
          this.cityName = loc.cityName ?? '';
        }
      }

      if (!this.countryCode || !this.countryName) {
        throw new Error('Still detecting location. Please wait a moment and try again.');
      }

      await this.gql.query(
        `
        mutation Update($input: UpdateProfileInput!) {
          updateProfile(input: $input) { user_id }
        }
        `,
        {
          input: {
            display_name: dn,
            avatar_url: this.avatarUrl,
            bio: this.bio.trim() || null,
            country_name: this.countryName,
            country_code: this.countryCode,
            city_name: this.cityName || null,
          },
        }
      );

      await this.router.navigateByUrl('/');
    } catch (e: any) {
      this.msg = e?.message ?? String(e);
    } finally {
      this.busy = false;
      this.cdr.detectChanges();
    }
  }

  async goBack(): Promise<void> {
    if (history.length > 1) {
      history.back();
      return;
    }
    await this.router.navigateByUrl('/');
  }
}
