import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';

import { BottomTabsComponent } from '../components/bottom-tabs.component';
import type { CountryPost } from '../core/models/post.model';
import { AuthService } from '../core/services/auth.service';
import { FollowService } from '../core/services/follow.service';
import { resolveAvatarUrl, resolveMediaUrl } from '../core/utils/media-url.util';
import { HubsCatalogService, type HubsChannel } from '../hubs/hubs-catalog.service';
import { HubsEngagementService } from '../hubs/hubs-engagement.service';
import { HubsPlaybackService } from '../hubs/hubs-playback.service';

@Component({
  selector: 'app-hubs-channel-page',
  standalone: true,
  imports: [CommonModule, BottomTabsComponent],
  template: `
    <div class="channel-shell" *ngIf="channel as c; else stateTpl">
      <div class="banner">
        <button type="button" class="back" (click)="back()" aria-label="Back">←</button>
        <img *ngIf="bannerThumb" class="banner-img" [src]="bannerThumb" alt="" />
      </div>
      <div class="head">
        <div class="avatar">
          <img *ngIf="avatar" [src]="avatar" alt="" />
          <span *ngIf="!avatar">{{ c.title.slice(0, 2).toUpperCase() }}</span>
        </div>
        <div class="info">
          <div class="title">{{ c.title }}</div>
          <div class="sub" *ngIf="c.handle">{{ c.handle }}</div>
          <div class="stats">
            {{ c.videoCount }} videos
            <span *ngIf="c.reelCount"> · {{ c.reelCount }} Sparks</span>
            · {{ catalog.formatViews(c.totalViews) }}
          </div>
        </div>
        <button
          type="button"
          class="follow"
          *ngIf="canFollow"
          (click)="toggleFollow()"
          [class.on]="isFollowing"
        >
          {{ isFollowing ? 'Following' : 'Follow' }}
        </button>
      </div>

      <div class="tabs">
        <button type="button" [class.active]="tab === 'videos'" (click)="tab = 'videos'">Videos</button>
        <button
          type="button"
          *ngIf="c.reelCount"
          [class.active]="tab === 'reels'"
          (click)="tab = 'reels'"
        >
          Sparks
        </button>
        <button type="button" [class.active]="tab === 'about'" (click)="tab = 'about'">About</button>
      </div>

      <div class="list" *ngIf="tab === 'videos'">
        <button
          type="button"
          class="row"
          *ngFor="let p of c.videos; trackBy: trackById"
          (click)="openVideo(p)"
        >
          <div class="thumb"><img *ngIf="thumb(p)" [src]="thumb(p)" alt="" /></div>
          <div class="meta">
            <div class="v-title">{{ catalog.displayHeadline(p) }}</div>
            <div class="v-sub">{{ catalog.formatViews(p.view_count || 0) }}</div>
          </div>
        </button>
        <div class="empty" *ngIf="!c.videos.length">No videos yet.</div>
      </div>

      <div class="sparks-grid" *ngIf="tab === 'reels'">
        <button
          type="button"
          class="spark"
          *ngFor="let p of c.reels; trackBy: trackById"
          (click)="openVideo(p)"
        >
          <img *ngIf="thumb(p)" [src]="thumb(p)" alt="" />
        </button>
      </div>

      <div class="about" *ngIf="tab === 'about'">
        <p>Channel on Matterya Hubs.</p>
        <p *ngIf="c.author?.country_name || c.author?.country_code">
          {{ c.author?.country_name || c.author?.country_code }}
        </p>
        <button type="button" class="share" (click)="share()">Share channel</button>
      </div>

      <app-bottom-tabs></app-bottom-tabs>
    </div>

    <ng-template #stateTpl>
      <div class="empty state">{{ error || 'Loading channel…' }}</div>
      <app-bottom-tabs></app-bottom-tabs>
    </ng-template>
  `,
  styles: [
    `
      :host {
        display: block;
        min-height: 100%;
        background: var(--m-paper, #f8f6f2);
        color: var(--m-ink, #2c2825);
      }
      .channel-shell {
        min-height: 100vh;
        padding-bottom: calc(var(--tabs-safe, 72px) + 16px);
      }
      .banner {
        position: relative;
        height: 120px;
        background: linear-gradient(135deg, #2c2825, #6b645d);
        overflow: hidden;
      }
      .banner-img {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        object-fit: cover;
        opacity: 0.35;
      }
      .back {
        position: absolute;
        top: 12px;
        left: 12px;
        z-index: 2;
        border: 0;
        width: 36px;
        height: 36px;
        border-radius: 999px;
        background: rgba(0, 0, 0, 0.4);
        color: #fff;
        cursor: pointer;
        font-size: 18px;
      }
      .head {
        display: flex;
        gap: 12px;
        align-items: flex-start;
        padding: 14px 14px 8px;
        max-width: none;
        margin: 0 auto;
      }
      .avatar {
        width: 64px;
        height: 64px;
        border-radius: 999px;
        overflow: hidden;
        background: var(--m-canvas-deep, #edeae5);
        display: grid;
        place-items: center;
        font-weight: 700;
        margin-top: -28px;
        border: 3px solid var(--m-paper, #f8f6f2);
        flex-shrink: 0;
      }
      .avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .info {
        flex: 1;
        min-width: 0;
      }
      .title {
        font-family: 'Iowan Old Style', Palatino, Georgia, serif;
        font-size: 20px;
        font-weight: 600;
      }
      .sub,
      .stats {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        margin-top: 2px;
      }
      .follow {
        border: 0;
        border-radius: 999px;
        padding: 8px 14px;
        font-weight: 650;
        background: var(--m-ink, #2c2825);
        color: #fefdfb;
        cursor: pointer;
      }
      .follow.on {
        background: var(--m-canvas-deep, #edeae5);
        color: var(--m-ink, #2c2825);
      }
      .tabs {
        display: flex;
        gap: 4px;
        padding: 8px 12px;
        max-width: none;
        margin: 0 auto;
        border-bottom: 0.5px solid var(--m-border, #ddd8d1);
      }
      .tabs button {
        border: 0;
        background: transparent;
        padding: 10px 14px;
        font-weight: 650;
        font-size: 13px;
        color: var(--m-ink-muted, #948b82);
        cursor: pointer;
        border-bottom: 2px solid transparent;
      }
      .tabs button.active {
        color: var(--m-ink, #2c2825);
        border-bottom-color: var(--m-ink, #2c2825);
      }
      .list {
        max-width: none;
        margin: 0 auto;
        padding: 8px 10px;
      }
      .row {
        display: flex;
        gap: 10px;
        width: 100%;
        border: 0;
        background: transparent;
        padding: 8px 4px;
        cursor: pointer;
        text-align: left;
        color: inherit;
      }
      .thumb {
        width: 148px;
        aspect-ratio: 16 / 9;
        border-radius: 10px;
        overflow: hidden;
        background: #171412;
        flex-shrink: 0;
      }
      .thumb img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .v-title {
        font-size: 14px;
        font-weight: 650;
        line-height: 1.3;
      }
      .v-sub {
        margin-top: 4px;
        font-size: 11px;
        color: var(--m-ink-muted, #948b82);
      }
      .sparks-grid {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: 4px;
        padding: 8px;
        max-width: none;
        margin: 0 auto;
      }
      .spark {
        border: 0;
        padding: 0;
        aspect-ratio: 9 / 16;
        background: #171412;
        overflow: hidden;
        cursor: pointer;
      }
      .spark img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .about {
        max-width: none;
        margin: 0 auto;
        padding: 16px;
        font-size: 14px;
        color: var(--m-ink-secondary, #6b645d);
      }
      .share {
        margin-top: 12px;
        border: 0;
        border-radius: 10px;
        padding: 10px 14px;
        background: var(--m-ink, #2c2825);
        color: #fefdfb;
        font-weight: 650;
        cursor: pointer;
      }
      .empty,
      .state {
        padding: 40px 16px;
        text-align: center;
        color: var(--m-ink-muted, #948b82);
      }
    `,
  ],
})
export class HubsChannelPageComponent implements OnInit {
  channel: HubsChannel | null = null;
  tab: 'videos' | 'reels' | 'about' = 'videos';
  error = '';
  canFollow = false;
  isFollowing = false;
  meId: string | null = null;
  avatar: string | null = null;
  bannerThumb: string | null = null;

