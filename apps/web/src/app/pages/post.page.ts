import { CommonModule } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { ActivatedRoute, Router } from '@angular/router';

import { PostsService } from '../core/services/posts.service';
import { NotificationsService } from '../core/services/notifications.service';
import { VideoPlayerComponent } from '../components/video-player.component';
import { BottomTabsComponent } from '../components/bottom-tabs.component';
import type { CountryPost } from '../core/models/post.model';

@Component({
  selector: 'app-post-page',
  standalone: true,
  imports: [CommonModule, VideoPlayerComponent, BottomTabsComponent],
  template: `
    <div class="post-shell">
      <button class="logo-btn" type="button" (click)="goHome()">
        <img src="/logo.png" alt="Matterya" />
      </button>

      <div class="post-card" *ngIf="loading">Loading post...</div>
      <div class="post-card error" *ngIf="!loading && error">{{ error }}</div>

      <div class="post-card" *ngIf="!loading && post">
        <div class="post-head">
          <div class="author-avatar">
            <img *ngIf="post.author?.avatar_url" [src]="post.author?.avatar_url" alt="avatar" />
            <div class="author-initials" *ngIf="!post.author?.avatar_url">
              {{ (post.author?.display_name || post.author?.username || 'U').slice(0, 2).toUpperCase() }}
            </div>
          </div>
          <div
            class="author-meta clickable"
            role="button"
            tabindex="0"
            (click)="openAuthorProfile(post.author, post.author_id)"
            (keyup.enter)="openAuthorProfile(post.author, post.author_id)"
          >
            <div class="author-name">{{ post.author?.display_name || post.author?.username || 'Member' }}</div>
            <div class="author-sub">
              {{ post.country_name || post.country_code || '' }}
              <span *ngIf="post.city_name">• {{ post.city_name }}</span>
            </div>
          </div>
          <div class="post-time">{{ post.created_at | date: 'medium' }}</div>
        </div>

        <div class="post-title" *ngIf="post.title">{{ post.title }}</div>
        <div class="post-body" *ngIf="post.body && !postHasVideo(post)">
          {{ post.body }}
        </div>
        <div class="post-shared" *ngIf="post.shared_post as shared">
          <div class="shared-label">Shared post</div>
          <div
            class="shared-card"
            role="button"
            tabindex="0"
            (click)="openSharedPost(shared, $event)"
            (keyup.enter)="openSharedPost(shared, $event)"
          >
            <div class="shared-author">
              <div class="shared-avatar">
                <img *ngIf="shared.author?.avatar_url" [src]="shared.author?.avatar_url" alt="avatar" />
                <div class="shared-initials" *ngIf="!shared.author?.avatar_url">
                  {{ (shared.author?.display_name || shared.author?.username || 'User').slice(0, 2).toUpperCase() }}
                </div>
              </div>
              <div
                class="shared-info clickable"
                role="button"
                tabindex="0"
                (click)="openAuthorProfile(shared.author, shared.author_id); $event.stopPropagation()"
                (keyup.enter)="openAuthorProfile(shared.author, shared.author_id); $event.stopPropagation()"
              >
                <div class="shared-name">{{ shared.author?.display_name || shared.author?.username || 'Member' }}</div>
                <div class="shared-meta">
                  @{{ shared.author?.username || 'user' }} Â· {{ shared.created_at | date: 'mediumDate' }}
                  <span *ngIf="shared.country_name || shared.country_code"> - {{ shared.country_name || shared.country_code }}</span>
                </div>
              </div>
            </div>
            <div class="shared-title" *ngIf="shared.title">{{ shared.title }}</div>
            <div class="shared-body" *ngIf="shared.body">{{ postPreview(shared.body) }}</div>
            <div class="shared-media" *ngIf="shared.media_url && shared.media_type !== 'none'">
              <ng-container *ngIf="postMediaUrls(shared) as sharedUrls">
                <ng-container *ngIf="postMediaTypes(shared) as sharedTypes">
                  <img
                    *ngIf="sharedTypes[0] === 'image'"
                    [src]="sharedUrls[0]"
                    alt="shared media"
                  />
                  <div class="shared-video" *ngIf="sharedTypes[0] === 'video'">
                    <img *ngIf="shared.thumb_url" [src]="shared.thumb_url" alt="video thumbnail" />
                    <div class="shared-video-tag">Video</div>
                  </div>
                </ng-container>
              </ng-container>
            </div>
          </div>
        </div>

        <ng-container *ngIf="postMediaUrls(post) as mediaUrls">
          <ng-container *ngIf="postMediaTypes(post) as mediaTypes">
            <div class="post-media" *ngIf="mediaUrls.length">
              <ng-container *ngIf="mediaUrls.length <= 1; else postGallery">
                <img
                  *ngIf="mediaTypes[0] === 'image'"
                  [src]="mediaUrls[0]"
                  alt="post media"
                />
                <app-video-player
                  *ngIf="mediaTypes[0] === 'video'"
                  [src]="mediaUrls[0]"
                  [poster]="post.thumb_url || null"
                  [adPlacement]="postIsReel(post) ? 'reel' : 'video'"
                  [adCountryCode]="post.country_code"
                  [adContentCountryCode]="post.country_code"
                  [adPostId]="post.id"
                  preload="metadata"
                ></app-video-player>
              </ng-container>
              <ng-template #postGallery>
                <div class="media-gallery">
                  <div class="media-strip" id="post-page-media-strip" (scroll)="onMediaScroll($event)">
                    <div class="media-item" *ngFor="let url of mediaUrls; let idx = index">
                      <app-video-player
                        *ngIf="mediaTypes[idx] === 'video'"
                        [src]="url"
                        [poster]="post.thumb_url || null"
                        [adPlacement]="postIsReel(post) ? 'reel' : 'video'"
                        [adCountryCode]="post.country_code"
                        [adContentCountryCode]="post.country_code"
                        [adPostId]="post.id"
                        preload="metadata"
                      ></app-video-player>
                      <img
                        *ngIf="mediaTypes[idx] === 'image'"
                        [src]="url"
                        alt="post media"
                      />
                    </div>
                  </div>
                  <button
                    class="media-arrow prev"
                    type="button"
                    [disabled]="mediaIndex === 0"
                    (click)="prevMedia($event)"
                    aria-label="Previous media"
                  >
                    ‹
                  </button>
                  <button
                    class="media-arrow next"
                    type="button"
                    [disabled]="mediaIndex >= mediaUrls.length - 1"
                    (click)="nextMedia(mediaUrls.length, $event)"
                    aria-label="Next media"
                  >
                    ›
                  </button>
                  <div class="media-dots">
                    <span
                      *ngFor="let _ of mediaUrls; let dotIndex = index"
                      [class.active]="dotIndex === mediaIndex"
                    ></span>
                    <span class="media-count">{{ mediaIndex + 1 }}/{{ mediaUrls.length }}</span>
                  </div>
                </div>
              </ng-template>
            </div>
            <div class="post-caption" *ngIf="mediaUrls.length && postCaptionText(post)">
              {{ postCaptionText(post) }}
            </div>
          </ng-container>
        </ng-container>

        <div class="post-actions">
          <div class="post-action">
            <span class="icon">&#x2661;</span>
            <span class="count">{{ post.like_count }}</span>
          </div>
          <div class="post-action">
            <span class="icon">&#x1F4AC;</span>
            <span class="count">{{ post.comment_count }}</span>
          </div>
          <div class="post-action">
            <span class="icon">&#x1F441;</span>
            <span class="count">{{ post.view_count }}</span>
          </div>
        </div>
      </div>
    </div>
    <app-bottom-tabs></app-bottom-tabs>
  `,
  styles: [
    `
      :host {
        display: block;
        min-height: 100dvh;
        height: 100dvh;
        overflow: auto;
        background: radial-gradient(circle at 20% 10%, rgba(40, 80, 120, 0.2), transparent 45%),
          radial-gradient(circle at 80% 0%, rgba(20, 60, 100, 0.25), transparent 40%),
          #060a12;
        color: #e9f2ff;
      }
      .post-shell {
        position: relative;
        min-height: 100dvh;
        padding: 88px 18px calc(24px + var(--tabs-safe, 64px));
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 16px;
      }
      .logo-btn {
        position: fixed;
        top: 18px;
        left: 18px;
        width: 46px;
        height: 46px;
        border-radius: 50%;
        border: 0;
        background: rgba(6, 12, 22, 0.7);
        display: grid;
        place-items: center;
        cursor: pointer;
        z-index: 10;
      }
      .logo-btn img {
        width: 36px;
        height: 36px;
      }
      .post-card {
        width: min(100%, 100%);
        background: rgba(10, 14, 22, 0.86);
        border-radius: 18px;
        border: 1px solid rgba(255, 255, 255, 0.08);
        padding: 20px;
        box-shadow: 0 18px 60px rgba(0, 0, 0, 0.45);
      }
      .post-card.error {
        border-color: rgba(255, 110, 110, 0.35);
        color: #ffb3b3;
      }
      .post-head {
        display: flex;
        gap: 12px;
        align-items: center;
        margin-bottom: 12px;
      }
      .author-avatar {
        width: 46px;
        height: 46px;
        border-radius: 50%;
        overflow: hidden;
        background: rgba(255, 255, 255, 0.1);
        display: grid;
        place-items: center;
      }
      .author-avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .author-initials {
        font-weight: 800;
        letter-spacing: 0.08em;
      }
      .author-meta {
        flex: 1;
        min-width: 0;
      }
      .author-meta.clickable,
      .shared-info.clickable {
        cursor: pointer;
      }
      .author-name {
        font-weight: 700;
      }
      .author-sub {
        font-size: 12px;
        opacity: 0.7;
      }
      .post-time {
        font-size: 11px;
        opacity: 0.7;
        white-space: nowrap;
      }
      .post-title {
        font-weight: 800;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        margin-bottom: 8px;
        font-size: 12px;
      }
      .post-body {
        line-height: 1.6;
      }
      .post-shared {
        margin-top: 14px;
      }
      .shared-label {
        font-size: 11px;
        font-weight: 800;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: rgba(233, 242, 255, 0.6);
        margin-bottom: 6px;
      }
      .shared-card {
        border: 1px solid rgba(255, 255, 255, 0.08);
        border-radius: 14px;
        padding: 12px;
        background: rgba(6, 10, 18, 0.6);
        cursor: pointer;
        transition: transform 0.2s ease, box-shadow 0.2s ease;
      }
      .shared-card:hover {
        transform: translateY(-1px);
        box-shadow: 0 12px 30px rgba(0, 0, 0, 0.35);
      }
      .shared-author {
        display: flex;
        gap: 10px;
        align-items: center;
      }
      .shared-avatar {
        width: 34px;
        height: 34px;
        border-radius: 50%;
        overflow: hidden;
        background: rgba(255, 255, 255, 0.1);
        display: grid;
        place-items: center;
        flex-shrink: 0;
      }
      .shared-avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .shared-initials {
        font-weight: 800;
        font-size: 12px;
        letter-spacing: 0.08em;
      }
      .shared-info {
        min-width: 0;
      }
      .shared-name {
        font-weight: 800;
        font-size: 13px;
      }
      .shared-meta {
        font-size: 11px;
        opacity: 0.7;
      }
      .shared-title {
        margin-top: 10px;
        font-weight: 800;
        font-size: 12px;
        letter-spacing: 0.06em;
        text-transform: uppercase;
      }
      .shared-body {
        margin-top: 6px;
        font-size: 13px;
        line-height: 1.4;
        color: rgba(233, 242, 255, 0.8);
      }
      .shared-media {
        --shared-media-max-height: min(56vh, 680px);
        margin-top: 10px;
        border-radius: 12px;
        overflow: hidden;
        background: #000;
      }
      .shared-media img {
        width: 100%;
        max-height: var(--shared-media-max-height);
        height: auto;
        display: block;
        object-fit: contain;
        margin: 0 auto;
      }
      .shared-video {
        position: relative;
        display: grid;
        place-items: center;
        min-height: 120px;
        background: #0b0f18;
        color: #e6eefc;
        font-size: 12px;
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }
      .shared-video img {
        width: 100%;
        max-height: var(--shared-media-max-height);
        height: auto;
        display: block;
        object-fit: contain;
        margin: 0 auto;
      }
      .shared-video-tag {
        position: absolute;
        right: 8px;
        bottom: 8px;
        background: rgba(0, 0, 0, 0.65);
        color: #fff;
        padding: 4px 6px;
        border-radius: 8px;
        font-size: 10px;
        letter-spacing: 0.12em;
        text-transform: uppercase;
      }
      .post-caption {
        margin-top: 12px;
        line-height: 1.5;
        opacity: 0.9;
      }
      .post-media {
        --post-media-max-height: min(72vh, 820px);
        margin-top: 14px;
        border-radius: 16px;
        overflow: hidden;
        background: #000;
      }
      .post-media app-video-player {
        display: block;
        width: 100%;
        max-height: var(--post-media-max-height);
        --player-max-height: var(--post-media-max-height);
      }
      .post-media img {
        width: 100%;
        max-height: var(--post-media-max-height);
        height: auto;
        display: block;
        object-fit: contain;
        margin: 0 auto;
      }
      .media-gallery {
        position: relative;
        width: 100%;
        background: #000;
        padding-bottom: 34px;
        box-sizing: border-box;
      }
      .media-strip {
        display: flex;
        width: 100%;
        overflow-x: auto;
        scroll-snap-type: x mandatory;
        scroll-behavior: smooth;
        -webkit-overflow-scrolling: touch;
        scrollbar-width: none;
      }
      .media-strip::-webkit-scrollbar {
        display: none;
      }
      .media-item {
        min-width: 100%;
        flex: 0 0 100%;
        scroll-snap-align: center;
        display: flex;
        align-items: center;
        justify-content: center;
        min-height: 180px;
      }
      .media-item app-video-player {
        display: block;
        width: 100%;
      }
      .media-arrow {
        position: absolute;
        top: 50%;
        transform: translateY(-50%);
        width: 42px;
        height: 42px;
        border-radius: 999px;
        border: 1px solid rgba(255, 255, 255, 0.2);
        background: rgba(0, 0, 0, 0.55);
        color: #fff;
        font-size: 28px;
        line-height: 1;
        display: grid;
        place-items: center;
        z-index: 3;
        cursor: pointer;
      }
      .media-arrow.prev {
        left: 10px;
      }
      .media-arrow.next {
        right: 10px;
      }
      .media-arrow:disabled {
        opacity: 0.35;
        cursor: default;
      }
      .media-dots {
        position: absolute;
        bottom: 10px;
        left: 50%;
        transform: translateX(-50%);
        display: flex;
        gap: 6px;
        padding: 4px 8px;
        border-radius: 999px;
        background: rgba(0, 0, 0, 0.4);
        z-index: 2;
        align-items: center;
      }
      .media-dots span {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: rgba(255, 255, 255, 0.5);
        display: inline-block;
      }
      .media-dots span.active {
        background: #fff;
      }
      .media-dots .media-count {
        width: auto;
        height: auto;
        border-radius: 12px;
        padding: 1px 6px;
        font-size: 10px;
        font-weight: 800;
        background: rgba(255, 255, 255, 0.16);
        color: #fff;
      }
      .post-actions {
        display: flex;
        gap: 16px;
        margin-top: 14px;
        font-size: 12px;
        opacity: 0.8;
      }
      .post-action {
        display: inline-flex;
        align-items: center;
        gap: 6px;
      }
      .post-action .icon {
        font-size: 14px;
      }
    `,
  ],
})
export class PostPageComponent implements OnInit {
  post: CountryPost | null = null;
  loading = true;
  error = '';
  mediaIndex = 0;
  private mediaUrlsCache = new Map<string, string[]>();
  private mediaTypesCache = new Map<string, Array<'image' | 'video'>>();

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private posts: PostsService,
    private notifications: NotificationsService
  ) {}

  postHasVideo(post: CountryPost | null): boolean {
    if (!post) return false;
    if (String(post.media_type || '').toLowerCase() === 'video') return true;
    const urls = this.postMediaUrls(post);
    return urls.some((url) => /\.(mp4|webm|mov|m4v|avi|mkv)(\?|#|$)/.test(String(url).toLowerCase()));
  }

  postCaptionText(post: CountryPost | null): string {
    if (!post) return '';
    const caption = String(post.media_caption || '').trim();
    if (caption) return caption;
    if (this.postHasVideo(post)) return String(post.body || '').trim();
    return '';
  }

  postPreview(text: string | null | undefined): string {
    const value = String(text || '').replace(/\s+/g, ' ').trim();
    if (!value) return '';
    const limit = 140;
    if (value.length <= limit) return value;
    const slice = value.slice(0, limit);
    const lastSpace = slice.lastIndexOf(' ');
    return (lastSpace > 40 ? slice.slice(0, lastSpace) : slice).trim();
  }

  postMediaUrls(post: CountryPost | null): string[] {
    if (!post) return [];
    const raw = String(post.media_url || '').trim();
    if (!raw) return [];
    const cachedUrls = this.mediaUrlsCache.get(raw);
    if (cachedUrls) return cachedUrls;
    let urls: string[] = [];
    if (raw.startsWith('{') || raw.startsWith('[')) {
      try {
        const parsed = JSON.parse(raw) as any;
        if (Array.isArray(parsed)) urls = parsed.filter(Boolean).map(String);
        else if (Array.isArray(parsed?.urls)) urls = parsed.urls.filter(Boolean).map(String);
        else if (parsed?.url) urls = [String(parsed.url)];
      } catch {}
    }
    if (!urls.length) urls = [raw];
    this.mediaUrlsCache.set(raw, urls);
    return urls;
  }

  postMediaTypes(post: CountryPost | null): Array<'image' | 'video'> {
    if (!post) return [];
    const raw = String(post.media_url || '').trim();
    if (!raw) return [];
    const typeKey = `${raw}::${String(post.media_type || '').toLowerCase()}`;
    const cachedTypes = this.mediaTypesCache.get(typeKey);
    if (cachedTypes) return cachedTypes;
    let types: Array<'image' | 'video'> = [];
    if (raw.startsWith('{') || raw.startsWith('[')) {
      try {
        const parsed = JSON.parse(raw) as any;
        if (Array.isArray(parsed)) {
          types = parsed.map((url: string) => this.inferMediaTypeFromUrl(url, post.media_type));
        } else if (Array.isArray(parsed?.types) && parsed.types.length) {
          if (Array.isArray(parsed?.urls) && parsed.urls.length) {
            types = parsed.urls.map((url: string, idx: number) => {
              const declared = parsed.types?.[idx];
              if (declared === 'video' || declared === 'image') return declared;
              return this.inferMediaTypeFromUrl(url, post.media_type);
            });
          } else {
            types = parsed.types.map((t: string) => (t === 'video' ? 'video' : 'image'));
          }
        } else if (Array.isArray(parsed?.urls)) {
          types = parsed.urls.map((url: string) => this.inferMediaTypeFromUrl(url, post.media_type));
        } else if (parsed?.url) {
          types = [this.inferMediaTypeFromUrl(parsed.url, post.media_type)];
        }
      } catch {}
    }
    if (!types.length) types = [this.inferMediaTypeFromUrl(raw, post.media_type)];
    this.mediaTypesCache.set(typeKey, types);
    return types;
  }

  private inferMediaTypeFromUrl(
    url: string,
    fallback: string | null | undefined
  ): 'image' | 'video' {
    const lower = String(url || '').toLowerCase();
    if (/\.(mp4|webm|mov|m4v|avi|mkv)(\?|#|$)/.test(lower)) return 'video';
    if (/\.(jpg|jpeg|png|gif|webp|avif)(\?|#|$)/.test(lower)) return 'image';
    return String(fallback || '').toLowerCase() === 'video' ? 'video' : 'image';
  }

  postIsReel(post: CountryPost | null): boolean {
    const raw = String(post?.media_url || '').trim();
    if (!raw) return false;
    if (raw.startsWith('{') || raw.startsWith('[')) {
      try {
        const parsed = JSON.parse(raw) as any;
        const reelFlag = parsed?.reel;
        return reelFlag === true || reelFlag === 'true' || reelFlag === 1 || reelFlag === '1';
      } catch {}
    }
    return false;
  }

  onMediaScroll(event: Event): void {
    const target = event?.target as HTMLElement | null;
    if (!target) return;
    const width = target.clientWidth || 1;
    const max = Math.max(0, target.children.length - 1);
    const idx = Math.round(target.scrollLeft / width);
    this.mediaIndex = Math.min(Math.max(idx, 0), max);
  }

  private scrollMediaTo(index: number): void {
    const strip = document.getElementById('post-page-media-strip');
    if (!strip) return;
    const width = strip.clientWidth || 0;
    strip.scrollTo({ left: width * index, behavior: 'smooth' });
  }

  nextMedia(total: number, event?: Event): void {
    event?.stopPropagation();
    const next = Math.min(total - 1, this.mediaIndex + 1);
    this.mediaIndex = next;
    this.scrollMediaTo(next);
  }

  prevMedia(event?: Event): void {
    event?.stopPropagation();
    const next = Math.max(0, this.mediaIndex - 1);
    this.mediaIndex = next;
    this.scrollMediaTo(next);
  }

  async ngOnInit(): Promise<void> {
    const id = String(this.route.snapshot.paramMap.get('id') || '').trim();
    if (!id) {
      this.error = 'Post not found.';
      this.loading = false;
      return;
    }
    try {
      this.post = await this.posts.getPostById(id);
      if (!this.post) this.error = 'Post not found.';
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    } finally {
      this.loading = false;
    }
  }

  goHome(): void {
    void this.router.navigate(['/globe']);
  }

  goMessages(): void {
    void this.router.navigate(['/messages']);
  }

  openNotifications(): void {
    void this.router.navigate(['/globe'], { queryParams: { panel: 'notifications' } });
  }

  openSearch(): void {
    void this.router.navigate(['/search']);
  }

  openAuthorProfile(
    author: CountryPost['author'] | null | undefined,
    fallbackId?: string | null
  ): void {
    const slug = fallbackId || author?.user_id || author?.username?.trim();
    if (!slug) return;
    void this.router.navigate(['/user', slug]);
  }

  openSharedPost(shared: CountryPost, event?: Event): void {
    if (event) {
      event.preventDefault();
      event.stopPropagation();
    }
    if (!shared) return;
    const targetId = shared.shared_post_id || shared.id;
    if (!targetId) return;
    void this.router.navigate(['/globe'], {
      queryParams: { post: targetId, tab: 'posts', panel: null },
    });
  }
}
