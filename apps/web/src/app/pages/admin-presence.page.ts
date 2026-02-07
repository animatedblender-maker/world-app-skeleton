import { CommonModule } from '@angular/common';
import { Component, OnDestroy, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { Subscription } from 'rxjs';

import { CountriesService, type CountryModel } from '../data/countries.service';
import {
  PresenceOverridesService,
  type PresenceOverridesMap,
  type PresenceOverride,
} from '../core/services/presence-overrides.service';
import { environment } from '../../envirnoments/envirnoment';

const ADMIN_KEY = 'worldapp-admin-2026';
const ADMIN_STORAGE = 'worldapp.adminKey.v1';
const CRON_STORAGE = 'worldapp.insightsCronSecret.v1';
const EMPTY_OVERRIDE: PresenceOverride = Object.freeze({ total: null, online: null });

@Component({
  selector: 'app-admin-presence-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="admin-shell">
      <div class="card lock-card" *ngIf="locked">
        <div class="card-title">Admin access</div>
        <div class="card-sub">
          Enter the key or open this page with <code>?key=YOUR_KEY</code>.
        </div>
        <div class="lock-row">
          <input
            type="password"
            placeholder="Admin key"
            [(ngModel)]="keyInput"
            (keydown.enter)="unlock()"
          />
          <button type="button" (click)="unlock()">Unlock</button>
        </div>
        <div class="card-error" *ngIf="keyError">{{ keyError }}</div>
      </div>

      <div class="card" *ngIf="!locked">
        <div class="card-head">
          <div>
            <div class="card-title">Presence overrides</div>
            <div class="card-sub">
              Override totals and online counts per country. Empty means auto.
            </div>
          </div>
          <div class="head-actions">
            <button class="ghost" type="button" (click)="resetAll()">Reset all</button>
            <button type="button" (click)="goBack()">Back to globe</button>
          </div>
        </div>

        <div class="tools">
          <input
            type="text"
            placeholder="Filter countries"
            [(ngModel)]="filter"
            (ngModelChange)="applyFilter()"
          />
          <div class="tools-meta">
            Active overrides: <b>{{ overrideCount }}</b>
          </div>
        </div>

        <div class="grid-head">
          <div>Country</div>
          <div>Total</div>
          <div>Online</div>
          <div></div>
        </div>

        <div class="grid-row" *ngFor="let country of filteredCountries">
          <div class="country-cell">
            <div class="country-name">{{ country.name }}</div>
            <div class="country-code">{{ country.code }}</div>
          </div>
          <input
            type="number"
            min="0"
            step="1"
            placeholder="auto"
            [ngModel]="overrideFor(country.code).total"
            (ngModelChange)="setOverrideValue(country.code, 'total', $event)"
          />
          <input
            type="number"
            min="0"
            step="1"
            placeholder="auto"
            [ngModel]="overrideFor(country.code).online"
            (ngModelChange)="setOverrideValue(country.code, 'online', $event)"
          />
          <button class="ghost" type="button" (click)="clearOverride(country.code)">
            Clear
          </button>
        </div>
      </div>

      <div class="card cron-card" *ngIf="!locked">
        <div class="card-head">
          <div>
            <div class="card-title">Daily insights</div>
            <div class="card-sub">Run the manual daily insights job.</div>
          </div>
        </div>
        <div class="cron-row">
          <input
            type="password"
            placeholder="Cron secret"
            [(ngModel)]="cronSecretInput"
          />
          <button type="button" (click)="runDailyInsights()" [disabled]="cronRunning">
            {{ cronRunning ? 'Running…' : 'Run now' }}
          </button>
        </div>
        <div class="card-sub" *ngIf="cronStatus">{{ cronStatus }}</div>
      </div>
    </div>
  `,
  styles: [
    `
      :host {
        display: block;
        min-height: 100vh;
        background: radial-gradient(circle at top, rgba(0, 60, 70, 0.28), transparent 60%),
          linear-gradient(180deg, #050a12 0%, #071723 100%);
        color: #e7f7ff;
        font-family: 'Sora', 'Space Grotesk', 'Avenir', sans-serif;
      }
      .admin-shell {
        max-width: 1100px;
        margin: 0 auto;
        padding: 36px 20px 72px;
      }
      .card {
        background: rgba(8, 18, 28, 0.92);
        border: 1px solid rgba(255, 255, 255, 0.08);
        border-radius: 18px;
        padding: 22px;
        box-shadow: 0 24px 60px rgba(0, 0, 0, 0.4);
      }
      .lock-card {
        max-width: 520px;
        margin: 12vh auto 0;
      }
      .cron-card {
        margin-top: 18px;
      }
      .card-title {
        font-size: 20px;
        font-weight: 700;
        letter-spacing: 0.01em;
      }
      .card-sub {
        margin-top: 6px;
        opacity: 0.7;
        font-size: 13px;
      }
      .card-sub code {
        background: rgba(255, 255, 255, 0.06);
        padding: 2px 6px;
        border-radius: 6px;
      }
      .lock-row {
        margin-top: 18px;
        display: flex;
        gap: 10px;
      }
      input[type='text'],
      input[type='password'],
      input[type='number'] {
        border-radius: 12px;
        border: 1px solid rgba(255, 255, 255, 0.12);
        background: rgba(4, 10, 16, 0.9);
        color: #e7f7ff;
        padding: 10px 12px;
        font-size: 13px;
        outline: none;
        width: 100%;
        box-sizing: border-box;
      }
      input[type='number'] {
        text-align: right;
      }
      input:focus {
        border-color: rgba(0, 255, 209, 0.6);
        box-shadow: 0 0 0 3px rgba(0, 255, 209, 0.12);
      }
      button {
        border-radius: 12px;
        border: none;
        background: rgba(0, 255, 209, 0.18);
        color: #c9fff2;
        padding: 10px 14px;
        font-weight: 700;
        cursor: pointer;
      }
      button.ghost {
        background: rgba(255, 255, 255, 0.08);
        color: rgba(255, 255, 255, 0.8);
      }
      .card-error {
        margin-top: 12px;
        color: #ff9f9f;
        font-size: 12px;
      }
      .card-head {
        display: flex;
        justify-content: space-between;
        gap: 16px;
        align-items: flex-start;
        flex-wrap: wrap;
      }
      .head-actions {
        display: flex;
        gap: 8px;
      }
      .tools {
        margin-top: 18px;
        display: flex;
        gap: 12px;
        align-items: center;
        flex-wrap: wrap;
      }
      .cron-row {
        margin-top: 14px;
        display: flex;
        gap: 10px;
        align-items: center;
        flex-wrap: wrap;
      }
      .cron-row input {
        flex: 1 1 240px;
      }
      .tools input {
        max-width: 320px;
      }
      .tools-meta {
        opacity: 0.7;
        font-size: 13px;
      }
      .grid-head,
      .grid-row {
        display: grid;
        grid-template-columns: minmax(180px, 1fr) 140px 140px 88px;
        gap: 12px;
        align-items: center;
      }
      .grid-head {
        margin-top: 18px;
        padding-bottom: 8px;
        font-size: 11px;
        letter-spacing: 0.2em;
        opacity: 0.6;
      }
      .grid-row {
        padding: 10px 0;
        border-top: 1px solid rgba(255, 255, 255, 0.06);
      }
      .country-cell {
        display: flex;
        flex-direction: column;
        gap: 2px;
      }
      .country-name {
        font-size: 14px;
        font-weight: 600;
      }
      .country-code {
        font-size: 11px;
        opacity: 0.6;
        letter-spacing: 0.2em;
      }
      @media (max-width: 720px) {
        .grid-head,
        .grid-row {
          grid-template-columns: 1fr 1fr;
        }
        .grid-head div:nth-child(3),
        .grid-head div:nth-child(4),
        .grid-row input:nth-child(3),
        .grid-row button {
          grid-column: span 1;
        }
        .grid-row {
          grid-template-areas:
            'country country'
            'total online'
            'clear clear';
        }
        .grid-row .country-cell {
          grid-area: country;
        }
        .grid-row input:nth-of-type(1) {
          grid-area: total;
        }
        .grid-row input:nth-of-type(2) {
          grid-area: online;
        }
        .grid-row button {
          grid-area: clear;
          width: 100%;
        }
        .grid-head {
          display: none;
        }
      }
    `,
  ],
})
export class AdminPresencePageComponent implements OnInit, OnDestroy {
  locked = true;
  keyInput = '';
  keyError = '';
  filter = '';
  cronSecretInput = '';
  cronRunning = false;
  cronStatus = '';

  countries: CountryModel[] = [];
  filteredCountries: CountryModel[] = [];
  overrides: PresenceOverridesMap = {};
  overrideCount = 0;

  private overridesSub?: Subscription;

  constructor(
    private countriesService: CountriesService,
    private overridesService: PresenceOverridesService,
    private route: ActivatedRoute,
    private router: Router
  ) {}

  ngOnInit(): void {
    this.overrides = this.overridesService.getOverrides();
    this.overrideCount = Object.keys(this.overrides).length;
    this.unlockFromStorage();
    this.unlockFromQuery();
    this.loadCronSecret();

    this.overridesSub = this.overridesService.observe().subscribe((next) => {
      this.overrides = next || {};
      this.overrideCount = Object.keys(this.overrides).length;
      this.applyFilter();
    });

    void this.loadCountries();
  }

  ngOnDestroy(): void {
    this.overridesSub?.unsubscribe();
  }

  unlock(): void {
    const key = this.keyInput.trim();
    if (!key) return;
    if (key !== ADMIN_KEY) {
      this.keyError = 'Invalid key.';
      return;
    }
    this.persistKey(key);
    this.locked = false;
    this.keyError = '';
    this.keyInput = '';
  }

  resetAll(): void {
    this.overridesService.clearAll();
  }

  applyFilter(): void {
    const term = this.filter.trim().toLowerCase();
    const list = this.countries;
    if (!term) {
      this.filteredCountries = list;
      return;
    }
    this.filteredCountries = list.filter((country) => {
      const name = country.name.toLowerCase();
      const code = (country.code || '').toLowerCase();
      return name.includes(term) || code.includes(term);
    });
  }

  overrideFor(code: string | null): PresenceOverride {
    const key = String(code ?? '').toUpperCase();
    return this.overrides[key] ?? EMPTY_OVERRIDE;
  }

  setOverrideValue(code: string | null, field: 'total' | 'online', value: any): void {
    const key = String(code ?? '').toUpperCase();
    if (!key) return;

    const current = this.overrides[key] ?? {};
    const next: PresenceOverride = { ...current, [field]: value };
    this.overridesService.setOverride(key, next);
  }

  clearOverride(code: string | null): void {
    const key = String(code ?? '').toUpperCase();
    if (!key) return;
    this.overridesService.setOverride(key, null);
  }

  goBack(): void {
    void this.router.navigate(['/globe']);
  }

  async runDailyInsights(): Promise<void> {
    const secret = this.cronSecretInput.trim();
    if (!secret) {
      this.cronStatus = 'Enter the cron secret first.';
      return;
    }
    this.persistCronSecret(secret);
    this.cronRunning = true;
    this.cronStatus = 'Running…';
    try {
      const res = await fetch(`${environment.apiBaseUrl}/insights/run-daily`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-cron-secret': secret,
        },
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        this.cronStatus = `Failed: ${data?.error ?? res.status}`;
      } else {
        const processed = Number(data?.processed ?? 0);
        const failed = Number(data?.failed ?? 0);
        this.cronStatus = `Done. Captions: ${processed}, Failed: ${failed}`;
      }
    } catch (err: any) {
      this.cronStatus = `Failed: ${err?.message ?? 'unknown error'}`;
    } finally {
      this.cronRunning = false;
    }
  }

  private async loadCountries(): Promise<void> {
    try {
      const data = await this.countriesService.loadCountries();
      this.countries = data.countries.filter((c) => !!c.code);
      this.applyFilter();
    } catch {
      this.countries = [];
      this.filteredCountries = [];
    }
  }

  private unlockFromQuery(): void {
    const key = this.route.snapshot.queryParamMap.get('key');
    if (!key) return;
    if (key === ADMIN_KEY) {
      this.persistKey(key);
      this.locked = false;
      this.keyError = '';
    } else {
      this.keyError = 'Invalid key.';
    }
  }

  private unlockFromStorage(): void {
    try {
      const stored = localStorage.getItem(ADMIN_STORAGE);
      if (stored === ADMIN_KEY) {
        this.locked = false;
        this.keyError = '';
      }
    } catch {}
  }

  private loadCronSecret(): void {
    try {
      const stored = localStorage.getItem(CRON_STORAGE);
      if (stored) this.cronSecretInput = stored;
    } catch {}
  }

  private persistKey(key: string): void {
    try {
      localStorage.setItem(ADMIN_STORAGE, key);
    } catch {}
  }

  private persistCronSecret(secret: string): void {
    try {
      localStorage.setItem(CRON_STORAGE, secret);
    } catch {}
  }
}
