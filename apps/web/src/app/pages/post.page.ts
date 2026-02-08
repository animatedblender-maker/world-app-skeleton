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
          <div class="author-meta">
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
              <div class="shared-info">
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
              <img
                *ngIf="mediaTypes[0] === 'image'"
                [src]="mediaUrls[0]"
                alt="post media"
              />
              <app-video-player
                *ngIf="mediaTypes[0] === 'video'"
                [src]="mediaUrls[0]"
                [poster]="post.thumb_url || null"
                preload="metadata"
              ></app-video-player>
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
        width: min(720px, 100%);
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
        margin-top: 10px;
        border-radius: 12px;
        overflow: hidden;
        background: #000;
      }
      .shared-media img {
        width: 100%;
        height: auto;
        display: block;
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
        height: auto;
        display: block;
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
        margin-top: 14px;
        border-radius: 16px;
        overflow: hidden;
        background: #000;
      }
      .post-media img {
        width: 100%;
        height: auto;
        display: block;
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
    if (raw.startsWith('{') || raw.startsWith('[')) {
      try {
        const parsed = JSON.parse(raw) as any;
        if (Array.isArray(parsed)) return parsed.filter(Boolean).map(String);
        if (Array.isArray(parsed?.urls)) return parsed.urls.filter(Boolean);
        if (parsed?.url) return [parsed.url];
      } catch {}
    }
    return [raw];
  }

  postMediaTypes(post: CountryPost | null): Array<'image' | 'video'> {
    if (!post) return [];
    const raw = String(post.media_url || '').trim();
    if (!raw) return [];
    if (raw.startsWith('{') || raw.startsWith('[')) {
      try {
        const parsed = JSON.parse(raw) as any;
        if (Array.isArray(parsed)) {
          return parsed.map((url: string) => this.inferMediaTypeFromUrl(url, post.media_type));
        }
        if (Array.isArray(parsed?.types) && parsed.types.length) {
          if (Array.isArray(parsed?.urls) && parsed.urls.length) {
            return parsed.urls.map((url: string, idx: number) => {
              const declared = parsed.types?.[idx];
              if (declared === 'video' || declared === 'image') return declared;
              return this.inferMediaTypeFromUrl(url, post.media_type);
            });
          }
          return parsed.types.map((t: string) => (t === 'video' ? 'video' : 'image'));
        }
        if (Array.isArray(parsed?.urls)) {
          return parsed.urls.map((url: string) => this.inferMediaTypeFromUrl(url, post.media_type));
        }
        if (parsed?.url) {
          return [this.inferMediaTypeFromUrl(parsed.url, post.media_type)];
        }
      } catch {}
    }
    return [this.inferMediaTypeFromUrl(raw, post.media_type)];
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
    void this.router.navigate(['/globe'], { queryParams: { search: '1' } });
  }

  openSharedPost(shared: CountryPost, event?: Event): void {
    if (event) {
      event.preventDefault();
      event.stopPropagation();
    }
    if (!shared) return;
    const targetId = shared.shared_post_id || shared.id;
    if (!targetId) return;
    void this.router.navigate(['/post', targetId]);
  }
}
