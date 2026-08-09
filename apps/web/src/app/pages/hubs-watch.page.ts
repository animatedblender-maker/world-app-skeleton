import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnDestroy, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { Subscription } from 'rxjs';

import { BottomTabsComponent } from '../components/bottom-tabs.component';
import { VideoPlayerComponent } from '../components/video-player.component';
import type { CountryPost, PostComment } from '../core/models/post.model';
import { AuthService } from '../core/services/auth.service';
import { FollowService } from '../core/services/follow.service';
import { PostsService } from '../core/services/posts.service';
import { ProfileService } from '../core/services/profile.service';
import { resolveAvatarUrl, resolveMediaUrl } from '../core/utils/media-url.util';
import { HubsCatalogService } from '../hubs/hubs-catalog.service';
import { HubsEngagementService } from '../hubs/hubs-engagement.service';
import { HubsPlaybackService } from '../hubs/hubs-playback.service';

/** Long-form Hubs watch — ports YouTubeWatchView + continuous player session. */
@Component({
  selector: 'app-hubs-watch-page',
  standalone: true,
  imports: [CommonModule, FormsModule, BottomTabsComponent, VideoPlayerComponent],
  template: `
    <div class="watch-shell" *ngIf="post as p; else loadingTpl">
      <div class="watch-layout">
        <div class="primary">
          <div
            class="player-stage"
            [style.--watch-video-ar]="videoAspectRatio"
          >
            <app-video-player
              *ngIf="mediaSrc"
              class="hubs-watch-player"
              [src]="mediaSrc"
              [poster]="poster"
              [adPlacement]="null"
              [startTime]="startTime"
              [preload]="'auto'"
              [showMute]="true"
              [showsControls]="true"
              [allowsFullscreen]="false"
              centerOverlayMode="always"
              (timeUpdate)="onTime($event)"
              (playState)="onPlayState($event)"
              (aspectRatio)="onVideoAspect($event)"
            ></app-video-player>
            <div class="no-media" *ngIf="!mediaSrc">
              <img *ngIf="poster" [src]="poster" alt="" />
              <span *ngIf="!poster">No playable media</span>
            </div>
          </div>

          <div class="watch-meta">
            <h1 class="title">{{ catalog.displayHeadline(p) }}</h1>
            <div class="stats" *ngIf="(p.view_count || 0) > 0 || p.created_at">
              <span *ngIf="(p.view_count || 0) > 0">{{ catalog.formatViews(p.view_count || 0) }}</span>
              <span *ngIf="(p.view_count || 0) > 0 && p.created_at"> · </span>
              <span *ngIf="p.created_at">{{ catalog.relativeTime(p.created_at) }}</span>
            </div>

            <div class="channel-row">
              <button type="button" class="channel-main" (click)="openChannel()">
                <div class="avatar">
                  <img *ngIf="avatar" [src]="avatar" alt="" />
                  <span *ngIf="!avatar">{{ initials }}</span>
                </div>
                <div class="channel-meta">
                  <div class="channel-name">{{ catalog.displayAuthor(p) }}</div>
                  <div class="channel-sub" *ngIf="p.author?.username">@{{ p.author?.username }}</div>
                </div>
              </button>
              <button
                type="button"
                class="follow-btn"
                *ngIf="canFollow"
                (click)="toggleFollow()"
                [class.on]="isFollowing"
              >
                {{ isFollowing ? 'Following' : 'Follow' }}
              </button>
            </div>

            <div class="actions">
              <button type="button" class="action" (click)="toggleLike()" [class.on]="p.liked_by_me" aria-label="Like">
                <svg *ngIf="!p.liked_by_me" class="ico" viewBox="0 0 24 24" aria-hidden="true">
                  <path fill="none" stroke="currentColor" stroke-width="1.75" stroke-linejoin="round"
                    d="M12.001 20.727s-7.35-4.48-7.35-9.2a4.12 4.12 0 0 1 7.35-2.55 4.12 4.12 0 0 1 7.35 2.55c0 4.72-7.35 9.2-7.35 9.2z"/>
                </svg>
                <svg *ngIf="p.liked_by_me" class="ico" viewBox="0 0 24 24" aria-hidden="true">
                  <path fill="currentColor"
                    d="M12.001 20.727s-7.35-4.48-7.35-9.2a4.12 4.12 0 0 1 7.35-2.55 4.12 4.12 0 0 1 7.35 2.55c0 4.72-7.35 9.2-7.35 9.2z"/>
                </svg>
                <span>{{ p.like_count || 0 }}</span>
              </button>
              <button type="button" class="action muted" (click)="focusComments()" aria-label="Comment">
                <svg class="ico" viewBox="0 0 24 24" aria-hidden="true">
                  <path fill="none" stroke="currentColor" stroke-width="1.75" stroke-linejoin="round"
                    d="M4.75 17.25V8.6A3.1 3.1 0 0 1 7.85 5.5h8.3A3.1 3.1 0 0 1 19.25 8.6v5.55a3.1 3.1 0 0 1-3.1 3.1H10.1L4.75 19.8v-2.55z"/>
                </svg>
                <span>{{ comments.length || p.comment_count || 0 }}</span>
              </button>
              <button type="button" class="action" (click)="share()" aria-label="Share">
                <svg class="ico ico-share" viewBox="0 0 24 24" aria-hidden="true">
                  <path fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"
                    d="M9.5 7.25V4.5L18.5 12l-9 7.5v-2.85c-5.1 0-7.65 1.35-9.15 4.1 0-5.4 2.55-9.35 9.15-9.9z"/>
                </svg>
                <span>Share</span>
              </button>
              <button type="button" class="action" (click)="toggleSave()" [class.on-ink]="saved" [class.muted]="!saved" aria-label="Save">
                <svg *ngIf="!saved" class="ico" viewBox="0 0 24 24" aria-hidden="true">
                  <path fill="none" stroke="currentColor" stroke-width="1.75" stroke-linejoin="round"
                    d="M7.25 4.25h9.5A1.75 1.75 0 0 1 18.5 6v13.25L12 15.75 5.5 19.25V6A1.75 1.75 0 0 1 7.25 4.25z"/>
                </svg>
                <svg *ngIf="saved" class="ico" viewBox="0 0 24 24" aria-hidden="true">
                  <path fill="currentColor"
                    d="M7.25 4.25h9.5A1.75 1.75 0 0 1 18.5 6v13.25L12 15.75 5.5 19.25V6A1.75 1.75 0 0 1 7.25 4.25z"/>
                </svg>
                <span>{{ saved ? 'Saved' : 'Save' }}</span>
              </button>
            </div>

            <div class="description" *ngIf="description">
              <p [class.clamped]="!descOpen">{{ description }}</p>
              <button
                type="button"
                class="more"
                *ngIf="description.length > 160"
                (click)="descOpen = !descOpen"
              >
                {{ descOpen ? 'Show less' : '…more' }}
              </button>
            </div>

            <section class="comments" aria-label="Comments">
              <header class="comments-head">
                <h2 class="comments-title">
                  Comments
                  <span class="comments-count">{{ comments.length || p.comment_count || 0 }}</span>
                </h2>
              </header>

              <form class="composer" (submit)="$event.preventDefault(); submitComment()">
                <div
                  class="hd-avatar"
                  aria-hidden="true"
                  [style.--hd-stroke]="frameAccent(meId || 'me')"
                >
                  <svg class="hd-svg" viewBox="0 0 100 100">
                    <defs>
                      <clipPath [attr.id]="'hd-me-clip'">
                        <path [attr.d]="framePath((meId || 'me') + '-inner')" />
                      </clipPath>
                    </defs>
                    <path class="hd-mat-path" [attr.d]="framePath(meId || 'me')" />
                    <image
                      *ngIf="meAvatar"
                      [attr.href]="meAvatar"
                      x="10"
                      y="10"
                      width="80"
                      height="80"
                      preserveAspectRatio="xMidYMid slice"
                      clip-path="url(#hd-me-clip)"
                    />
                    <g *ngIf="!meAvatar" clip-path="url(#hd-me-clip)">
                      <rect x="10" y="10" width="80" height="80" class="hd-fallback" />
                      <text x="50" y="56" text-anchor="middle" class="hd-initials">{{ meInitials }}</text>
                    </g>
                    <path class="hd-stroke outer" [attr.d]="framePath(meId || 'me')" />
                    <path class="hd-stroke inner" [attr.d]="framePath((meId || 'me') + '-rim')" />
                  </svg>
                </div>
                <div class="composer-field">
                  <textarea
                    rows="1"
                    [(ngModel)]="commentDraft"
                    name="comment"
                    [placeholder]="replyTarget ? 'Write a reply…' : 'Write a comment…'"
                    autocomplete="off"
                    (keydown.enter)="onComposerEnter($event)"
                  ></textarea>
                  <div class="composer-reply" *ngIf="replyTarget as rt">
                    <span>Replying to <strong>{{ rt.authorName }}</strong></span>
                    <button type="button" class="composer-cancel" (click)="cancelReply()">Cancel</button>
                  </div>
                </div>
                <button
                  type="submit"
                  class="composer-send"
                  [disabled]="!commentDraft.trim() || commenting"
                  [attr.aria-label]="replyTarget ? 'Post reply' : 'Post comment'"
                >
                  {{ commenting ? '…' : 'Post' }}
                </button>
              </form>

              <div class="comment-empty" *ngIf="!comments.length">
                No comments yet. Be the first to comment.
              </div>

              <ul class="comment-list" *ngIf="comments.length">
                <li
                  class="comment-row"
                  *ngFor="let c of visibleComments; trackBy: trackComment"
                  [class.is-reply]="!!c.parent_id"
                >
                  <div
                    class="hd-avatar"
                    [class.sm]="!!c.parent_id"
                    aria-hidden="true"
                    [style.--hd-stroke]="frameAccent(c.author_id || c.id)"
                  >
                    <svg class="hd-svg" viewBox="0 0 100 100">
                      <defs>
                        <clipPath [attr.id]="'hd-clip-' + c.id">
                          <path [attr.d]="framePath((c.author_id || c.id) + '-inner')" />
                        </clipPath>
                      </defs>
                      <path class="hd-mat-path" [attr.d]="framePath(c.author_id || c.id)" />
                      <image
                        *ngIf="commentAvatar(c)"
                        [attr.href]="commentAvatar(c)!"
                        x="10"
                        y="10"
                        width="80"
                        height="80"
                        preserveAspectRatio="xMidYMid slice"
                        [attr.clip-path]="'url(#hd-clip-' + c.id + ')'"
                      />
                      <g *ngIf="!commentAvatar(c)" [attr.clip-path]="'url(#hd-clip-' + c.id + ')'">
                        <rect x="10" y="10" width="80" height="80" class="hd-fallback" />
                        <text x="50" y="56" text-anchor="middle" class="hd-initials">
                          {{ commentInitials(c) }}
                        </text>
                      </g>
                      <path class="hd-stroke outer" [attr.d]="framePath(c.author_id || c.id)" />
                      <path
                        class="hd-stroke inner"
                        [attr.d]="framePath((c.author_id || c.id) + '-rim')"
                      />
                    </svg>
                  </div>
                  <div class="c-main">
                    <div class="c-bubble">
                      <div class="c-name">{{ commentAuthor(c) }}</div>
                      <div class="c-body">{{ c.body }}</div>
                    </div>
                    <div class="c-actions">
                      <button
                        type="button"
                        class="c-act"
                        [class.on]="c.liked_by_me"
                        (click)="toggleCommentLike(c)"
                      >
                        {{ c.liked_by_me ? 'Liked' : 'Like' }}
                        <span *ngIf="(c.like_count || 0) > 0" class="c-likes">{{ c.like_count }}</span>
                      </button>
                      <button type="button" class="c-act" (click)="startReply(c)">Reply</button>
                      <span class="c-time" *ngIf="c.created_at">{{ catalog.relativeTime(c.created_at) }}</span>
                    </div>
                  </div>
                </li>
              </ul>

              <button
                type="button"
                class="load-more-comments"
                *ngIf="comments.length > commentLimit"
                (click)="commentLimit = comments.length"
              >
                Load more comments ({{ comments.length - commentLimit }} more)
              </button>
            </section>
          </div>
        </div>

        <aside class="secondary" (scroll)="onRelatedScroll($event)">
          <section class="related">
            <div class="section-title">More on Hubs</div>
            <div class="related-empty" *ngIf="!related.length">No more videos right now.</div>
            <button
              type="button"
              class="related-row"
              *ngFor="let r of related; trackBy: trackRelated"
              (click)="openRelated(r)"
            >
              <div class="r-thumb">
                <img *ngIf="thumbOf(r)" [src]="thumbOf(r)" alt="" />
              </div>
              <div class="r-meta">
                <div class="r-title">{{ catalog.displayHeadline(r) }}</div>
                <div class="r-sub">
                  {{ catalog.displayAuthor(r) }}
                  <span *ngIf="(r.view_count || 0) > 0"> · {{ catalog.formatViews(r.view_count || 0) }}</span>
                </div>
              </div>
            </button>
            <div class="related-loading" *ngIf="relatedLoading">Loading more…</div>
          </section>
        </aside>
      </div>

      <app-bottom-tabs></app-bottom-tabs>

      <!-- iOS SharePostSheet — works on desktop (Web Share is often unavailable) -->
      <div class="share-root" *ngIf="shareOpen" (click)="closeShare()">
        <div class="share-sheet" (click)="$event.stopPropagation()" role="dialog" aria-label="Share">
          <div class="share-handle"></div>
          <header class="share-head">
            <div>
              <div class="share-title">Share</div>
              <div class="share-sub" *ngIf="post">{{ catalog.displayHeadline(post) }}</div>
            </div>
            <button type="button" class="share-close" (click)="closeShare()" aria-label="Close">×</button>
          </header>

          <section class="share-section">
            <div class="share-section-label">Outside Matterya</div>
            <button type="button" class="share-row" (click)="copyShareLink()">
              <span class="share-ico" aria-hidden="true">🔗</span>
              <span class="share-row-text">
                <span class="share-row-title">Copy link</span>
                <span class="share-row-sub">Best on desktop — paste anywhere</span>
              </span>
            </button>
            <button type="button" class="share-row" (click)="shareAnywhere()">
              <span class="share-ico" aria-hidden="true">↗</span>
              <span class="share-row-text">
                <span class="share-row-title">Share anywhere</span>
                <span class="share-row-sub">System share, email, or X / Facebook</span>
              </span>
            </button>
            <div class="share-web-row">
              <button type="button" class="share-chip" (click)="shareViaEmail()">Email</button>
              <button type="button" class="share-chip" (click)="shareViaX()">X</button>
              <button type="button" class="share-chip" (click)="shareViaFacebook()">Facebook</button>
              <button type="button" class="share-chip" (click)="shareViaWhatsApp()">WhatsApp</button>
            </div>
          </section>

          <section class="share-section">
            <div class="share-section-label">Inside Matterya</div>
            <button type="button" class="share-row" [disabled]="shareBusy" (click)="shareToCountryFeed()">
              <span class="share-ico" aria-hidden="true">🌐</span>
              <span class="share-row-text">
                <span class="share-row-title">Share to your feed</span>
                <span class="share-row-sub">{{ shareToFeedSubtitle }}</span>
              </span>
            </button>
            <button type="button" class="share-row" (click)="shareInMessage()">
              <span class="share-ico" aria-hidden="true">✈</span>
              <span class="share-row-text">
                <span class="share-row-title">Send in message</span>
                <span class="share-row-sub">Private chat with a friend</span>
              </span>
            </button>
            <button type="button" class="share-row" (click)="repostWithQuote()">
              <span class="share-ico" aria-hidden="true">❝</span>
              <span class="share-row-text">
                <span class="share-row-title">Repost with quote</span>
                <span class="share-row-sub">Write your take on your home feed</span>
              </span>
            </button>
          </section>

          <div
            class="share-feedback"
            *ngIf="shareFeedback"
            [class.ok]="shareFeedbackKind === 'ok'"
            [class.err]="shareFeedbackKind === 'err'"
          >
            {{ shareFeedback }}
          </div>
        </div>
      </div>
    </div>

    <ng-template #loadingTpl>
      <div class="state">
        <div *ngIf="!error">Loading video…</div>
        <div class="error" *ngIf="error">{{ error }}</div>
        <button type="button" class="back-link" (click)="goHubs()">Back to Hubs</button>
      </div>
      <app-bottom-tabs></app-bottom-tabs>
    </ng-template>
  `,
  styles: [
    `
      :host {
        display: block;
        min-height: 100%;
        background: var(--m-paper, #f8f6f2);
        color: var(--m-ink, #2c2825);
      }
      .watch-shell {
        min-height: 100vh;
        padding-bottom: calc(var(--tabs-safe, 72px) + 24px);
        background: var(--m-paper, #f8f6f2);
      }
      .watch-layout {
        width: 100%;
        max-width: none;
        margin: 0 auto;
        padding: 0 0 8px;
        box-sizing: border-box;
      }
      .primary {
        min-width: 0;
        /* Enables 100cqw for iOS watchPlayerHeight formula */
        container-type: inline-size;
        container-name: watch-primary;
      }
      .secondary {
        min-width: 0;
        padding: 0 14px 16px;
      }
      /*
       * Compact 16:9 stage — not half-screen. Video cover-fills so no black bars.
       */
      .player-stage {
        position: relative;
        width: calc(100% - 24px);
        max-width: none;
        margin: 10px auto 0;
        background: transparent;
        aspect-ratio: 16 / 9;
        height: auto;
        max-height: min(42vh, 100%);
        touch-action: pan-y;
        will-change: transform;
        overflow: hidden;
        flex-shrink: 0;
        border-radius: 12px;
        box-shadow: 0 8px 16px rgba(44, 40, 37, 0.12);
      }
      .player-stage app-video-player,
      .player-stage .hubs-watch-player {
        display: block;
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
      }
      :host ::ng-deep .hubs-watch-player,
      :host ::ng-deep .hubs-watch-player .video-shell {
        width: 100% !important;
        height: 100% !important;
        max-height: none !important;
        background: var(--m-ink, #2c2825) !important;
      }
      /* Full-bleed cover: no letterbox bars top/bottom */
      :host ::ng-deep .hubs-watch-player,
      :host ::ng-deep .hubs-watch-player .video-shell {
        position: absolute !important;
        inset: 0 !important;
        width: 100% !important;
        height: 100% !important;
        background: transparent !important;
      }
      :host ::ng-deep .hubs-watch-player video {
        position: absolute !important;
        inset: 0 !important;
        width: 100% !important;
        height: 100% !important;
        max-height: none !important;
        object-fit: cover !important;
        object-position: center center !important;
        background: transparent !important;
      }
      :host ::ng-deep .hubs-watch-player .video-overlay {
        display: none !important;
      }
      /* Matterya chrome owns controls on watch — don't fight with old mute/center styles */
      :host ::ng-deep .hubs-watch-player .center-play,
      :host ::ng-deep .hubs-watch-player .mute-toggle {
        display: none !important;
      }
      .no-media {
        position: absolute;
        inset: 0;
        display: grid;
        place-items: center;
        color: #aaa;
      }
      .no-media img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .watch-meta {
        /* iOS: padding.top 14 under video so title isn’t covered */
        padding: 14px 16px 8px;
        margin: 0;
      }
      /*
       * Desktop full-bleed watch:
       * Player is 3/4 size (width + height); the freed quarter goes to
       * More on Hubs (right) and meta/comments (below). No side gaps.
       */
      @media (min-width: 900px) {
        :host {
          display: block;
          width: 100%;
          max-width: none;
          height: auto;
          max-height: none;
          overflow: visible;
          --watch-gap: 24px;
          --watch-pad-x: 12px;
          --watch-pad-y: 12px;
          --watch-sticky-top: 0px;
          /*
           * Left open space is filled by the expanded Matterya menu
           * (html.hubs-watch-desktop → wider --m-sidebar-w). Content is
           * full-bleed against that rail; related stays wide.
           */
          --watch-side: clamp(380px, 34vw, 520px);
          /*
           * Compact 16:9 stage — title/comments get the rest of the viewport.
           */
          --watch-player-max-h: min(42vh, 520px);
          --watch-title: 26px;
          --watch-body: 17px;
          --watch-meta: 15px;
          --watch-comment: 16px;
          --watch-comment-name: 14px;
          --watch-related-title: 16px;
          --watch-related-sub: 14px;
          --watch-thumb: clamp(200px, 14vw, 280px);
        }
        .watch-shell {
          height: auto;
          max-height: none;
          min-height: 100dvh;
          width: 100%;
          max-width: none;
          margin: 0;
          padding: 0 0 calc(var(--tabs-safe, 72px) + 32px);
          overflow: visible;
          display: block;
          box-sizing: border-box;
          background: var(--m-paper, #f8f6f2);
        }
        .watch-layout {
          height: auto;
          min-height: 0;
          width: 100%;
          max-width: none;
          margin: 0;
          display: grid;
          /* Flush after expanded menu: player | related (no empty left strip) */
          grid-template-columns: minmax(0, 1fr) var(--watch-side);
          grid-template-rows: auto;
          column-gap: var(--watch-gap);
          row-gap: 0;
          align-items: start;
          padding: var(--watch-pad-y) var(--watch-pad-x) 0;
          box-sizing: border-box;
        }
        .primary {
          display: block;
          min-width: 0;
          min-height: 0;
          width: 100%;
          height: auto;
          max-height: none;
          background: var(--m-paper, #f8f6f2);
          container-type: inline-size;
          container-name: watch-primary;
        }
        .player-stage {
          position: sticky;
          top: var(--watch-sticky-top);
          z-index: 6;
          /* Fixed compact 16:9 + cover fill — no black margins, no half-screen stage. */
          width: 100%;
          max-width: none;
          margin: 0;
          aspect-ratio: 16 / 9;
          height: auto;
          max-height: var(--watch-player-max-h);
          min-height: 160px;
          border-radius: 12px;
          box-shadow: 0 8px 16px rgba(44, 40, 37, 0.12);
          background: transparent;
        }
        .watch-meta {
          /* Larger block under the shorter player — title, actions, comments */
          height: auto;
          min-height: 0;
          overflow: visible;
          margin: 0;
          padding: 20px 4px 40px;
          font-size: var(--watch-body);
        }
        .watch-meta .title {
          font-size: var(--watch-title);
          line-height: 1.28;
          margin-bottom: 10px;
        }
        .watch-meta .description {
          font-size: var(--watch-body) !important;
          padding: 16px 18px;
          margin-bottom: 20px;
        }
        .watch-meta .comments {
          margin-top: 16px;
          padding-top: 12px;
        }
        .watch-meta .comments-title {
          font-size: 22px !important;
        }
        .watch-meta .c-body {
          font-size: var(--watch-comment) !important;
        }
        .watch-meta .composer textarea {
          min-height: 48px;
          font-size: 16px !important;
        }
        .secondary {
          width: var(--watch-side);
          min-width: var(--watch-side);
          max-width: var(--watch-side);
          min-height: 0;
          height: auto;
          position: sticky;
          top: var(--watch-sticky-top);
          max-height: calc(100dvh - var(--watch-sticky-top));
          overflow: auto;
          padding: 0 0 12px;
          overscroll-behavior: contain;
          align-self: start;
          border-left: none;
          background: var(--m-paper, #f8f6f2);
        }
        .related {
          display: block !important;
        }
        .section-title {
          padding-top: 0;
          margin-bottom: 12px;
          font-size: 18px;
          font-weight: 700;
          position: sticky;
          top: 0;
          background: var(--m-paper, #f8f6f2);
          z-index: 2;
          padding-bottom: 8px;
        }
        .title {
          font-size: var(--watch-title);
          line-height: 1.3;
          margin: 0 0 8px;
        }
        .stats {
          font-size: var(--watch-meta) !important;
          margin-bottom: 14px;
        }
        .channel-row {
          margin-bottom: 14px;
        }
        .channel-name {
          font-size: calc(var(--watch-body) + 1px) !important;
        }
        .channel-sub {
          font-size: var(--watch-meta) !important;
        }
        .description {
          margin-bottom: 18px;
          font-size: var(--watch-body) !important;
          line-height: 1.5;
          padding: 14px 16px;
        }
        .description .more {
          font-size: 14px;
        }
        .comments {
          margin-top: 12px;
          margin-bottom: 16px;
        }
        .comments-title {
          font-size: 20px !important;
        }
        .comment-empty,
        .related-empty {
          font-size: var(--watch-meta) !important;
        }
        .c-name {
          font-size: var(--watch-comment-name) !important;
        }
        .c-body {
          font-size: var(--watch-comment) !important;
        }
        .composer textarea {
          font-size: 16px !important;
        }
        .avatar {
          width: 48px;
          height: 48px;
          font-size: 14px;
        }
        .action {
          font-size: 15px;
          padding: 10px 16px;
        }
        .follow-btn {
          font-size: 15px;
          padding: 10px 18px;
        }
        .related .section-title {
          font-size: 20px;
          margin-bottom: 14px;
        }
        .related-row {
          padding: 12px;
          gap: 14px;
          border-radius: 14px;
          background: var(--m-surface, #fefdfb);
          border: 0.5px solid var(--m-border, #ddd8d1);
          box-shadow: 0 2px 8px rgba(44, 40, 37, 0.04);
          margin-bottom: 10px;
        }
        .related-row:hover {
          background: var(--m-canvas-muted, #f2f0ec);
          border-color: var(--m-divider, #e2ded8);
        }
        .r-thumb {
          width: var(--watch-thumb);
          max-width: 52%;
          aspect-ratio: 16 / 9;
          border-radius: 12px;
          flex-shrink: 0;
        }
        .r-title {
          font-size: var(--watch-related-title) !important;
          font-weight: 650;
          line-height: 1.35;
          -webkit-line-clamp: 2;
        }
        .r-sub {
          font-size: var(--watch-related-sub) !important;
          margin-top: 6px;
        }
      }
      @media (min-width: 1280px) {
        :host {
          --watch-gap: 24px;
          --watch-pad-x: 16px;
          --watch-pad-y: 16px;
          --watch-side: clamp(400px, 34vw, 540px);
          --watch-player-max-h: min(96vh, 1040px);
          --watch-title: 28px;
          --watch-body: 17px;
          --watch-comment: 16px;
          --watch-related-title: 16px;
          --watch-related-sub: 14px;
          --watch-thumb: clamp(210px, 15vw, 290px);
        }
      }
      @media (min-width: 1600px) {
        :host {
          --watch-gap: 24px;
          --watch-pad-x: 16px;
          --watch-side: clamp(420px, 32vw, 560px);
          --watch-player-max-h: min(98vh, 1100px);
          --watch-title: 30px;
          --watch-body: 18px;
          --watch-comment: 16px;
          --watch-related-title: 17px;
          --watch-related-sub: 14px;
          --watch-thumb: clamp(220px, 14vw, 300px);
        }
      }
      .title {
        font-family: 'Iowan Old Style', Palatino, Georgia, serif;
        font-size: 20px;
        font-weight: 600;
        line-height: 1.25;
        margin: 0 0 6px;
      }
      .stats {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        margin-bottom: 14px;
      }
      .channel-row {
        display: flex;
        align-items: center;
        gap: 10px;
        margin-bottom: 12px;
      }
      .channel-main {
        display: flex;
        align-items: center;
        gap: 10px;
        flex: 1;
        min-width: 0;
        border: 0;
        background: transparent;
        padding: 0;
        cursor: pointer;
        text-align: left;
        color: inherit;
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
      .channel-meta {
        flex: 1;
        min-width: 0;
      }
      .channel-name {
        font-weight: 650;
        font-size: 14px;
      }
      .channel-sub {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
      }
      .follow-btn {
        border: 0;
        border-radius: 999px;
        padding: 8px 14px;
        font-weight: 650;
        font-size: 13px;
        background: var(--m-ink, #2c2825);
        color: #fefdfb;
        cursor: pointer;
      }
      .follow-btn.on {
        background: var(--m-canvas-deep, #edeae5);
        color: var(--m-ink, #2c2825);
      }
      .actions {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 10px;
        margin-bottom: 14px;
      }
      .action {
        border: 0.5px solid var(--m-border, #ddd8d1);
        background: var(--m-surface, #fefdfb);
        border-radius: 999px;
        padding: 8px 14px;
        font-size: 13px;
        font-weight: 600;
        cursor: pointer;
        color: var(--m-ink, #2c2825);
        display: inline-flex;
        align-items: center;
        gap: 7px;
        line-height: 1;
      }
      .action.muted {
        color: var(--m-ink-muted, #948b82);
      }
      .action .ico {
        width: 18px;
        height: 18px;
        display: block;
        flex-shrink: 0;
      }
      .action .ico-share {
        width: 17px;
        height: 17px;
      }
      /* liked heart — Theme.like red, not inverted chip */
      .action.on {
        color: var(--m-danger, #ea000b);
        background: var(--m-surface, #fefdfb);
        border-color: var(--m-border, #ddd8d1);
      }
      .action.on-ink {
        color: var(--m-ink, #2c2825);
      }
      .description {
        background: var(--m-canvas-muted, #f2f0ec);
        border-radius: 12px;
        padding: 12px;
        margin-bottom: 18px;
        font-size: 13px;
        line-height: 1.45;
      }
      .description p {
        margin: 0;
      }
      .description p.clamped {
        display: -webkit-box;
        -webkit-line-clamp: 3;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .more {
        border: 0;
        background: transparent;
        color: var(--m-ink-secondary, #6b645d);
        font-weight: 650;
        font-size: 12px;
        margin-top: 6px;
        cursor: pointer;
        padding: 0;
      }
      .section-title {
        font-weight: 700;
        font-size: 15px;
        margin-bottom: 10px;
      }
      /* —— Matterya comments (iOS PostComments / FacebookCommentRow) —— */
      .comments {
        margin: 18px 0 28px;
        padding-top: 6px;
        border-top: 0.5px solid var(--m-divider, #e2ded8);
      }
      .comments-head {
        display: flex;
        align-items: baseline;
        gap: 10px;
        margin-bottom: 14px;
      }
      .comments-title {
        margin: 0;
        font-family: 'Iowan Old Style', Palatino, Georgia, serif;
        font-size: 18px;
        font-weight: 650;
        letter-spacing: -0.01em;
        color: var(--m-ink, #2c2825);
      }
      .comments-count {
        display: inline-block;
        margin-left: 8px;
        font-family: system-ui, -apple-system, sans-serif;
        font-size: 14px;
        font-weight: 650;
        color: var(--m-ink-muted, #948b82);
        vertical-align: middle;
      }
      .composer {
        display: flex;
        align-items: flex-start;
        gap: 10px;
        margin-bottom: 18px;
      }
      /*
       * Hand-drawn picture frame avatar — ports iOS HandDrawnPictureFrame / AvatarView
       * (scrapbook photo frame, not a circle).
       */
      .hd-avatar {
        --hd-size: 40px;
        --hd-stroke: rgba(44, 40, 37, 0.55);
        width: var(--hd-size);
        height: var(--hd-size);
        flex-shrink: 0;
        filter: drop-shadow(0 1.5px 2.5px rgba(44, 40, 37, 0.14));
      }
      .hd-avatar.sm {
        --hd-size: 30px;
      }
      .hd-svg {
        display: block;
        width: 100%;
        height: 100%;
        overflow: visible;
      }
      .hd-mat-path {
        fill: var(--m-paper, #f8f6f2);
      }
      .hd-fallback {
        fill: var(--m-canvas-muted, #f2f0ec);
      }
      .hd-initials {
        fill: var(--m-ink-secondary, #6b645d);
        font-size: 22px;
        font-weight: 650;
        font-family: 'Iowan Old Style', Palatino, Georgia, serif;
      }
      .hd-stroke {
        fill: none;
        stroke: var(--hd-stroke);
        stroke-linejoin: round;
        stroke-linecap: round;
      }
      .hd-stroke.outer {
        stroke-width: 2.6;
      }
      .hd-stroke.inner {
        stroke-width: 1.15;
        opacity: 0.48;
        transform-origin: 50% 50%;
        transform: scale(0.9);
      }
      .composer-field {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 6px;
      }
      .composer textarea {
        width: 100%;
        min-height: 42px;
        max-height: 120px;
        resize: vertical;
        border: 0.5px solid var(--m-border, #ddd8d1);
        border-radius: 22px;
        padding: 11px 16px;
        font-size: 14px;
        line-height: 1.35;
        font-family: inherit;
        color: var(--m-ink, #2c2825);
        background: var(--m-surface, #fefdfb);
        box-sizing: border-box;
        outline: none;
      }
      .composer textarea:focus {
        border-color: var(--m-accent, #7b6347);
        box-shadow: 0 0 0 3px rgba(123, 99, 71, 0.12);
      }
      .composer-reply {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
        padding: 0 4px;
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
      }
      .composer-reply strong {
        color: var(--m-accent, #7b6347);
        font-weight: 650;
      }
      .composer-cancel {
        border: 0;
        background: transparent;
        color: var(--m-ink-muted, #948b82);
        font-size: 12px;
        font-weight: 650;
        cursor: pointer;
        padding: 0;
      }
      .composer-send {
        flex-shrink: 0;
        align-self: flex-start;
        margin-top: 2px;
        border: 0;
        border-radius: 999px;
        padding: 10px 16px;
        min-height: 42px;
        background: var(--m-ink, #2c2825);
        color: #fefdfb;
        font-size: 14px;
        font-weight: 650;
        cursor: pointer;
      }
      .composer-send:disabled {
        opacity: 0.4;
        cursor: default;
      }
      .comment-empty,
      .related-empty {
        font-size: 14px;
        color: var(--m-ink-muted, #948b82);
        padding: 4px 0 14px;
      }
      .comment-list {
        list-style: none;
        margin: 0;
        padding: 0;
        display: flex;
        flex-direction: column;
        gap: 14px;
      }
      .comment-row {
        display: flex;
        align-items: flex-start;
        gap: 10px;
      }
      .comment-row.is-reply {
        /* iOS CommentThreadLayout.indentPerLevel = 44 */
        margin-left: 44px;
        padding-left: 10px;
        border-left: 2px solid color-mix(in srgb, var(--m-accent, #7b6347) 45%, transparent);
        box-sizing: border-box;
      }
      .c-main {
        flex: 1;
        min-width: 0;
      }
      .c-bubble {
        display: inline-block;
        max-width: 100%;
        background: var(--m-canvas-muted, #f2f0ec);
        border-radius: 16px;
        padding: 10px 14px 12px;
        box-sizing: border-box;
      }
      .c-name {
        font-size: 13px;
        font-weight: 700;
        color: var(--m-ink, #2c2825);
        margin-bottom: 3px;
        line-height: 1.25;
      }
      .c-body {
        font-size: 14px;
        line-height: 1.45;
        color: var(--m-ink, #2c2825);
        white-space: pre-wrap;
        word-break: break-word;
      }
      .c-actions {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 12px;
        margin-top: 6px;
        padding-left: 4px;
      }
      .c-act {
        border: 0;
        background: transparent;
        padding: 0;
        font-size: 12px;
        font-weight: 650;
        color: var(--m-ink-muted, #948b82);
        cursor: pointer;
      }
      .c-act.on {
        color: var(--m-ink, #2c2825);
      }
      .c-act:hover {
        color: var(--m-ink, #2c2825);
      }
      .c-likes {
        margin-left: 4px;
        font-weight: 700;
      }
      .c-time {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
      }
      .load-more-comments {
        margin-top: 12px;
        border: 0;
        background: transparent;
        padding: 0;
        font-size: 14px;
        font-weight: 650;
        color: var(--m-ink-secondary, #6b645d);
        cursor: pointer;
      }
      .load-more-comments:hover {
        color: var(--m-ink, #2c2825);
      }
      .related-loading {
        padding: 14px 4px 20px;
        font-size: 13px;
        font-weight: 650;
        color: var(--m-ink-muted, #948b82);
        text-align: center;
      }
      .related-row {
        display: flex;
        gap: 12px;
        width: 100%;
        border: 0;
        background: transparent;
        padding: 8px 0;
        cursor: pointer;
        text-align: left;
        color: inherit;
        box-sizing: border-box;
      }
      .r-thumb {
        width: 160px;
        aspect-ratio: 16 / 9;
        border-radius: 12px;
        overflow: hidden;
        background: #171412;
        flex-shrink: 0;
      }
      .r-thumb img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .r-meta {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        justify-content: center;
        gap: 2px;
      }
      .r-title {
        font-size: 13px;
        font-weight: 650;
        line-height: 1.3;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .r-sub {
        margin-top: 4px;
        font-size: 11px;
        color: var(--m-ink-muted, #948b82);
      }
      .state {
        min-height: 50vh;
        display: grid;
        place-content: center;
        gap: 12px;
        text-align: center;
        color: var(--m-ink-muted, #948b82);
        padding: 40px 16px;
      }
      .state .error {
        color: var(--m-danger, #ea000b);
      }
      .back-link {
        border: 0;
        background: var(--m-ink, #2c2825);
        color: #fefdfb;
        border-radius: 10px;
        padding: 10px 16px;
        font-weight: 650;
        cursor: pointer;
      }
      @media (max-width: 520px) {
        .r-thumb {
          width: 128px;
        }
      }

      /* —— Share sheet (iOS SharePostSheet) —— */
      .share-root {
        position: fixed;
        inset: 0;
        z-index: 200;
        background: rgba(20, 16, 14, 0.45);
        display: flex;
        align-items: flex-end;
        justify-content: center;
        padding: 16px;
        box-sizing: border-box;
      }
      .share-sheet {
        width: min(440px, 100%);
        max-height: min(86vh, 640px);
        overflow: auto;
        background: var(--m-surface, #fefdfb);
        color: var(--m-ink, #2c2825);
        border-radius: 18px;
        border: 0.5px solid var(--m-border, #ddd8d1);
        box-shadow: 0 24px 60px rgba(44, 40, 37, 0.22);
        padding: 10px 0 16px;
        box-sizing: border-box;
      }
      @media (min-width: 900px) {
        .share-root {
          align-items: center;
        }
        .share-sheet {
          width: min(420px, 100%);
        }
        .share-handle {
          display: none;
        }
      }
      .share-handle {
        width: 40px;
        height: 4px;
        border-radius: 999px;
        background: var(--m-border, #ddd8d1);
        margin: 4px auto 10px;
      }
      .share-head {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 12px;
        padding: 4px 18px 12px;
        border-bottom: 0.5px solid var(--m-divider, #e2ded8);
      }
      .share-title {
        font-family: 'Iowan Old Style', Palatino, Georgia, serif;
        font-size: 20px;
        font-weight: 600;
      }
      .share-sub {
        margin-top: 4px;
        font-size: 13px;
        color: var(--m-ink-muted, #948b82);
        line-height: 1.35;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .share-close {
        border: 0;
        background: var(--m-canvas-muted, #f2f0ec);
        width: 32px;
        height: 32px;
        border-radius: 999px;
        font-size: 20px;
        line-height: 1;
        cursor: pointer;
        color: var(--m-ink, #2c2825);
        flex-shrink: 0;
      }
      .share-section {
        padding: 10px 10px 4px;
      }
      .share-section-label {
        padding: 8px 10px 6px;
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        color: var(--m-ink-muted, #948b82);
      }
      .share-row {
        display: flex;
        align-items: center;
        gap: 14px;
        width: 100%;
        border: 0;
        background: transparent;
        text-align: left;
        padding: 12px 10px;
        border-radius: 12px;
        cursor: pointer;
        color: inherit;
      }
      .share-row:hover:not(:disabled) {
        background: rgba(44, 40, 37, 0.05);
      }
      .share-row:disabled {
        opacity: 0.5;
        cursor: default;
      }
      .share-ico {
        width: 36px;
        height: 36px;
        border-radius: 10px;
        background: var(--m-canvas-muted, #f2f0ec);
        display: grid;
        place-items: center;
        font-size: 16px;
        flex-shrink: 0;
      }
      .share-row-text {
        display: grid;
        gap: 2px;
        min-width: 0;
      }
      .share-row-title {
        font-size: 15px;
        font-weight: 650;
      }
      .share-row-sub {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        line-height: 1.3;
      }
      .share-feedback {
        margin: 8px 18px 0;
        padding: 10px 12px;
        border-radius: 10px;
        background: var(--m-canvas-muted, #f2f0ec);
        font-size: 13px;
        font-weight: 600;
        color: var(--m-ink-secondary, #6b645d);
      }
      .share-feedback.ok {
        background: rgba(107, 88, 65, 0.14);
        color: var(--m-ink, #2c2825);
      }
      .share-feedback.err {
        background: rgba(234, 0, 11, 0.1);
        color: var(--m-danger, #ea000b);
      }
      .share-web-row {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
        padding: 4px 10px 12px;
      }
      .share-chip {
        border: 0.5px solid var(--m-border, #ddd8d1);
        background: var(--m-paper, #f8f6f2);
        color: var(--m-ink, #2c2825);
        border-radius: 999px;
        padding: 8px 12px;
        font-size: 12px;
        font-weight: 650;
        cursor: pointer;
      }
      .share-chip:hover {
        background: var(--m-canvas-muted, #f2f0ec);
      }
    `,
  ],
})
export class HubsWatchPageComponent implements OnInit, OnDestroy {
  post: CountryPost | null = null;
  related: CountryPost[] = [];
  relatedLoading = false;
  private relatedOffset = 0;
  private relatedCycle = 0;
  private relatedPageSize = 12;
  private relatedSeq = 0;
  comments: PostComment[] = [];
  commentLimit = 12;
  commentDraft = '';
  commenting = false;
  replyTarget: { threadRootId: string; authorName: string } | null = null;
  descOpen = false;
  saved = false;
  isFollowing = false;
  canFollow = false;
  meId: string | null = null;
  meAvatar: string | null = null;
  meInitials = 'You';
  error = '';
  startTime = 0;
  mediaSrc = '';
  poster: string | null = null;
  avatar: string | null = null;
  initials = '?';
  description = '';
  /** Native video width/height ratio — stage matches so contain fills without letterbox gaps. */
  videoAspectRatio = 16 / 9;

