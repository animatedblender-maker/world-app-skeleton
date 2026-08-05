import { CommonModule } from '@angular/common';
import { Component, EventEmitter, Input, OnChanges, Output, SimpleChanges } from '@angular/core';
import { Router } from '@angular/router';

import type { CountryPost } from '../core/models/post.model';
import { PostsService } from '../core/services/posts.service';
import { resolveAvatarUrl, resolveMediaUrl } from '../core/utils/media-url.util';
import { VideoPlayerComponent } from './video-player.component';
import { HubsCatalogService } from '../hubs/hubs-catalog.service';

/**
 * Ports iOS FacebookPostCard layout for home / country feeds:
 * journal header (avatar + name + location + time) → media → body → heart/comment/share/save → meta.
 */
@Component({
  selector: 'app-matterya-post-card',
  standalone: true,
  imports: [CommonModule, VideoPlayerComponent],
  template: `
    <article class="card" [class.edge]="edgeToEdge">
      <!-- Journal header (iOS showsAuthorHeader: false on home feed) -->
      <div class="journal-head">
        <button type="button" class="author-hit" (click)="openAuthor()">
          <div class="avatar">
            <img *ngIf="avatar" [src]="avatar" alt="" />
            <span *ngIf="!avatar">{{ initials }}</span>
          </div>
          <div class="author-meta">
            <div class="name">{{ authorName }}</div>
            <div class="loc" *ngIf="locationLine">{{ locationLine }}</div>
          </div>
        </button>
        <div class="head-right">
          <div class="time">{{ relativeTime }}</div>
          <button type="button" class="icon-ghost" aria-label="More" (click)="openPost()">⋯</button>
        </div>
      </div>

      <h2 class="headline" *ngIf="headline" (click)="openPost()">{{ headline }}</h2>

      <!-- Media -->
      <div class="media" *ngIf="hasMedia" [class.video]="isVideo">
        <ng-container *ngIf="isVideo; else imageTpl">
          <div class="hubs-chip" *ngIf="isLongFormHub" (click)="openHubs($event)">
            <span class="hubs-dot">▣</span> Hubs
          </div>
          <app-video-player
            *ngIf="mediaSrc"
            [src]="mediaSrc"
            [poster]="poster"
            [adPlacement]="isLongFormHub ? null : 'video'"
            [adCountryCode]="post.country_code || null"
            [adPostId]="post.id"
            (videoTap)="onVideoTap()"
          ></app-video-player>
        </ng-container>
        <ng-template #imageTpl>
          <img *ngIf="mediaSrc" [src]="mediaSrc" alt="" (click)="openPost()" />
        </ng-template>
      </div>

      <p class="body" *ngIf="bodyText" (click)="openPost()">{{ bodyText }}</p>

      <!-- Actions — iOS SF Symbol row -->
      <div class="actions">
        <button type="button" class="act" (click)="toggleLike()" [class.on]="post.liked_by_me" aria-label="Like">
          <svg viewBox="0 0 24 24" width="22" height="22" [attr.fill]="post.liked_by_me ? 'currentColor' : 'none'" stroke="currentColor" stroke-width="1.6">
            <path d="M12 20s-7-4.4-7-9.2A4 4 0 0 1 12 7a4 4 0 0 1 7 3.8C19 15.6 12 20 12 20z" stroke-linejoin="round"/>
          </svg>
        </button>
        <button type="button" class="act" (click)="openPost()" aria-label="Comment">
          <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.6">
            <path d="M5 16.5V7.8A2.3 2.3 0 0 1 7.3 5.5h9.4A2.3 2.3 0 0 1 19 7.8v5.4a2.3 2.3 0 0 1-2.3 2.3H9.2L5 18.5v-2z" stroke-linejoin="round"/>
          </svg>
        </button>
        <button type="button" class="act" (click)="share()" aria-label="Share">
          <svg viewBox="0 0 24 24" width="21" height="21" fill="none" stroke="currentColor" stroke-width="1.7">
            <path d="M7 12l10-6v12L7 12z" stroke-linejoin="round"/>
          </svg>
        </button>
        <button type="button" class="act" (click)="toggleSave()" [class.on]="saved" aria-label="Save">
          <svg viewBox="0 0 24 24" width="21" height="21" [attr.fill]="saved ? 'currentColor' : 'none'" stroke="currentColor" stroke-width="1.6">
            <path d="M7 4h10a1 1 0 0 1 1 1v15l-6-3.5L6 20V5a1 1 0 0 1 1-1z" stroke-linejoin="round"/>
          </svg>
        </button>
      </div>

      <div class="meta">
        <div class="likes" *ngIf="(post.like_count || 0) > 0">
          {{ post.like_count }} {{ post.like_count === 1 ? 'like' : 'likes' }}
        </div>
        <button
          type="button"
          class="view-comments"
          *ngIf="(post.comment_count || 0) > 0"
          (click)="openPost()"
        >
          View {{ post.comment_count }} {{ post.comment_count === 1 ? 'comment' : 'comments' }}
        </button>
      </div>
    </article>
  `,
  styles: [
    `
      :host {
        display: block;
      }
      .card {
        background: var(--m-canvas, #f8f6f2);
        border-bottom: 0.5px solid var(--m-divider, #e2ded8);
        padding-bottom: 10px;
        color: var(--m-ink, #2c2825);
      }
      .card:not(.edge) {
        background: var(--m-surface, #fefdfb);
        border: 0.5px solid var(--m-border, #ddd8d1);
        border-radius: var(--m-card-radius, 12px);
        margin: 0 var(--m-feed-gutter, 14px) 12px;
      }
      .journal-head {
        display: flex;
        align-items: flex-start;
        gap: 10px;
        padding: 16px 14px 10px;
      }
      .author-hit {
        display: flex;
        align-items: center;
        gap: 10px;
        flex: 1;
        min-width: 0;
        border: 0;
        background: transparent;
        padding: 0;
        text-align: left;
        color: inherit;
        cursor: pointer;
      }
      .avatar {
        width: 36px;
        height: 36px;
        border-radius: 8px;
        overflow: hidden;
        background: var(--m-canvas-deep, #edeae5);
        display: grid;
        place-items: center;
        font-size: 11px;
        font-weight: 700;
        flex-shrink: 0;
        /* hand-drawn-ish square frame like iOS scrapbook avatar */
        box-shadow: inset 0 0 0 1px rgba(44, 40, 37, 0.12);
      }
      .avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .name {
        font-size: 14px;
        font-weight: 650;
        line-height: 1.2;
      }
      .loc,
      .time {
        font-size: 11px;
        color: var(--m-ink-muted, #948b82);
        margin-top: 2px;
      }
      .head-right {
        display: flex;
        flex-direction: column;
        align-items: flex-end;
        gap: 6px;
      }
      .icon-ghost {
        border: 0;
        background: transparent;
        color: var(--m-ink-muted, #948b82);
        font-size: 18px;
        line-height: 1;
        cursor: pointer;
        padding: 0 4px;
      }
      .headline {
        font-family: 'Iowan Old Style', Palatino, Georgia, serif;
        font-size: 18px;
        font-weight: 500;
        line-height: 1.3;
        margin: 0 14px 10px;
        cursor: pointer;
      }
      .media {
        position: relative;
        width: 100%;
        background: #0c0a09;
        max-height: min(62vh, 520px);
        overflow: hidden;
      }
      .media img {
        display: block;
        width: 100%;
        max-height: min(62vh, 520px);
        object-fit: cover;
        cursor: pointer;
      }
      .media.video app-video-player {
        display: block;
        width: 100%;
      }
      .hubs-chip {
        position: absolute;
        top: 10px;
        left: 10px;
        z-index: 4;
        display: inline-flex;
        align-items: center;
        gap: 5px;
        padding: 5px 10px 5px 6px;
        border-radius: 999px;
        background: rgba(254, 253, 251, 0.94);
        border: 0.5px solid rgba(221, 216, 209, 0.8);
        font-size: 11px;
        font-weight: 700;
        color: var(--m-ink, #2c2825);
        cursor: pointer;
      }
      .hubs-dot {
        font-size: 12px;
      }
      .body {
        margin: 12px 14px 4px;
        font-size: 15px;
        line-height: 1.45;
        color: var(--m-ink-secondary, #6b645d);
        white-space: pre-wrap;
        display: -webkit-box;
        -webkit-line-clamp: 4;
        -webkit-box-orient: vertical;
        overflow: hidden;
        cursor: pointer;
      }
      .actions {
        display: flex;
        gap: 18px;
        padding: 10px 14px 4px;
      }
      .act {
        border: 0;
        background: transparent;
        color: var(--m-ink, #2c2825);
        padding: 0;
        cursor: pointer;
        display: grid;
        place-items: center;
      }
      .act.on {
        color: var(--m-danger, #ea000b);
      }
      .meta {
        padding: 0 14px 14px;
      }
      .likes {
        font-size: 14px;
        font-weight: 650;
        margin-bottom: 4px;
      }
      .view-comments {
        border: 0;
        background: transparent;
        padding: 0;
        font-size: 14px;
        color: var(--m-ink-muted, #948b82);
        cursor: pointer;
      }
    `,
  ],
})
export class MatteryaPostCardComponent implements OnChanges {
  @Input({ required: true }) post!: CountryPost;
  @Input() edgeToEdge = true;
  @Output() liked = new EventEmitter<CountryPost>();
  @Output() changed = new EventEmitter<CountryPost>();

