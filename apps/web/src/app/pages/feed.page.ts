import { CommonModule } from '@angular/common';
import {
  AfterViewChecked,
  ChangeDetectorRef,
  Component,
  ElementRef,
  OnDestroy,
  OnInit,
  ViewChild,
} from '@angular/core';
import { Router } from '@angular/router';
import { Subscription } from 'rxjs';

import { BottomTabsComponent } from '../components/bottom-tabs.component';
import { MatteryaPostCardComponent } from '../components/matterya-post-card.component';
import { MatteryaTopbarComponent } from '../components/matterya-topbar.component';
import { SparksStripComponent } from '../components/sparks-strip.component';
import { AuthService } from '../core/services/auth.service';
import { NotificationsUiService } from '../core/services/notifications-ui.service';
import { LocationService } from '../core/services/location.service';
import { Frame0PosterService } from '../core/services/frame0-poster.service';
import { MediaSessionService } from '../core/services/media-session.service';
import { PostsService } from '../core/services/posts.service';
import { ProfileService } from '../core/services/profile.service';
import { R2PlaybackService } from '../core/services/r2-playback.service';
import { SurfacePageService } from '../core/services/surface-page.service';
import { HubsPlaybackService } from '../hubs/hubs-playback.service';
import type { CountryPost } from '../core/models/post.model';
import { resolveAvatarUrl, resolveMediaUrl } from '../core/utils/media-url.util';

