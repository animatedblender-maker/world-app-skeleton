import { CommonModule } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';

import {
  StudioService,
  type StudioRange,
  type StudioVideoAnalytics,
} from '../../core/services/studio.service';

@Component({
  selector: 'app-studio-video-page',
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <a class="back" routerLink="/studio/content">← Content</a>

    <header class="head" *ngIf="analytics as a">
      <div class="title-block">
        <img *ngIf="a.video.thumbUrl" [src]="a.video.thumbUrl" alt="" />
        <div>
          <div class="kicker">Video analytics</div>
          <h1>{{ a.video.title || 'Untitled video' }}</h1>
          <div class="meta" *ngIf="a.video.createdAt">
            Published {{ a.video.createdAt | date: 'mediumDate' }}
          </div>
        </div>
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
    <p class="hint" *ngIf="loading">Loading analytics…</p>

    <ng-container *ngIf="analytics as a">
      <section class="kpis">
        <div class="kpi">
          <div class="lab">Impressions</div>
          <div class="val">{{ studio.formatCount(a.funnel.impressions) }}</div>
        </div>
        <div class="kpi">
          <div class="lab">CTR</div>
          <div class="val">{{ studio.formatCtr(a.funnel.ctr) }}</div>
        </div>
        <div class="kpi">
          <div class="lab">Views</div>
          <div class="val">{{ studio.formatCount(a.funnel.views) }}</div>
        </div>
        <div class="kpi">
          <div class="lab">Watch time</div>
          <div class="val">{{ studio.formatWatch(a.funnel.watchMs) }}</div>
        </div>
        <div class="kpi">
          <div class="lab">Completes</div>
          <div class="val">{{ studio.formatCount(a.funnel.completes) }}</div>
        </div>
        <div class="kpi">
          <div class="lab">Skips</div>
          <div class="val">{{ studio.formatCount(a.funnel.skips) }}</div>
        </div>
      </section>

      <div class="grid">
        <section class="panel">
          <div class="panel-title">Traffic sources</div>
          <div class="empty-inline" *ngIf="!a.sources.length">No source breakdown yet.</div>
          <div class="source" *ngFor="let s of a.sources">
            <span>{{ s.source }}</span>
            <span>{{ studio.formatCount(s.views) }}</span>
          </div>
        </section>

        <section class="panel">
          <div class="panel-title">Retention</div>
          <div class="empty-inline" *ngIf="!hasRetention">No progress events yet.</div>
          <div class="ret" *ngFor="let b of a.retention">
            <span>{{ b.bucket }}%</span>
            <div class="track">
              <div class="fill" [style.width.%]="b.reached * 100"></div>
            </div>
            <span>{{ (b.reached * 100).toFixed(0) }}%</span>
          </div>
        </section>
      </div>

      <section class="panel" *ngIf="a.daily.length">
        <div class="panel-title">Daily views</div>
        <div class="chart">
          <div
            class="bar"
            *ngFor="let day of a.daily"
            [style.height.%]="barHeight(day.views)"
            [title]="day.day + ': ' + day.views"
          ></div>
        </div>
      </section>

      <p class="note">{{ a.note }}</p>
    </ng-container>
  `,
  styles: [
    `
      .back {
        display: inline-block;
        margin-bottom: 14px;
        color: var(--m-ink-secondary, #5c564f);
        text-decoration: none;
        font-size: 13px;
      }
      .head {
        display: flex;
        justify-content: space-between;
        gap: 16px;
        flex-wrap: wrap;
        margin-bottom: 18px;
      }
      .title-block {
        display: flex;
        gap: 14px;
        align-items: flex-start;
        min-width: 0;
      }
      .title-block img {
        width: 128px;
        height: 72px;
        object-fit: cover;
        border-radius: 12px;
        background: var(--m-matte-deep, #efebe4);
      }
      .kicker {
        font-size: 11px;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--m-ink-muted, #948b82);
      }
      h1 {
        margin: 4px 0 0;
        font-size: 24px;
        letter-spacing: -0.02em;
      }
      .meta {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        margin-top: 4px;
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
        grid-template-columns: repeat(auto-fill, minmax(130px, 1fr));
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
        font-size: 20px;
        font-weight: 650;
      }
      .grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
        gap: 12px;
        margin-bottom: 12px;
      }
      .panel-title {
        font-weight: 650;
        margin-bottom: 10px;
      }
      .source,
      .ret {
        display: grid;
        grid-template-columns: 1fr auto;
        gap: 10px;
        padding: 8px 0;
        border-top: 0.5px solid var(--m-border, #ddd8d1);
        font-size: 13px;
      }
      .ret {
        grid-template-columns: 40px 1fr 40px;
        align-items: center;
      }
      .track {
        height: 8px;
        border-radius: 999px;
        background: var(--m-matte-deep, #efebe4);
        overflow: hidden;
      }
      .fill {
        height: 100%;
        background: var(--m-ink, #2c2825);
      }
      .chart {
        display: flex;
        align-items: flex-end;
        gap: 3px;
        height: 110px;
      }
      .bar {
        flex: 1;
        min-width: 4px;
        background: var(--m-ink, #2c2825);
        opacity: 0.78;
        border-radius: 4px 4px 0 0;
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
export class StudioVideoPageComponent implements OnInit {
  ranges: StudioRange[] = ['7d', '28d', '90d'];
  range: StudioRange = '28d';
  analytics: StudioVideoAnalytics | null = null;
  loading = false;
  error = '';
  hasRetention = false;
  private videoId = '';
  private maxViews = 1;

  constructor(
    public studio: StudioService,
    private route: ActivatedRoute
  ) {}

  ngOnInit(): void {
    this.videoId = String(this.route.snapshot.paramMap.get('id') || '').trim();
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
    if (!this.videoId) {
      this.error = 'Missing video id.';
      return;
    }
    this.loading = true;
    this.error = '';
    try {
      this.analytics = await this.studio.videoAnalytics(this.videoId, this.range);
      this.maxViews = Math.max(1, ...this.analytics.daily.map((d) => d.views));
      this.hasRetention = this.analytics.retention.some((b) => b.reached > 0);
    } catch (e: any) {
      this.error = e?.message ?? String(e);
      this.analytics = null;
    } finally {
      this.loading = false;
    }
  }
}