  shareOpen = false;
  shareBusy = false;
  shareFeedback = '';
  shareFeedbackKind: 'ok' | 'err' | '' = '';
  private shareFeedbackTimer: ReturnType<typeof setTimeout> | null = null;
  homeCountryName = 'your country';
  homeCountryCode: string | null = null;

  private routeSub?: Subscription;
  /** Ignore stale async results when route id changes mid-load. */
  private loadSeq = 0;
  private mediaMql: MediaQueryList | null = null;
  private mediaMqlHandler: (() => void) | null = null;

  constructor(
    public catalog: HubsCatalogService,
    private engagement: HubsEngagementService,
    private playback: HubsPlaybackService,
    private follow: FollowService,
    private auth: AuthService,
    private profiles: ProfileService,
    private posts: PostsService,
    private route: ActivatedRoute,
    private router: Router,
    private cdr: ChangeDetectorRef
  ) {}

  get shareToFeedSubtitle(): string {
    const src = this.post?.country_name?.trim();
    if (src && src !== this.homeCountryName) {
      return `Adds this ${src} video to ${this.homeCountryName}`;
    }
    return `Posts land in ${this.homeCountryName}`;
  }

  get shareUrl(): string {
    if (!this.post) return window.location.href;
    return `${window.location.origin}/hubs/watch/${this.post.id}`;
  }

