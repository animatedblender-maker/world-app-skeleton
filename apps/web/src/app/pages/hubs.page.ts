import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { BottomTabsComponent } from '../components/bottom-tabs.component';
import { HubsVideoRowComponent } from '../components/hubs-video-row.component';
import { MatteryaTopbarComponent } from '../components/matterya-topbar.component';
import { SparksStripComponent } from '../components/sparks-strip.component';
import type { CountryPost } from '../core/models/post.model';
import { AuthService } from '../core/services/auth.service';
import { FollowService } from '../core/services/follow.service';
import { LocationService } from '../core/services/location.service';
import { ProfileService } from '../core/services/profile.service';
import { resolveAvatarUrl } from '../core/utils/media-url.util';
import {
  HUBS_HOME_FILTERS,
  HubsCatalogService,
  type HubsChannel,
  type HubsHomeFilter,
  type HubsLibrarySection,
} from '../hubs/hubs-catalog.service';
import { HubsPlaybackService } from '../hubs/hubs-playback.service';

type HubsMode = 'home' | 'library';

@Component({
  selector: 'app-hubs-page',
  standalone: true,
  imports: [
    CommonModule,
    FormsModule,
    BottomTabsComponent,
    HubsVideoRowComponent,
    MatteryaTopbarComponent,
    SparksStripComponent,
  ],
  template: `
    <div class="hubs-shell">
      <app-matterya-topbar
        title="Matterya Hubs"
        (search)="showSearch = true"
        (notifications)="openNotifications()"
      ></app-matterya-topbar>

      <div class="chips" *ngIf="mode === 'home'">
        <button
          type="button"
          class="chip"
          *ngFor="let f of filters"
          [class.active]="homeFilter === f.id"
          (click)="setFilter(f.id)"
        >
          {{ f.title }}
        </button>
        <button type="button" class="chip library" (click)="openLibrary()">Library</button>
      </div>

      <main class="hubs-body" *ngIf="mode === 'home'">
        <div class="state" *ngIf="loading">Loading Matterya Hubs...</div>
        <div class="state error" *ngIf="!loading && error">{{ error }}</div>
        <div class="state" *ngIf="!loading && !error && homeEmpty">
          No videos here yet. Try another category or publish on Matterya Hubs.
        </div>

        <ng-container *ngIf="!loading && !error && !homeEmpty">
          <app-sparks-strip
            *ngIf="homeFilter === 'all' && playReels.length"
            [posts]="sparksRail"
            title="Sparks for you"
            subtitle="Short videos from the world"
            (open)="openSpark($event)"
            (brandTap)="openSpark(sparksRail[0] || playReels[0])"
          ></app-sparks-strip>

          <section class="shelf continue-shelf" *ngIf="homeFilter === 'all' && continueWatchingVisible.length">
            <div class="section-title">Continue watching</div>
            <div
              class="continue-rail"
              #continueRail
              (scroll)="onContinueScroll($event)"
            >
              <button
                type="button"
                class="continue-card"
                *ngFor="let p of continueWatchingVisible; trackBy: trackById"
                (click)="openVideo(p)"
              >
                <div class="continue-thumb">
                  <img *ngIf="thumb(p)" [src]="thumb(p)" alt="" />
                </div>
                <div class="continue-title">{{ catalog.displayHeadline(p) }}</div>
                <div class="progress"><span [style.width.%]="progressPercent(p)"></span></div>
              </button>
              <div class="continue-end" *ngIf="continueHasMore" aria-hidden="true"></div>
            </div>
          </section>

          <section class="shelf" *ngIf="homeFilter === 'all' && (subscriptionChannels.length || subscriptionVideos.length)">
            <div class="section-title">Following</div>
            <div class="channel-rail" *ngIf="subscriptionChannels.length">
              <button
                type="button"
                class="channel"
                *ngFor="let c of subscriptionChannels; trackBy: trackChannel"
                (click)="openChannel(c)"
              >
                <div class="channel-avatar">
                  <img *ngIf="avatar(c)" [src]="avatar(c)" alt="" />
                  <span *ngIf="!avatar(c)">{{ c.title.slice(0, 2).toUpperCase() }}</span>
                </div>
                <div class="channel-name">{{ c.title }}</div>
              </button>
            </div>
            <div class="hubs-video-grid following-grid">
              <app-hubs-video-row
                *ngFor="let p of followingPreviewVideos; trackBy: trackById"
                [post]="p"
                (open)="openVideo($event)"
              ></app-hubs-video-row>
            </div>
          </section>

          <div class="hubs-video-grid">
            <app-hubs-video-row
              *ngFor="let p of discoverVideos; trackBy: trackById"
              [post]="p"
              (open)="openVideo($event)"
            ></app-hubs-video-row>
          </div>
        </ng-container>
      </main>

      <main class="library-screen" *ngIf="mode === 'library'">
        <header class="library-top">
          <button type="button" class="back" (click)="mode = 'home'" aria-label="Back">‹</button>
          <div class="library-title">Library</div>
        </header>
        <div class="library-tabs">
          <button
            type="button"
            class="chip"
            *ngFor="let s of librarySections"
            [class.active]="librarySection === s.id"
            (click)="librarySection = s.id"
          >
            {{ s.title }}
          </button>
        </div>
        <div class="state" *ngIf="!libraryVideos.length">{{ libraryEmptyText }}</div>
        <div class="sparks-grid" *ngIf="librarySection === 'reels' && libraryVideos.length">
          <button
            type="button"
            class="spark-cell"
            *ngFor="let p of libraryVideos; trackBy: trackById"
            (click)="openSpark(p)"
          >
            <img *ngIf="thumb(p)" [src]="thumb(p)" alt="" />
          </button>
        </div>
        <div class="hubs-video-grid" *ngIf="librarySection !== 'reels'">
          <app-hubs-video-row
            *ngFor="let p of libraryVideos; trackBy: trackById"
            [post]="p"
            (open)="openVideo($event)"
          ></app-hubs-video-row>
        </div>
      </main>

      <button type="button" class="search-backdrop" *ngIf="showSearch" (click)="closeSearch()" aria-label="Close search"></button>
      <section class="search-panel" *ngIf="showSearch">
        <div class="search-head">
          <input
            name="hubsSearch"
            [(ngModel)]="searchQuery"
            placeholder="Search Matterya Hubs"
            autocomplete="off"
            autofocus
          />
          <button type="button" (click)="closeSearch()" aria-label="Close">×</button>
        </div>
        <div class="search-state" *ngIf="!searchQuery.trim()">Find videos and creators on Matterya Hubs.</div>
        <button
          type="button"
          class="search-channel"
          *ngFor="let c of searchResults.channels; trackBy: trackChannel"
          (click)="openChannel(c)"
        >
          <div class="channel-avatar small">
            <img *ngIf="avatar(c)" [src]="avatar(c)" alt="" />
            <span *ngIf="!avatar(c)">{{ c.title.slice(0, 2).toUpperCase() }}</span>
          </div>
          <div>
            <div class="s-title">{{ c.title }}</div>
            <div class="s-sub">{{ c.videoCount }} videos</div>
          </div>
        </button>
        <app-hubs-video-row
          *ngFor="let p of searchResults.videos; trackBy: trackById"
          [post]="p"
          (open)="openVideo($event)"
        ></app-hubs-video-row>
      </section>

      <app-bottom-tabs></app-bottom-tabs>
    </div>
  `,
  styles: [
    `
      :host {
        display: block;
        min-height: 100%;
        background: var(--m-paper, #f8f6f2);
        color: var(--m-ink, #2c2825);
      }
      .hubs-shell {
        min-height: 100vh;
        padding-bottom: calc(var(--tabs-safe, 72px) + 16px);
        background: var(--m-paper, #f8f6f2);
      }
      .chips,
      .library-tabs {
        display: flex;
        gap: 4px;
        min-height: 48px;
        overflow-x: auto;
        padding: 4px var(--m-page-padding, 16px);
        background: var(--m-paper, #f8f6f2);
        border-bottom: 0.5px solid var(--m-divider, #e2ded8);
        scrollbar-width: none;
      }
      .chips::-webkit-scrollbar,
      .library-tabs::-webkit-scrollbar {
        display: none;
      }
      .chip {
        flex: 0 0 auto;
        border: 0;
        background: transparent;
        color: var(--m-ink-muted, #948b82);
        font-size: 12px;
        font-weight: 700;
        text-transform: uppercase;
        padding: 8px 12px;
        position: relative;
        cursor: pointer;
      }
      .chip.active {
        color: var(--m-ink, #2c2825);
      }
      .chip.active::after {
        content: '';
        position: absolute;
        left: 12px;
        right: 12px;
        bottom: 2px;
        height: 1px;
        background: var(--m-ink, #2c2825);
      }
      .chip.library {
        margin-left: 8px;
      }
      .hubs-body,
      .library-screen {
        max-width: none;
        margin: 0;
        padding: 8px 0 24px;
        width: 100%;
      }
      .hubs-video-grid {
        display: grid;
        grid-template-columns: 1fr;
        gap: 0;
      }
      @media (min-width: 900px) {
        .hubs-shell {
          background: var(--m-paper, #f8f6f2);
          padding-bottom: 24px;
        }
        .chips,
        .library-tabs {
          background: var(--m-surface, #fefdfb);
          padding: 6px 16px;
          position: sticky;
          top: 56px;
          z-index: 20;
        }
        .chip {
          font-size: 13px;
          padding: 10px 14px;
        }
        .hubs-body,
        .library-screen {
          max-width: none;
          margin: 0;
          padding: 12px 0 28px;
          width: 100%;
        }
        /* Fluid grid: fills every available column, no empty gutters */
        .hubs-video-grid {
          grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
          gap: 16px 14px;
          padding: 0 16px;
        }
        .section-title {
          padding: 0 16px 10px;
          font-size: 13px;
        }
        .continue-rail,
        .channel-rail {
          padding: 0 16px 8px;
          gap: 14px;
        }
        .continue-card {
          flex: 0 0 240px;
          width: 240px;
        }
        .continue-thumb {
          width: 100%;
        }
        .continue-title {
          font-size: 13px;
        }
        .sparks-grid {
          grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
          gap: 10px;
          padding: 0 16px;
        }
        .search-panel {
          left: var(--m-sidebar-w, 200px);
          width: min(520px, calc(100vw - var(--m-sidebar-w, 200px)));
        }
        .search-backdrop {
          left: var(--m-sidebar-w, 200px);
        }
      }
      @media (min-width: 1400px) {
        .hubs-video-grid {
          grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
          gap: 18px 16px;
          padding: 0 18px;
        }
      }
      .state,
      .search-state {
        padding: 44px 16px;
        text-align: center;
        color: var(--m-ink-muted, #948b82);
        font-size: 14px;
      }
      .state.error {
        color: var(--m-danger, #ea000b);
      }
      .shelf {
        padding-bottom: 20px;
      }
      .section-title {
        padding: 0 var(--m-page-padding, 16px) 10px;
        color: var(--m-ink-muted, #948b82);
        font-size: 12px;
        font-weight: 700;
        text-transform: uppercase;
      }
      .continue-rail,
      .channel-rail {
        display: flex;
        gap: 12px;
        overflow-x: auto;
        padding: 0 var(--m-page-padding, 16px);
        scrollbar-width: thin;
        -webkit-overflow-scrolling: touch;
        scroll-snap-type: x proximity;
      }
      .continue-rail {
        padding-bottom: 6px;
      }
      .continue-rail::-webkit-scrollbar {
        height: 6px;
      }
      .continue-rail::-webkit-scrollbar-thumb {
        background: var(--m-border, #ddd8d1);
        border-radius: 999px;
      }
      .channel-rail::-webkit-scrollbar {
        display: none;
      }
      .continue-card {
        flex: 0 0 168px;
        border: 0;
        background: transparent;
        padding: 0;
        color: inherit;
        text-align: left;
        cursor: pointer;
        scroll-snap-align: start;
      }
      .continue-thumb {
        width: 168px;
        aspect-ratio: 16 / 9;
        background: #171412;
        border-radius: 12px;
        overflow: hidden;
      }
      .continue-end {
        flex: 0 0 24px;
        height: 1px;
      }
      .continue-thumb img,
      .spark-cell img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .continue-title {
        margin-top: 7px;
        font-size: 12px;
        font-weight: 650;
        line-height: 1.25;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .progress {
        margin-top: 7px;
        height: 2px;
        border-radius: 999px;
        background: var(--m-canvas-deep, #edeae5);
        overflow: hidden;
      }
      .progress span {
        display: block;
        height: 100%;
        background: var(--m-accent-bright, #7b6347);
      }
      .channel {
        flex: 0 0 72px;
        border: 0;
        background: transparent;
        padding: 0 0 8px;
        color: inherit;
        cursor: pointer;
      }
      .channel-avatar {
        width: 52px;
        height: 52px;
        margin: 0 auto 6px;
        border-radius: 999px;
        overflow: hidden;
        background: var(--m-canvas-deep, #edeae5);
        display: grid;
        place-items: center;
        font-size: 12px;
        font-weight: 700;
      }
      .channel-avatar.small {
        width: 42px;
        height: 42px;
        margin: 0;
        flex: 0 0 auto;
      }
      .channel-avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .channel-name {
        font-size: 11px;
        font-weight: 650;
        line-height: 1.2;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .library-top {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 2px var(--m-page-padding, 16px) 10px;
        border-bottom: 0.5px solid var(--m-divider, #e2ded8);
      }
      .back {
        width: 36px;
        height: 36px;
        border-radius: 999px;
        border: 0.5px solid var(--m-border, #ddd8d1);
        background: var(--m-surface, #fefdfb);
        color: var(--m-ink, #2c2825);
        font-size: 24px;
        cursor: pointer;
      }
      .library-title {
        font-size: 16px;
        font-weight: 700;
      }
      .sparks-grid {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 8px;
        padding: 8px var(--m-page-padding, 16px) 24px;
      }
      .spark-cell {
        border: 0;
        padding: 0;
        aspect-ratio: 9 / 16;
        border-radius: 0;
        overflow: hidden;
        background: #171412;
        cursor: pointer;
      }
      .search-backdrop {
        position: fixed;
        inset: 0;
        z-index: 110;
        border: 0;
        background: rgba(44, 40, 37, 0.18);
      }
      .search-panel {
        position: fixed;
        left: 0;
        right: 0;
        top: 0;
        bottom: 0;
        z-index: 111;
        overflow-y: auto;
        background: var(--m-paper, #f8f6f2);
        padding: calc(env(safe-area-inset-top) + 12px) 0 calc(var(--tabs-safe, 72px) + 24px);
      }
      .search-head {
        display: flex;
        gap: 8px;
        padding: 0 var(--m-page-padding, 16px) 12px;
        max-width: none;
        margin: 0 auto;
      }
      .search-head input {
        flex: 1;
        min-width: 0;
        border: 0.5px solid var(--m-border, #ddd8d1);
        background: var(--m-canvas-muted, #f2f0ec);
        border-radius: 8px;
        padding: 11px 12px;
        font-size: 16px;
        color: var(--m-ink, #2c2825);
      }
      .search-head button {
        width: 40px;
        height: 40px;
        border: 0;
        background: transparent;
        color: var(--m-ink, #2c2825);
        font-size: 24px;
        cursor: pointer;
      }
      .search-channel {
        display: flex;
        align-items: center;
        gap: 12px;
        width: 100%;
        max-width: none;
        margin: 0 auto;
        border: 0;
        background: transparent;
        color: inherit;
        text-align: left;
        padding: 10px var(--m-page-padding, 16px);
        cursor: pointer;
      }
      .s-title {
        font-size: 14px;
        font-weight: 700;
      }
      .s-sub {
        margin-top: 2px;
        color: var(--m-ink-muted, #948b82);
        font-size: 12px;
      }
    `,
  ],
})
export class HubsPageComponent implements OnInit {
  allVideos: CountryPost[] = [];
  channels: HubsChannel[] = [];
  homeCountry: string | null = null;
  homeFilter: HubsHomeFilter = 'all';
  mode: HubsMode = 'home';
  librarySection: HubsLibrarySection = 'history';
  loading = true;
  error = '';
  showSearch = false;
  searchQuery = '';
  meId: string | null = null;
  followingIds = new Set<string>();
  filters = HUBS_HOME_FILTERS;
  sparksStrip: CountryPost[] = [];
  librarySections: { id: HubsLibrarySection; title: string }[] = [
    { id: 'history', title: 'History' },
    { id: 'reels', title: 'Sparks' },
    { id: 'saved', title: 'Saved' },
    { id: 'liked', title: 'Liked' },
    { id: 'uploads', title: 'Uploads' },
  ];

