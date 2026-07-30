import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnInit } from '@angular/core';
import { Router } from '@angular/router';

import { BottomTabsComponent } from '../components/bottom-tabs.component';
import { MatteryaTopbarComponent } from '../components/matterya-topbar.component';
import { LocationService } from '../core/services/location.service';
import { PostsService } from '../core/services/posts.service';
import { ProfileService } from '../core/services/profile.service';
import { AuthService } from '../core/services/auth.service';
import type { CountryPost } from '../core/models/post.model';

@Component({
  selector: 'app-hubs-page',
  standalone: true,
  imports: [CommonModule, BottomTabsComponent, MatteryaTopbarComponent],
  template: `
    <div class="hubs-shell">
      <app-matterya-topbar
        title="Matterya Hubs"
        (search)="openSearch()"
        (notifications)="openNotifications()"
      ></app-matterya-topbar>

      <div class="hubs-intro">
        <div class="intro-title">Watch on Matterya Hubs</div>
        <div class="intro-sub">Long-form and Sparks from creators around the world.</div>
        <button type="button" class="sparks-btn" (click)="openSparks()" *ngIf="homeCountry">
          Watch Sparks · {{ homeCountry }}
        </button>
      </div>

      <main class="hubs-body">
        <div class="state" *ngIf="loading">Loading Matterya Hubs…</div>
        <div class="state error" *ngIf="!loading && error">{{ error }}</div>
        <div class="state" *ngIf="!loading && !error && !videos.length">
          No hub videos yet. Publish a video or Spark from Create.
        </div>

        <div class="grid">
          <button type="button" class="tile" *ngFor="let post of videos; trackBy: trackById" (click)="openPost(post)">
            <div class="thumb">
              <img *ngIf="post.thumb_url || isImage(post)" [src]="post.thumb_url || post.media_url" alt="" />
              <div class="play">▶</div>
            </div>
            <div class="tile-meta">
              <div class="tile-title">{{ post.title || post.body || 'Video' }}</div>
              <div class="tile-sub">{{ post.author?.display_name || post.author?.username || 'Creator' }}</div>
            </div>
          </button>
        </div>
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
      .hubs-shell {
        min-height: 100vh;
        padding-bottom: calc(var(--tabs-safe, 72px) + 16px);
        background: var(--m-paper, #f8f6f2);
      }
      .hubs-intro {
        max-width: 720px;
        margin: 0 auto;
        padding: 18px 16px 8px;
      }
      .intro-title {
        font-family: 'Iowan Old Style', Palatino, Georgia, serif;
        font-size: 24px;
        margin-bottom: 4px;
      }
      .intro-sub {
        color: var(--m-ink-muted, #948b82);
        font-size: 14px;
        margin-bottom: 12px;
      }
      .sparks-btn {
        border: 0;
        border-radius: 10px;
        background: var(--m-ink, #2c2825);
        color: var(--m-surface, #fefdfb);
        font-weight: 650;
        font-size: 13px;
        padding: 10px 14px;
        cursor: pointer;
      }
      .hubs-body {
        max-width: 720px;
        margin: 0 auto;
        padding: 8px 12px 24px;
      }
      .state {
        padding: 40px 16px;
        text-align: center;
        color: var(--m-ink-muted, #948b82);
      }
      .state.error {
        color: var(--m-danger, #ea000b);
      }
      .grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
        gap: 12px;
      }
      .tile {
        border: 0.5px solid var(--m-border, #ddd8d1);
        background: var(--m-surface, #fefdfb);
        border-radius: 12px;
        overflow: hidden;
        text-align: left;
        cursor: pointer;
        padding: 0;
      }
      .thumb {
        position: relative;
        aspect-ratio: 16 / 10;
        background: #171412;
      }
      .thumb img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .play {
        position: absolute;
        inset: 0;
        display: grid;
        place-items: center;
        color: rgba(255, 255, 255, 0.92);
        font-size: 22px;
        background: linear-gradient(180deg, transparent, rgba(0, 0, 0, 0.28));
      }
      .tile-meta {
        padding: 10px 10px 12px;
      }
      .tile-title {
        font-size: 13px;
        font-weight: 650;
        line-height: 1.3;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .tile-sub {
        margin-top: 4px;
        font-size: 11px;
        color: var(--m-ink-muted, #948b82);
      }
    `,
  ],
})
export class HubsPageComponent implements OnInit {
  videos: CountryPost[] = [];
  loading = true;
  error = '';
  homeCountry: string | null = null;