  get shareText(): string {
    if (!this.post) return 'Matterya';
    const title = this.catalog.displayHeadline(this.post);
    const author = this.catalog.displayAuthor(this.post);
    return `${title} — ${author} on Matterya`;
  }

  ngOnInit(): void {
    this.bindWatchDesktopNav();
    this.routeSub = this.route.paramMap.subscribe((params) => {
      void this.load(params.get('id'));
    });
  }

  ngOnDestroy(): void {
    this.loadSeq += 1;
    this.routeSub?.unsubscribe();
    this.unbindWatchDesktopNav();
    if (this.shareFeedbackTimer) clearTimeout(this.shareFeedbackTimer);
    if (this.playback.post && this.playback.expanded) {
      this.playback.minimize();
    }
  }

  /** Widen Matterya left rail on desktop watch so it fills the left open space. */
  private bindWatchDesktopNav(): void {
    if (typeof window === 'undefined' || typeof document === 'undefined') return;
    this.mediaMql = window.matchMedia('(min-width: 900px)');
    this.mediaMqlHandler = () => {
      document.documentElement.classList.toggle(
        'hubs-watch-desktop',
        !!this.mediaMql?.matches
      );
    };
    this.mediaMqlHandler();
    this.mediaMql.addEventListener?.('change', this.mediaMqlHandler);
  }

