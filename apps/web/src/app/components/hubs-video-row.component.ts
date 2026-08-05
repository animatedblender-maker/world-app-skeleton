import { CommonModule } from '@angular/common';
import { Component, EventEmitter, Input, Output } from '@angular/core';

import type { CountryPost } from '../core/models/post.model';
import { resolveAvatarUrl, resolveMediaUrl } from '../core/utils/media-url.util';
import { HubsCatalogService } from '../hubs/hubs-catalog.service';

/** Ports iOS YouTubeVideoListRow: full-width 16:9 thumb + avatar metadata. */
@Component({
  selector: 'app-hubs-video-row',
  standalone: true,
  imports: [CommonModule],
  template: `
    <button type="button" class="row" (click)="open.emit(post)">
      <div class="thumb">
        <img *ngIf="thumb" [src]="thumb" alt="" />
      </div>
      <div class="meta">
        <div class="avatar">
          <img *ngIf="avatar" [src]="avatar" alt="" />
          <span *ngIf="!avatar">{{ initials }}</span>
        </div>
        <div class="text">
          <div class="title">{{ catalog.displayHeadline(post) }}</div>
          <div class="sub">
            {{ catalog.displayAuthor(post) }}
            <span *ngIf="post.view_count"> · {{ catalog.formatViews(post.view_count) }}</span>
            <span *ngIf="post.created_at"> · {{ catalog.relativeTime(post.created_at) }}</span>
          </div>
        </div>
      </div>
    </button>
  `,
  styles: [
    `
      .row {
        display: block;
        width: 100%;
        border: 0;
        background: transparent;
        padding: 0 0 18px;
        text-align: left;
        color: inherit;
        cursor: pointer;
      }
      .thumb {
        width: 100%;
        aspect-ratio: 16 / 9;
        background: #171412;
        overflow: hidden;
        border-radius: 0;
      }
      .thumb img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .meta {
        display: flex;
        gap: 12px;
        padding: 10px 16px 0;
        align-items: flex-start;
      }
      .avatar {
        width: 40px;
        height: 40px;
        border-radius: 999px;
        overflow: hidden;
        background: var(--m-canvas-deep, #edeae5);
        display: grid;
        place-items: center;
        font-size: 12px;
        font-weight: 700;
        flex-shrink: 0;
      }
      .avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .title {
        font-family: 'Iowan Old Style', Palatino, Georgia, serif;
        font-size: 15px;
        font-weight: 500;
        line-height: 1.3;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
        color: var(--m-ink, #2c2825);
      }
      .sub {
        margin-top: 5px;
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        line-height: 1.35;
      }
      /* Desktop: card tiles inside multi-column grids */
      :host-context(.hubs-video-grid) .row {
        padding: 0;
        height: 100%;
      }
      :host-context(.hubs-video-grid) .thumb {
        border-radius: 12px;
        background: #171412;
      }
      :host-context(.hubs-video-grid) .meta {
        padding: 10px 4px 0;
      }
      :host-context(.hubs-video-grid) .title {
        font-size: 14px;
      }
    `,
  ],
})
export class HubsVideoRowComponent {
  @Input({ required: true }) post!: CountryPost;
  @Output() open = new EventEmitter<CountryPost>();

  constructor(public catalog: HubsCatalogService) {}

  get thumb(): string | null {
    const t = this.post.thumb_url || this.catalog.mediaUrl(this.post);
    return t ? resolveMediaUrl(t) || t : null;
  }

  get avatar(): string | null {
    const u = this.post.author?.avatar_url;
    return u ? resolveAvatarUrl(u) || u : null;
  }

  get initials(): string {
    return this.catalog.displayAuthor(this.post).slice(0, 2).toUpperCase();
  }
}