@Component({
  selector: 'app-feed-page',
  standalone: true,
  imports: [
    CommonModule,
    BottomTabsComponent,
    MatteryaTopbarComponent,
    MatteryaPostCardComponent,
    SparksStripComponent,
  ],
  template: `
    <div class="feed-shell">
      <app-matterya-topbar
        title="Matterya"
        (search)="openSearch()"
        (notifications)="openNotifications()"
      ></app-matterya-topbar>

      <div class="feed-layout">
        <main class="feed-body" #feedBody>
          <!-- iOS FeedView: Sparks for you horizontal strip -->
          <app-sparks-strip
            *ngIf="sparksRail.length"
            title="Sparks for you"
            subtitle="Swipe the world on Matterya"
            [posts]="sparksRail"
            [showsBrand]="false"
            (open)="openSpark($event)"
            (brandTap)="openSparks()"
          ></app-sparks-strip>

          <div class="feed-state" *ngIf="loading">Loading feed…</div>
          <div class="feed-state error" *ngIf="!loading && error">{{ error }}</div>
          <div class="feed-state" *ngIf="!loading && !error && !posts.length">
            Your feed is quiet. Posts from everywhere will show up here as people share.
          </div>

          <!-- iOS FacebookPostCard parity — Sparks as cards; AV only on focus winner -->
          <div
            class="feed-card-slot"
            *ngFor="let post of posts; trackBy: trackById"
            [attr.data-post-id]="post.id"
            [attr.data-has-video]="isVideoPost(post) ? '1' : null"
          >
            <app-matterya-post-card
              [post]="post"
              [edgeToEdge]="false"
              [playGate]="focusPostId === post.id && isVideoPost(post)"
              (changed)="onPostChanged($event)"
              (requestPlay)="onRequestPlay($event)"
            ></app-matterya-post-card>
          </div>
        </main>

        <!-- Desktop right rail (≥1280px) — Facebook-web style companion column -->
        <aside class="feed-rail" aria-label="Suggestions">
          <section class="rail-card" *ngIf="sparksRail.length">
            <div class="rail-head">
              <span class="rail-title">Sparks</span>
              <button type="button" class="rail-link" (click)="openSparks()">Open</button>
            </div>
            <button
              type="button"
              class="rail-spark"
              *ngFor="let spark of sparksRail.slice(0, 4); trackBy: trackById"
              (click)="openSpark(spark)"
            >
              <img *ngIf="posterForRail(spark)" [src]="posterForRail(spark)!" alt="" />
              <span class="rail-spark-copy">
                <span class="rail-spark-name">{{ displayName(spark) }}</span>
                <span class="rail-spark-place" *ngIf="spark.country_name || spark.country_code">
                  {{ spark.country_name || spark.country_code }}
                </span>
              </span>
            </button>
          </section>

          <section class="rail-card" *ngIf="railPeople.length">
            <div class="rail-head">
              <span class="rail-title">People</span>
              <button type="button" class="rail-link" (click)="openPeople()">Browse</button>
            </div>
            <button
              type="button"
              class="rail-person"
              *ngFor="let person of railPeople"
              (click)="openRailPerson(person)"
            >
              <span class="rail-avatar">
                <img *ngIf="person.avatar" [src]="person.avatar" alt="" />
                <span *ngIf="!person.avatar">{{ person.initials }}</span>
              </span>
              <span class="rail-person-copy">
                <span class="rail-person-name">{{ person.name }}</span>
                <span class="rail-person-meta">@{{ person.username }}</span>
              </span>
            </button>
          </section>

          <section class="rail-card">
            <div class="rail-head">
              <span class="rail-title">Explore</span>
            </div>
            <button type="button" class="rail-nav" (click)="openHubs()">Matterya Hubs</button>
            <button type="button" class="rail-nav" (click)="openAnonymous()">Anonymous</button>
            <button type="button" class="rail-nav" (click)="openSearch()">Search</button>
          </section>
        </aside>
      </div>

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
      .feed-shell {
        min-height: 100%;
        padding-bottom: calc(var(--tabs-safe, 72px) + 12px);
        background:
          radial-gradient(900px 420px at 50% -10%, rgba(255, 255, 255, 0.9), transparent 60%),
          var(--m-paper, #f8f6f2);
      }
      .feed-layout {
        width: 100%;
        max-width: 1280px;
        margin: 0 auto;
        display: grid;
        grid-template-columns: minmax(0, 1fr);
        gap: 0;
        align-items: start;
        box-sizing: border-box;
      }
      .feed-body {
        max-width: 100%;
        margin: 0 auto;
        padding: 0 0 24px;
        width: 100%;
        box-sizing: border-box;
        --m-feed-card-gap: 0px;
        min-width: 0;
      }
      .feed-rail {
        display: none;
      }
      .feed-state {
        padding: 48px 24px;
        text-align: center;
        color: var(--m-ink-muted, #948b82);
        font-size: 15px;
        line-height: 1.45;
      }
      .feed-state.error {
        color: var(--m-danger, #ea000b);
      }
      .feed-card-slot {
        content-visibility: auto;
        contain-intrinsic-size: 720px;
      }
      .rail-card {
        background: var(--m-surface, #fffcf8);
        border: 1px solid var(--m-border, #ddd6cc);
        border-radius: 16px;
        padding: 14px;
        display: grid;
        gap: 10px;
        box-shadow: 0 10px 28px rgba(44, 40, 37, 0.05);
      }
      .rail-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
      }
      .rail-title {
        font-family: ui-serif, Georgia, serif;
        font-size: 1.05rem;
        font-weight: 500;
        color: var(--m-ink, #2c2825);
      }
      .rail-link,
      .rail-nav {
        border: 0;
        background: transparent;
        color: var(--m-accent, #7b6347);
        font: inherit;
        font-size: 0.85rem;
        font-weight: 650;
        cursor: pointer;
        text-align: left;
        padding: 0;
      }
      .rail-nav {
        padding: 8px 10px;
        border-radius: 10px;
        background: var(--m-wash, #f3efe8);
        border: 1px solid var(--m-border, #ddd6cc);
      }
      .rail-nav:hover,
      .rail-link:hover {
        text-decoration: underline;
      }
      .rail-spark,
      .rail-person {
        display: grid;
        grid-template-columns: 48px 1fr;
        gap: 10px;
        align-items: center;
        width: 100%;
        border: 0;
        background: transparent;
        cursor: pointer;
        text-align: left;
        padding: 0;
        color: inherit;
        font: inherit;
      }
      .rail-spark img {
        width: 48px;
        height: 64px;
        object-fit: cover;
        border-radius: 10px;
        background: #111;
      }
      .rail-spark-copy,
      .rail-person-copy {
        display: grid;
        gap: 2px;
        min-width: 0;
      }
      .rail-spark-name,
      .rail-person-name {
        font-weight: 650;
        font-size: 0.9rem;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .rail-spark-place,
      .rail-person-meta {
        color: var(--m-ink-muted, #948b82);
        font-size: 0.78rem;
      }
      .rail-avatar {
        width: 48px;
        height: 48px;
        border-radius: 50%;
        overflow: hidden;
        display: grid;
        place-items: center;
        background: var(--m-wash, #f3efe8);
        border: 1px solid var(--m-border, #ddd6cc);
        font-weight: 700;
        font-size: 0.85rem;
      }
      .rail-avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      @media (min-width: 900px) {
        .feed-shell {
          padding-bottom: 40px;
          background: var(--m-canvas-muted, #f2f0ec);
          min-height: 100dvh;
        }
        .feed-layout {
          padding: 16px 20px 48px;
        }
        .feed-body {
          width: 100%;
          max-width: 680px;
          margin: 0 auto;
          padding: 0;
          --m-feed-card-gap: 0px;
        }
      }
      @media (min-width: 1280px) {
        .feed-layout {
          grid-template-columns: minmax(0, 1fr) 320px;
          gap: 22px;
          padding: 20px 28px 56px;
        }
        .feed-body {
          max-width: none;
          margin: 0;
        }
        .feed-rail {
          display: grid;
          gap: 14px;
          position: sticky;
          top: 72px;
        }
      }
    `,
  ],
})
export class FeedPageComponent implements OnInit, AfterViewChecked, OnDestroy {
  @ViewChild('feedBody') feedBody?: ElementRef<HTMLElement>;