  constructor(
    public catalog: HubsCatalogService,
    private auth: AuthService,
    private cdr: ChangeDetectorRef,
    private follow: FollowService,
    private location: LocationService,
    private playback: HubsPlaybackService,
    private profiles: ProfileService,
    private router: Router
  ) {}

  ngOnInit(): void {
    void this.refresh();
  }

  get playReels(): CountryPost[] {
    return this.catalog.reels(this.allVideos);
  }

  get sparksRail(): CountryPost[] {
    return this.sparksStrip.length ? this.sparksStrip : this.playReels.slice(0, 10);
  }

  /** Full continue-watching source (history + in-progress + catalog filler). */
  get continueWatchingAll(): CountryPost[] {
    return this.catalog.continueWatchingFeed(this.allVideos);
  }

  /** Progressively revealed items for infinite horizontal scroll. */
  get continueWatchingVisible(): CountryPost[] {
    return this.continueWatchingAll.slice(0, this.continueVisibleCount);
  }

  get continueHasMore(): boolean {
    return this.continueVisibleCount < this.continueWatchingAll.length;
  }

  /** @deprecated alias for empty-state checks */
  get continueWatching(): CountryPost[] {
    return this.continueWatchingVisible;
  }

  continueVisibleCount = 24;
  private readonly continuePageSize = 24;