  private unbindWatchDesktopNav(): void {
    if (typeof document !== 'undefined') {
      document.documentElement.classList.remove('hubs-watch-desktop');
    }
    if (this.mediaMql && this.mediaMqlHandler) {
      this.mediaMql.removeEventListener?.('change', this.mediaMqlHandler);
    }
    this.mediaMql = null;
    this.mediaMqlHandler = null;
  }

  private paint(): void {
    try {
      this.cdr.detectChanges();
    } catch {
      // destroyed
    }
  }

  private async load(id: string | null): Promise<void> {
    if (!id) {
      this.error = 'Missing video';
      this.post = null;
      this.paint();
      return;
    }
    const seq = ++this.loadSeq;
    this.error = '';

    // Kick catalog in background for related rail — don't block first paint on it.
    const catalogPromise =
      this.catalog.currentCatalog.length > 0
        ? Promise.resolve(this.catalog.currentCatalog)
        : this.catalog.loadCatalog().catch(() => this.catalog.currentCatalog);

    try {
      // Prefer in-memory catalog hit; fall back to seed/network resolve only.
      let post =
        this.catalog.findPost(id) ||
        (await this.catalog.resolvePost(id));
      if (seq !== this.loadSeq) return;

      if (!post) {
        // Last chance after catalog finishes (deep link race).
        await catalogPromise;
        if (seq !== this.loadSeq) return;
        post = await this.catalog.resolvePost(id);
        if (seq !== this.loadSeq) return;
      }
      if (!post) {
        this.error = 'Video not found';
        this.post = null;
        this.paint();
        return;
      }

      // —— First paint ASAP: player + chrome (comments/auth deferred) ——
      post = this.engagement.applyLikeState(post);
      this.post = post;
      this.saved = this.catalog.isSaved(post.id);
      this.description = this.catalog.displayBody(post) || post.media_caption || '';
      if (String(post.external_ref_type || '').toLowerCase() === 'hub') {
        this.descOpen = true;
      }
      this.mediaSrc = resolveMediaUrl(this.catalog.mediaUrl(post)) || this.catalog.mediaUrl(post);
      this.videoAspectRatio = 16 / 9;
      this.poster = post.thumb_url ? resolveMediaUrl(post.thumb_url) || post.thumb_url : null;
      this.avatar = post.author?.avatar_url
        ? resolveAvatarUrl(post.author.avatar_url) || post.author.avatar_url
        : null;
      const name = this.catalog.displayAuthor(post);
      this.initials = name.slice(0, 2).toUpperCase();
      this.startTime = this.catalog.playbackPosition(post.id);
      // Local comments only for instant UI; full seed thread fills in async.
      this.comments = this.engagement
        .listComments(post.id)
        .filter((c) => !!String(c.body || '').trim());
      this.commentLimit = Math.max(this.comments.length, 8);
      if (this.catalog.currentCatalog.length > 0) {
        this.resetRelatedFeed(post, this.catalog.currentCatalog);
      } else {
        this.related = [];
      }

      this.playback.start(post, true);
      this.paint();

      // Related when catalog is ready (usually already warm from Hubs home).
      void catalogPromise.then((catalog) => {
        if (seq !== this.loadSeq || !this.post) return;
        this.resetRelatedFeed(this.post, catalog);
      });

      // Comments + auth in parallel — never block the video surface.
      void Promise.all([
        this.engagement.loadComments(post).catch(() => this.comments),
        this.auth.getUser().catch(() => null),
      ]).then(async ([comments, user]) => {
        if (seq !== this.loadSeq || !this.post) return;
        this.comments = (comments || []).filter((c) => !!String(c.body || '').trim());
        this.commentLimit = Math.max(this.comments.length, 20);
        this.post = {
          ...this.post,
          comment_count: Math.max(this.post.comment_count || 0, this.comments.length),
        };
        this.meId = user?.id ?? null;
        if (user?.id) {
          try {
            const { meProfile } = await this.profiles.meProfile();
            if (seq !== this.loadSeq) return;
            const name =
              meProfile?.display_name || meProfile?.username || user.email || 'You';
            this.meInitials = String(name).slice(0, 2).toUpperCase();
            this.meAvatar = meProfile?.avatar_url
              ? resolveAvatarUrl(meProfile.avatar_url) || meProfile.avatar_url
              : null;
            this.homeCountryName = meProfile?.country_name || 'your country';
            this.homeCountryCode = meProfile?.country_code || null;
          } catch {
            this.meInitials = 'You';
            this.meAvatar = null;
          }
        }
        this.canFollow =
          !!this.meId &&
          this.meId !== this.post.author_id &&
          !this.post.author_id.startsWith('hub_');
        if (this.canFollow && this.meId) {
          this.isFollowing = await this.follow
            .isFollowing(this.meId, this.post.author_id)
            .catch(() => false);
        }
        if (seq !== this.loadSeq) return;
        this.paint();
      });
    } catch (e: any) {
      if (seq !== this.loadSeq) return;
      this.error = e?.message || 'Could not load video';
      this.post = null;
      this.paint();
    }
  }

