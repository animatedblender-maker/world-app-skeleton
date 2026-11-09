import { CommonModule } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { RouterLink } from '@angular/router';

import {
  StudioService,
  type StudioRange,
  type StudioVideoRow,
} from '../../core/services/studio.service';

@Component({
  selector: 'app-studio-content-page',
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <header class="head">
      <div>
        <div class="kicker">Library</div>
        <h1>Content</h1>
      </div>
      <div class="tools">
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
        <select class="sort" [value]="sort" (change)="setSort($any($event.target).value)">
          <option value="views">Views</option>
          <option value="watch">Watch time</option>
          <option value="ctr">CTR</option>
          <option value="newest">Newest</option>
        </select>
      </div>
    </header>

    <p class="error" *ngIf="error">{{ error }}</p>
    <p class="hint" *ngIf="loading && !videos.length">Loading videos…</p>
    <p class="hint" *ngIf="!loading && !videos.length && !error">No channel videos yet.</p>

    <div class="table" *ngIf="videos.length">
      <div class="thead">
        <span>Video</span>
        <span>Views</span>
        <span>Watch</span>
        <span>CTR</span>
        <span>Date</span>
      </div>
      <a class="trow" *ngFor="let v of videos" [routerLink]="['/studio/content', v.id]">
        <span class="video">
          <img *ngIf="v.thumbUrl" [src]="v.thumbUrl" alt="" />
          <span>
            <span class="title">{{ v.title || 'Untitled video' }}</span>
            <span class="sub" *ngIf="v.hubSlug">{{ v.hubSlug }}</span>
          </span>
        </span>
        <span>{{ studio.formatCount(v.views) }}</span>
        <span>{{ studio.formatWatch(v.watchMs) }}</span>
        <span>{{ studio.formatCtr(v.ctr) }}</span>
        <span>{{ v.createdAt ? (v.createdAt | date: 'mediumDate') : '—' }}</span>
      </a>
    </div>
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
      .tools {
        display: flex;
        gap: 10px;
        flex-wrap: wrap;
        align-items: center;
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
      .sort {
        border: 0.5px solid var(--m-border, #ddd8d1);
        background: var(--m-surface, #fefdfb);
        border-radius: 12px;
        padding: 8px 10px;
        color: var(--m-ink, #2c2825);
      }
      .table {
        background: var(--m-surface, #fefdfb);
        border: 0.5px solid var(--m-border, #ddd8d1);
        border-radius: 18px;
        overflow: hidden;
      }
      .thead,
      .trow {
        display: grid;
        grid-template-columns: minmax(0, 2.4fr) 0.7fr 0.8fr 0.6fr 0.9fr;
        gap: 10px;
        padding: 12px 14px;
        align-items: center;
      }
      .thead {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        border-bottom: 0.5px solid var(--m-border, #ddd8d1);
      }
      .trow {
        text-decoration: none;
        color: inherit;
        border-top: 0.5px solid var(--m-border, #ddd8d1);
      }
      .trow:hover {
        background: var(--m-matte-deep, #efebe4);
      }
      .video {
        display: flex;
        gap: 10px;
        align-items: center;
        min-width: 0;
      }
      .video img {
        width: 72px;
        height: 40px;
        object-fit: cover;
        border-radius: 8px;
        background: var(--m-matte-deep, #efebe4);
        flex-shrink: 0;
      }
      .title {
        display: block;
        font-weight: 600;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .sub {
        display: block;
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
      }
      .hint,
      .error {
        font-size: 13px;
        color: var(--m-ink-muted, #948b82);
      }
      .error {
        color: #6b2f28;
      }
      @media (max-width: 720px) {
        .thead {
          display: none;
        }
        .trow {
          grid-template-columns: 1fr;
          gap: 6px;
        }
      }
    `,
  ],
})
export class StudioContentPageComponent implements OnInit {
  ranges: StudioRange[] = ['7d', '28d', '90d'];
  range: StudioRange = '28d';
  sort = 'views';
  videos: StudioVideoRow[] = [];
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

  setSort(sort: string): void {
    this.sort = sort || 'views';
    void this.load();
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      const page = await this.studio.videos(this.range, { sort: this.sort, limit: 50 });
      this.videos = page.videos;
    } catch (e: any) {
      this.error = e?.message ?? String(e);
      this.videos = [];
    } finally {
      this.loading = false;
    }
  }
}