  constructor(
    private posts: PostsService,
    private location: LocationService,
    private profiles: ProfileService,
    private auth: AuthService,
    private router: Router,
    private cdr: ChangeDetectorRef
  ) {}

  async ngOnInit(): Promise<void> {
    void this.refresh();
  }

  private paint(): void {
    try {
      this.cdr.detectChanges();
    } catch {
      // destroyed
    }
  }

  private async refresh(): Promise<void> {
    this.loading = true;
    this.error = '';
    this.homeCountry = this.location.getCachedLocation()?.countryCode?.trim().toUpperCase() || null;
    this.paint();

    const hardStop = window.setTimeout(() => {
      if (!this.loading) return;
      this.loading = false;
      if (!this.videos.length && !this.error) {
        this.error = 'Hubs is taking too long. Try again.';
      }
      this.paint();
    }, 10000);

    try {
      try {
        const user = await this.withTimeout(this.auth.getUser(), 3000, 'auth').catch(() => null);
        if (user?.id) {
          const { meProfile } = await this.withTimeout(this.profiles.meProfile(), 4000, 'profile');
          if (meProfile?.country_code) {
            this.homeCountry = String(meProfile.country_code).trim().toUpperCase();
          }
        }
      } catch {
        // keep cached country
      }
      this.paint();

      const recent = await this.withTimeout(this.posts.listRecent(40), 8000, 'recentPosts').catch(
        () => [] as CountryPost[]
      );

      this.videos = (recent || []).filter(
        (p) => !this.posts.isMoment(p) && (this.isVideo(p) || !!p.thumb_url)
      );

      if (!this.videos.length && this.homeCountry) {
        const countryPosts = await this.withTimeout(
          this.posts.listByCountry(this.homeCountry, 30, { skipComments: true }),
          6000,
          'countryPosts'
        ).catch(() => [] as CountryPost[]);
        this.videos = (countryPosts || []).filter(
          (p) => !this.posts.isMoment(p) && (this.isVideo(p) || !!p.media_url)
        );
      }
    } catch (e: any) {
      this.error = e?.message || 'Could not load Hubs';
      this.videos = [];
    } finally {
      window.clearTimeout(hardStop);
      this.loading = false;
      this.paint();
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

  trackById(_: number, post: CountryPost): string {
    return post.id;
  }

  isImage(post: CountryPost): boolean {
    const t = String(post.media_type || '').toLowerCase();
    return t === 'image' || t === 'photo';
  }

  isVideo(post: CountryPost): boolean {
    const t = String(post.media_type || '').toLowerCase();
    return t === 'video' || t === 'reel' || t === 'spark';
  }

  openSearch(): void {
    void this.router.navigate(['/search']);
  }

  openNotifications(): void {
    void this.router.navigate(['/globe'], {
      queryParams: { panel: 'notifications', search: '0' },
    });
  }

  openSparks(): void {
    if (!this.homeCountry) return;
    void this.router.navigate(['/sparks', this.homeCountry]);
  }

  openPost(post: CountryPost): void {
    if (this.isVideo(post) && post.country_code) {
      void this.router.navigate(['/sparks', post.country_code], {
        queryParams: { post: post.id },
      });
      return;
    }
    void this.router.navigate(['/post', post.id]);
  }
}
