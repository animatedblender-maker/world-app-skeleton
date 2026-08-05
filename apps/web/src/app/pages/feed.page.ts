import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { Router } from '@angular/router';

import { BottomTabsComponent } from '../components/bottom-tabs.component';
import { MatteryaTopbarComponent } from '../components/matterya-topbar.component';
import { VideoPlayerComponent } from '../components/video-player.component';
import { AuthService } from '../core/services/auth.service';
import { FollowService } from '../core/services/follow.service';
import { LocationService } from '../core/services/location.service';
import { PostsService } from '../core/services/posts.service';
import { ProfileService } from '../core/services/profile.service';
import type { CountryPost } from '../core/models/post.model';
import { resolveAvatarUrl, resolveMediaUrl } from '../core/utils/media-url.util';

@Component({
  selector: 'app-feed-page',
  standalone: true,
  imports: [CommonModule, BottomTabsComponent, MatteryaTopbarComponent, VideoPlayerComponent],
  template: `
    <div class="feed-shell">
      <app-matterya-topbar
        title="Matterya"
        (search)="openSearch()"
        (notifications)="openNotifications()"
      ></app-matterya-topbar>

      <main class="feed-body">
        <section class="sparks-entry" *ngIf="homeCountry">
          <div class="sparks-copy">
            <div class="sparks-title">Matterya Sparks</div>
            <div class="sparks-sub">Short videos from {{ homeCountry }} and beyond</div>
          </div>
          <button type="button" class="sparks-go" (click)="openSparks()">Watch Sparks</button>
        </section>

        <div class="feed-state" *ngIf="loading">Loading feed…</div>
        <div class="feed-state error" *ngIf="!loading && error">{{ error }}</div>
        <div class="feed-state" *ngIf="!loading && !error && !posts.length">
          Your feed is quiet. Posts from everywhere will show up here as people share.
        </div>

        <article class="post-card" *ngFor="let post of posts; trackBy: trackById">
          <div class="post-head" (click)="openAuthor(post)">
            <div class="avatar">
              <img *ngIf="avatarFor(post)" [src]="avatarFor(post)" alt="" />
              <span *ngIf="!avatarFor(post)">{{ initialsFor(post) }}</span>
            </div>
            <div class="meta">
              <div class="name">{{ displayName(post) }}</div>
              <div class="sub">
                <span *ngIf="post.country_name || post.country_code">{{ post.country_name || post.country_code }} · </span>
                {{ post.created_at | date: 'mediumDate' }}
              </div>
            </div>
          </div>

          <div class="post-title" *ngIf="post.title">{{ post.title }}</div>
          <p class="post-body-text" *ngIf="displayBody(post)">{{ displayBody(post) }}</p>

          <div class="post-media" *ngIf="post.media_url && post.media_type !== 'none'">
            <img *ngIf="isImage(post)" [src]="mediaUrl(post)" alt="" />
            <app-video-player
              *ngIf="isVideo(post)"
              [src]="mediaUrl(post)"
              [poster]="post.thumb_url || null"
              adPlacement="video"
              [adCountryCode]="post.country_code || null"
              [adPostId]="post.id"
            ></app-video-player>
          </div>

          <div class="post-actions">
            <button type="button" class="action" (click)="toggleLike(post)" [class.on]="post.liked_by_me">
              {{ post.liked_by_me ? '♥' : '♡' }} {{ post.like_count || 0 }}
            </button>
            <button type="button" class="action" (click)="openPost(post)">
              💬 {{ post.comment_count || 0 }}
            </button>
            <button type="button" class="action muted" (click)="openCountry(post)" *ngIf="post.country_code">
              Globe
            </button>
          </div>
        </article>
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
      .feed-shell {
        min-height: 100%;
        padding-bottom: calc(var(--tabs-safe, 72px) + 12px);
        background:
          radial-gradient(900px 420px at 50% -10%, rgba(255, 255, 255, 0.9), transparent 60%),
          var(--m-paper, #f8f6f2);
      }
      .feed-body {
        /* Normal social-feed column (~FB/X width), not stretched wall-to-wall */
        max-width: 680px;
        margin: 0 auto;
        padding: 0 0 24px;
        width: 100%;
        box-sizing: border-box;
      }
      .sparks-entry {
        margin: 12px 16px;
        padding: 14px 16px;
        border-radius: 14px;
        background: var(--m-surface, #fefdfb);
        border: 0.5px solid var(--m-border, #ddd8d1);
        display: flex;
        align-items: center;
        gap: 12px;
        justify-content: space-between;
      }
      .sparks-title {
        font-family: 'Iowan Old Style', Palatino, Georgia, serif;
        font-size: 18px;
        color: var(--m-ink, #2c2825);
      }
      .sparks-sub {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        margin-top: 2px;
      }
      .sparks-go {
        border: 0;
        border-radius: 10px;
        background: var(--m-ink, #2c2825);
        color: var(--m-surface, #fefdfb);
        font-weight: 650;
        font-size: 13px;
        padding: 10px 14px;
        cursor: pointer;
        white-space: nowrap;
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
      .post-card {
        background: var(--m-surface, #fefdfb);
        border-bottom: 0.5px solid var(--m-divider, #e2ded8);
        padding: 14px 16px 10px;
      }
      .post-head {
        display: flex;
        gap: 12px;
        align-items: center;
        cursor: pointer;
        margin-bottom: 10px;
      }
      .avatar {
        width: 40px;
        height: 40px;
        border-radius: 999px;
        overflow: hidden;
        background: var(--m-canvas-muted, #f2f0ec);
        display: grid;
        place-items: center;
        font-size: 12px;
        font-weight: 700;
        color: var(--m-ink-secondary, #6b645d);
        flex-shrink: 0;
      }
      .avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .name {
        font-weight: 650;
        font-size: 15px;
        color: var(--m-ink, #2c2825);
      }
      .sub {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        margin-top: 2px;
      }
      .post-title {
        font-family: 'Iowan Old Style', 'Palatino Linotype', Palatino, Georgia, serif;
        font-size: 18px;
        line-height: 1.3;
        margin: 0 0 6px;
        color: var(--m-ink, #2c2825);
      }
      .post-body-text {
        margin: 0 0 10px;
        font-size: 15px;
        line-height: 1.45;
        white-space: pre-wrap;
        color: var(--m-ink, #2c2825);
      }
      .post-media {
        border-radius: 12px;
        overflow: hidden;
        background: #0a0a0a;
        margin-bottom: 8px;
      }
      .post-media img {
        display: block;
        width: 100%;
        max-height: 560px;
        object-fit: cover;
      }
      .post-media app-video-player,
      .post-media ::ng-deep .video-shell {
        max-height: 560px;
      }
      .post-media ::ng-deep video {
        max-height: 560px;
        object-fit: contain;
        background: #000;
      }
      .post-actions {
        display: flex;
        gap: 8px;
        padding-top: 4px;
      }
      .action {
        border: 0;
        background: transparent;
        color: var(--m-ink-secondary, #6b645d);
        font-size: 13px;
        font-weight: 600;
        padding: 8px 10px;
        border-radius: 10px;
        cursor: pointer;
      }
      .action:hover {
        background: rgba(44, 40, 37, 0.05);
      }
      .action.on {
        color: var(--m-danger, #ea000b);
      }
      .action.muted {
        margin-left: auto;
        color: var(--m-ink-muted, #948b82);
      }
      /* Desktop: keep standard card column centered in the content pane */
      @media (min-width: 900px) {
        .feed-shell {
          padding-bottom: 32px;
          background: var(--m-canvas-muted, #f2f0ec);
        }
        .feed-body {
          max-width: 680px;
          margin: 0 auto;
          padding: 16px 0 40px;
        }
        .sparks-entry {
          margin: 0 0 12px;
        }
        .post-card {
          margin: 0 0 12px;
          padding: 14px 16px 12px;
          border: 0.5px solid var(--m-border, #ddd8d1);
          border-radius: 12px;
          border-bottom: 0.5px solid var(--m-border, #ddd8d1);
          background: var(--m-surface, #fefdfb);
        }
        .post-media {
          border-radius: 10px;
        }
        .post-media img {
          max-height: 560px;
        }
      }
    `,
  ],
})
export class FeedPageComponent implements OnInit {
  posts: CountryPost[] = [];
  loading = true;
  error = '';
  homeCountry: string | null = null;
  meId: string | null = null;
  myAvatar: string | null = null;
  myInitials = 'ME';