  constructor(
    public catalog: HubsCatalogService,
    private engagement: HubsEngagementService,
    private playback: HubsPlaybackService,
    private follow: FollowService,
    private auth: AuthService,
    private route: ActivatedRoute,
    private router: Router,
    private cdr: ChangeDetectorRef
  ) {}

  async ngOnInit(): Promise<void> {
    const id = this.route.snapshot.paramMap.get('id');
    if (!id) {
      this.error = 'Missing channel';
      return;
    }
    try {
      if (!this.catalog.currentCatalog.length) {
        await this.catalog.loadCatalog();
      }
      this.channel = await this.catalog.expandChannel(id);
      if (!this.channel) {
        // Try build from catalog posts for this author
        const posts = this.catalog.currentCatalog.filter((p) => p.author_id === id);
        if (posts.length) {
          this.channel = this.catalog.buildChannels(posts)[0] || null;
        }
      }
      if (!this.channel) {
        this.error = 'Channel not found';
        this.paint();
        return;
      }
      this.avatar = this.channel.author?.avatar_url
        ? resolveAvatarUrl(this.channel.author.avatar_url) || this.channel.author.avatar_url
        : null;
      const latest = this.channel.latestVideo;
      this.bannerThumb = latest?.thumb_url
        ? resolveMediaUrl(latest.thumb_url) || latest.thumb_url
        : null;

      const user = await this.auth.getUser().catch(() => null);
      this.meId = user?.id ?? null;
      this.canFollow =
        !!this.meId && this.meId !== this.channel.authorID && !this.channel.authorID.startsWith('hub_');
      if (this.canFollow && this.meId) {
        this.isFollowing = await this.follow
          .isFollowing(this.meId, this.channel.authorID)
          .catch(() => false);
      }
      this.paint();
    } catch (e: any) {
      this.error = e?.message || 'Could not load channel';
      this.paint();
    }
  }