  saved = false;

  constructor(
    private posts: PostsService,
    private catalog: HubsCatalogService,
    private router: Router
  ) {}

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['post'] && this.post) {
      this.saved = this.catalog.isSaved(this.post.id);
    }
  }

  get authorName(): string {
    return this.post.author?.display_name || this.post.author?.username || 'Member';
  }

  get initials(): string {
    return this.authorName.slice(0, 2).toUpperCase();
  }

  get avatar(): string | null {
    const seed = this.post.author?.username || this.post.author_id;
    return resolveAvatarUrl(this.post.author?.avatar_url, seed) || null;
  }

  get locationLine(): string | null {
    return this.post.country_name || this.post.country_code || null;
  }

  get relativeTime(): string {
    return this.catalog.relativeTime(this.post.created_at);
  }

  get headline(): string | null {
    const t = (this.post.title || '').trim();
    return t || null;
  }

  get bodyText(): string {
    let body = String(this.post.body || '');
    body = body
      .split('\n')
      .filter((line) => !line.trim().startsWith('__story__|') && !line.trim().startsWith('__spark__|'))
      .join('\n')
      .trim();
    // If title duplicates body start, still show body.
    return body;
  }

  get hasMedia(): boolean {
    return !!(this.post.media_url || this.post.thumb_url) && this.post.media_type !== 'none';
  }

  get isVideo(): boolean {
    const t = String(this.post.media_type || '').toLowerCase();
    if (t === 'video' || t === 'reel' || t === 'spark') return true;
    const url = this.mediaSrc.toLowerCase();
    return /\.(mp4|webm|mov|m4v)(\?|#|$)/.test(url) || url.includes('/download/');
  }

  get isLongFormHub(): boolean {
    return (
      this.isVideo &&
      !this.posts.isSpark(this.post) &&
      (String(this.post.external_ref_type || '').toLowerCase() === 'hub' ||
        String(this.post.author_id || '').startsWith('hub_') ||
        this.isVideo)
    );
  }

  get mediaSrc(): string {
    return resolveMediaUrl(this.post.media_url || this.post.thumb_url || '');
  }

  get poster(): string | null {
    return this.post.thumb_url ? resolveMediaUrl(this.post.thumb_url) || this.post.thumb_url : null;
  }

  openAuthor(): void {
    const u = this.post.author?.username?.trim();
    if (u) void this.router.navigate(['/user', u]);
    else if (this.post.author_id) void this.router.navigate(['/user', this.post.author_id]);
  }

  openPost(): void {
    if (this.posts.isSpark(this.post)) {
      const country = this.post.country_code || 'WORLD';
      void this.router.navigate(['/sparks', country], {
        queryParams: { post: this.post.id },
        state: { seedPosts: [this.post] },
      });
      return;
    }
    void this.router.navigate(['/post', this.post.id]);
  }

  openHubs(ev: Event): void {
    ev.stopPropagation();
    void this.router.navigate(['/hubs', 'watch', this.post.id]);
  }

  onVideoTap(): void {
    if (this.posts.isSpark(this.post)) this.openPost();
    else if (this.isLongFormHub) void this.router.navigate(['/hubs', 'watch', this.post.id]);
  }

  async toggleLike(): Promise<void> {
    try {
      const updated = this.post.liked_by_me
        ? await this.posts.unlikePost(this.post.id)
        : await this.posts.likePost(this.post.id);
      this.post = { ...this.post, ...updated };
      this.liked.emit(this.post);
      this.changed.emit(this.post);
    } catch {
      // optimistic fallback
      const liked = !this.post.liked_by_me;
      this.post = {
        ...this.post,
        liked_by_me: liked,
        like_count: Math.max(0, (this.post.like_count || 0) + (liked ? 1 : -1)),
      };
      this.changed.emit(this.post);
    }
  }

  toggleSave(): void {
    this.saved = this.catalog.toggleSave(this.post.id);
  }

  async share(): Promise<void> {
    const url = `${window.location.origin}/post/${this.post.id}`;
    try {
      if (navigator.share) {
        await navigator.share({ title: this.headline || this.authorName, url });
      } else {
        await navigator.clipboard.writeText(url);
      }
    } catch {
      // cancelled
    }
  }
}