  onContinueScroll(event: Event): void {
    const el = event.target as HTMLElement | null;
    if (!el || !this.continueHasMore) return;
    const remaining = el.scrollWidth - el.scrollLeft - el.clientWidth;
    if (remaining < 280) {
      this.continueVisibleCount = Math.min(
        this.continueWatchingAll.length,
        this.continueVisibleCount + this.continuePageSize
      );
      this.paint();
    }
  }

  get homeVideos(): CountryPost[] {
    return this.catalog.filterVideos(this.allVideos, this.homeFilter, this.followingIds, this.homeCountry);
  }

  get subscriptionVideos(): CountryPost[] {
    return this.catalog.subscriptionFeed(this.allVideos, this.followingIds);
  }

  get subscriptionChannels(): HubsChannel[] {
    return this.catalog.subscriptionChannels(this.channels, this.followingIds);
  }

  get followingPreviewVideos(): CountryPost[] {
    return this.subscriptionVideos.slice(0, 3);
  }

  get discoverVideos(): CountryPost[] {
    if (this.homeFilter !== 'all') return this.homeVideos;
    const subscriptionIDs = new Set(this.subscriptionVideos.map((p) => p.id));
    return this.homeVideos.filter((p) => !subscriptionIDs.has(p.id));
  }

  get homeEmpty(): boolean {
    if (this.homeFilter !== 'all') return !this.homeVideos.length;
    return (
      !this.playReels.length &&
      !this.continueWatching.length &&
      !this.subscriptionVideos.length &&
      !this.discoverVideos.length
    );
  }

