import { CommonModule } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { RouterLink } from '@angular/router';

import {
  StudioService,
  type StudioDashboard,
  type StudioRange,
} from '../../core/services/studio.service';

@Component({
  selector: 'app-studio-dashboard-page',
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <header class="head">
      <div>
        <div class="kicker">Overview</div>
        <h1>Dashboard</h1>
      </div>
      <div class="ranges">
        <button
          type="button"
          *ngFor="let r of ranges"
          class="chip"
          [class.on]="range === r"
          (click)="setRange(r)"
        >
          {{ r }}
        </button>
      </div>
    </header>

    <p class="error" *ngIf="error">{{ error }}</p>
    <p class="hint" *ngIf="loading">Loading metrics…</p>

    <ng-container *ngIf="dashboard as d">
      <section class="kpis">
        <div class="kpi">
          <div class="lab">Views</div>
          <div class="val">{{ studio.formatCount(d.kpis.views) }}</div>
        </div>
        <div class="kpi">
          <div class="lab">Watch time</div>
          <div class="val">{{ studio.formatWatch(d.kpis.watchMs) }}</div>
        </div>
        <div class="kpi">
          <div class="lab">CTR</div>
          <div class="val">{{ studio.formatCtr(d.kpis.ctr) }}</div>
        </div>
        <div class="kpi">
          <div class="lab">Impressions</div>
          <div class="val">{{ studio.formatCount(d.kpis.impressions) }}</div>
        </div>
        <div class="kpi">
          <div class="lab">Avg view</div>
          <div class="val">
            {{ d.kpis.avgViewDurationMs != null ? studio.formatWatch(d.kpis.avgViewDurationMs) : '—' }}
          </div>
        </div>
        <div class="kpi">
          <div class="lab">Subscribers</div>
          <div class="val">{{ studio.formatCount(d.kpis.subscribers) }}</div>
        </div>
      </section>

      <section class="panel" *ngIf="d.daily.length">
        <div class="panel-title">Views · {{ d.range }}</div>
        <div class="chart" role="img" [attr.aria-label]="'Daily views for ' + d.range">
          <div
            class="bar"
            *ngFor="let day of d.daily"
            [style.height.%]="barHeight(day.views)"
            [title]="day.day + ': ' + day.views + ' views'"
          ></div>
        </div>
      </section>

      <section class="panel">
        <div class="panel-head">
          <div class="panel-title">Top videos</div>
          <a routerLink="/studio/content">See all</a>
        </div>
        <div class="empty-inline" *ngIf="!d.topVideos.length">No video activity in this range yet.</div>
        <a class="row" *ngFor="let v of d.topVideos" [routerLink]="['/studio/content', v.id]">
          <img *ngIf="v.thumbUrl" [src]="v.thumbUrl" alt="" />
          <div class="row-body">
            <div class="row-title">{{ v.title || 'Untitled video' }}</div>
            <div class="row-meta">
              {{ studio.formatCount(v.views) }} views ·
              {{ studio.formatWatch(v.watchMs) }} · CTR {{ studio.formatCtr(v.ctr) }}
            </div>
          </div>
        </a>
      </section>

      <p class="note">{{ d.note }}</p>
    </ng-container>
  `,
  styles: [
    `
      .head {
        display: flex;
        justify-content: space-between;
        gap: 16px;
        align-items: flex-start;
        flex-wrap: wrap;
        margin-bottom: 22px;
      }
      .kicker {
        font-size: 11px;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--m-ink-muted, #948b82);
      }
      h1 {
        margin: 4px 0 0;
        font-size: 28px;
        letter-spacing: -0.02em;
      }
      .ranges {
        display: flex;
        gap: 8px;
      }
      .chip {
        border: 0.5px solid var(--m-border, #ddd8d1);
        background: var(--m-surface, #fefdfb);
        color: var(--m-ink-secondary, #5c564f);
        border-radius: 999px;
        padding: 8px 12px;
        font-weight: 600;
        cursor: pointer;
      }
      .chip.on {
        background: var(--m-ink, #2c2825);
        color: var(--m-paper, #f8f6f2);
        border-color: transparent;
      }
      .kpis {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
        gap: 12px;
        margin-bottom: 18px;
      }
      .kpi {
        background: var(--m-surface, #fefdfb);
        border: 0.5px solid var(--m-border, #ddd8d1);
        border-radius: 16px;
        padding: 14px 16px;
      }
      .lab {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
      }
      .val {
        margin-top: 6px;
        font-size: 22px;
        font-weight: 650;
        letter-spacing: -0.02em;
      }
      .panel {
        background: var(--m-surface, #fefdfb);
        border: 0.5px solid var(--m-border, #ddd8d1);
        border-radius: 18px;
        padding: 16px;
        margin-bottom: 16px;
      }
      .panel-head {
        display: flex;
        justify-content: space-between;
        align-items: baseline;
        margin-bottom: 10px;
      }
      .panel-head a {
        color: var(--m-ink, #2c2825);
        font-weight: 600;
        text-decoration: none;
        font-size: 13px;
      }
      .panel-title {
        font-weight: 650;
        margin-bottom: 10px;
      }
      .panel-head .panel-title {
        margin-bottom: 0;
      }
      .chart {
        display: flex;
        align-items: flex-end;
        gap: 3px;
        height: 120px;
        padding-top: 8px;
      }
      .bar {
        flex: 1;
        min-width: 4px;
        background: var(--m-ink, #2c2825);
        opacity: 0.78;
        border-radius: 4px 4px 0 0;
      }
      .row {
        display: grid;
        grid-template-columns: 72px minmax(0, 1fr);
        gap: 12px;
        padding: 10px 0;
        border-top: 0.5px solid var(--m-border, #ddd8d1);
        text-decoration: none;
        color: inherit;
      }
      .row:first-of-type {
        border-top: none;
      }
      .row img {
        width: 72px;
        height: 40px;
        object-fit: cover;
        border-radius: 8px;
        background: var(--m-matte-deep, #efebe4);
      }
      .row-title {
        font-weight: 600;
      }
      .row-meta {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        margin-top: 3px;
      }
      .note,
      .hint,
      .error,
      .empty-inline {
        font-size: 13px;
        color: var(--m-ink-muted, #948b82);
      }
      .error {
        color: #6b2f28;
      }
    `,
  ],
})
export class StudioDashboardPageComponent implements OnInit {
  ranges: StudioRange[] = ['7d', '28d', '90d'];
  range: StudioRange = '28d';
  dashboard: StudioDashboard | null = null;
  loading = false;
  error = '';
  private maxViews = 1;

  constructor(public studio: StudioService) {}

  ngOnInit(): void {
    void this.load();
  }

  setRange(r: StudioRange): void {
    if (this.range === r) return;
    this.range = r;
    void this.load();
  }

  barHeight(views: number): number {
    return Math.max(4, Math.round((views / this.maxViews) * 100));
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      this.dashboard = await this.studio.dashboard(this.range);
      this.maxViews = Math.max(1, ...this.dashboard.daily.map((d) => d.views));
    } catch (e: any) {
      this.error = e?.message ?? String(e);
      this.dashboard = null;
    } finally {
      this.loading = false;
    }
  }
}