  constructor(
    private postsService: PostsService,
    private auth: AuthService,
    private profiles: ProfileService,
    private follow: FollowService,
    private location: LocationService,
    private router: Router,
    private cdr: ChangeDetectorRef
  ) {}


  async ngOnInit(): Promise<void> {
    // Fire-and-forget so a hung network never blocks bootstrap forever.
    void this.refresh();
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
    void this.router.navigate(['/globe'], {
      queryParams: { panel: 'notifications', search: '0' },
    });
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
    void this.router.navigate(['/globe'], {
      queryParams: { country: code, tab: 'posts' },
    });
  }

  openSparks(): void {
    if (!this.homeCountry) return;
    void this.router.navigate(['/sparks', this.homeCountry]);
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
      let followingIds: string[] = [];

      if (this.meId) {
        try {
          const { meProfile } = await this.withTimeout(this.profiles.meProfile(), 4000, 'profile');
          if (meProfile?.country_code) {
            countryCode = String(meProfile.country_code).trim().toUpperCase();
          }
          authorId = meProfile?.user_id || this.meId;
          this.myAvatar =
            resolveAvatarUrl(meProfile?.avatar_url, meProfile?.username || meProfile?.user_id || this.meId) ||
            null;
          const name = meProfile?.display_name || meProfile?.username || user?.email || 'ME';
          this.myInitials = String(name).slice(0, 2).toUpperCase();
          this.paint();
        } catch {
          // keep cached
        }
        try {
          followingIds = await this.withTimeout(
            this.follow.listFollowingIds(this.meId),
            3000,
            'following'
          );
        } catch {
          followingIds = [];
        }
      }

      this.homeCountry = countryCode;
      this.paint();

      // Primary path: recent posts only (fast). Secondary enrich runs after spinner clears.
      const feed = await this.withTimeout(
        this.postsService.listRecent(40),
        8000,
        'recentPosts'
      ).catch(() => [] as CountryPost[]);

      const filtered = (feed || []).filter(
        (p) => !this.postsService.isMoment(p) && !this.postsService.isSpark(p)
      );
      this.posts = filtered;
      this.loading = false;
      this.paint();

      // Optional country posts — never block the spinner.
      void this.loadSecondary(authorId, countryCode, followingIds);
    } catch (e: any) {
      this.error = e?.message || 'Feed unavailable';
      this.posts = [];
      this.loading = false;
      this.paint();
    } finally {
      window.clearTimeout(hardStop);
      this.loading = false;
      this.paint();
    }
  }

  private async loadSecondary(
    _authorId: string | null,
    countryCode: string | null,
    _followingIds: string[]
  ): Promise<void> {
    try {
      if (!countryCode) return;
      const extra = await this.withTimeout(
        this.postsService.listByCountry(countryCode, 20, {
          demoLimit: 10,
          skipComments: true,
        }),
        6000,
        'countryFeed'
      ).catch(() => [] as CountryPost[]);

      if (extra?.length) {
        const seen = new Set(this.posts.map((p) => p.id));
        const merged = [...this.posts];
        for (const post of extra) {
          if (!post?.id || seen.has(post.id)) continue;
          if (this.postsService.isMoment(post) || this.postsService.isSpark(post)) continue;
          seen.add(post.id);
          merged.push(post);
        }
        merged.sort((a, b) => {
          const ta = Date.parse(a.created_at || '') || 0;
          const tb = Date.parse(b.created_at || '') || 0;
          return tb - ta;
        });
        this.posts = merged.slice(0, 50);
        this.paint();
      }
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