  get visibleComments(): PostComment[] {
    return this.comments
      .filter((c) => !!String(c.body || '').trim())
      .slice(0, this.commentLimit);
  }

  trackPost(_: number, p: CountryPost): string {
    return p.id;
  }

  /** Allow the same video to reappear across infinite cycles without trackBy collisions. */
  trackRelated(index: number, p: CountryPost): string {
    return `${p.id}__${index}`;
  }

  trackComment(_: number, c: PostComment): string {
    return c.id;
  }

  onRelatedScroll(ev: Event): void {
    const el = ev.target as HTMLElement | null;
    if (!el || this.relatedLoading || !this.post) return;
    if (el.scrollTop + el.clientHeight < el.scrollHeight - 160) return;
    this.appendRelatedPage();
  }

  private resetRelatedFeed(post: CountryPost, catalog: CountryPost[]): void {
    this.related = [];
    this.relatedOffset = 0;
    this.relatedCycle = 0;
    this.relatedSeq += 1;
    this.appendRelatedPage(post, catalog);
    // Prefetch a couple pages so the rail feels full immediately
    this.appendRelatedPage(post, catalog);
  }

  private appendRelatedPage(post?: CountryPost | null, catalog?: CountryPost[]): void {
    const p = post ?? this.post;
    if (!p) return;
    const cat = catalog ?? this.catalog.currentCatalog;
    if (!cat?.length) return;
    this.relatedLoading = true;
    const page = this.catalog.relatedVideosPage(
      p,
      cat,
      this.relatedOffset,
      this.relatedPageSize,
      this.relatedCycle
    );
    const batch = this.engagement.applyMany(page.items);
    if (batch.length) {
      this.related = this.related.concat(batch);
    }
    this.relatedOffset = page.nextOffset;
    this.relatedCycle = page.nextCycle;
    this.relatedLoading = false;
    this.paint();
  }

