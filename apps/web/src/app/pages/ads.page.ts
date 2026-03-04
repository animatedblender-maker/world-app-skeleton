import { CommonModule } from '@angular/common';
import { Component, OnDestroy, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AdsService, type AdCampaignModel } from '../core/services/ads.service';

@Component({
  selector: 'app-ads-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="ads-shell">
      <section class="ads-panel">
        <div class="hero">
          <div>
            <div class="eyebrow">Matterya Ads</div>
            <h1>Advertiser dashboard</h1>
            <p>
              MVP setup for direct campaigns. Create a campaign, attach one hosted video creative,
              then it can serve as pre-roll on videos and reels.
            </p>
          </div>
        </div>

        <section class="manual">
          <div class="manual-head">
            <h2>Field guide</h2>
            <p>Quick manual for what each campaign field does in the current MVP.</p>
          </div>
          <div class="manual-grid">
            <article class="manual-item">
              <strong>Name</strong>
              <span>The internal campaign name you use to identify the ad.</span>
            </article>
            <article class="manual-item">
              <strong>Placement</strong>
              <span><b>Video</b> serves before normal videos. <b>Reel</b> serves before reels.</span>
            </article>
            <article class="manual-item">
              <strong>Status</strong>
              <span><b>Draft</b> does not serve, <b>Active</b> can serve, <b>Paused</b> stops delivery.</span>
            </article>
            <article class="manual-item">
              <strong>Target countries</strong>
              <span>Comma-separated ISO codes like <b>US, DE, FR</b>. Empty means global.</span>
            </article>
            <article class="manual-item">
              <strong>Total budget</strong>
              <span>Entered in euros. Stored internally in cents for billing-safe math later.</span>
            </article>
            <article class="manual-item">
              <strong>Daily budget</strong>
              <span>Entered in euros. Used now for simple pacing so one campaign does not dominate requests.</span>
            </article>
            <article class="manual-item">
              <strong>Start / End</strong>
              <span>Optional schedule window for when the campaign is eligible to run.</span>
            </article>
            <article class="manual-item">
              <strong>Creative video URL</strong>
              <span>Required for the current MVP. It must be a direct hosted ad video URL.</span>
            </article>
            <article class="manual-item">
              <strong>Creative title / Ad copy</strong>
              <span>Optional text displayed on top of the pre-roll player.</span>
            </article>
            <article class="manual-item">
              <strong>CTA label / Click URL</strong>
              <span>If a click URL exists, the ad shows a button and click analytics are logged.</span>
            </article>
            <article class="manual-item">
              <strong>Duration</strong>
              <span>The ad length in seconds. Skip becomes available after a short delay.</span>
            </article>
          </div>
        </section>

        <form class="composer" (ngSubmit)="createCampaign()" #campaignForm="ngForm">
          <div class="composer-head">
            <div>
              <h2>New campaign</h2>
              <p>Hosted creative URL for now. Billing and uploads come later.</p>
            </div>
            <button type="submit" [disabled]="saving || !newCampaign.name || !newCreative.media_url">
              {{ saving ? 'Saving...' : 'Create' }}
            </button>
          </div>

          <div class="grid">
            <label>
              <span>Name</span>
              <input name="name" [(ngModel)]="newCampaign.name" required />
            </label>
            <label>
              <span>Placement</span>
              <select name="placement" [(ngModel)]="newCampaign.placement">
                <option value="video">Video</option>
                <option value="reel">Reel</option>
              </select>
            </label>
            <label>
              <span>Status</span>
              <select name="status" [(ngModel)]="newCampaign.status">
                <option value="draft">Draft</option>
                <option value="active">Active</option>
                <option value="paused">Paused</option>
              </select>
            </label>
            <label>
              <span>Target countries</span>
              <input
                name="countries"
                [(ngModel)]="countryCodesInput"
                placeholder="US, DE, FR"
              />
            </label>
            <label>
              <span>Total budget (EUR)</span>
              <input
                type="number"
                min="0"
                step="0.01"
                name="budget"
                [(ngModel)]="newCampaign.budget_eur"
              />
            </label>
            <label>
              <span>Daily budget (EUR)</span>
              <input
                type="number"
                min="0"
                step="0.01"
                name="dailyBudget"
                [(ngModel)]="newCampaign.daily_budget_eur"
              />
            </label>
            <label>
              <span>Start</span>
              <input type="datetime-local" name="startAt" [(ngModel)]="newCampaign.start_at" />
            </label>
            <label>
              <span>End</span>
              <input type="datetime-local" name="endAt" [(ngModel)]="newCampaign.end_at" />
            </label>
            <label class="wide">
              <span>Creative video URL</span>
              <input
                name="mediaUrl"
                [(ngModel)]="newCreative.media_url"
                placeholder="https://..."
                required
              />
            </label>
            <label>
              <span>Creative title</span>
              <input name="creativeTitle" [(ngModel)]="newCreative.title" />
            </label>
            <label>
              <span>CTA label</span>
              <input name="ctaLabel" [(ngModel)]="newCreative.cta_label" placeholder="Learn more" />
            </label>
            <label class="wide">
              <span>Click URL</span>
              <input name="clickUrl" [(ngModel)]="newCreative.click_url" placeholder="https://..." />
            </label>
            <label>
              <span>Duration (sec)</span>
              <input
                type="number"
                min="3"
                max="30"
                name="duration"
                [(ngModel)]="newCreative.duration_seconds"
              />
            </label>
            <label class="wide">
              <span>Ad copy</span>
              <textarea
                name="body"
                rows="3"
                [(ngModel)]="newCreative.body"
                placeholder="Optional ad copy shown in the pre-roll overlay"
              ></textarea>
            </label>
          </div>
          <div class="status success" *ngIf="success">{{ success }}</div>
          <div class="status error" *ngIf="error">{{ error }}</div>
        </form>

        <section class="list">
          <div class="list-head">
            <h2>Campaigns</h2>
            <button type="button" class="ghost" (click)="loadCampaigns()" [disabled]="loading">
              {{ loading ? 'Refreshing...' : 'Refresh' }}
            </button>
          </div>

          <div class="empty" *ngIf="!loading && !campaigns.length">No campaigns yet.</div>

          <article class="campaign-card" *ngFor="let campaign of campaigns">
            <div class="campaign-top">
              <div>
                <h3>{{ campaign.name }}</h3>
                <div class="meta">
                  <span>{{ campaign.placement }}</span>
                  <span>{{ campaign.status }}</span>
                  <span *ngIf="campaign.target_country_codes.length">
                    {{ campaign.target_country_codes.join(', ') }}
                  </span>
                </div>
              </div>
              <div class="stats">
                <div><strong>{{ campaign.impression_count }}</strong><span>Impressions</span></div>
                <div><strong>{{ campaign.click_count }}</strong><span>Clicks</span></div>
              </div>
            </div>

            <div class="budget-row">
              <span>Total {{ formatMoney(campaign.budget_cents) }}</span>
              <span>Daily {{ formatMoney(campaign.daily_budget_cents) }}</span>
              <span *ngIf="campaign.start_at">Starts {{ campaign.start_at | date: 'medium' }}</span>
              <span *ngIf="campaign.end_at">Ends {{ campaign.end_at | date: 'medium' }}</span>
            </div>

            <div class="creative-list">
              <div class="creative" *ngFor="let creative of campaign.creatives">
                <div class="creative-copy">
                  <strong>{{ creative.title || 'Creative' }}</strong>
                  <span>{{ creative.body || creative.media_url }}</span>
                </div>
                <div class="creative-meta">
                  <span>{{ creative.media_kind }}</span>
                  <span>{{ creative.duration_seconds }}s</span>
                </div>
              </div>
            </div>

            <div class="campaign-actions">
              <button type="button" class="ghost" (click)="setStatus(campaign, 'draft')">Draft</button>
              <button type="button" class="ghost" (click)="setStatus(campaign, 'active')">Activate</button>
              <button type="button" class="ghost" (click)="setStatus(campaign, 'paused')">Pause</button>
            </div>
          </article>
        </section>
      </section>
    </div>
  `,
  styles: [
    `
      :host {
        display: block;
        min-height: 100dvh;
        background: linear-gradient(180deg, #f7f8fb 0%, #eef2f7 100%);
        color: #0f1723;
        overflow-y: auto;
      }
      .ads-shell {
        min-height: 100dvh;
        box-sizing: border-box;
        padding: calc(20px + env(safe-area-inset-top)) 16px calc(124px + env(safe-area-inset-bottom));
      }
      .ads-panel {
        max-width: 980px;
        margin: 0 auto;
        display: grid;
        gap: 18px;
      }
      .hero,
      .manual,
      .composer,
      .list,
      .campaign-card {
        background: #fff;
        border: 1px solid rgba(15, 23, 35, 0.08);
        border-radius: 24px;
        box-shadow: 0 12px 30px rgba(15, 23, 35, 0.06);
      }
      .hero {
        padding: 24px;
      }
      .eyebrow {
        font-size: 12px;
        letter-spacing: 0.2em;
        text-transform: uppercase;
        color: #607086;
      }
      h1, h2, h3, p {
        margin: 0;
      }
      h1 {
        margin-top: 8px;
        font-size: 30px;
      }
      .hero p {
        margin-top: 10px;
        max-width: 700px;
        color: #607086;
        line-height: 1.5;
      }
      .manual,
      .composer,
      .list {
        padding: 20px;
      }
      .manual-head p {
        margin-top: 6px;
        color: #607086;
      }
      .manual-grid {
        margin-top: 16px;
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 12px;
      }
      .manual-item {
        border-radius: 18px;
        background: #f7f9fc;
        padding: 14px 16px;
        display: grid;
        gap: 6px;
      }
      .manual-item strong {
        font-size: 13px;
        letter-spacing: 0.04em;
        text-transform: uppercase;
      }
      .manual-item span {
        color: #607086;
        font-size: 13px;
        line-height: 1.45;
      }
      .composer-head,
      .list-head,
      .campaign-top,
      .campaign-actions {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 12px;
      }
      .composer-head p,
      .list-head p {
        margin-top: 4px;
        color: #607086;
      }
      .grid {
        margin-top: 18px;
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 14px;
      }
      label {
        display: grid;
        gap: 8px;
        font-size: 13px;
        font-weight: 700;
        color: #304254;
      }
      label.wide {
        grid-column: 1 / -1;
      }
      input,
      select,
      textarea,
      button {
        font: inherit;
      }
      input,
      select,
      textarea {
        border: 1px solid rgba(15, 23, 35, 0.12);
        border-radius: 16px;
        padding: 12px 14px;
        background: #fbfcfe;
        color: #0f1723;
        outline: none;
      }
      textarea {
        resize: vertical;
      }
      input:focus,
      select:focus,
      textarea:focus {
        border-color: rgba(35, 136, 255, 0.55);
        box-shadow: 0 0 0 3px rgba(35, 136, 255, 0.12);
      }
      button {
        border: 0;
        border-radius: 16px;
        background: #0f1723;
        color: #fff;
        padding: 12px 16px;
        font-weight: 700;
        cursor: pointer;
      }
      button.ghost {
        background: #edf2f8;
        color: #203041;
      }
      button:disabled {
        opacity: 0.6;
        cursor: default;
      }
      .status {
        margin-top: 14px;
        border-radius: 14px;
        padding: 12px 14px;
        font-size: 13px;
      }
      .status.success {
        background: #e9fff4;
        color: #0f7a47;
      }
      .status.error {
        background: #fff1f1;
        color: #b33434;
      }
      .list {
        display: grid;
        gap: 14px;
      }
      .empty {
        color: #607086;
        font-size: 14px;
      }
      .campaign-card {
        padding: 18px;
      }
      .meta,
      .budget-row,
      .creative-meta {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
      }
      .meta span,
      .budget-row span,
      .creative-meta span {
        border-radius: 999px;
        background: #edf2f8;
        padding: 6px 10px;
        font-size: 12px;
        color: #486074;
      }
      .stats {
        display: flex;
        gap: 12px;
      }
      .stats div {
        min-width: 88px;
        border-radius: 18px;
        background: #f7f9fc;
        padding: 10px 12px;
        display: grid;
        gap: 4px;
        text-align: right;
      }
      .stats strong {
        font-size: 20px;
      }
      .stats span {
        font-size: 11px;
        color: #607086;
        text-transform: uppercase;
        letter-spacing: 0.08em;
      }
      .budget-row {
        margin-top: 12px;
      }
      .creative-list {
        margin-top: 14px;
        display: grid;
        gap: 10px;
      }
      .creative {
        border-radius: 18px;
        background: #f7f9fc;
        padding: 12px 14px;
        display: flex;
        justify-content: space-between;
        gap: 12px;
      }
      .creative-copy {
        display: grid;
        gap: 4px;
      }
      .creative-copy span {
        color: #607086;
        font-size: 13px;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .campaign-actions {
        margin-top: 14px;
      }
      @media (max-width: 720px) {
        .manual-grid,
        .grid {
          grid-template-columns: 1fr;
        }
        label.wide {
          grid-column: auto;
        }
        .campaign-top,
        .campaign-actions,
        .composer-head,
        .list-head {
          flex-direction: column;
        }
        .stats {
          width: 100%;
        }
        .stats div {
          flex: 1;
          text-align: left;
        }
        .creative {
          flex-direction: column;
        }
      }
    `,
  ],
})
export class AdsPageComponent implements OnInit, OnDestroy {
  campaigns: AdCampaignModel[] = [];
  loading = false;
  saving = false;
  error = '';
  success = '';
  countryCodesInput = '';
  private previousHtmlOverflow = '';
  private previousBodyOverflow = '';
  newCampaign = {
    name: '',
    placement: 'video' as 'video' | 'reel',
    status: 'draft',
    budget_eur: 0,
    daily_budget_eur: 0,
    start_at: '',
    end_at: '',
  };
  newCreative = {
    title: '',
    body: '',
    media_url: '',
    click_url: '',
    cta_label: 'Learn more',
    duration_seconds: 8,
  };

  constructor(private ads: AdsService) {}

  ngOnInit(): void {
    this.enablePageScroll();
    void this.loadCampaigns();
  }

  ngOnDestroy(): void {
    this.restorePageScroll();
  }

  async loadCampaigns(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      this.campaigns = await this.ads.myCampaigns();
    } catch (error: any) {
      this.error = error?.message ?? 'Failed to load campaigns.';
    } finally {
      this.loading = false;
    }
  }

  async createCampaign(): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    this.error = '';
    this.success = '';
    try {
      const campaign = await this.ads.createCampaign({
        name: this.newCampaign.name,
        placement: this.newCampaign.placement,
        status: this.newCampaign.status,
        target_country_codes: this.parseCountryCodes(this.countryCodesInput),
        budget_cents: this.toCents(this.newCampaign.budget_eur),
        daily_budget_cents: this.toCents(this.newCampaign.daily_budget_eur),
        start_at: this.toIsoOrNull(this.newCampaign.start_at),
        end_at: this.toIsoOrNull(this.newCampaign.end_at),
      });
      await this.ads.createCreative(campaign.id, {
        title: this.newCreative.title,
        body: this.newCreative.body,
        media_kind: 'video',
        media_url: this.newCreative.media_url,
        click_url: this.newCreative.click_url || null,
        cta_label: this.newCreative.cta_label || null,
        duration_seconds: this.newCreative.duration_seconds,
      });
      this.resetForm();
      this.success = 'Campaign created.';
      await this.loadCampaigns();
    } catch (error: any) {
      this.error = error?.message ?? 'Failed to create campaign.';
    } finally {
      this.saving = false;
    }
  }

  async setStatus(campaign: AdCampaignModel, status: string): Promise<void> {
    try {
      const updated = await this.ads.updateCampaign(campaign.id, {
        name: campaign.name,
        placement: campaign.placement as 'video' | 'reel',
        status,
        target_country_codes: campaign.target_country_codes,
        budget_cents: campaign.budget_cents,
        daily_budget_cents: campaign.daily_budget_cents,
        start_at: campaign.start_at,
        end_at: campaign.end_at,
      });
      this.campaigns = this.campaigns.map((item) => (item.id === updated.id ? updated : item));
    } catch (error: any) {
      this.error = error?.message ?? 'Failed to update campaign.';
    }
  }

  formatMoney(cents: number): string {
    const value = Number(cents ?? 0) / 100;
    return `EUR ${value.toFixed(2)}`;
  }

  private parseCountryCodes(raw: string): string[] {
    return String(raw || '')
      .split(',')
      .map((item) => item.trim().toUpperCase())
      .filter(Boolean);
  }

  private toIsoOrNull(value: string): string | null {
    const trimmed = String(value || '').trim();
    if (!trimmed) return null;
    const date = new Date(trimmed);
    return Number.isNaN(date.getTime()) ? null : date.toISOString();
  }

  private toCents(value: number): number {
    return Math.max(0, Math.round(Number(value ?? 0) * 100));
  }

  private resetForm(): void {
    this.countryCodesInput = '';
    this.newCampaign = {
      name: '',
      placement: 'video',
      status: 'draft',
      budget_eur: 0,
      daily_budget_eur: 0,
      start_at: '',
      end_at: '',
    };
    this.newCreative = {
      title: '',
      body: '',
      media_url: '',
      click_url: '',
      cta_label: 'Learn more',
      duration_seconds: 8,
    };
  }

  private enablePageScroll(): void {
    if (typeof document === 'undefined') return;
    this.previousHtmlOverflow = document.documentElement.style.overflowY || '';
    this.previousBodyOverflow = document.body.style.overflowY || '';
    document.documentElement.style.overflowY = 'auto';
    document.body.style.overflowY = 'auto';
  }

  private restorePageScroll(): void {
    if (typeof document === 'undefined') return;
    document.documentElement.style.overflowY = this.previousHtmlOverflow;
    document.body.style.overflowY = this.previousBodyOverflow;
  }
}