  posts: CountryPost[] = [];
  sparksRail: CountryPost[] = [];
  railPeople: Array<{
    id: string;
    name: string;
    username: string;
    avatar: string | null;
    initials: string;
  }> = [];
  loading = true;
  error = '';
  homeCountry: string | null = null;
  meId: string | null = null;
  myAvatar: string | null = null;
  myInitials = 'ME';
  /** Single feed focus winner — only this card mounts AV (iOS playGate). */
  focusPostId: string | null = null;

  private focusObserver: IntersectionObserver | null = null;
  private observedIds = new Set<string>();
  private ratios = new Map<string, number>();
  private hubsSub?: Subscription;
  private focusRaf = 0;

  constructor(
    private postsService: PostsService,
    private surface: SurfacePageService,
    private playback: R2PlaybackService,
    private frame0: Frame0PosterService,
    private mediaSession: MediaSessionService,
    private hubsPlayback: HubsPlaybackService,
    private auth: AuthService,
    private profiles: ProfileService,
    private location: LocationService,
    private notificationsUi: NotificationsUiService,
    private router: Router,
    private cdr: ChangeDetectorRef
  ) {}

  async ngOnInit(): Promise<void> {
    // Fire-and-forget so a hung network never blocks bootstrap forever.
    void this.refresh();
    this.hubsSub = this.hubsPlayback.changes$.subscribe((s) => {
      if (s.post) {
        this.mediaSession.claimHubs(s.post.id);
        // Mini/expanded hubs owns AV — clear feed focus so cards stay posters.
        if (this.focusPostId) {
          this.focusPostId = null;
          this.paint();
        }
      } else if (this.mediaSession.hubsOwns) {
        this.mediaSession.releaseHubs();
      }
    });
  }

  ngAfterViewChecked(): void {
    this.ensureFocusObserver();
  }

  ngOnDestroy(): void {
    this.hubsSub?.unsubscribe();
    this.focusObserver?.disconnect();
    this.focusObserver = null;
    if (this.focusRaf) cancelAnimationFrame(this.focusRaf);
    this.mediaSession.releaseFeed(this.focusPostId);
  }

  private paint(): void {
    // Angular 21 is zoneless here — async state must be pushed into the view.
    try {
      this.cdr.detectChanges();
    } catch {
      // component may be destroyed mid-request
    }
  }

  trackById(_: number, post: CountryPost): string {
    return post.id;
  }

  isVideoPost(post: CountryPost): boolean {
    return this.isVideo(post);
  }

  onRequestPlay(post: CountryPost): void {
    if (!post?.id || this.hubsPlayback.isActive) return;
    this.setFocus(post.id);
  }

  onPostChanged(post: CountryPost): void {
    const i = this.posts.findIndex((p) => p.id === post.id);
    if (i >= 0) {
      this.posts[i] = post;
      this.paint();
    }
  }

