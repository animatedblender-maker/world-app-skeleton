import { CommonModule } from '@angular/common';
import { Component, EventEmitter, Input, OnChanges, Output, SimpleChanges } from '@angular/core';
import { Router } from '@angular/router';

import type { CountryPost } from '../core/models/post.model';
import { PostsService } from '../core/services/posts.service';
import { resolveAvatarUrl, resolveMediaUrl } from '../core/utils/media-url.util';
import { HubsCatalogService } from '../hubs/hubs-catalog.service';
import { PostCommentsComponent } from './post-comments.component';
import { VideoPlayerComponent } from './video-player.component';

/**
 * Ports iOS FacebookPostCard layout for home / country feeds:
 * journal header → media → body → heart/comment/share/save → meta → inline comments.
 */
@Component({
  selector: 'app-matterya-post-card',
  standalone: true,
  imports: [CommonModule, VideoPlayerComponent, PostCommentsComponent],
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

      <!-- Media — Facebook feed dimensions (FacebookMediaLayout) -->
      <div
        class="media"
        *ngIf="hasMedia"
        [class.video]="isVideo && !isReel"
        [class.reel]="isReel"
        [class.photo]="!isVideo"
        [style.height.px]="!isVideo && photoFrameH ? photoFrameH : null"
      >
        <ng-container *ngIf="isVideo; else imageTpl">
          <!-- iOS HubsOriginBadge: MatteryaHubsLogoView (TV + app icon) + “Hubs” -->
          <button type="button" class="hubs-chip" *ngIf="isLongFormHub" (click)="openHubs($event)" aria-label="Matterya Hubs">
            <span class="hubs-mark" aria-hidden="true">
              <svg class="hubs-tv" viewBox="0 0 24 24" width="16" height="16">
                <!-- antennas -->
                <path d="M7.5 3.2 L8.8 5.6" fill="none" stroke="rgba(255,255,255,0.95)" stroke-width="1.4" stroke-linecap="round"/>
                <path d="M16.5 3.1 L15.2 5.6" fill="none" stroke="rgba(255,255,255,0.95)" stroke-width="1.4" stroke-linecap="round"/>
                <!-- screen bezel -->
                <rect x="3.2" y="4.6" width="17.6" height="12.2" rx="2.4" fill="rgba(254,253,251,0.96)" stroke="rgba(255,255,255,0.95)" stroke-width="1.35"/>
                <!-- stand neck -->
                <path d="M11.2 16.8 L10.6 20.2 L13.4 20.2 L12.8 16.8 Z" fill="rgba(255,255,255,0.92)"/>
                <!-- base -->
                <path d="M6.5 21.1 Q12 22.4 17.5 21.2" fill="none" stroke="rgba(255,255,255,0.95)" stroke-width="1.5" stroke-linecap="round"/>
              </svg>
              <img
                class="hubs-icon"
                src="assets/matterya-app-icon.png"
                alt=""
                width="9"
                height="9"
                decoding="async"
                (error)="onHubsIconError($event)"
              />
            </span>
            <span class="hubs-label">Hubs</span>
          </button>
          <app-video-player
            *ngIf="mediaSrc"
            class="feed-media-player"
            [class.reel-player]="isReel"
            [src]="mediaSrc"
            [poster]="poster"
            [adPlacement]="null"
            [adCountryCode]="post.country_code || null"
            [adPostId]="post.id"
            [showsControls]="!isReel"
            [allowsFullscreen]="!isReel"
            [showMute]="true"
            [preload]="'metadata'"
            centerOverlayMode="always"
            (videoTap)="onVideoTap()"
          ></app-video-player>
        </ng-container>
        <ng-template #imageTpl>
          <img
            *ngIf="mediaSrc"
            class="photo-img"
            [src]="mediaSrc"
            alt=""
            loading="lazy"
            decoding="async"
            (load)="onPhotoLoad($event)"
            (click)="openPost()"
          />
        </ng-template>
      </div>

      <p class="body" *ngIf="bodyText" (click)="openPost()">{{ bodyText }}</p>

      <!-- Actions — iOS FacebookPostCard: heart / bubble.right / arrowshape.turn.up.right / bookmark -->
      <div class="actions">
        <button type="button" class="act" (click)="toggleLike()" [class.on]="post.liked_by_me" aria-label="Like">
          <svg *ngIf="!post.liked_by_me" class="ico" viewBox="0 0 24 24" aria-hidden="true">
            <path
              fill="none"
              stroke="currentColor"
              stroke-width="1.75"
              stroke-linejoin="round"
              d="M12.001 20.727s-7.35-4.48-7.35-9.2a4.12 4.12 0 0 1 7.35-2.55 4.12 4.12 0 0 1 7.35 2.55c0 4.72-7.35 9.2-7.35 9.2z"
            />
          </svg>
          <svg *ngIf="post.liked_by_me" class="ico" viewBox="0 0 24 24" aria-hidden="true">
            <path
              fill="currentColor"
              d="M12.001 20.727s-7.35-4.48-7.35-9.2a4.12 4.12 0 0 1 7.35-2.55 4.12 4.12 0 0 1 7.35 2.55c0 4.72-7.35 9.2-7.35 9.2z"
            />
          </svg>
        </button>
        <button
          type="button"
          class="act"
          [class.muted]="!commentsExpanded"
          [class.on-ink]="commentsExpanded"
          (click)="toggleComments()"
          aria-label="Comment"
        >
          <svg *ngIf="!commentsExpanded" class="ico" viewBox="0 0 24 24" aria-hidden="true">
            <path
              fill="none"
              stroke="currentColor"
              stroke-width="1.75"
              stroke-linejoin="round"
              d="M4.75 17.25V8.6A3.1 3.1 0 0 1 7.85 5.5h8.3A3.1 3.1 0 0 1 19.25 8.6v5.55a3.1 3.1 0 0 1-3.1 3.1H10.1L4.75 19.8v-2.55z"
            />
          </svg>
          <svg *ngIf="commentsExpanded" class="ico" viewBox="0 0 24 24" aria-hidden="true">
            <path
              fill="currentColor"
              d="M4.75 17.25V8.6A3.1 3.1 0 0 1 7.85 5.5h8.3A3.1 3.1 0 0 1 19.25 8.6v5.55a3.1 3.1 0 0 1-3.1 3.1H10.1L4.75 19.8v-2.55z"
            />
          </svg>
        </button>
        <button type="button" class="act" (click)="share()" aria-label="Share">
          <svg class="ico ico-share" viewBox="0 0 24 24" aria-hidden="true">
            <path
              fill="none"
              stroke="currentColor"
              stroke-width="1.9"
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M9.5 7.25V4.5L18.5 12l-9 7.5v-2.85c-5.1 0-7.65 1.35-9.15 4.1 0-5.4 2.55-9.35 9.15-9.9z"
            />
          </svg>
        </button>
        <button type="button" class="act" (click)="toggleSave()" [class.on-ink]="saved" [class.muted]="!saved" aria-label="Save">
          <svg *ngIf="!saved" class="ico" viewBox="0 0 24 24" aria-hidden="true">
            <path
              fill="none"
              stroke="currentColor"
              stroke-width="1.75"
              stroke-linejoin="round"
              d="M7.25 4.25h9.5A1.75 1.75 0 0 1 18.5 6v13.25L12 15.75 5.5 19.25V6A1.75 1.75 0 0 1 7.25 4.25z"
            />
          </svg>
          <svg *ngIf="saved" class="ico" viewBox="0 0 24 24" aria-hidden="true">
            <path
              fill="currentColor"
              d="M7.25 4.25h9.5A1.75 1.75 0 0 1 18.5 6v13.25L12 15.75 5.5 19.25V6A1.75 1.75 0 0 1 7.25 4.25z"
            />
          </svg>
        </button>
        <span class="actions-spacer"></span>
      </div>

      <div class="meta">
        <div class="likes" *ngIf="(post.like_count || 0) > 0">
          {{ post.like_count }} {{ post.like_count === 1 ? 'like' : 'likes' }}
        </div>
        <button
          type="button"
          class="view-comments"
          *ngIf="(post.comment_count || 0) > 0 && !commentsExpanded"
          (click)="toggleComments()"
        >
          View {{ post.comment_count }} {{ post.comment_count === 1 ? 'comment' : 'comments' }}
        </button>
      </div>

      <!-- Inline comments — same page as feed (iOS expandsCommentsInline) -->
      <div class="inline-comments" *ngIf="commentsExpanded">
        <div class="inline-comments-rule"></div>
        <app-post-comments
          [postId]="post.id"
          [post]="post"
          [totalCommentCount]="post.comment_count || 0"
          [initialVisible]="8"
          (commentCountChange)="onCommentCount($event)"
        ></app-post-comments>
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
        border-radius: var(--m-card-radius, 8px);
        /* Facebook: card fills the ~680px feed column */
        margin: 0 var(--m-feed-card-gap, 0px) 16px;
        overflow: hidden;
        box-shadow: 0 1px 2px rgba(44, 40, 37, 0.04);
      }
      .journal-head {
        display: flex;
        align-items: flex-start;
        gap: 12px;
        padding: 12px 16px 10px;
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
        width: var(--m-avatar-sm, 40px);
        height: var(--m-avatar-sm, 40px);
        border-radius: 50%;
        overflow: hidden;
        background: var(--m-canvas-deep, #edeae5);
        display: grid;
        place-items: center;
        font-size: 12px;
        font-weight: 700;
        flex-shrink: 0;
        box-shadow: inset 0 0 0 1px rgba(44, 40, 37, 0.1);
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
        font-size: 17px;
        font-weight: 500;
        line-height: 1.3;
        margin: 0 16px 10px;
        cursor: pointer;
      }
      /*
       * Facebook news-feed media (FacebookMediaLayout / FB feed):
       *  - column width ~680px (parent)
       *  - photo: full card width; height = natural within max 4:5 and 520px
       *  - never crop (object-fit: contain)
       *  - landscape ~1.91:1; square 1:1; portrait max 4:5
       *  - in-feed video: 16:9 of card width
       *  - reel/spark: 9:16 capped
       */
      .media {
        position: relative;
        width: 100%;
        background: #0c0a09;
        overflow: hidden;
        container-type: inline-size;
        container-name: feed-media;
      }
      .media.photo {
        width: 100% !important;
        max-width: 100% !important;
        /* Default before load: FB portrait max (4:5) capped at 520 */
        height: min(520px, 125cqw);
        max-height: 520px !important;
        min-height: 0;
        display: flex !important;
        align-items: center;
        justify-content: center;
        aspect-ratio: unset !important;
        overflow: hidden !important;
        background: #000;
      }
      .media.photo .photo-img,
      .media.photo img {
        position: static !important;
        display: block !important;
        width: auto !important;
        height: auto !important;
        max-width: 100% !important;
        max-height: 100% !important;
        margin: 0 auto !important;
        padding: 0 !important;
        border: 0 !important;
        object-fit: contain !important;
        object-position: center center !important;
        cursor: pointer;
      }
      /* Facebook in-feed horizontal video = 16:9 of post width */
      .media.video {
        width: 100%;
        aspect-ratio: 16 / 9;
        height: auto;
        max-height: min(520px, 68vh);
      }
      .media.reel {
        width: min(100%, calc(min(520px, 68vh) * 9 / 16));
        margin-left: auto;
        margin-right: auto;
        aspect-ratio: 9 / 16;
        height: auto;
        max-height: min(520px, 68vh);
      }
      .media.video app-video-player,
      .media.reel app-video-player,
      .media.video .feed-media-player,
      .media.reel .feed-media-player {
        display: block;
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
      }
      :host ::ng-deep .media.video .video-shell,
      :host ::ng-deep .media.reel .video-shell {
        width: 100% !important;
        height: 100% !important;
        max-height: none !important;
      }
      :host ::ng-deep .media.video video,
      :host ::ng-deep .media.reel video {
        width: 100% !important;
        height: 100% !important;
        max-height: none !important;
        object-fit: cover !important;
        object-position: center center !important;
        background: #000 !important;
      }
      /* iOS HubsOriginBadge — accent capsule + MatteryaHubsLogoView mark */
      .hubs-chip {
        position: absolute;
        top: 10px;
        left: 10px;
        z-index: 4;
        display: inline-flex;
        align-items: center;
        gap: 6px;
        padding: 6px 10px 6px 8px;
        border-radius: 999px;
        background: rgba(123, 99, 71, 0.92);
        border: 0.5px solid rgba(255, 255, 255, 0.28);
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.35);
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.35px;
        color: #fff;
        cursor: pointer;
        line-height: 1;
        font-family: inherit;
      }
      .hubs-chip:hover {
        filter: brightness(1.06);
      }
      .hubs-mark {
        position: relative;
        width: 16px;
        height: 16px;
        flex-shrink: 0;
        display: block;
      }
      .hubs-tv {
        display: block;
        width: 16px;
        height: 16px;
      }
      /* MatteryaAppIcon inset on the TV screen (iOS MatteryaAppIconView) */
      .hubs-icon {
        position: absolute;
        left: 50%;
        top: 42%;
        width: 7px;
        height: 7px;
        transform: translate(-50%, -50%);
        border-radius: 1.5px;
        object-fit: cover;
        box-shadow: 0 0 0 0.4px rgba(44, 40, 37, 0.25);
        pointer-events: none;
      }
      .hubs-label {
        color: #fff;
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 0.35px;
      }
      .body {
        margin: 10px 16px 4px;
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
        align-items: center;
        gap: 18px;
        padding: 8px 16px 4px;
      }
      .actions-spacer {
        flex: 1;
      }
      .act {
        border: 0;
        background: transparent;
        color: var(--m-ink, #2c2825);
        padding: 0;
        cursor: pointer;
        display: grid;
        place-items: center;
        line-height: 0;
      }
      .act.muted {
        color: var(--m-ink-muted, #948b82);
      }
      /* Theme.like / danger for liked heart */
      .act.on {
        color: var(--m-danger, #ea000b);
      }
      /* Saved bookmark uses ink (iOS), not red */
      .act.on-ink {
        color: var(--m-ink, #2c2825);
      }
      .act .ico,
      .act svg {
        display: block;
        width: 22px;
        height: 22px;
      }
      .act .ico-share {
        width: 21px;
        height: 21px;
      }
      .meta {
        padding: 0 16px 12px;
      }
      .likes {
        font-size: 14px;
        font-weight: 650;
        margin-bottom: 4px;
        color: var(--m-ink, #2c2825);
      }
      .view-comments {
        border: 0;
        background: transparent;
        padding: 0;
        font-size: 14px;
        color: var(--m-ink-muted, #948b82);
        cursor: pointer;
      }
      .inline-comments {
        padding: 0 16px 14px;
      }
      .inline-comments-rule {
        height: 0.5px;
        background: var(--m-divider, #e2ded8);
        margin: 4px 0 12px;
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
  /** iOS expandsCommentsInline — stay on the feed card */
  commentsExpanded = false;
  /**
   * Facebook photo frame height (px).
   * natural height at full card width, capped to min(520, width×5/4) — portrait max 4:5.
   * Null until image loads (CSS fallback uses 4:5 max).
   */
  photoFrameH: number | null = null;

  /** FacebookMediaLayout.maxFeedMediaHeight */
  private readonly maxFeedMediaHeight = 520;
  /** FacebookMediaLayout.photoPortraitAspect = 4/5 → max H = W × 5/4 */
  private readonly photoPortraitMaxRatio = 5 / 4;
  constructor(
    private posts: PostsService,
    private catalog: HubsCatalogService,
    private router: Router
  ) {}

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['post'] && this.post) {
      this.saved = this.catalog.isSaved(this.post.id);
      this.photoFrameH = null;
      this.commentsExpanded = false;
    }
  }

  /**
   * Size photo like Facebook feed:
   * - width = full card
   * - height follows image aspect ratio
   * - never taller than 4:5 of width or 520px
   * - never crop (contain inside that frame)
   */
  onPhotoLoad(ev: Event): void {
    const img = ev.target as HTMLImageElement | null;
    if (!img?.naturalWidth || !img.naturalHeight) return;
    const frame = img.closest('.media') as HTMLElement | null;
    const width = frame?.clientWidth || img.clientWidth || 680;
    const naturalH = width * (img.naturalHeight / img.naturalWidth);
    const maxPortraitH = width * this.photoPortraitMaxRatio;
    // Landscape FB guideline ~1.91:1 is a soft floor only for very wide media —
    // we still use natural height so short images stay short.
    const capped = Math.min(naturalH, maxPortraitH, this.maxFeedMediaHeight);
    this.photoFrameH = Math.max(1, Math.round(capped));
  }

  toggleComments(): void {
    this.commentsExpanded = !this.commentsExpanded;
  }

  onCommentCount(n: number): void {
    if (!this.post) return;
    const next = Math.max(this.post.comment_count || 0, n);
    if (next !== this.post.comment_count) {
      this.post = { ...this.post, comment_count: next };
      this.changed.emit(this.post);
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
      .filter(
        (line) =>
          !line.trim().startsWith('__story__|') &&
          !line.trim().startsWith('__spark__|') &&
          !line.trim().startsWith('__hub__|')
      )
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
    // Explicit image types must never take the tall video frame
    if (t === 'image' || t === 'photo' || t === 'gif' || t === 'picture') return false;
    if (t === 'video' || t === 'reel' || t === 'spark') return true;
    const url = this.mediaSrc.toLowerCase();
    if (/\.(jpe?g|png|gif|webp|avif|heic|bmp)(\?|#|$)/i.test(url)) return false;
    return /\.(mp4|webm|mov|m4v)(\?|#|$)/.test(url);
  }

  /** iOS FacebookMediaLayout.reelAspect / isReel */
  get isReel(): boolean {
    return this.isVideo && this.posts.isSpark(this.post);
  }

  /**
   * Hubs badge (iOS HubsOriginBadge) — hub seed posts + re-shares from Hubs,
   * not every plain feed video.
   */
  get isLongFormHub(): boolean {
    if (!this.isVideo || this.posts.isSpark(this.post)) return false;
    return this.looksLikeHubOrigin(this.post);
  }

  private looksLikeHubOrigin(post: CountryPost): boolean {
    if (String(post.external_ref_type || '').toLowerCase() === 'hub') return true;
    const author = String(post.author_id || '');
    if (author.startsWith('hub_') || author.startsWith('ia_') || author.startsWith('archive_')) {
      return true;
    }
    const id = String(post.id || '');
    if (id.startsWith('ia_') || id.startsWith('hub_') || id.startsWith('archive_')) return true;
    const body = String(post.body || '');
    if (/shared from hubs/i.test(body) || body.includes('__hub__|')) return true;
    const media = String(post.media_url || '').toLowerCase();
    if (media.includes('archive.org') || media.includes('/download/')) return true;
    if (post.shared_post && this.looksLikeHubOrigin(post.shared_post as CountryPost)) return true;
    return false;
  }

  /** Prefer original hub/seed id for watch navigation when this is a feed re-share. */
  private hubsWatchId(): string {
    if (String(this.post.external_ref_type || '').toLowerCase() === 'hub') {
      const ref = String(this.post.external_ref_id || '').trim();
      if (ref) return ref;
    }
    const media = String(this.post.media_url || '');
    const m = media.match(/archive\.org\/download\/([^/?#]+)/i);
    if (m?.[1]) return `ia_${m[1]}`;
    return this.post.id;
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
    void this.router.navigate(['/hubs', 'watch', this.hubsWatchId()]);
  }

  /** Prefer app icon; fall back to site logo if the imageset asset 404s. */
  onHubsIconError(ev: Event): void {
    const img = ev.target as HTMLImageElement | null;
    if (!img) return;
    const fallbacks = ['assets/logo.png', '/logo.png', '/matterya-app-icon.png'];
    const cur = img.getAttribute('src') || '';
    const next = fallbacks.find((u) => u !== cur && !img.dataset['tried']?.includes(u));
    if (!next) return;
    img.dataset['tried'] = `${img.dataset['tried'] || ''}|${cur}`;
    img.src = next;
  }

  onVideoTap(): void {
    if (this.posts.isSpark(this.post)) this.openPost();
    else if (this.isLongFormHub) void this.router.navigate(['/hubs', 'watch', this.hubsWatchId()]);
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
