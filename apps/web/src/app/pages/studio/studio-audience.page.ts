import { CommonModule } from '@angular/common';
import { Component, OnInit } from '@angular/core';

import {
  StudioService,
  type StudioDashboard,
  type StudioRange,
} from '../../core/services/studio.service';

@Component({
  selector: 'app-studio-audience-page',
  standalone: true,
  imports: [CommonModule],
  template: `
    <header class="head">
      <div>
        <div class="kicker">People</div>
        <h1>Audience</h1>
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
    <p class="hint" *ngIf="loading">Loading audience…</p>

    <ng-container *ngIf="dashboard as d">
      <section class="kpis">
        <div class="kpi">
          <div class="lab">Subscribers</div>
          <div class="val">{{ studio.formatCount(d.kpis.subscribers) }}</div>
        </div>
        <div class="kpi">
          <div class="lab">Views</div>
          <div class="val">{{ studio.formatCount(d.kpis.views) }}</div>
        </div>
        <div class="kpi">
          <div class="lab">Likes</div>
          <div class="val">{{ studio.formatCount(d.kpis.likes) }}</div>
        </div>
        <div class="kpi">
          <div class="lab">Comments</div>
          <div class="val">{{ studio.formatCount(d.kpis.comments) }}</div>
        </div>
      </section>

      <section class="panel">
        <div class="panel-title">Coming next</div>
        <p>
          Deeper audience (returning vs new, country affinity, follow-after-watch) lands with the
          ranking deepen pass. Today’s numbers are organic engagement on your Hubs videos.
        </p>
      </section>
    </ng-container>
  `,
  styles: [
    `
      .head {
        display: flex;
        justify-content: space-between;
        gap: 16px;
        flex-wrap: wrap;
        margin-bottom: 18px;
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
        margin-bottom: 16px;
      }
      .kpi,
      .panel {
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
      }
      .panel-title {
        font-weight: 650;
        margin-bottom: 8px;
      }
      .panel p {
        margin: 0;
        color: var(--m-ink-secondary, #5c564f);
        line-height: 1.5;
        font-size: 14px;
      }
      .hint,
      .error {
        font-size: 13px;
        color: var(--m-ink-muted, #948b82);
      }
      .error {
        color: #6b2f28;
      }
    `,
  ],
})
export class StudioAudiencePageComponent implements OnInit {
  ranges: StudioRange[] = ['7d', '28d', '90d'];
  range: StudioRange = '28d';
  dashboard: StudioDashboard | null = null;
  loading = false;
  error = '';

  constructor(public studio: StudioService) {}

  ngOnInit(): void {
    void this.load();
  }

  setRange(r: StudioRange): void {
    if (this.range === r) return;
    this.range = r;
    void this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      this.dashboard = await this.studio.dashboard(this.range);
    } catch (e: any) {
      this.error = e?.message ?? String(e);
      this.dashboard = null;
    } finally {
      this.loading = false;
    }
  }
}