  private ensureFocusObserver(): void {
    const root = this.feedBody?.nativeElement;
    if (!root || typeof IntersectionObserver === 'undefined') return;
    if (!this.focusObserver) {
      this.focusObserver = new IntersectionObserver(
        (entries) => {
          for (const entry of entries) {
            const id = (entry.target as HTMLElement).dataset['postId'];
            if (!id) continue;
            if (entry.isIntersecting) {
              this.ratios.set(id, entry.intersectionRatio);
            } else {
              this.ratios.delete(id);
            }
          }
          this.scheduleFocusPick();
        },
        {
          root: null,
          // Prefer cards near viewport center.
          rootMargin: '-28% 0px -28% 0px',
          threshold: [0, 0.15, 0.35, 0.55, 0.75, 1],
        }
      );
    }
    const slots = root.querySelectorAll<HTMLElement>('.feed-card-slot[data-has-video="1"]');
    for (const el of Array.from(slots)) {
      const id = el.dataset['postId'];
      if (!id || this.observedIds.has(id)) continue;
      this.focusObserver.observe(el);
      this.observedIds.add(id);
    }
  }

  private scheduleFocusPick(): void {
    if (this.focusRaf) return;
    this.focusRaf = requestAnimationFrame(() => {
      this.focusRaf = 0;
      this.pickFocusWinner();
    });
  }

  private pickFocusWinner(): void {
    if (this.hubsPlayback.isActive || this.mediaSession.sparksOwns) {
      if (this.focusPostId) {
        this.focusPostId = null;
        this.mediaSession.releaseFeed();
        this.paint();
      }
      return;
    }
    let bestId: string | null = null;
    let bestRatio = 0;
    for (const [id, ratio] of this.ratios) {
      if (ratio > bestRatio) {
        bestRatio = ratio;
        bestId = id;
      }
    }
    // Require meaningful visibility before mounting AV.
    if (!bestId || bestRatio < 0.2) {
      if (this.focusPostId) {
        this.mediaSession.releaseFeed(this.focusPostId);
        this.focusPostId = null;
        this.paint();
      }
      return;
    }
    if (bestId !== this.focusPostId) {
      this.setFocus(bestId, bestRatio);
    } else {
      this.mediaSession.claimFeed(bestId, bestRatio);
    }
  }

  private setFocus(postId: string, score = 1): void {
    if (this.focusPostId === postId) {
      this.mediaSession.claimFeed(postId, score);
      return;
    }
    if (!this.mediaSession.claimFeed(postId, score)) return;
    this.focusPostId = postId;
    // Freshen play URL for the winner only (not the whole feed).
    const post = this.posts.find((p) => p.id === postId);
    if (post) {
      void this.playback.freshenPosts([post], 1).then((rows) => {
        const fresh = rows[0];
        if (!fresh) return;
        const i = this.posts.findIndex((p) => p.id === fresh.id);
        if (i >= 0) this.posts[i] = fresh;
        this.paint();
      });
    }
    this.paint();
  }

  displayName(post: CountryPost): string {
    return post.author?.display_name || post.author?.username || 'Member';
  }

  displayBody(post: CountryPost): string {
    return String(post.body || '')
      .split('\n')
      .filter((line) => !line.trim().startsWith('__story__|'))
      .join('\n')
      .trim();
  }

  initialsFor(post: CountryPost): string {
    return this.displayName(post).slice(0, 2).toUpperCase();
  }

  avatarFor(post: CountryPost): string | null {
    const seed = post.author?.username || post.author?.user_id || post.author_id || null;
    const resolved = resolveAvatarUrl(post.author?.avatar_url, seed);
    return resolved || null;
  }

