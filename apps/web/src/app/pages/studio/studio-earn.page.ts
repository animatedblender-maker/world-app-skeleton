import { CommonModule } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { RouterLink } from '@angular/router';

import {
  StudioService,
  type StudioEarn,
  type StudioRange,
} from '../../core/services/studio.service';

@Component({
  selector: 'app-studio-earn-page',
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <header class="head">
      <div>
        <div class="kicker">Monetization</div>
        <h1>Earn</h1>
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
    <p class="hint" *ngIf="loading">Loading Earn…</p>
    <p class="hint" *ngIf="actionMsg">{{ actionMsg }}</p>

    <ng-container *ngIf="earn as e">
      <section class="status" [attr.data-status]="e.status">
        <div class="status-kicker">{{ e.payoutsLive ? 'Live' : 'Ledger live · withdrawals closed' }}</div>
        <h2>{{ e.statusLabel }}</h2>
        <p>{{ e.statusDetail }}</p>
        <button
          type="button"
          class="btn"
          *ngIf="e.monetization?.canApply"
          [disabled]="acting"
          (click)="apply()"
        >
          {{ acting ? 'Applying…' : 'Apply for Earn' }}
        </button>
      </section>

      <section class="kpis">
        <div class="kpi highlight">
          <div class="lab">Available balance</div>
          <div class="val">{{ studio.formatMoneyUsd(e.balance?.availableUsd) }}</div>
          <div class="sub">
            Pending {{ studio.formatMoneyUsd(e.balance?.pendingUsd) }} · Min payout
            {{ studio.formatMoneyUsd(e.monetization?.minPayoutUsd) }}
          </div>
        </div>
        <div class="kpi">
          <div class="lab">Lifetime earned</div>
          <div class="val">{{ studio.formatMoneyUsd(e.balance?.lifetimeEarnedUsd) }}</div>
        </div>
        <div class="kpi">
          <div class="lab">Lifetime paid</div>
          <div class="val">{{ studio.formatMoneyUsd(e.balance?.lifetimePaidUsd) }}</div>
        </div>
        <div class="kpi">
          <div class="lab">Views</div>
          <div class="val">{{ studio.formatCount(e.metrics.views) }}</div>
        </div>
        <div class="kpi">
          <div class="lab">Impressions</div>
          <div class="val">{{ studio.formatCount(e.metrics.impressions) }}</div>
        </div>
        <div class="kpi">
          <div class="lab">Watch hours</div>
          <div class="val">{{ e.metrics.watchHours }}</div>
        </div>
      </section>

      <section class="panel">
        <div class="panel-title">{{ e.estimate.label }}</div>
        <div class="estimate-val">{{ studio.formatMoneyUsd(e.estimate.estimatedRevenueUsd) }}</div>
        <div class="meta">
          Stub RPM {{ studio.formatMoneyUsd(e.estimate.rpmUsd) }} · {{ e.estimate.basis }}
        </div>
        <p class="disclaimer">{{ e.estimate.disclaimer }}</p>
      </section>

      <section class="panel">
        <div class="panel-title">Eligibility checklist</div>
        <div class="check" *ngFor="let item of e.checklist" [class.met]="item.met">
          <div class="check-mark">{{ item.met ? '✓' : '○' }}</div>
          <div>
            <div class="check-label">{{ item.label }}</div>
            <div class="check-detail">{{ item.detail }}</div>
          </div>
        </div>
      </section>

      <section class="panel" *ngIf="e.payouts?.length">
        <div class="panel-title">Payout history</div>
        <div class="row" *ngFor="let p of e.payouts">
          <div>
            <div class="check-label">{{ studio.formatMoneyUsd(p.amountUsd) }}</div>
            <div class="check-detail">{{ p.state }} · {{ p.createdAt | date: 'mediumDate' }}</div>
          </div>
        </div>
      </section>

      <section class="panel" *ngIf="e.ledger?.length">
        <div class="panel-title">Ledger</div>
        <div class="row" *ngFor="let row of e.ledger">
          <div>
            <div class="check-label">
              {{ row.entryType }} · {{ studio.formatMoneyUsd(row.amountUsd) }}
            </div>
            <div class="check-detail">
              {{ row.memo || '—' }} · {{ row.createdAt | date: 'mediumDate' }}
            </div>
          </div>
        </div>
      </section>

      <section class="panel" *ngIf="!e.payouts?.length && !e.ledger?.length">
        <div class="panel-title">Payouts &amp; ledger</div>
        <p>No payouts or ledger credits yet. Balances stay at $0 until ads revshare credits your channel.</p>
      </section>

      <div class="grid">
        <section class="panel">
          <div class="panel-title">Paid promotion</div>
          <p>{{ e.promotion.note }}</p>
          <div class="meta" *ngIf="e.promotion.disclosedCount > 0">
            {{ e.promotion.disclosedCount }} disclosed in your library
          </div>
        </section>

        <section class="panel">
          <div class="panel-title">{{ e.ads.label }}</div>
          <p>{{ e.ads.detail }}</p>
          <a class="btn" [routerLink]="e.ads.path">Open Ads</a>
        </section>
      </div>

      <p class="note">{{ e.note }}</p>
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
      .error {
        color: #a33;
        margin-bottom: 12px;
      }
      .hint {
        color: var(--m-ink-muted, #948b82);
      }
      .status {
        background: var(--m-surface, #fefdfb);
        border: 0.5px solid var(--m-border, #ddd8d1);
        border-radius: 18px;
        padding: 18px 20px;
        margin-bottom: 16px;
      }
      .status[data-status='ready_when_live'],
      .status[data-status='live'],
      .status[data-status='approved'] {
        border-color: #2c2825;
      }
      .status-kicker {
        font-size: 11px;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--m-ink-muted, #948b82);
      }
      .status h2 {
        margin: 6px 0 8px;
        font-size: 22px;
        letter-spacing: -0.02em;
      }
      .status p {
        margin: 0 0 12px;
        color: var(--m-ink-secondary, #5c564f);
        line-height: 1.45;
      }
      .kpis {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
        gap: 12px;
        margin-bottom: 10px;
      }
      .kpi {
        background: var(--m-surface, #fefdfb);
        border: 0.5px solid var(--m-border, #ddd8d1);
        border-radius: 16px;
        padding: 14px 16px;
      }
      .kpi.highlight {
        background: var(--m-ink, #2c2825);
        color: var(--m-paper, #f8f6f2);
        border-color: transparent;
      }
      .kpi.highlight .lab,
      .kpi.highlight .sub {
        color: rgba(248, 246, 242, 0.72);
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
      .sub {
        margin-top: 6px;
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
      }
      .estimate-val {
        font-size: 22px;
        font-weight: 650;
        letter-spacing: -0.02em;
        margin-bottom: 6px;
      }
      .disclaimer {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        margin: 10px 0 0;
        line-height: 1.45;
      }
      .panel {
        background: var(--m-surface, #fefdfb);
        border: 0.5px solid var(--m-border, #ddd8d1);
        border-radius: 18px;
        padding: 16px;
        margin-bottom: 16px;
      }
      .panel-title {
        font-weight: 650;
        margin-bottom: 12px;
      }
      .panel p {
        margin: 0 0 12px;
        color: var(--m-ink-secondary, #5c564f);
        line-height: 1.45;
      }
      .check,
      .row {
        display: flex;
        gap: 12px;
        padding: 10px 0;
        border-top: 0.5px solid var(--m-border, #ddd8d1);
      }
      .check:first-of-type,
      .row:first-of-type {
        border-top: none;
        padding-top: 0;
      }
      .check-mark {
        width: 22px;
        height: 22px;
        border-radius: 999px;
        display: grid;
        place-items: center;
        font-size: 12px;
        font-weight: 700;
        background: var(--m-matte-deep, #efebe4);
        color: var(--m-ink-muted, #948b82);
        flex-shrink: 0;
      }
      .check.met .check-mark {
        background: var(--m-ink, #2c2825);
        color: var(--m-paper, #f8f6f2);
      }
      .check-label {
        font-weight: 600;
      }
      .check-detail {
        margin-top: 2px;
        font-size: 13px;
        color: var(--m-ink-muted, #948b82);
      }
      .grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
        gap: 12px;
      }
      .btn {
        display: inline-block;
        text-decoration: none;
        background: var(--m-ink, #2c2825);
        color: var(--m-paper, #f8f6f2);
        border: none;
        border-radius: 999px;
        padding: 10px 14px;
        font-weight: 600;
        font-size: 13px;
        cursor: pointer;
      }
      .btn:disabled {
        opacity: 0.55;
        cursor: default;
      }
      .meta {
        font-size: 13px;
        color: var(--m-ink-muted, #948b82);
      }
      .note {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        margin-top: 8px;
      }
    `,
  ],
})
export class StudioEarnPageComponent implements OnInit {
  ranges: StudioRange[] = ['7d', '28d', '90d'];
  range: StudioRange = '28d';
  earn: StudioEarn | null = null;
  loading = true;
  acting = false;
  error = '';
  actionMsg = '';

  constructor(public studio: StudioService) {}

  ngOnInit(): void {
    void this.load();
  }

  setRange(range: StudioRange): void {
    if (this.range === range) return;
    this.range = range;
    void this.load();
  }

  async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      this.earn = await this.studio.earn(this.range);
    } catch (e: any) {
      this.earn = null;
      this.error = e?.message === 'channel_required' ? 'Create a Hubs channel to open Earn.' : String(e?.message || e);
    } finally {
      this.loading = false;
    }
  }

  async apply(): Promise<void> {
    if (this.acting) return;
    this.acting = true;
    this.actionMsg = '';
    this.error = '';
    try {
      await this.studio.applyEarn();
      this.actionMsg = 'Application submitted.';
      await this.load();
    } catch (e: any) {
      this.error = String(e?.message || e);
    } finally {
      this.acting = false;
    }
  }
}