  private paint(): void {
    try {
      this.cdr.detectChanges();
    } catch {
      // destroyed
    }
  }

  trackById(_: number, p: CountryPost): string {
    return p.id;
  }

  thumb(p: CountryPost): string | null {
    const t = p.thumb_url || this.catalog.mediaUrl(p);
    return t ? resolveMediaUrl(t) || t : null;
  }

  back(): void {
    void this.router.navigate(['/hubs']);
  }

  openVideo(p: CountryPost): void {
    if (this.catalog.isReel(p)) {
      this.playback.stop();
      const country = p.country_code || 'WORLD';
      const seeds = this.channel?.reels?.length ? this.channel.reels : [p];
      void this.router.navigate(['/sparks', country], {
        queryParams: { post: p.id },
        state: { seedPosts: seeds, seedCountry: country },
      });
      return;
    }
    this.playback.start(this.engagement.applyLikeState(p), true);
    void this.router.navigate(['/hubs', 'watch', p.id]);
  }

  async toggleFollow(): Promise<void> {
    if (!this.meId || !this.channel || !this.canFollow) return;
    try {
      if (this.isFollowing) {
        await this.follow.unfollow(this.meId, this.channel.authorID);
        this.isFollowing = false;
      } else {
        await this.follow.follow(this.meId, this.channel.authorID);
        this.isFollowing = true;
      }
    } catch {
      // ignore
    }
    this.paint();
  }

  async share(): Promise<void> {
    if (!this.channel) return;
    const url = `${window.location.origin}/hubs/channel/${this.channel.authorID}`;
    try {
      if (navigator.share) await navigator.share({ title: this.channel.title, url });
      else await navigator.clipboard.writeText(url);
    } catch {
      // cancelled
    }
  }
}