  isImage(post: CountryPost): boolean {
    const t = String(post.media_type || '').toLowerCase();
    if (t === 'story' || t === 'moment') {
      const url = this.mediaUrl(post).toLowerCase();
      return !/\.(mp4|webm|mov|m4v)(\?|#|$)/.test(url);
    }
    return t === 'image' || t === 'photo' || (!!post.media_url && !this.isVideo(post));
  }

  isVideo(post: CountryPost): boolean {
    const t = String(post.media_type || '').toLowerCase();
    if (t === 'story' || t === 'moment') {
      const url = this.mediaUrl(post).toLowerCase();
      return /\.(mp4|webm|mov|m4v)(\?|#|$)/.test(url);
    }
    return t === 'video' || t === 'reel' || t === 'spark';
  }

  mediaUrl(post: CountryPost): string {
    return resolveMediaUrl(post.media_url || post.thumb_url || '');
  }

  openSearch(): void {
    void this.router.navigate(['/search']);
  }

  openNotifications(): void {
    this.notificationsUi.open();
  }

  openAuthor(post: CountryPost): void {
    const username = post.author?.username?.trim();
    if (username) {
      void this.router.navigate(['/user', username]);
      return;
    }
    if (post.author_id) {
      void this.router.navigate(['/user', post.author_id]);
    }
  }

  openPost(post: CountryPost): void {
    void this.router.navigate(['/post', post.id]);
  }

  openCountry(post: CountryPost): void {
    const code = post.country_code?.trim().toUpperCase();
    if (!code) return;
    void this.router.navigate(['/country', code]);
  }

  openSparks(): void {
    const code = this.homeCountry || this.sparksRail[0]?.country_code || 'WORLD';
    void this.router.navigate(['/sparks', code], {
      state: { seedPosts: this.sparksRail.slice(0, 24), seedCountry: code },
    });
  }

  openSpark(post: CountryPost): void {
    const country = post.country_code || this.homeCountry || 'WORLD';
    void this.router.navigate(['/sparks', country], {
      queryParams: { post: post.id },
      state: {
        seedPosts: [post, ...this.sparksRail.filter((p) => p.id !== post.id)].slice(0, 24),
        seedCountry: country,
        countryName: post.country_name,
      },
    });
  }

  openHubs(): void {
    void this.router.navigate(['/hubs']);
  }

  openPeople(): void {
    void this.router.navigate(['/people']);
  }

  openAnonymous(): void {
    void this.router.navigate(['/anonymous']);
  }

  openRailPerson(person: { username: string; id: string }): void {
    const slug = person.username?.trim() || person.id;
    if (!slug) return;
    void this.router.navigate(['/user', slug]);
  }

  posterForRail(post: CountryPost): string | null {
    const raw = post.thumb_url || post.media_url || '';
    const url = resolveMediaUrl(raw);
    if (!url || url.trim().startsWith('{')) return null;
    return url;
  }

  private rebuildRailPeople(): void {
    const seen = new Set<string>();
    const out: FeedPageComponent['railPeople'] = [];
    for (const post of this.posts) {
      const id = post.author_id || post.author?.user_id || post.author?.username || '';
      if (!id || seen.has(id) || id === this.meId) continue;
      seen.add(id);
      const name = this.displayName(post);
      out.push({
        id,
        name,
        username: post.author?.username || id.slice(0, 8),
        avatar: this.avatarFor(post),
        initials: name.slice(0, 2).toUpperCase(),
      });
      if (out.length >= 6) break;
    }
    this.railPeople = out;
  }

  async toggleLike(post: CountryPost): Promise<void> {
    try {
      if (post.liked_by_me) {
        await this.postsService.unlikePost(post.id);
        post.liked_by_me = false;
        post.like_count = Math.max(0, (post.like_count || 0) - 1);
      } else {
        await this.postsService.likePost(post.id);
        post.liked_by_me = true;
        post.like_count = (post.like_count || 0) + 1;
      }
    } catch {
      // ignore
    }
  }

  private async refresh(): Promise<void> {
    this.loading = true;
    this.error = '';
    this.paint();

    // Absolute ceiling: never leave Home on "Loading feed…" forever.
    const hardStop = window.setTimeout(() => {
      if (!this.loading) return;
      this.loading = false;
      if (!this.posts.length && !this.error) {
        this.error = 'Feed is taking too long. Pull to refresh or try again.';
      }
      this.paint();
    }, 10000);

    try {
      const user = await this.withTimeout(this.auth.getUser(), 3000, 'auth').catch(() => null);
      this.meId = user?.id ?? null;
      let countryCode = this.location.getCachedLocation()?.countryCode?.trim().toUpperCase() || null;
      let authorId = this.meId;
      // followingIds stay off the critical path (iOS: refresh follows in parallel / after paint).
      const followingIds: string[] = [];

      if (this.meId) {
        // Profile is best-effort and must not block thin /v1/feed.
        void this.withTimeout(this.profiles.meProfile(), 4000, 'profile')
          .then(({ meProfile }) => {
            if (meProfile?.country_code) {
              this.homeCountry = String(meProfile.country_code).trim().toUpperCase();
            }
            this.myAvatar =
              resolveAvatarUrl(meProfile?.avatar_url, meProfile?.username || meProfile?.user_id || this.meId) ||
              null;
            const name = meProfile?.display_name || meProfile?.username || user?.email || 'ME';
            this.myInitials = String(name).slice(0, 2).toUpperCase();
            this.paint();
          })
          .catch(() => undefined);
      }

      this.homeCountry = countryCode;
      this.paint();

      // iOS path: thin /v1/feed first (Sparks + posts), GraphQL recent as fallback.
      // Keep Sparks on Home (SparkFeedCard) — Moments only are excluded.
      const thin = await this.withTimeout(
        this.surface.fetchHomeFeed(36),
        6000,
        'thinFeed'
      ).catch(() => null);

      let feed = (thin?.items || []).filter((p) => !this.postsService.isMoment(p));
      if (!feed.length) {
        feed = await this.withTimeout(
          this.postsService.listRecent(40),
          8000,
          'recentPosts'
        )
          .then((rows) => (rows || []).filter((p) => !this.postsService.isMoment(p)))
          .catch(() => [] as CountryPost[]);
      }

      // Paint posters first — do NOT await AV URL freshen on the open path.
      this.posts = feed;
      this.sparksRail = feed
        .filter((p) => this.postsService.isSpark(p))
        .slice(0, 12);
      this.rebuildRailPeople();
      this.focusPostId = null;
      this.ratios.clear();
      this.observedIds.clear();
      this.focusObserver?.disconnect();
      this.focusObserver = null;
      this.loading = false;
      this.paint();

      // After first paint: Frame0 thumbs only, then optional secondary top-up.
      // Playback freshen happens for the focus winner in setFocus (no AV storm).
      void this.warmPostersAfterPaint();
      void this.loadSecondary(authorId, countryCode, followingIds);
    } catch (e: any) {
      this.error = e?.message || 'Feed unavailable';
      this.posts = [];
      this.sparksRail = [];
      this.loading = false;
      this.paint();
    } finally {
      window.clearTimeout(hardStop);
      this.loading = false;
      this.paint();
    }
  }

  /** Thumbs / Frame0 only — mirrors iOS warmHead(lite). */
  private async warmPostersAfterPaint(): Promise<void> {
    try {
      const videoIds = this.posts.filter((p) => this.isVideo(p)).slice(0, 24).map((p) => p.id);
      const railIds = this.sparksRail.map((p) => p.id);
      await this.frame0.prefetch([...railIds, ...videoIds]);
      this.paint();
    } catch {
      // best-effort
    }
  }

  private async loadSecondary(
    _authorId: string | null,
    countryCode: string | null,
    _followingIds: string[]
  ): Promise<void> {
    try {
      const extras: CountryPost[] = [];
      if (countryCode) {
        const country = await this.withTimeout(
          this.postsService.listByCountry(countryCode, 20, {
            demoLimit: 10,
            skipComments: true,
          }),
          6000,
          'countryFeed'
        ).catch(() => [] as CountryPost[]);
        extras.push(...(country || []));
      }

      // World Sparks top-up for the rail (iOS discoverSparks /v1/sparks).
      if (this.sparksRail.length < 8) {
        const sparksPage = await this.withTimeout(
          this.surface.fetchSparks(16),
          6000,
          'sparksRail'
        ).catch(() => null);
        if (sparksPage?.items?.length) {
          // Posters only for rail top-up — no playback freshen storm.
          extras.push(...sparksPage.items);
          void this.frame0.prefetch(sparksPage.items.map((p) => p.id));
        }
      }

      if (!extras.length) return;

      const seen = new Set(this.posts.map((p) => p.id));
      const merged = [...this.posts];
      for (const post of extras) {
        if (!post?.id || seen.has(post.id)) continue;
        if (this.postsService.isMoment(post)) continue;
        seen.add(post.id);
        merged.push(post);
      }
      merged.sort((a, b) => {
        const ta = Date.parse(a.created_at || '') || 0;
        const tb = Date.parse(b.created_at || '') || 0;
        return tb - ta;
      });
      this.posts = merged.slice(0, 50);
      if (!this.sparksRail.length) {
        this.sparksRail = this.posts
          .filter((p) => this.postsService.isSpark(p))
          .slice(0, 12);
      }
      this.observedIds.clear();
      this.focusObserver?.disconnect();
      this.focusObserver = null;
      this.paint();
    } catch {
      // secondary is best-effort
    }
  }

  private async withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
    let timer: ReturnType<typeof setTimeout> | null = null;
    try {
      return await Promise.race([
        promise,
        new Promise<T>((_, reject) => {
          timer = setTimeout(() => reject(new Error(`${label} timeout`)), ms);
        }),
      ]);
    } finally {
      if (timer) clearTimeout(timer);
    }
  }
}
