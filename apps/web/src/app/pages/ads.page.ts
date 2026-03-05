import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnDestroy, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { AdsService, type AdCampaignModel } from '../core/services/ads.service';
import { MediaService } from '../core/services/media.service';

@Component({
  selector: 'app-ads-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="ads-shell">
      <div class="topbar-fixed">
        <button type="button" class="icon-button ghost" (click)="goBack()">Back</button>
      </div>

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
              <strong>Creative upload</strong>
              <span>Upload a video file here. Matterya hosts it and uses that file automatically.</span>
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
              <h2>{{ editingCampaignId ? 'Edit campaign' : 'New campaign' }}</h2>
              <p>
                {{
                  editingCampaignId
                    ? 'Update campaign settings and replace the video creative at any time.'
                    : 'Upload one video creative, then activate the campaign.'
                }}
              </p>
            </div>
            <div class="composer-head-actions">
              <button
                type="button"
                class="ghost"
                *ngIf="editingCampaignId"
                [disabled]="saving"
                (click)="cancelEdit()"
              >
                Cancel
              </button>
              <button type="submit" [disabled]="saving || !newCampaign.name || !newCreative.media_url">
                {{ saving ? 'Saving...' : editingCampaignId ? 'Save changes' : 'Create' }}
              </button>
            </div>
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
            <div class="upload-row wide">
              <div class="upload-copy">
                <span>Upload creative video</span>
                <small>Upload one ad video file. The hosted URL is generated automatically.</small>
              </div>
              <label class="upload-button">
                <input
                  type="file"
                  accept="video/mp4,video/webm,video/quicktime,video/*"
                  (change)="onCreativeFileSelected($event)"
                />
                {{ uploadingCreative ? 'Uploading...' : 'Upload video' }}
              </label>
            </div>
            <div class="upload-note wide" *ngIf="creativeUploadName">
              Uploaded: {{ creativeUploadName }}
            </div>
            <div class="creative-preview wide" *ngIf="newCreative.media_url">
              <div class="preview-copy">
                <span>Creative preview</span>
                <small>This hosted file is the one used for pre-roll delivery.</small>
              </div>
              <video
                class="preview-video"
                [src]="newCreative.media_url"
                controls
                playsinline
                preload="metadata"
              ></video>
            </div>
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
                  <span
                    class="state-pill"
                    [class.live]="campaignPhase(campaign) === 'ongoing'"
                    [class.scheduled]="campaignPhase(campaign) === 'scheduled'"
                    [class.ended]="campaignPhase(campaign) === 'ended'"
                  >
                    {{ campaignPhaseLabel(campaign) }}
                  </span>
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
            <div class="campaign-timer">{{ campaignTimerText(campaign) }}</div>

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
              <button
                type="button"
                class="ghost"
                [disabled]="isCampaignBusy(campaign.id)"
                (click)="beginEdit(campaign)"
              >
                Edit
              </button>
              <button
                type="button"
                class="ghost"
                [disabled]="isCampaignBusy(campaign.id)"
                (click)="setStatus(campaign, 'draft')"
              >
                Draft
              </button>
              <button
                type="button"
                class="ghost"
                [disabled]="isCampaignBusy(campaign.id)"
                (click)="setStatus(campaign, 'active')"
              >
                Activate
              </button>
              <button
                type="button"
                class="ghost"
                [disabled]="isCampaignBusy(campaign.id)"
                (click)="setStatus(campaign, 'paused')"
              >
                Pause
              </button>
              <button
                type="button"
                class="ghost danger"
                [disabled]="isCampaignBusy(campaign.id)"
                (click)="deleteCampaign(campaign)"
              >
                {{ deletingCampaignId === campaign.id ? 'Deleting...' : 'Delete' }}
              </button>
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
      .topbar-fixed {
        position: fixed;
        top: calc(env(safe-area-inset-top) + 10px);
        right: 12px;
        z-index: 60;
        display: flex;
        align-items: center;
        justify-content: flex-end;
      }
      .topbar-fixed .icon-button.ghost {
        background: rgba(255, 255, 255, 0.94);
        border: 1px solid rgba(15, 23, 35, 0.12);
        color: #102132;
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
      .composer-head-actions {
        display: inline-flex;
        align-items: center;
        gap: 8px;
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
      .upload-row {
        border: 1px dashed rgba(15, 23, 35, 0.16);
        border-radius: 18px;
        background: #fbfcfe;
        padding: 14px;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
      }
      .upload-copy {
        display: grid;
        gap: 4px;
      }
      .upload-copy span {
        font-size: 13px;
        font-weight: 700;
        color: #304254;
      }
      .upload-copy small,
      .upload-note {
        color: #607086;
        font-size: 12px;
        line-height: 1.4;
      }
      .upload-button {
        position: relative;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-height: 44px;
        padding: 0 14px;
        border-radius: 14px;
        background: #0f1723;
        color: #fff;
        cursor: pointer;
        white-space: nowrap;
      }
      .upload-button input {
        position: absolute;
        inset: 0;
        opacity: 0;
        cursor: pointer;
      }
      .creative-preview {
        border-radius: 18px;
        background: #f7f9fc;
        padding: 14px;
        display: grid;
        gap: 10px;
      }
      .preview-copy {
        display: grid;
        gap: 4px;
      }
      .preview-copy span {
        font-size: 13px;
        font-weight: 700;
        color: #304254;
      }
      .preview-copy small {
        color: #607086;
        font-size: 12px;
        line-height: 1.4;
      }
      .preview-video {
        width: 100%;
        display: block;
        border-radius: 16px;
        background: #000;
        max-height: 280px;
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
      button.ghost.danger {
        color: #922f2f;
        background: #fdecec;
      }
      .icon-button {
        min-width: 54px;
        min-height: 48px;
        padding: 10px 14px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 8px;
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
      .campaign-timer {
        margin-top: 8px;
        color: #607086;
        font-size: 13px;
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
      .state-pill.live {
        background: #e9fff4;
        color: #0f7a47;
      }
      .state-pill.scheduled {
        background: #eef4ff;
        color: #1f4f93;
      }
      .state-pill.ended {
        background: #f5f6f8;
        color: #66768a;
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
        .topbar-fixed {
          top: calc(env(safe-area-inset-top) + 8px);
          right: 10px;
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
  creativeUploadName = '';
  uploadingCreative = false;
  countryCodesInput = '';
  private previousHtmlOverflow = '';
  private previousBodyOverflow = '';
  private initialRefreshTimer: number | null = null;
  private clockTimer: number | null = null;
  busyCampaignIds = new Set<string>();
  deletingCampaignId: string | null = null;
  nowMs = Date.now();
  editingCampaignId: string | null = null;
  editingCreativeId: string | null = null;
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

  constructor(
    private ads: AdsService,
    private router: Router,
    private media: MediaService,
    private cdr: ChangeDetectorRef
  ) {}

  ngOnInit(): void {
    this.enablePageScroll();
    void this.loadCampaigns();
    if (typeof window !== 'undefined') {
      this.clockTimer = window.setInterval(() => {
        this.nowMs = Date.now();
      }, 1000);
    }
    if (typeof window !== 'undefined') {
      this.initialRefreshTimer = window.setTimeout(() => {
        void this.loadCampaigns({ silent: true });
      }, 900);
    }
  }

  ngOnDestroy(): void {
    if (this.initialRefreshTimer) {
      window.clearTimeout(this.initialRefreshTimer);
      this.initialRefreshTimer = null;
    }
    if (this.clockTimer) {
      window.clearInterval(this.clockTimer);
      this.clockTimer = null;
    }
    this.restorePageScroll();
  }

  async loadCampaigns(options?: { silent?: boolean }): Promise<void> {
    const silent = !!options?.silent;
    if (!silent) this.loading = true;
    this.error = '';
    this.cdr.detectChanges();
    try {
      this.campaigns = await this.withTimeout(
        this.ads.myCampaigns(),
        12000,
        'Loading campaigns timed out. Pull to refresh.'
      );
      this.cdr.detectChanges();
    } catch (error: any) {
      this.error = error?.message ?? 'Failed to load campaigns.';
      this.cdr.detectChanges();
    } finally {
      if (!silent) this.loading = false;
      this.cdr.detectChanges();
    }
  }

  async createCampaign(): Promise<void> {
    if (this.saving) return;
    if (!this.newCreative.media_url) {
      this.error = 'Upload a creative video first.';
      return;
    }
    this.saving = true;
    this.error = '';
    this.success = '';
    try {
      if (this.editingCampaignId) {
        const updatedCampaign = await this.ads.updateCampaign(this.editingCampaignId, {
          name: this.newCampaign.name,
          placement: this.newCampaign.placement,
          status: this.newCampaign.status,
          target_country_codes: this.parseCountryCodes(this.countryCodesInput),
          budget_cents: this.toCents(this.newCampaign.budget_eur),
          daily_budget_cents: this.toCents(this.newCampaign.daily_budget_eur),
          start_at: this.toIsoOrNull(this.newCampaign.start_at),
          end_at: this.toIsoOrNull(this.newCampaign.end_at),
        });
        if (this.editingCreativeId) {
          await this.ads.updateCreative(this.editingCreativeId, {
            title: this.newCreative.title,
            body: this.newCreative.body,
            media_kind: 'video',
            media_url: this.newCreative.media_url,
            click_url: this.newCreative.click_url || null,
            cta_label: this.newCreative.cta_label || null,
            duration_seconds: this.newCreative.duration_seconds,
          });
        } else {
          await this.ads.createCreative(updatedCampaign.id, {
            title: this.newCreative.title,
            body: this.newCreative.body,
            media_kind: 'video',
            media_url: this.newCreative.media_url,
            click_url: this.newCreative.click_url || null,
            cta_label: this.newCreative.cta_label || null,
            duration_seconds: this.newCreative.duration_seconds,
          });
        }
        this.success = 'Campaign updated.';
      } else {
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
        this.success = 'Campaign created.';
      }
      this.resetForm();
      void this.loadCampaigns({ silent: true });
      this.cdr.detectChanges();
    } catch (error: any) {
      this.error = error?.message ?? 'Failed to create campaign.';
      this.cdr.detectChanges();
    } finally {
      this.saving = false;
      this.cdr.detectChanges();
    }
  }

  async setStatus(campaign: AdCampaignModel, status: string): Promise<void> {
    if (this.busyCampaignIds.has(campaign.id)) return;
    if ((campaign.status || '').toLowerCase() === status.toLowerCase()) {
      this.success = `Campaign already ${status}.`;
      this.error = '';
      return;
    }
    this.busyCampaignIds.add(campaign.id);
    this.error = '';
    this.success = '';
    try {
      const updated = await this.ads.updateCampaign(campaign.id, {
        name: campaign.name,
        placement: campaign.placement as 'video' | 'reel',
        status,
        target_country_codes: campaign.target_country_codes,
        budget_cents: campaign.budget_cents,
        daily_budget_cents: campaign.daily_budget_cents,
        start_at: this.toApiDate(campaign.start_at),
        end_at: this.toApiDate(campaign.end_at),
      });
      this.campaigns = this.campaigns.map((item) => (item.id === updated.id ? updated : item));
      this.success = `Campaign set to ${status}.`;
      this.error = '';
      this.cdr.detectChanges();
    } catch (error: any) {
      this.error = error?.message ?? 'Failed to update campaign.';
      this.success = '';
      this.cdr.detectChanges();
    } finally {
      this.busyCampaignIds.delete(campaign.id);
    }
  }

  async deleteCampaign(campaign: AdCampaignModel): Promise<void> {
    if (this.busyCampaignIds.has(campaign.id)) return;
    const ok = typeof window === 'undefined' ? true : window.confirm(`Delete "${campaign.name}"?`);
    if (!ok) return;
    this.busyCampaignIds.add(campaign.id);
    this.deletingCampaignId = campaign.id;
    this.error = '';
    this.success = '';
    this.cdr.detectChanges();
    try {
      const deleted = await this.ads.deleteCampaign(campaign.id);
      if (!deleted) throw new Error('Delete was not applied.');
      this.campaigns = this.campaigns.filter((item) => item.id !== campaign.id);
      this.success = 'Campaign deleted.';
      this.error = '';
      this.cdr.detectChanges();
    } catch (error: any) {
      this.error = error?.message ?? 'Failed to delete campaign.';
      this.success = '';
      this.cdr.detectChanges();
    } finally {
      this.busyCampaignIds.delete(campaign.id);
      this.deletingCampaignId = null;
      this.cdr.detectChanges();
    }
  }

  beginEdit(campaign: AdCampaignModel): void {
    const creative = campaign.creatives?.[0] ?? null;
    this.editingCampaignId = campaign.id;
    this.editingCreativeId = creative?.id ?? null;
    this.countryCodesInput = (campaign.target_country_codes || []).join(', ');
    this.newCampaign = {
      name: campaign.name || '',
      placement: (campaign.placement as 'video' | 'reel') || 'video',
      status: campaign.status || 'draft',
      budget_eur: Number(campaign.budget_cents || 0) / 100,
      daily_budget_eur: Number(campaign.daily_budget_cents || 0) / 100,
      start_at: this.toLocalDateTime(campaign.start_at),
      end_at: this.toLocalDateTime(campaign.end_at),
    };
    this.newCreative = {
      title: creative?.title || '',
      body: creative?.body || '',
      media_url: creative?.media_url || '',
      click_url: creative?.click_url || '',
      cta_label: creative?.cta_label || 'Learn more',
      duration_seconds: Number(creative?.duration_seconds || 8),
    };
    this.creativeUploadName = '';
    this.success = '';
    this.error = '';
    this.cdr.detectChanges();
  }

  cancelEdit(): void {
    this.resetForm();
    this.success = '';
    this.error = '';
    this.cdr.detectChanges();
  }

  goBack(): void {
    if (typeof window !== 'undefined' && window.history.length > 1) {
      window.history.back();
      return;
    }
    void this.router.navigate(['/globe']);
  }

  formatMoney(cents: number): string {
    const value = Number(cents ?? 0) / 100;
    return `EUR ${value.toFixed(2)}`;
  }

  async onCreativeFileSelected(event: Event): Promise<void> {
    const input = event.target as HTMLInputElement | null;
    const file = input?.files?.[0];
    if (!file) return;
    this.error = '';
    this.success = '';
    if (!String(file.type || '').startsWith('video/')) {
      this.error = 'Creative upload must be a video file.';
      if (input) input.value = '';
      this.cdr.detectChanges();
      return;
    }
    this.uploadingCreative = true;
    this.cdr.detectChanges();
    try {
      const uploaded = await this.media.uploadAdMedia(file);
      this.newCreative.media_url = uploaded.publicUrl;
      this.creativeUploadName = file.name;
      this.success = 'Creative video uploaded.';
      this.cdr.detectChanges();
    } catch (error: any) {
      this.error = error?.message ?? 'Failed to upload creative video.';
      this.cdr.detectChanges();
    } finally {
      this.uploadingCreative = false;
      if (input) input.value = '';
      this.cdr.detectChanges();
    }
  }

  isCampaignBusy(campaignId: string): boolean {
    return this.busyCampaignIds.has(campaignId);
  }

  campaignPhase(campaign: AdCampaignModel): 'scheduled' | 'ongoing' | 'ended' {
    const startMs = this.parseDateMs(campaign.start_at);
    const endMs = this.parseDateMs(campaign.end_at);
    if (endMs && this.nowMs > endMs) return 'ended';
    if (startMs && this.nowMs < startMs) return 'scheduled';
    return 'ongoing';
  }

  campaignPhaseLabel(campaign: AdCampaignModel): string {
    const phase = this.campaignPhase(campaign);
    if (phase === 'scheduled') return 'Scheduled';
    if (phase === 'ended') return 'Ended';
    return 'Ongoing';
  }

  campaignTimerText(campaign: AdCampaignModel): string {
    const startMs = this.parseDateMs(campaign.start_at);
    const endMs = this.parseDateMs(campaign.end_at);
    const phase = this.campaignPhase(campaign);
    if (phase === 'scheduled' && startMs) {
      return `Starts in ${this.formatCountdown(startMs - this.nowMs)}.`;
    }
    if (phase === 'ongoing' && endMs) {
      return `Ends in ${this.formatCountdown(endMs - this.nowMs)}.`;
    }
    if (phase === 'ended' && endMs) {
      return `Ended on ${new Date(endMs).toLocaleString()}.`;
    }
    return 'No end date set.';
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

  private toLocalDateTime(value: string | null | undefined): string {
    const ms = this.parseDateMs(value);
    if (!ms) return '';
    const date = new Date(ms);
    const pad = (n: number) => String(n).padStart(2, '0');
    const yyyy = date.getFullYear();
    const mm = pad(date.getMonth() + 1);
    const dd = pad(date.getDate());
    const hh = pad(date.getHours());
    const min = pad(date.getMinutes());
    return `${yyyy}-${mm}-${dd}T${hh}:${min}`;
  }

  private toApiDate(value: string | null | undefined): string | null {
    const raw = String(value ?? '').trim();
    if (!raw) return null;
    const epochMs = /^[0-9]{10,16}$/.test(raw) ? Number(raw) : Number.NaN;
    const date = Number.isFinite(epochMs) ? new Date(epochMs) : new Date(raw);
    return Number.isNaN(date.getTime()) ? null : date.toISOString();
  }

  private toCents(value: number): number {
    return Math.max(0, Math.round(Number(value ?? 0) * 100));
  }

  private withTimeout<T>(promise: Promise<T>, timeoutMs: number, message: string): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      let done = false;
      const timer = setTimeout(() => {
        if (done) return;
        done = true;
        reject(new Error(message));
      }, timeoutMs);
      promise.then(
        (value) => {
          if (done) return;
          done = true;
          clearTimeout(timer);
          resolve(value);
        },
        (error) => {
          if (done) return;
          done = true;
          clearTimeout(timer);
          reject(error);
        }
      );
    });
  }

  private parseDateMs(value: string | null | undefined): number | null {
    const raw = String(value ?? '').trim();
    if (!raw) return null;
    const epochMs = /^[0-9]{10,16}$/.test(raw) ? Number(raw) : Number.NaN;
    const ms = Number.isFinite(epochMs) ? epochMs : Date.parse(raw);
    return Number.isFinite(ms) ? ms : null;
  }

  private formatCountdown(ms: number): string {
    const seconds = Math.max(0, Math.floor(ms / 1000));
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const secs = seconds % 60;
    if (days > 0) return `${days}d ${hours}h ${minutes}m`;
    if (hours > 0) return `${hours}h ${minutes}m ${secs}s`;
    return `${minutes}m ${secs}s`;
  }

  private resetForm(): void {
    this.editingCampaignId = null;
    this.editingCreativeId = null;
    this.countryCodesInput = '';
    this.creativeUploadName = '';
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
