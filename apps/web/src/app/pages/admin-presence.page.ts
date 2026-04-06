import { CommonModule } from '@angular/common';
import { Component, OnDestroy, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
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
const EMPTY_OVERRIDE: PresenceOverride = Object.freeze({ total: null, online: null });
const DEFAULT_SETTINGS: AdminSettings = {
  insight_window_hours: 24,
  insight_min_posts: 3,
  insight_cache_minutes: 5,
  insight_max_posts: 250,
  insight_max_lookback_hours: 720,
  ollama_enabled: true,
  ollama_model: 'qwen3.5:397b-cloud',
};

type AdminTab = 'overview' | 'insights' | 'reports' | 'ads' | 'presence';

type AdminOverview = {
  total_profiles: number;
  online_users: number;
  posts_last_24h: number;
  reports_last_7d: number;
  active_campaigns: number;
  total_campaigns: number;
};

type AdminSettings = {
  insight_window_hours: number;
  insight_min_posts: number;
  insight_cache_minutes: number;
  insight_max_posts: number;
  insight_max_lookback_hours: number;
  ollama_enabled: boolean;
  ollama_model: string;
};

type ReportedPostItem = {
  report_id: string;
  created_at: string;
  reason: string;
  post_id: string;
  post_excerpt: string;
  country_code: string | null;
  reporter_id: string;
  reporter_name: string | null;
  author_id: string | null;
  author_name: string | null;
};

type AdsSummary = {
  active_campaigns: number;
  draft_campaigns: number;
  paused_campaigns: number;
  total_creatives: number;
  total_budget_cents: number;
};

type AdminBootstrap = {
  overview: AdminOverview;
  settings: AdminSettings;
  reports: ReportedPostItem[];
  ads: AdsSummary;
};

function clampInt(value: any, fallback: number, min: number, max: number): number {
  const next = Number(value);
  if (!Number.isFinite(next)) return fallback;
  return Math.max(min, Math.min(max, Math.round(next)));
}

function normalizeSettings(input: Partial<AdminSettings> | null | undefined): AdminSettings {
  const raw = input || {};
  return {
    insight_window_hours: clampInt(raw.insight_window_hours, DEFAULT_SETTINGS.insight_window_hours, 1, 720),
    insight_min_posts: clampInt(raw.insight_min_posts, DEFAULT_SETTINGS.insight_min_posts, 1, 1000),
    insight_cache_minutes: clampInt(raw.insight_cache_minutes, DEFAULT_SETTINGS.insight_cache_minutes, 1, 1440),
    insight_max_posts: clampInt(raw.insight_max_posts, DEFAULT_SETTINGS.insight_max_posts, 10, 1000),
    insight_max_lookback_hours: clampInt(
      raw.insight_max_lookback_hours,
      DEFAULT_SETTINGS.insight_max_lookback_hours,
      1,
      24 * 365
    ),
    ollama_enabled:
      typeof raw.ollama_enabled === 'boolean' ? raw.ollama_enabled : DEFAULT_SETTINGS.ollama_enabled,
    ollama_model: String(raw.ollama_model || DEFAULT_SETTINGS.ollama_model).trim() || DEFAULT_SETTINGS.ollama_model,
  };
}

@Component({
  selector: 'app-admin-presence-page',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  template: `
    <div class="admin-shell">
      <div class="card lock-card" *ngIf="locked">
        <div class="card-title">Admin Hub</div>
        <div class="card-sub">Enter the admin key or open this page with <code>?key=YOUR_KEY</code>.</div>
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

      <ng-container *ngIf="!locked">
        <div class="hero">
          <div>
            <div class="eyebrow">Ops Portal</div>
            <h1>Admin Hub</h1>
            <p>Phase 1 centralizes the feed controls we already have: insights, reported posts, ads health, and presence overrides.</p>
          </div>
          <div class="hero-actions">
            <button class="ghost" type="button" (click)="refreshBootstrap()" [disabled]="loadingBootstrap">
              {{ loadingBootstrap ? 'Refreshing…' : 'Refresh data' }}
            </button>
            <button type="button" (click)="goBack()">Back to globe</button>
          </div>
        </div>

        <div class="tabs">
          <button type="button" [class.active]="activeTab==='overview'" (click)="activeTab='overview'">Overview</button>
          <button type="button" [class.active]="activeTab==='insights'" (click)="activeTab='insights'">Insights</button>
          <button type="button" [class.active]="activeTab==='reports'" (click)="activeTab='reports'">Reported Posts</button>
          <button type="button" [class.active]="activeTab==='ads'" (click)="activeTab='ads'">Ads</button>
          <button type="button" [class.active]="activeTab==='presence'" (click)="activeTab='presence'">Presence</button>
        </div>

        <div class="card status-card" *ngIf="bootstrapError">{{ bootstrapError }}</div>

        <div class="panel-grid" *ngIf="activeTab==='overview'">
          <div class="metric-card">
            <div class="metric-label">Profiles</div>
            <div class="metric-value">{{ overview.total_profiles }}</div>
            <div class="metric-sub">Saved user profiles in Supabase.</div>
          </div>
          <div class="metric-card">
            <div class="metric-label">Online Now</div>
            <div class="metric-value">{{ overview.online_users }}</div>
            <div class="metric-sub">Presence seen in the last 90 seconds.</div>
          </div>
          <div class="metric-card">
            <div class="metric-label">Posts 24h</div>
            <div class="metric-value">{{ overview.posts_last_24h }}</div>
            <div class="metric-sub">Recent posting activity across the app.</div>
          </div>
          <div class="metric-card">
            <div class="metric-label">Reports 7d</div>
            <div class="metric-value">{{ overview.reports_last_7d }}</div>
            <div class="metric-sub">Reported posts waiting for moderation review.</div>
          </div>
          <div class="metric-card">
            <div class="metric-label">Active Campaigns</div>
            <div class="metric-value">{{ overview.active_campaigns }}</div>
            <div class="metric-sub">Out of {{ overview.total_campaigns }} total campaigns.</div>
          </div>
          <div class="metric-card">
            <div class="metric-label">Insight Window</div>
            <div class="metric-value">{{ settings.insight_window_hours }}h</div>
            <div class="metric-sub">Current summary lookback period.</div>
          </div>
        </div>

        <div class="card" *ngIf="activeTab==='insights'">
          <div class="card-head">
            <div>
              <div class="card-title">Insights Settings</div>
              <div class="card-sub">Control how country summaries are computed and when Ollama is used.</div>
            </div>
          </div>

          <div class="settings-grid">
            <label>
              <span>Insight window hours</span>
              <input type="number" min="1" max="720" [(ngModel)]="settingsDraft.insight_window_hours" />
            </label>
            <label>
              <span>Minimum posts needed</span>
              <input type="number" min="1" max="1000" [(ngModel)]="settingsDraft.insight_min_posts" />
            </label>
            <label>
              <span>Cache minutes</span>
              <input type="number" min="1" max="1440" [(ngModel)]="settingsDraft.insight_cache_minutes" />
            </label>
            <label>
              <span>Max posts for summary</span>
              <input type="number" min="10" max="1000" [(ngModel)]="settingsDraft.insight_max_posts" />
            </label>
            <label>
              <span>Max lookback hours</span>
              <input type="number" min="1" max="8760" [(ngModel)]="settingsDraft.insight_max_lookback_hours" />
            </label>
            <label>
              <span>Ollama model</span>
              <input type="text" [(ngModel)]="settingsDraft.ollama_model" placeholder="qwen3.5:397b-cloud" />
            </label>
            <label class="toggle">
              <input type="checkbox" [(ngModel)]="settingsDraft.ollama_enabled" />
              <span>Use Ollama for summary generation</span>
            </label>
          </div>

          <div class="actions-row">
            <button type="button" (click)="saveSettings()" [disabled]="savingSettings">
              {{ savingSettings ? 'Saving…' : 'Save settings' }}
            </button>
            <button class="ghost" type="button" (click)="resetSettingsDraft()" [disabled]="savingSettings || cronRunning">
              Reset form
            </button>
            <button class="ghost" type="button" (click)="runDailyInsights()" [disabled]="cronRunning">
              {{ cronRunning ? 'Running…' : 'Rebuild country insights' }}
            </button>
          </div>
          <div class="card-sub" *ngIf="settingsStatus">{{ settingsStatus }}</div>
        </div>

        <div class="card" *ngIf="activeTab==='reports'">
          <div class="card-head">
            <div>
              <div class="card-title">Reported Posts</div>
              <div class="card-sub">Newest reports first. Phase 1 is a moderation inbox, not a full resolver yet.</div>
            </div>
            <button class="ghost" type="button" (click)="reloadReports()" [disabled]="loadingReports">
              {{ loadingReports ? 'Refreshing…' : 'Refresh reports' }}
            </button>
          </div>

          <div class="report-list" *ngIf="reports.length; else noReports">
            <div class="report-item" *ngFor="let item of reports">
              <div class="report-head">
                <div>
                  <div class="report-title">{{ item.post_excerpt || 'Untitled post' }}</div>
                  <div class="report-meta">
                    {{ item.country_code || 'GLOBAL' }} · reported {{ item.created_at | date:'medium' }}
                  </div>
                </div>
                <a [routerLink]="['/post', item.post_id]">Open post</a>
              </div>
              <div class="report-reason">{{ item.reason }}</div>
              <div class="report-users">
                <span>Reporter: {{ item.reporter_name || item.reporter_id }}</span>
                <span>Author: {{ item.author_name || item.author_id || 'Unknown' }}</span>
              </div>
            </div>
          </div>
          <ng-template #noReports>
            <div class="empty-state">No reported posts right now.</div>
          </ng-template>
        </div>

        <div class="panel-grid" *ngIf="activeTab==='ads'">
          <div class="metric-card">
            <div class="metric-label">Active Campaigns</div>
            <div class="metric-value">{{ ads.active_campaigns }}</div>
          </div>
          <div class="metric-card">
            <div class="metric-label">Draft Campaigns</div>
            <div class="metric-value">{{ ads.draft_campaigns }}</div>
          </div>
          <div class="metric-card">
            <div class="metric-label">Paused Campaigns</div>
            <div class="metric-value">{{ ads.paused_campaigns }}</div>
          </div>
          <div class="metric-card">
            <div class="metric-label">Creatives</div>
            <div class="metric-value">{{ ads.total_creatives }}</div>
          </div>
          <div class="metric-card wide">
            <div class="metric-label">Budget</div>
            <div class="metric-value">{{ formatCurrency(ads.total_budget_cents) }}</div>
            <div class="metric-sub">Phase 1 gives visibility; full ad management can grow from here.</div>
          </div>
        </div>

        <div class="card" *ngIf="activeTab==='presence'">
          <div class="card-head">
            <div>
              <div class="card-title">Presence Overrides</div>
              <div class="card-sub">Override totals and online counts per country. Empty means auto.</div>
            </div>
            <div class="head-actions">
              <button class="ghost" type="button" (click)="resetAll()">Reset all</button>
            </div>
          </div>

          <div class="tools">
            <input
              type="text"
              placeholder="Filter countries"
              [(ngModel)]="filter"
              (ngModelChange)="applyFilter()"
            />
            <div class="tools-meta">Active overrides: <b>{{ overrideCount }}</b></div>
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
            <button class="ghost" type="button" (click)="clearOverride(country.code)">Clear</button>
          </div>
        </div>
      </ng-container>
    </div>
  `,
  styles: [
    `
      :host {
        display: block;
        min-height: 100vh;
        background:
          radial-gradient(circle at top left, rgba(0, 255, 209, 0.15), transparent 30%),
          radial-gradient(circle at top right, rgba(0, 151, 255, 0.12), transparent 28%),
          linear-gradient(180deg, #050a12 0%, #071723 100%);
        color: #e7f7ff;
        font-family: 'Sora', 'Space Grotesk', 'Avenir', sans-serif;
      }
      .admin-shell {
        max-width: 1180px;
        margin: 0 auto;
        padding: 36px 20px 72px;
      }
      .hero {
        display: flex;
        justify-content: space-between;
        align-items: flex-start;
        gap: 16px;
        margin-bottom: 20px;
      }
      .eyebrow {
        font-size: 11px;
        letter-spacing: 0.24em;
        text-transform: uppercase;
        opacity: 0.6;
      }
      h1 {
        margin: 8px 0 10px;
        font-size: 34px;
        line-height: 1.05;
      }
      p {
        margin: 0;
        max-width: 640px;
        opacity: 0.78;
      }
      .hero-actions,
      .head-actions,
      .actions-row,
      .lock-row {
        display: flex;
        gap: 10px;
        align-items: center;
        flex-wrap: wrap;
      }
      .tabs {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
        margin-bottom: 18px;
      }
      .tabs button,
      button {
        border-radius: 12px;
        border: none;
        background: rgba(0, 255, 209, 0.18);
        color: #c9fff2;
        padding: 10px 14px;
        font-weight: 700;
        cursor: pointer;
      }
      .tabs button {
        background: rgba(255, 255, 255, 0.08);
        color: rgba(255, 255, 255, 0.82);
      }
      .tabs button.active {
        background: rgba(0, 255, 209, 0.18);
        color: #c9fff2;
      }
      button.ghost {
        background: rgba(255, 255, 255, 0.08);
        color: rgba(255, 255, 255, 0.82);
      }
      .panel-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
        gap: 16px;
      }
      .metric-card,
      .card {
        background: rgba(8, 18, 28, 0.92);
        border: 1px solid rgba(255, 255, 255, 0.08);
        border-radius: 18px;
        padding: 22px;
        box-shadow: 0 24px 60px rgba(0, 0, 0, 0.32);
      }
      .metric-card.wide {
        grid-column: span 2;
      }
      .metric-label,
      .country-code {
        font-size: 11px;
        letter-spacing: 0.18em;
        text-transform: uppercase;
        opacity: 0.6;
      }
      .metric-value {
        margin-top: 8px;
        font-size: 34px;
        font-weight: 800;
        line-height: 1;
      }
      .metric-sub,
      .card-sub,
      .tools-meta {
        margin-top: 8px;
        font-size: 13px;
        opacity: 0.72;
      }
      .status-card,
      .empty-state {
        margin-bottom: 18px;
        font-size: 14px;
      }
      .card + .card,
      .panel-grid + .card {
        margin-top: 18px;
      }
      .card-title {
        font-size: 20px;
        font-weight: 700;
      }
      .card-head {
        display: flex;
        justify-content: space-between;
        gap: 16px;
        align-items: flex-start;
        flex-wrap: wrap;
      }
      .lock-card {
        max-width: 520px;
        margin: 12vh auto 0;
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
      input:focus {
        border-color: rgba(0, 255, 209, 0.6);
        box-shadow: 0 0 0 3px rgba(0, 255, 209, 0.12);
      }
      .settings-grid {
        margin-top: 18px;
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
        gap: 14px;
      }
      .settings-grid label {
        display: flex;
        flex-direction: column;
        gap: 8px;
        font-size: 13px;
      }
      .toggle {
        justify-content: flex-end;
      }
      .toggle input {
        width: auto;
      }
      .report-list {
        margin-top: 18px;
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .report-item {
        border: 1px solid rgba(255, 255, 255, 0.08);
        border-radius: 14px;
        padding: 14px;
        background: rgba(255, 255, 255, 0.03);
      }
      .report-head {
        display: flex;
        justify-content: space-between;
        gap: 12px;
        align-items: flex-start;
      }
      .report-title,
      .country-name {
        font-size: 15px;
        font-weight: 700;
      }
      .report-meta,
      .report-users {
        margin-top: 6px;
        font-size: 12px;
        opacity: 0.7;
      }
      .report-reason {
        margin-top: 10px;
        font-size: 14px;
      }
      .report-users {
        display: flex;
        gap: 14px;
        flex-wrap: wrap;
      }
      a {
        color: #92fff0;
        text-decoration: none;
      }
      .tools {
        margin-top: 18px;
        display: flex;
        gap: 12px;
        align-items: center;
        flex-wrap: wrap;
      }
      .tools input {
        max-width: 320px;
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
      .card-error {
        margin-top: 12px;
        color: #ff9f9f;
        font-size: 12px;
      }
      code {
        background: rgba(255, 255, 255, 0.06);
        padding: 2px 6px;
        border-radius: 6px;
      }
      @media (max-width: 780px) {
        .hero {
          flex-direction: column;
        }
        .metric-card.wide {
          grid-column: span 1;
        }
        .grid-head,
        .grid-row {
          grid-template-columns: 1fr 1fr;
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
  activeTab: AdminTab = 'overview';

  loadingBootstrap = false;
  bootstrapError = '';
  loadingReports = false;
  savingSettings = false;
  cronRunning = false;
  settingsStatus = '';

  overview: AdminOverview = {
    total_profiles: 0,
    online_users: 0,
    posts_last_24h: 0,
    reports_last_7d: 0,
    active_campaigns: 0,
    total_campaigns: 0,
  };
  settings: AdminSettings = {
    ...DEFAULT_SETTINGS,
  };
  settingsDraft: AdminSettings = { ...DEFAULT_SETTINGS };
  reports: ReportedPostItem[] = [];
  ads: AdsSummary = {
    active_campaigns: 0,
    draft_campaigns: 0,
    paused_campaigns: 0,
    total_creatives: 0,
    total_budget_cents: 0,
  };

  filter = '';
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
    this.overridesSub = this.overridesService.observe().subscribe((next) => {
      this.overrides = next || {};
      this.overrideCount = Object.keys(this.overrides).length;
      this.applyFilter();
    });
    void this.loadCountries();
    if (!this.locked) void this.refreshBootstrap();
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
    void this.refreshBootstrap();
  }

  async refreshBootstrap(): Promise<void> {
    if (this.locked) return;
    this.loadingBootstrap = true;
    this.bootstrapError = '';
    try {
      const data = await this.adminRequest<AdminBootstrap>('/admin/bootstrap');
      this.overview = data.overview;
      this.settings = normalizeSettings(data.settings);
      this.settingsDraft = { ...this.settings };
      this.reports = data.reports;
      this.ads = data.ads;
    } catch (err: any) {
      this.bootstrapError = err?.message ?? 'Failed to load admin data.';
    } finally {
      this.loadingBootstrap = false;
    }
  }

  async saveSettings(): Promise<void> {
    this.savingSettings = true;
    this.settingsStatus = '';
    try {
      const payload = normalizeSettings(this.settingsDraft);
      const data = await this.adminRequest<{ settings: AdminSettings }>('/admin/settings', {
        method: 'POST',
        body: JSON.stringify(payload),
      });
      this.settings = normalizeSettings(data.settings);
      this.settingsDraft = { ...this.settings };
      this.settingsStatus = 'Settings saved.';
      await this.refreshBootstrap();
    } catch (err: any) {
      this.settingsStatus = err?.message ?? 'Failed to save settings.';
    } finally {
      this.savingSettings = false;
    }
  }

  async runDailyInsights(): Promise<void> {
    this.cronRunning = true;
    this.settingsStatus = 'Running country insights rebuild…';
    try {
      const data = await this.adminRequest<{ processed: number; failed: number }>('/admin/insights/run', {
        method: 'POST',
      });
      this.settingsStatus = `Done. Countries processed: ${Number(data.processed ?? 0)}, failed: ${Number(data.failed ?? 0)}.`;
      await this.refreshBootstrap();
    } catch (err: any) {
      this.settingsStatus = err?.message ?? 'Failed to run insights.';
    } finally {
      this.cronRunning = false;
    }
  }

  async reloadReports(): Promise<void> {
    this.loadingReports = true;
    try {
      const data = await this.adminRequest<{ reports: ReportedPostItem[] }>('/admin/reports?limit=40');
      this.reports = data.reports || [];
    } catch (err: any) {
      this.bootstrapError = err?.message ?? 'Failed to load reports.';
    } finally {
      this.loadingReports = false;
    }
  }

  resetAll(): void {
    this.overridesService.clearAll();
  }

  applyFilter(): void {
    const term = this.filter.trim().toLowerCase();
    if (!term) {
      this.filteredCountries = this.countries;
      return;
    }
    this.filteredCountries = this.countries.filter((country) => {
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

  formatCurrency(cents: number): string {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      maximumFractionDigits: 2,
    }).format((Number(cents) || 0) / 100);
  }

  resetSettingsDraft(): void {
    this.settingsDraft = { ...this.settings };
    this.settingsStatus = 'Settings reset to the latest saved values.';
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

  private persistKey(key: string): void {
    try {
      localStorage.setItem(ADMIN_STORAGE, key);
    } catch {}
  }

  private async adminRequest<T>(path: string, init: RequestInit = {}): Promise<T> {
    const key = localStorage.getItem(ADMIN_STORAGE) || ADMIN_KEY;
    const headers = new Headers(init.headers || {});
    headers.set('x-admin-key', key);
    if (init.body && !headers.has('Content-Type')) {
      headers.set('Content-Type', 'application/json');
    }
    const controller = new AbortController();
    const timeout = window.setTimeout(() => controller.abort(), 45000);
    try {
      const res = await fetch(`${environment.apiBaseUrl}${path}`, {
        ...init,
        headers,
        signal: controller.signal,
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(String(data?.error || `Request failed (${res.status})`));
      }
      return data as T;
    } catch (err: any) {
      if (String(err?.name) === 'AbortError') {
        throw new Error('Request timed out. The backend may still be processing.');
      }
      throw err;
    } finally {
      window.clearTimeout(timeout);
    }
  }
}