  get libraryVideos(): CountryPost[] {
    switch (this.librarySection) {
      case 'history':
        return this.catalog.historyVideos(this.allVideos);
      case 'reels':
        return this.catalog.reels(this.allVideos).filter((p) => this.catalog.isSaved(p.id) || p.author_id === this.meId);
      case 'saved':
        return this.catalog.savedVideos(this.allVideos);
      case 'liked':
        return this.catalog.likedVideos(this.allVideos);
      case 'uploads':
        return this.catalog.myUploads(this.allVideos, this.meId);
    }
  }

  get libraryEmptyText(): string {
    switch (this.librarySection) {
      case 'history':
        return 'Nothing in history yet. Videos you watch will appear here.';
      case 'reels':
        return 'No saved Sparks yet. Save Sparks while watching or publish your own.';
      case 'saved':
        return 'No saved videos. Tap Save on any video to watch later.';
      case 'liked':
        return 'No liked videos. Like videos while watching to collect them here.';
      case 'uploads':
        return 'No uploads yet. Publish a video or Spark from Create.';
    }
  }

  get searchResults(): { videos: CountryPost[]; channels: HubsChannel[] } {
    return this.catalog.search(this.searchQuery, this.allVideos, this.channels);
  }

  private async refresh(): Promise<void> {
    this.loading = true;
    this.error = '';
    this.continueVisibleCount = this.continuePageSize;
    this.homeCountry = this.location.getCachedLocation()?.countryCode?.trim().toUpperCase() || null;
    this.paint();

    try {
      const user = await this.auth.getUser().catch(() => null);
      this.meId = user?.id || null;
      if (this.meId) {
        const [following, profileResult] = await Promise.all([
          this.follow.listFollowingIds(this.meId).catch(() => [] as string[]),
          this.profiles.meProfile().catch(() => ({ meProfile: null })),
        ]);
        this.followingIds = new Set(following);
        if (profileResult.meProfile?.country_code) {
          this.homeCountry = String(profileResult.meProfile.country_code).trim().toUpperCase();
        }
      }

      this.allVideos = await this.catalog.loadCatalog({
        forceRefresh: false,
        followingIDs: [...this.followingIds],
        viewerCountry: this.homeCountry,
      });
      this.channels = this.catalog.currentChannels;
      this.sparksStrip = this.shuffle(this.catalog.reels(this.allVideos)).slice(0, 10);
    } catch (e: any) {
      this.error = e?.message || 'Could not load Matterya Hubs right now.';
      this.allVideos = [];
      this.channels = [];
    } finally {
      this.loading = false;
      this.paint();
    }
  }

