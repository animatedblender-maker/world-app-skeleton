import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { AuthService } from '../core/services/auth.service';
import { ProfileService, Country } from '../core/services/profile.service';

@Component({
  selector: 'app-profile-setup-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
  <div class="wrap">
    <div class="card">
      <div class="title">Complete your profile</div>
      <div class="sub">Pick a country so your presence works on the globe.</div>

      <div class="field">
        <label>Display name</label>
        <input [(ngModel)]="displayName" placeholder="Your name" />
      </div>

      <div class="field">
        <label>Country</label>
        <select [(ngModel)]="countryCode">
          <option value="">Select…</option>
          <option *ngFor="let c of countries" [value]="c.iso">
            {{ c.name }} ({{ c.iso }})
          </option>
        </select>
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
    input,select{
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
export class ProfileSetupPageComponent implements OnInit {
  countries: Country[] = [];

  displayName = '';
  countryCode = '';

  busy = false;
  msg = '';

  constructor(
    private auth: AuthService,
    private profiles: ProfileService,
    private router: Router
  ) {}

  async ngOnInit(): Promise<void> {
    this.busy = true;
    this.msg = '';

    try {
      const user = await this.auth.getUser();
      if (!user) {
        await this.router.navigateByUrl('/auth');
        return;
      }

      // Load country list from API (geojson -> GraphQL)
      const countriesRes = await this.profiles.countries();
      const list = countriesRes.countries.countries;

      this.countries = list
        .filter((c: Country) => !!c.iso && c.iso !== 'XX')
        .sort((a: Country, b: Country) => a.name.localeCompare(b.name));

      // Load profile
      const { meProfile } = await this.profiles.meProfile();
      if (this.profiles.isComplete(meProfile)) {
        await this.router.navigateByUrl('/');
        return;
      }

      this.displayName = meProfile?.display_name ?? (user.email?.split('@')[0] ?? 'New User');
      this.countryCode = meProfile?.country_code ?? '';
    } catch (e: unknown) {
      this.msg = e instanceof Error ? e.message : String(e);
    } finally {
      this.busy = false;
    }
  }

  async save(): Promise<void> {
    this.msg = '';
    this.busy = true;

    try {
      const dn = this.displayName.trim();
      const cc = this.countryCode.trim();
      const selected = this.countries.find((c: Country) => c.iso === cc);

      if (!dn) throw new Error('Enter a display name.');
      if (!selected) throw new Error('Select a valid country.');

      await this.profiles.updateProfile({
        display_name: dn,
        country_code: selected.iso,
        country_name: selected.name,
      });

      await this.router.navigateByUrl('/');
    } catch (e: unknown) {
      this.msg = e instanceof Error ? e.message : String(e);
    } finally {
      this.busy = false;
    }
  }
}
