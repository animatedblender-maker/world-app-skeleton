import { Component, OnInit, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { AuthService } from '../core/services/auth.service';
import { CountriesService, CountryModel } from '../data/countries.service';
import { GraphqlService } from '../core/services/graphql.service';
import { MediaService } from '../core/services/media.service';

type DetectLocationResult = {
  detectLocation: {
    countryCode: string;
    countryName: string;
    cityName?: string | null;
    source: string;
  };
};

@Component({
  selector: 'app-profile-setup-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
  <div class="wrap">
    <div class="card">
      <div class="title">Create your profile</div>
      <div class="sub">Auto-detect is default. Manual selection is fallback.</div>

      <div class="field">
        <label>Screen name</label>
        <input [(ngModel)]="displayName" placeholder="e.g. Amr" />
      </div>

      <div class="field">
        <label>Avatar (optional)</label>
        <div class="row">
          <label class="btn2" style="cursor:pointer;">
            Choose image
            <input type="file" accept="image/*" (change)="onAvatar($event)" style="display:none;" />
          </label>
          <small class="muted" *ngIf="avatarUrl">Selected ✅</small>
        </div>
      </div>

      <div class="field">
        <label>Detected location</label>
        <div class="locbox">
          <div class="locrow"><div class="k">Country</div><div class="v">{{ countryName || '—' }}</div></div>
          <div class="locrow"><div class="k">City</div><div class="v">{{ cityName || '—' }}</div></div>
          <div class="locrow"><div class="k">Status</div><div class="v">{{ detecting ? 'Detecting…' : (detectSource || '—') }}</div></div>
        </div>

        <div class="row" style="margin-top:10px;">
          <button class="btn2" type="button" (click)="detect()" [disabled]="detecting">
            {{ detecting ? 'Detecting…' : 'Detect again' }}
          </button>
          <button class="link" type="button" (click)="manual = !manual">
            {{ manual ? 'Hide manual' : 'Manual fallback' }}
          </button>
        </div>
      </div>

      <div class="field" *ngIf="manual">
        <label>Manual country</label>
        <select [(ngModel)]="manualCountryName">
          <option value="">Select…</option>
          <option *ngFor="let c of countries" [value]="c.name">{{ c.name }}</option>
        </select>
        <small class="muted">Used only if auto-detect fails.</small>
      </div>

      <div class="row" style="margin-top:16px;">
        <button class="btn" (click)="save()" [disabled]="busy">
          {{ busy ? 'Saving…' : 'Save & Continue' }}
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
    .field{ margin-top:14px; display:grid; gap:8px; }
    label{ font-size:12px; opacity:.75; letter-spacing:0.12em; }
    input,select{
      padding:12px; border-radius:16px;
      border:1px solid rgba(255,255,255,0.12);
      background: rgba(0,0,0,0.28);
      color: rgba(255,255,255,0.92);
      outline:none;
    }
    .locbox{
      border:1px solid rgba(255,255,255,0.10);
      background: rgba(0,0,0,0.20);
      border-radius:16px;
      padding:12px;
      display:grid;
      gap:8px;
    }
    .locrow{ display:flex; justify-content:space-between; gap:12px; }
    .k{ opacity:.7; font-size:12px; }
    .v{ font-weight:800; font-size:13px; }
    .row{ display:flex; gap:12px; align-items:center; }
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
    .link{
      border:0; background:transparent; padding:0;
      color: rgba(0,255,209,0.90);
      cursor:pointer; font-weight:900; letter-spacing:0.08em;
      font-size:12px;
    }
    .msg{ font-size:13px; opacity:.95; white-space:pre-wrap; }
  `],
})
export class ProfileSetupPageComponent implements OnInit {
  countries: CountryModel[] = [];

  displayName = '';
  avatarUrl: string | null = null;

  detecting = false;
  detectSource = '';
  countryName = '';
  countryCode = '';
  cityName = '';

  manual = false;
  manualCountryName = '';

  busy = false;
  msg = '';

  constructor(
    private auth: AuthService,
    private countriesService: CountriesService,
    private gql: GraphqlService,
    private media: MediaService,
    private router: Router,
    private cdr: ChangeDetectorRef
  ) {}

  async ngOnInit(): Promise<void> {
    const user = await this.auth.getUser();
    if (!user) {
      await this.router.navigateByUrl('/auth');
      return;
    }

    this.displayName = user.email?.split('@')[0] ?? 'User';

    // Load countries for fallback (always)
    const data = await this.countriesService.loadCountries();
    this.countries = data.countries ?? [];
    this.cdr.detectChanges();

    // Auto-detect ON LOAD (default)
    // Use a microtask so page renders first (helps permission prompts)
    queueMicrotask(() => this.detect());
  }

  async onAvatar(e: Event): Promise<void> {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;

    this.msg = '';

    try {
      const res = await this.media.uploadAvatar(file);
      this.avatarUrl = res.url;
    } catch (err: any) {
      this.msg = `Avatar upload failed: ${err?.message ?? err}`;
    } finally {
      input.value = '';
      this.cdr.detectChanges();
    }
  }

  async detect(): Promise<void> {
    this.msg = '';
    this.detecting = true;
    this.detectSource = '';

    try {
      const coords = await this.getBrowserCoords(9000);

      if (!coords) {
        this.manual = true;
        this.detectSource = 'location unavailable';
        return;
      }

      const result = await this.gql.query<DetectLocationResult>(
        `
        mutation Detect($lat: Float!, $lng: Float!) {
          detectLocation(lat: $lat, lng: $lng) {
            countryCode
            countryName
            cityName
            source
          }
        }
        `,
        { lat: coords.lat, lng: coords.lng }
      );

      const d = result.detectLocation;

      this.countryName = d.countryName;
      this.countryCode = d.countryCode;
      this.cityName = d.cityName ?? '';
      this.detectSource = d.source;

      this.manual = false;
    } catch (e: any) {
      this.manual = true;
      this.detectSource = 'detect failed';
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

      // if auto-detect failed, use manual fallback
      let cn = (this.countryName || '').trim();
      let cc = (this.countryCode || '').trim();
      let city = (this.cityName || '').trim();

      if (!cn || cn === 'Unknown') {
        if (!this.manualCountryName) throw new Error('Auto-detect failed. Select a country manually.');
        const manualName = this.manualCountryName.trim().toLowerCase();
        const match = this.countries.find((c) => c.name.trim().toLowerCase() === manualName);
        if (!match?.code) throw new Error('Selected country has no code. Pick another country.');
        cn = match.name;
        cc = match.code;
        city = '';
        this.countryName = cn;
        this.countryCode = cc;
        this.cityName = '';
        this.detectSource = 'manual selection';
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
            country_name: cn,
            country_code: cc || null,
            city_name: city || null,
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

  private getBrowserCoords(timeoutMs: number): Promise<{ lat: number; lng: number } | null> {
    return new Promise((resolve) => {
      if (!('geolocation' in navigator)) return resolve(null);

      let done = false;
      const finish = (v: any) => { if (!done) { done = true; resolve(v); } };

      const t = window.setTimeout(() => finish(null), timeoutMs);

      navigator.geolocation.getCurrentPosition(
        (pos) => {
          clearTimeout(t);
          finish({ lat: pos.coords.latitude, lng: pos.coords.longitude });
        },
        () => {
          clearTimeout(t);
          finish(null);
        },
        { enableHighAccuracy: false, timeout: timeoutMs, maximumAge: 60_000 }
      );
    });
  }
}
