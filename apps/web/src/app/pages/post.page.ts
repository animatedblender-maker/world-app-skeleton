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
        <div class="post-body">{{ post.body }}</div>

        <div class="post-media" *ngIf="post.media_url && post.media_type === 'image'">
          <img [src]="post.media_url" alt="post media" />
        </div>
        <div class="post-media" *ngIf="post.media_url && post.media_type === 'video'">
          <app-video-player [src]="post.media_url" [poster]="post.thumb_url || null" preload="metadata"></app-video-player>
        </div>

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
}