  setFilter(filter: HubsHomeFilter): void {
    this.homeFilter = filter;
  }

  openLibrary(): void {
    this.mode = 'library';
  }

  closeSearch(): void {
    this.showSearch = false;
    this.searchQuery = '';
  }

  openNotifications(): void {
    void this.router.navigate(['/globe'], {
      queryParams: { panel: 'notifications', search: '0' },
    });
  }

  openVideo(post: CountryPost): void {
    if (!post) return;
    if (this.catalog.isReel(post)) {
      this.openSpark(post);
      return;
    }
    this.playback.start(post, true);
    void this.router.navigate(['/hubs', 'watch', post.id]);
  }

  openSpark(post: CountryPost | null | undefined): void {
    if (!post) return;
    const country = post.country_code || this.homeCountry || 'US';
    void this.router.navigate(['/sparks', country], {
      queryParams: { post: post.id },
      state: { seedPosts: [post, ...this.playReels] },
    });
  }

  openChannel(channel: HubsChannel): void {
    this.closeSearch();
    void this.router.navigate(['/hubs', 'channel', channel.authorID]);
  }

  thumb(post: CountryPost): string | null {
    return post.thumb_url || this.catalog.mediaUrl(post) || null;
  }

  avatar(channel: HubsChannel): string | null {
    const u = channel.author?.avatar_url;
    return u ? resolveAvatarUrl(u) || u : null;
  }

  progressPercent(post: CountryPost): number {
    const seconds = this.catalog.playbackPosition(post.id);
    return Math.max(8, Math.min(92, (seconds / 900) * 100));
  }

  trackById(_: number, post: CountryPost): string {
    return post.id;
  }

  trackChannel(_: number, channel: HubsChannel): string {
    return channel.authorID;
  }

  private shuffle(posts: CountryPost[]): CountryPost[] {
    return posts
      .map((post) => ({ post, rank: Math.random() }))
      .sort((a, b) => a.rank - b.rank)
      .map(({ post }) => post);
  }

  private paint(): void {
    try {
      this.cdr.detectChanges();
    } catch {
      // destroyed
    }
  }
}
