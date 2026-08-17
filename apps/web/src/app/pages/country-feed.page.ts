import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';

import { BottomTabsComponent } from '../components/bottom-tabs.component';
import { MatteryaPostCardComponent } from '../components/matterya-post-card.component';
import type { CountryPost } from '../core/models/post.model';
import { AuthService } from '../core/services/auth.service';
import { FollowService } from '../core/services/follow.service';
import { NewsService } from '../core/services/news.service';
import { PostsService } from '../core/services/posts.service';
import { ProfileService } from '../core/services/profile.service';
import { CountriesService, type CountryModel } from '../data/countries.service';
import type { ExternalNewsItem } from '@world/shared';

type CountryTab = 'posts' | 'following' | 'media' | 'stats' | 'news';

/**
 * Pixel port of iOS CountryFeedView:
 * nav title + Sparks + ISO · pill tabs · composer bar · edge-to-edge post cards.
 */
@Component({
  selector: 'app-country-feed-page',
  standalone: true,
  imports: [CommonModule, BottomTabsComponent, MatteryaPostCardComponent],
  template: `
    <div class="shell">
      <header class="nav">
        <button type="button" class="nav-btn" (click)="backToGlobe()" aria-label="Back">←</button>
        <div class="nav-title">{{ countryName }}</div>
        <div class="nav-trailing">
          <button type="button" class="nav-btn sparks" (click)="openSparks()" aria-label="Sparks">✦</button>
          <span class="iso" *ngIf="countryCode">{{ countryCode }}</span>
        </div>
      </header>

      <div class="tabs">
        <button
          type="button"
          class="tab"
          *ngFor="let t of tabs"
          [class.active]="tab === t.id"
          (click)="setTab(t.id)"
        >
          {{ t.label }}
        </button>
      </div>

      <div class="state" *ngIf="loading">Loading {{ countryName }}…</div>
      <div class="state error" *ngIf="!loading && loadError && tab !== 'news'">{{ loadError }}</div>

      <!-- Posts -->
      <main class="body" *ngIf="!loading && tab === 'posts'">
        <button type="button" class="composer-bar" *ngIf="canPostHere" (click)="openComposer()">
          <div class="composer-copy">
            <div class="composer-title">Post to your feed</div>
            <div class="composer-sub">Write in {{ countryName }} — your home feed</div>
          </div>
          <span class="composer-plus">＋</span>
        </button>
        <div class="composer-bar browse" *ngIf="!canPostHere">
          <div class="composer-copy">
            <div class="composer-title">Browsing {{ countryName }}</div>
            <div class="composer-sub">You can read here; post from your home country.</div>
          </div>
        </div>
        <div class="state" *ngIf="!posts.length">No posts in {{ countryName }} yet.</div>
        <app-matterya-post-card
          *ngFor="let post of posts; trackBy: trackById"
          [post]="post"
          [edgeToEdge]="true"
          (changed)="onPostChanged($event)"
        ></app-matterya-post-card>
      </main>

      <!-- Following -->
      <main class="body" *ngIf="!loading && tab === 'following'">
        <div class="state" *ngIf="!followingPosts.length">
          Follow people to see their posts from around the world here.
        </div>
        <app-matterya-post-card
          *ngFor="let post of followingPosts; trackBy: trackById"
          [post]="post"
          [edgeToEdge]="true"
        ></app-matterya-post-card>
      </main>

      <!-- Media -->
      <main class="body" *ngIf="!loading && tab === 'media'">
        <div class="state" *ngIf="!mediaPosts.length">No photos or videos in {{ countryName }} yet.</div>
        <app-matterya-post-card
          *ngFor="let post of mediaPosts; trackBy: trackById"
          [post]="post"
          [edgeToEdge]="true"
        ></app-matterya-post-card>
      </main>

      <!-- Stats -->
      <main class="body pad" *ngIf="!loading && tab === 'stats'">
        <div class="stat-card">
          <div class="stat-row"><span>Posts loaded</span><b>{{ posts.length }}</b></div>
          <div class="stat-row"><span>With media</span><b>{{ mediaPosts.length }}</b></div>
          <div class="stat-hint">Live online stats appear when presence is available.</div>
        </div>
      </main>

      <!-- News -->
      <main class="body pad" *ngIf="tab === 'news'">
        <div class="state" *ngIf="newsLoading">Loading news…</div>
        <div class="state error" *ngIf="!newsLoading && newsError && !newsItems.length">{{ newsError }}</div>
        <div class="state" *ngIf="!newsLoading && !newsError && !newsItems.length">
          No news updates for this country right now.
        </div>
        <button
          type="button"
          class="news-card"
          *ngFor="let item of newsItems"
          (click)="openNews(item)"
        >
          <div class="news-src">{{ item.source_name || 'News' }}</div>
          <div class="news-title">{{ item.title }}</div>
          <div class="news-snip" *ngIf="item.snippet">{{ item.snippet }}</div>
        </button>
      </main>

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
      .shell {
        min-height: 100vh;
        padding-bottom: calc(var(--tabs-safe, 49px) + 16px);
        background: var(--m-paper, #f8f6f2);
        width: 100%;
      }
      .nav {
        display: grid;
        grid-template-columns: 44px 1fr auto;
        align-items: center;
        height: calc(44px + env(safe-area-inset-top));
        padding: env(safe-area-inset-top) 8px 0;
        background: var(--m-paper, #f8f6f2);
        border-bottom: 0.5px solid var(--m-divider, #e2ded8);
        position: sticky;
        top: 0;
        z-index: 20;
      }
      .nav-title {
        text-align: center;
        font-size: 16px;
        font-weight: 650;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .nav-trailing {
        display: flex;
        align-items: center;
        gap: 4px;
        min-width: 72px;
        justify-content: flex-end;
      }
      .nav-btn {
        border: 0;
        background: transparent;
        width: 40px;
        height: 40px;
        font-size: 18px;
        color: var(--m-ink, #2c2825);
        cursor: pointer;
      }
      .nav-btn.sparks {
        color: var(--m-accent-bright, #7b6347);
      }
      .iso {
        font-size: 11px;
        font-weight: 800;
        letter-spacing: 1px;
        color: var(--m-ink-muted, #948b82);
        padding-right: 6px;
      }
      .tabs {
        display: flex;
        gap: 8px;
        overflow-x: auto;
        padding: 12px var(--m-page-padding, 16px);
        background: var(--m-paper, #f8f6f2);
        border-bottom: 0.5px solid var(--m-divider, #e2ded8);
        scrollbar-width: none;
      }
      .tabs::-webkit-scrollbar {
        display: none;
      }
      .tab {
        flex-shrink: 0;
        border: 0;
        background: transparent;
        color: var(--m-ink-muted, #948b82);
        font-size: 12px;
        font-weight: 650;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        padding: 8px 12px;
        cursor: pointer;
        position: relative;
      }
      .tab.active {
        color: var(--m-ink, #2c2825);
      }
      .tab.active::after {
        content: '';
        position: absolute;
        left: 12px;
        right: 12px;
        bottom: 0;
        height: 1px;
        background: var(--m-ink, #2c2825);
      }
      .body {
        padding-top: 8px;
        max-width: 100%;
        margin: 0 auto;
        width: 100%;
        padding-left: 8px;
        padding-right: 8px;
        box-sizing: border-box;
        --m-feed-card-gap: 0px;
      }
      @media (min-width: 900px) {
        .shell {
          background: var(--m-canvas-muted, #f2f0ec);
        }
        .body {
          width: 60%;
          max-width: 60%;
          min-width: min(100%, 520px);
          margin: 0 auto;
          padding: 12px 0 24px;
        }
      }
      .body.pad {
        padding: 12px var(--m-page-padding, 16px) 24px;
      }
      .composer-bar {
        display: flex;
        align-items: center;
        gap: 14px;
        margin: 12px var(--m-page-padding, 16px) 8px;
        padding: 16px;
        border: 0.5px solid var(--m-border, #ddd8d1);
        border-radius: var(--m-card-radius, 12px);
        background: var(--m-surface, #fefdfb);
        box-shadow: 0 6px 14px rgba(44, 40, 37, 0.05);
        text-align: left;
        color: inherit;
        cursor: pointer;
        width: calc(100% - 32px);
      }
      .composer-bar.browse {
        cursor: default;
      }
      .composer-title {
        font-size: 14px;
        font-weight: 650;
      }
      .composer-sub {
        margin-top: 2px;
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
      }
      .composer-plus {
        margin-left: auto;
        font-size: 28px;
        color: var(--m-accent-bright, #7b6347);
        line-height: 1;
      }
      .state {
        padding: 28px 16px;
        text-align: center;
        color: var(--m-ink-muted, #948b82);
        font-size: 14px;
      }
      .state.error {
        color: var(--m-danger, #ea000b);
      }
      .stat-card {
        background: var(--m-surface, #fefdfb);
        border: 0.5px solid var(--m-border, #ddd8d1);
        border-radius: 12px;
        padding: 16px;
      }
      .stat-row {
        display: flex;
        justify-content: space-between;
        padding: 10px 0;
        border-bottom: 0.5px solid var(--m-divider, #e2ded8);
        font-size: 14px;
      }
      .stat-row:last-of-type {
        border-bottom: 0;
      }
      .stat-hint {
        margin-top: 10px;
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
      }
      .news-card {
        display: block;
        width: 100%;
        text-align: left;
        border: 0.5px solid var(--m-border, #ddd8d1);
        border-radius: 12px;
        background: var(--m-surface, #fefdfb);
        padding: 16px;
        margin-bottom: 12px;
        color: inherit;
        cursor: pointer;
      }
      .news-src {
        font-size: 11px;
        font-weight: 650;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        color: var(--m-ink-muted, #948b82);
        margin-bottom: 6px;
      }
      .news-title {
        font-size: 14px;
        font-weight: 650;
        line-height: 1.35;
      }
      .news-snip {
        margin-top: 6px;
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        display: -webkit-box;
        -webkit-line-clamp: 3;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      /* desktop layout */

      @media (min-width: 900px) {
        .shell {
          background: var(--m-paper, #f8f6f2);
          max-width: none;
          padding-bottom: 24px;
        }
        .shell > *:not(.nav):not(app-bottom-tabs) {
          max-width: none;
          margin-left: 0;
          margin-right: 0;
          padding-left: 16px;
          padding-right: 16px;
          box-sizing: border-box;
        }
        .nav {
          padding-left: 12px;
          padding-right: 12px;
        }
      }

    `,
  ],
})
export class CountryFeedPageComponent implements OnInit {
  tabs: { id: CountryTab; label: string }[] = [
    { id: 'posts', label: 'Posts' },
    { id: 'following', label: 'Following' },
    { id: 'media', label: 'Media' },
    { id: 'stats', label: 'Stats' },
    { id: 'news', label: 'News' },
  ];
  tab: CountryTab = 'posts';
  countryCode = '';
  countryName = '';
  posts: CountryPost[] = [];
  followingPosts: CountryPost[] = [];
  newsItems: ExternalNewsItem[] = [];
  loading = true;
  newsLoading = false;
  loadError = '';
  newsError = '';
  canPostHere = false;
  meId: string | null = null;
  homeCountryCode: string | null = null;

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private countries: CountriesService,
    private postsService: PostsService,
    private profiles: ProfileService,
    private follow: FollowService,
    private news: NewsService,
    private auth: AuthService,
    private cdr: ChangeDetectorRef
  ) {}

  get mediaPosts(): CountryPost[] {
    return this.posts.filter((p) => !!(p.media_url || p.thumb_url) && p.media_type !== 'none');
  }

  async ngOnInit(): Promise<void> {
    const code = (this.route.snapshot.paramMap.get('code') || '').trim().toUpperCase();
    const tabParam = (this.route.snapshot.queryParamMap.get('tab') || 'posts') as CountryTab;
    this.tab = this.tabs.some((t) => t.id === tabParam) ? tabParam : 'posts';
    this.countryCode = code;
    await this.bootstrap(code);
    if (this.route.snapshot.queryParamMap.get('compose')) {
      this.openComposer();
    }
  }

  trackById(_: number, p: CountryPost): string {
    return p.id;
  }

  setTab(tab: CountryTab): void {
    this.tab = tab;
    void this.router.navigate([], {
      relativeTo: this.route,
      queryParams: { tab },
      queryParamsHandling: 'merge',
      replaceUrl: true,
    });
    void this.loadTab();
  }

  backToGlobe(): void {
    void this.router.navigate(['/globe']);
  }

  openSparks(): void {
    if (!this.countryCode) return;
    void this.router.navigate(['/sparks', this.countryCode]);
  }

  openComposer(): void {
    void this.router.navigate(['/globe'], {
      queryParams: {
        country: this.countryCode,
        tab: 'posts',
        compose: 'post',
      },
    });
  }

  openNews(item: ExternalNewsItem): void {
    void this.router.navigate(['/news', item.id]);
  }

  onPostChanged(post: CountryPost): void {
    const i = this.posts.findIndex((p) => p.id === post.id);
    if (i >= 0) this.posts[i] = post;
  }

  private paint(): void {
    try {
      this.cdr.detectChanges();
    } catch {
      // destroyed
    }
  }

  private async bootstrap(code: string): Promise<void> {
    this.loading = true;
    this.loadError = '';
    this.paint();
    try {
      const user = await this.auth.getUser().catch(() => null);
      this.meId = user?.id ?? null;
      if (this.meId) {
        const { meProfile } = await this.profiles.meProfile().catch(() => ({ meProfile: null as any }));
        this.homeCountryCode = meProfile?.country_code
          ? String(meProfile.country_code).trim().toUpperCase()
          : null;
      }
      this.canPostHere = !!this.homeCountryCode && this.homeCountryCode === code;

      const loaded = await this.countries.loadCountries().catch(() => ({ countries: [] as CountryModel[] }));
      const found = (loaded.countries || []).find(
        (c) => String(c.code || '').toUpperCase() === code
      );
      this.countryName = found?.name || code || 'Country';
      this.countryCode = code;

      await this.loadTab();
    } catch (e: any) {
      this.loadError = e?.message || 'Could not load country';
    } finally {
      this.loading = false;
      this.paint();
    }
  }

  private async loadTab(): Promise<void> {
    if (this.tab === 'news') {
      await this.loadNews();
      return;
    }
    if (this.tab === 'following') {
      await this.loadFollowing();
      return;
    }
    if (this.tab === 'stats') {
      this.paint();
      return;
    }
    // posts + media share posts list
    if (!this.posts.length || this.tab === 'posts' || this.tab === 'media') {
      await this.loadPosts();
    }
  }

  private async loadPosts(): Promise<void> {
    if (!this.countryCode) return;
    this.loadError = '';
    try {
      const list = await this.postsService.listByCountry(this.countryCode, 40, {
        demoLimit: 40,
        skipComments: true,
      });
      this.posts = (list || []).filter(
        (p) => !this.postsService.isMoment(p) && !this.postsService.isSpark(p)
      );
    } catch (e: any) {
      this.loadError = e?.message || 'Posts unavailable';
      this.posts = [];
    }
    this.paint();
  }

  private async loadFollowing(): Promise<void> {
    if (!this.meId) {
      this.followingPosts = [];
      this.paint();
      return;
    }
    try {
      const ids = await this.follow.listFollowingIds(this.meId);
      const batches = await Promise.all(
        ids.slice(0, 8).map((id) => this.postsService.listForAuthor(id, 6).catch(() => [] as CountryPost[]))
      );
      const merged: CountryPost[] = [];
      const seen = new Set<string>();
      for (const batch of batches) {
        for (const p of batch) {
          if (!p?.id || seen.has(p.id)) continue;
          if (this.postsService.isMoment(p) || this.postsService.isSpark(p)) continue;
          seen.add(p.id);
          merged.push(p);
        }
      }
      merged.sort((a, b) => (b.created_at || '').localeCompare(a.created_at || ''));
      this.followingPosts = merged;
    } catch {
      this.followingPosts = [];
    }
    this.paint();
  }

  private async loadNews(): Promise<void> {
    if (!this.countryCode) return;
    this.newsLoading = true;
    this.newsError = '';
    this.paint();
    try {
      this.newsItems = await this.news.countryConflictUpdates(this.countryCode, 20, 0);
    } catch (e: any) {
      this.newsError = e?.message || 'News unavailable';
      this.newsItems = [];
    } finally {
      this.newsLoading = false;
      this.paint();
    }
  }
}