  thumbOf(p: CountryPost): string | null {
    const t = p.thumb_url || this.catalog.mediaUrl(p);
    return t ? resolveMediaUrl(t) || t : null;
  }

  commentAuthor(c: PostComment): string {
    return c.author?.display_name || c.author?.username || 'Member';
  }

  commentAvatar(c: PostComment): string | null {
    const url = c.author?.avatar_url;
    if (!url) return null;
    return resolveAvatarUrl(url) || url;
  }

  commentInitials(c: PostComment): string {
    return this.commentAuthor(c).slice(0, 2).toUpperCase();
  }

  /** iOS MatteryaAvatarStyle.frameAccent(for:) */
  frameAccent(seed: string): string {
    let hash = 0;
    for (let i = 0; i < seed.length; i++) {
      hash = (hash * 31 + seed.charCodeAt(i)) >>> 0;
    }
    const hues = [
      'rgba(44, 40, 37, 0.55)',
      'rgba(123, 99, 71, 0.75)',
      'rgba(115, 97, 82, 0.85)',
      'rgba(82, 107, 102, 0.8)',
    ];
    return hues[hash % hues.length];
  }

  /** FNV-ish wobble like iOS HandDrawnPictureFrame.seedWobble */
  private seedWobble(seed: string): number[] {
    let h = 2166136261;
    for (let i = 0; i < seed.length; i++) {
      h ^= seed.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    h = h >>> 0;
    const values: number[] = [];
    let x = h || 1;
    for (let i = 0; i < 8; i++) {
      x = Math.imul(x, 1664525) + 1013904223;
      x = x >>> 0;
      const unit = (x % 1000) / 1000;
      values.push((unit - 0.5) * 3.2);
    }
    return values;
  }

  /**
   * SVG path for hand-drawn rounded frame in 0..100 viewBox.
   * Ports iOS HandDrawnPictureFrame.path(in:).
   */
  framePath(seed: string): string {
    const w = this.seedWobble(seed);
    const inset = 5;
    const minX = inset;
    const minY = inset;
    const maxX = 100 - inset;
    const maxY = 100 - inset;
    const corners = [
      { x: minX + w[0], y: minY + w[1] },
      { x: maxX + w[2], y: minY + w[3] },
      { x: maxX + w[4], y: maxY + w[5] },
      { x: minX + w[6], y: maxY + w[7] },
    ];
    const radius = Math.min(maxX - minX, maxY - minY) * 0.16;
    const parts: string[] = [];
    for (let i = 0; i < 4; i++) {
      const curr = corners[i];
      const next = corners[(i + 1) % 4];
      const prev = corners[(i + 3) % 4];
      const toPrev = { dx: prev.x - curr.x, dy: prev.y - curr.y };
      const toNext = { dx: next.x - curr.x, dy: next.y - curr.y };
      const lenPrev = Math.max(0.001, Math.hypot(toPrev.dx, toPrev.dy));
      const lenNext = Math.max(0.001, Math.hypot(toNext.dx, toNext.dy));
      const start = {
        x: curr.x + (toPrev.dx / lenPrev) * radius,
        y: curr.y + (toPrev.dy / lenPrev) * radius,
      };
      const end = {
        x: curr.x + (toNext.dx / lenNext) * radius,
        y: curr.y + (toNext.dy / lenNext) * radius,
      };
      if (i === 0) parts.push(`M ${start.x.toFixed(2)} ${start.y.toFixed(2)}`);
      else parts.push(`L ${start.x.toFixed(2)} ${start.y.toFixed(2)}`);
      parts.push(`Q ${curr.x.toFixed(2)} ${curr.y.toFixed(2)} ${end.x.toFixed(2)} ${end.y.toFixed(2)}`);
    }
    parts.push('Z');
    return parts.join(' ');
  }

  startReply(c: PostComment): void {
    const rootId = c.parent_id || c.id;
    this.replyTarget = {
      threadRootId: rootId,
      authorName: c.author?.username || this.commentAuthor(c),
    };
  }

  cancelReply(): void {
    this.replyTarget = null;
  }

  onComposerEnter(ev: Event): void {
    const ke = ev as KeyboardEvent;
    if (ke.shiftKey) return;
    ke.preventDefault();
    void this.submitComment();
  }

  toggleCommentLike(c: PostComment): void {
    const liked = !c.liked_by_me;
    const next: PostComment = {
      ...c,
      liked_by_me: liked,
      like_count: Math.max(0, (c.like_count || 0) + (liked ? 1 : -1)),
    };
    this.comments = this.comments.map((x) => (x.id === c.id ? next : x));
    this.paint();
  }

  goHubs(): void {
    void this.router.navigate(['/hubs']);
  }

  openChannel(): void {
    if (!this.post) return;
    this.playback.minimize();
    void this.router.navigate(['/hubs', 'channel', this.post.author_id]);
  }

  openRelated(r: CountryPost): void {
    if (this.catalog.isReel(r)) {
      this.playback.stop();
      const country = r.country_code || 'WORLD';
      void this.router.navigate(['/sparks', country], {
        queryParams: { post: r.id },
        state: { seedPosts: [r], seedCountry: country },
      });
      return;
    }
    void this.router.navigate(['/hubs', 'watch', r.id]);
  }

  async toggleLike(): Promise<void> {
    if (!this.post) return;
    this.post = await this.engagement.toggleLike(this.post);
    this.playback.updatePost(this.post);
    this.paint();
  }

  toggleSave(): void {
    if (!this.post) return;
    this.saved = this.catalog.toggleSave(this.post.id);
    this.paint();
  }

  /** Scroll to comments — same affordance as feed bubble.right */
  focusComments(): void {
    const el = document.querySelector('.comments');
    if (el instanceof HTMLElement) {
      el.scrollIntoView({ behavior: 'smooth', block: 'start' });
      const ta = el.querySelector('textarea');
      if (ta instanceof HTMLTextAreaElement) {
        setTimeout(() => ta.focus(), 280);
      }
    }
  }

  /** Open iOS-style share sheet (desktop + mobile web). Never minimize / mini-player. */
  share(): void {
    if (!this.post) return;
    // Keep full watch expanded while sharing — mini player must not appear under the sheet.
    if (this.playback.post && !this.playback.expanded) {
      this.playback.expand();
    }
    this.shareFeedback = '';
    this.shareOpen = true;
    this.paint();
  }

  closeShare(): void {
    this.shareOpen = false;
    this.shareBusy = false;
    this.paint();
  }

  private flashShare(msg: string, kind: 'ok' | 'err' = 'ok', closeAfter = false): void {
    this.shareFeedback = msg;
    this.shareFeedbackKind = kind;
    this.paint();
    if (this.shareFeedbackTimer) clearTimeout(this.shareFeedbackTimer);
    this.shareFeedbackTimer = setTimeout(() => {
      this.shareFeedback = '';
      this.shareFeedbackKind = '';
      if (closeAfter) this.closeShare();
      else this.paint();
    }, closeAfter ? 1400 : 2800);
  }

  private async writeClipboard(text: string): Promise<boolean> {
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(text);
        return true;
      }
    } catch {
      // fall through
    }
    try {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.setAttribute('readonly', '');
      ta.style.position = 'fixed';
      ta.style.left = '-9999px';
      document.body.appendChild(ta);
      ta.select();
      const ok = document.execCommand('copy');
      document.body.removeChild(ta);
      return ok;
    } catch {
      return false;
    }
  }

  async shareAnywhere(): Promise<void> {
    if (!this.post) return;
    if (this.playback.post) this.playback.expand();
    const url = this.shareUrl;
    const title = this.catalog.displayHeadline(this.post);
    const text = this.shareText;
    // Desktop browsers rarely support navigator.share — still try, then always copy.
    let usedSystem = false;
    try {
      if (typeof navigator !== 'undefined' && typeof navigator.share === 'function') {
        await navigator.share({ title, text, url });
        usedSystem = true;
        this.flashShare('Shared', 'ok', true);
        return;
      }
    } catch {
      // user cancelled or share failed
    }
    const copied = await this.writeClipboard(`${text}\n${url}`);
    if (copied) {
      this.flashShare(
        usedSystem ? 'Shared' : 'Link copied — paste into Messages, Mail, or social apps',
        'ok',
        true
      );
    } else {
      this.flashShare('Copy failed — use Email / X / Facebook below', 'err');
    }
  }

  async copyShareLink(): Promise<void> {
    const ok = await this.writeClipboard(this.shareUrl);
    if (ok) this.flashShare('Link copied', 'ok', true);
    else this.flashShare('Copy failed — select the link manually', 'err');
  }

  shareViaEmail(): void {
    const subject = encodeURIComponent(this.shareText);
    const body = encodeURIComponent(`${this.shareText}\n\n${this.shareUrl}`);
    window.open(`mailto:?subject=${subject}&body=${body}`, '_blank');
    this.flashShare('Opening email…', 'ok');
  }

  shareViaX(): void {
    const text = encodeURIComponent(this.shareText);
    const url = encodeURIComponent(this.shareUrl);
    window.open(`https://twitter.com/intent/tweet?text=${text}&url=${url}`, '_blank', 'noopener');
    this.flashShare('Opening X…', 'ok');
  }

  shareViaFacebook(): void {
    const url = encodeURIComponent(this.shareUrl);
    window.open(`https://www.facebook.com/sharer/sharer.php?u=${url}`, '_blank', 'noopener');
    this.flashShare('Opening Facebook…', 'ok');
  }

  shareViaWhatsApp(): void {
    const text = encodeURIComponent(`${this.shareText}\n${this.shareUrl}`);
    window.open(`https://wa.me/?text=${text}`, '_blank', 'noopener');
    this.flashShare('Opening WhatsApp…', 'ok');
  }

  async shareToCountryFeed(): Promise<void> {
    if (!this.post) return;
    if (!this.meId) {
      this.flashShare('Sign in to share to your feed', 'err');
      return;
    }
    // Refresh profile country if missing (common after cold load)
    if (!this.homeCountryCode || this.homeCountryName === 'your country') {
      try {
        const { meProfile } = await this.profiles.meProfile();
        this.homeCountryName = meProfile?.country_name || this.homeCountryName;
        this.homeCountryCode = meProfile?.country_code || null;
      } catch {
        // ignore
      }
    }
    if (!this.homeCountryCode || !this.homeCountryName || this.homeCountryName === 'your country') {
      this.flashShare('Set your home country in Profile first', 'err');
      return;
    }
    if (this.shareBusy) return;
    this.shareBusy = true;
    this.paint();
    try {
      const p = this.post;
      const originalId = p.shared_post_id || p.id;
      const isHubSeed =
        this.engagement.usesLocalEngagement(originalId) ||
        originalId.startsWith('ia_') ||
        originalId.startsWith('hub_');
      const media = this.catalog.mediaUrl(p) || this.mediaSrc || null;
      const thumb = p.thumb_url || this.poster || null;
      const title = this.catalog.displayHeadline(p);
      // Hub/archive IDs are not real GraphQL posts — share as a video post with media.
      // Stamp body with "Shared from Hubs" so feed cards show the Hubs badge (iOS).
      // Real posts use shared_post_id like the iOS app.
      await this.posts.createPost({
        authorId: this.meId,
        title: isHubSeed ? title : null,
        body: isHubSeed
          ? `__hub__|id=${originalId}\nShared from Hubs · ${this.catalog.displayAuthor(p)}`
          : `Shared from Hubs`,
        countryName: this.homeCountryName,
        countryCode: this.homeCountryCode,
        visibility: 'country',
        mediaType: isHubSeed && media ? 'video' : 'none',
        mediaUrl: isHubSeed ? media : null,
        thumbUrl: isHubSeed ? thumb : null,
        sharedPostId: isHubSeed ? null : originalId,
        externalRefType: isHubSeed ? 'hub' : null,
        externalRefId: isHubSeed ? originalId : null,
      });
      this.flashShare(`Shared to ${this.homeCountryName}`, 'ok', true);
    } catch (e: any) {
      const msg = e?.message || e?.error?.message || 'Share failed';
      this.flashShare(String(msg).slice(0, 160), 'err');
    } finally {
      this.shareBusy = false;
      this.paint();
    }
  }

  shareInMessage(): void {
    if (!this.post) return;
    const url = this.shareUrl;
    const text = this.shareText;
    // Leave a draft for Messages to pick up even if query params are ignored
    try {
      sessionStorage.setItem(
        'matterya.share.draft',
        JSON.stringify({
          postId: this.post.id,
          url,
          text,
          at: Date.now(),
        })
      );
    } catch {
      // ignore
    }
    this.closeShare();
    void this.router.navigate(['/messages'], {
      queryParams: { shareUrl: url, shareText: text, sharePost: this.post.id },
      state: { sharePostId: this.post.id, shareUrl: url, shareText: text },
    });
  }

  repostWithQuote(): void {
    if (!this.post) return;
    if (!this.meId) {
      this.flashShare('Sign in to repost', 'err');
      return;
    }
    const quoteId = this.post.shared_post_id || this.post.id;
    const title = this.catalog.displayHeadline(this.post);
    try {
      sessionStorage.setItem(
        'matterya.share.quote',
        JSON.stringify({
          postId: quoteId,
          title,
          url: this.shareUrl,
          mediaUrl: this.catalog.mediaUrl(this.post) || this.mediaSrc,
          at: Date.now(),
        })
      );
    } catch {
      // ignore
    }
    this.closeShare();
    void this.router.navigate(['/feed'], {
      queryParams: { compose: 'post', quote: quoteId },
      state: { quotedSharePostID: quoteId },
    });
  }

  async toggleFollow(): Promise<void> {
    if (!this.meId || !this.post || !this.canFollow) return;
    try {
      if (this.isFollowing) {
        await this.follow.unfollow(this.meId, this.post.author_id);
        this.isFollowing = false;
      } else {
        await this.follow.follow(this.meId, this.post.author_id);
        this.isFollowing = true;
      }
    } catch {
      // ignore
    }
    this.paint();
  }

  async submitComment(): Promise<void> {
    if (!this.post || !this.commentDraft.trim() || this.commenting) return;
    this.commenting = true;
    try {
      const user = await this.auth.getUser().catch(() => null);
      let displayName: string | null = null;
      let username: string | null = null;
      let avatar: string | null = null;
      if (user?.id) {
        try {
          const { meProfile } = await this.profiles.meProfile();
          displayName = meProfile?.display_name ?? null;
          username = meProfile?.username ?? null;
          avatar = meProfile?.avatar_url ?? null;
          this.meAvatar = avatar ? resolveAvatarUrl(avatar) || avatar : this.meAvatar;
          if (displayName || username) {
            this.meInitials = String(displayName || username || 'You')
              .slice(0, 2)
              .toUpperCase();
          }
        } catch {
          // ignore
        }
      }
      const parentId = this.replyTarget?.threadRootId ?? null;
      const c = await this.engagement.addComment(this.post, this.commentDraft, {
        id: user?.id || 'anon',
        display_name: displayName,
        username,
        avatar_url: avatar,
        parent_id: parentId,
      });
      if (c) {
        const withParent =
          parentId && !c.parent_id
            ? { ...c, parent_id: parentId }
            : c;
        this.comments = [withParent, ...this.comments];
        this.commentDraft = '';
        this.replyTarget = null;
        this.commentLimit = Math.max(this.commentLimit, this.comments.length);
        this.post = {
          ...this.post,
          comment_count: (this.post.comment_count || 0) + 1,
        };
      }
    } finally {
      this.commenting = false;
      this.paint();
    }
  }

  onTime(ev: { currentTime: number; duration: number }): void {
    if (!this.post) return;
    this.catalog.notePlaybackPosition(ev.currentTime, this.post.id, ev.duration);
  }

  onPlayState(playing: boolean): void {
    this.playback.setPlaying(playing);
  }

  onVideoAspect(ratio: number): void {
    if (!Number.isFinite(ratio) || ratio < 0.4 || ratio > 3.2) return;
    this.videoAspectRatio = ratio;
    this.paint();
  }
}
