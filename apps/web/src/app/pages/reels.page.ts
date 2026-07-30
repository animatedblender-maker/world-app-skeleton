import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, ElementRef, OnDestroy, OnInit, ViewChild } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { Subscription } from 'rxjs';

import { VideoPlayerComponent } from '../components/video-player.component';
import { AuthService } from '../core/services/auth.service';
import { PostsService } from '../core/services/posts.service';
import { CountryPost, PostComment } from '../core/models/post.model';
import { resolveAvatarUrl, resolveMediaUrl } from '../core/utils/media-url.util';

@Component({
  selector: 'app-reels-page',
  standalone: true,
  imports: [CommonModule, FormsModule, VideoPlayerComponent],
  template: `
    <div class="reels-root" [class.comments-open]="!!commentOpenPostId">
      <header class="reels-chrome">
        <button type="button" class="chrome-btn" (click)="goBack()" aria-label="Close Sparks">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.2">
            <path d="M6 6l12 12M18 6L6 18" stroke-linecap="round" />
          </svg>
        </button>

        <div class="chrome-island">
          <span class="island-label">Sparks</span>
          <span class="island-place">{{ countryName || countryCode || 'World' }}</span>
        </div>

        <button type="button" class="chrome-btn" (click)="goGlobe()" aria-label="Open globe">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.7">
            <circle cx="12" cy="12" r="9" />
            <path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18" stroke-linecap="round" />
          </svg>
        </button>
      </header>

      <div class="progress-rail" *ngIf="videoPosts.length > 1" aria-hidden="true">
        <span
          class="progress-seg"
          *ngFor="let post of progressWindow; let i = index"
          [class.active]="i === activeIndex % progressWindow.length"
        ></span>
      </div>

      <div class="reels-feed" #feed (scroll)="onFeedScroll($event)">
        <div class="reels-state" *ngIf="loading">Loading sparks…</div>
        <div class="reels-state error" *ngIf="!loading && error">{{ error }}</div>
        <div class="reels-state" *ngIf="!loading && !error && !videoPosts.length">
          No sparks for {{ countryName || countryCode || 'this country' }} yet.
        </div>

        <section
          class="reel"
          *ngFor="let post of videoPosts; let i = index; trackBy: trackPostById"
          [attr.data-post-id]="post.id"
          [attr.data-index]="i"
        >
          <div class="reel-frame">
            <app-video-player
              class="reel-player controls-hidden"
              [src]="reelMediaSrc(post)"
              [poster]="posterFor(post)"
              adPlacement="reel"
              [adCountryCode]="post.country_code ?? countryCode"
              [adContentCountryCode]="post.country_code ?? countryCode"
              [adPostId]="post.id"
              preload="auto"
              centerOverlayMode="on-click"
              [showMute]="false"
              (viewed)="recordView(post)"
            ></app-video-player>

            <div class="reel-gradient" aria-hidden="true"></div>

            <div class="reel-bottom">
              <div class="reel-meta">
                <button
                  type="button"
                  class="reel-author"
                  (click)="openAuthorProfile(post.author, post.author_id)"
                >
                  <span class="author-avatar">
                    <img *ngIf="avatarFor(post)" [src]="avatarFor(post)" alt="" />
                    <span *ngIf="!avatarFor(post)">{{ initialsFor(post) }}</span>
                  </span>
                  <span class="author-name">{{ displayName(post) }}</span>
                </button>

                <p class="reel-caption" *ngIf="captionFor(post)">{{ captionFor(post) }}</p>

                <button
                  type="button"
                  class="country-chip"
                  *ngIf="post.country_code || post.country_name"
                  (click)="openCountrySparks(post)"
                >
                  <span class="chip-dot"></span>
                  {{ post.country_name || post.country_code }}
                </button>
              </div>

              <div class="reel-actions" (click)="$event.stopPropagation()">
                <button
                  type="button"
                  class="rail-btn"
                  [class.liked]="post.liked_by_me"
                  [disabled]="likeBusy[post.id]"
                  (click)="togglePostLike(post)"
                  aria-label="Like"
                >
                  <svg class="rail-icon" viewBox="0 0 24 24" aria-hidden="true">
                    <path
                      [attr.fill]="post.liked_by_me ? 'currentColor' : 'none'"
                      stroke="currentColor"
                      stroke-width="1.8"
                      d="M12 21s-6.7-4.4-9.2-7.4C.9 11.4 1.5 7.6 4.6 6 6.6 5 9 5.6 10.5 7.4L12 9l1.5-1.6C15 5.6 17.4 5 19.4 6c3.1 1.6 3.7 5.4 1.8 7.6C18.7 16.6 12 21 12 21z"
                    ></path>
                  </svg>
                  <span class="rail-label">{{ post.like_count || 0 }}</span>
                </button>

                <button
                  type="button"
                  class="rail-btn"
                  [class.active]="commentOpenPostId === post.id"
                  (click)="toggleComments(post)"
                  aria-label="Comments"
                >
                  <svg class="rail-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
                    <path d="M4 5h16a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H9l-5 4v-4H4a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z"></path>
                  </svg>
                  <span class="rail-label">{{ post.comment_count || 0 }}</span>
                </button>

                <button type="button" class="rail-btn" (click)="sharePost(post)" aria-label="Share">
                  <svg class="rail-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
                    <path d="M4 12v7a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-7" stroke-linecap="round" />
                    <path d="M12 16V4M8 8l4-4 4 4" stroke-linecap="round" stroke-linejoin="round" />
                  </svg>
                  <span class="rail-label">Share</span>
                </button>

                <button type="button" class="rail-btn" (click)="openPost(post)" aria-label="Open post">
                  <svg class="rail-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
                    <path d="M7 17L17 7M9 7h8v8" stroke-linecap="round" stroke-linejoin="round" />
                  </svg>
                  <span class="rail-label">Open</span>
                </button>
              </div>
            </div>

            <div class="reel-error" *ngIf="postActionError[post.id]">
              {{ postActionError[post.id] }}
            </div>
          </div>
        </section>
      </div>

      <div class="comments-backdrop" *ngIf="commentOpenPostId as openId" (click)="closeComments()">
        <div class="comments-panel" (click)="$event.stopPropagation()">
          <div class="comments-head">
            <div class="comments-title">Comments</div>
            <button type="button" class="comments-close" (click)="closeComments()" aria-label="Close">×</button>
          </div>
          <div class="comments-meta" *ngIf="commentPost">
            <div>{{ displayName(commentPost) }}</div>
            <div class="comments-meta-sub">{{ commentPost.created_at | date: 'mediumDate' }}</div>
          </div>
          <div class="comment-status" *ngIf="commentLoading[openId]">Loading comments…</div>
          <div class="comment-status error" *ngIf="commentErrors[openId]">{{ commentErrors[openId] }}</div>
          <div class="comments-body" *ngIf="!commentLoading[openId] && !commentErrors[openId]">
            <div class="comment-empty" *ngIf="!(commentDisplay[openId]?.length)">No comments yet.</div>
            <div
              class="comment-row"
              *ngFor="let comment of commentDisplay[openId] || []"
              [style.marginLeft.px]="(commentDepth[openId]?.[comment.id] ?? 0) * 16"
            >
              <button class="comment-avatar" type="button" (click)="openAuthorProfile(comment.author)">
                <img *ngIf="commentAvatar(comment)" [src]="commentAvatar(comment)" alt="" />
                <span *ngIf="!commentAvatar(comment)">
                  {{ (comment.author?.display_name || comment.author?.username || 'U').slice(0, 2).toUpperCase() }}
                </span>
              </button>
              <div class="comment-core">
                <div class="comment-meta">
                  <span class="comment-name">{{ comment.author?.display_name || comment.author?.username || 'Member' }}</span>
                  <span class="comment-time">{{ comment.created_at | date: 'short' }}</span>
                </div>
                <div class="comment-text">{{ comment.body }}</div>
                <div class="comment-actions">
                  <button
                    class="comment-action"
                    type="button"
                    (click)="startCommentReply(openId, comment)"
                    [disabled]="commentBusy[openId]"
                  >
                    Reply
                  </button>
                  <button
                    class="comment-action"
                    type="button"
                    (click)="toggleCommentLike(openId, comment)"
                    [class.active]="comment.liked_by_me"
                    [disabled]="commentLikeBusy[openId]?.[comment.id]"
                  >
                    <span>{{ comment.liked_by_me ? 'Loved' : 'Love' }}</span>
                    <span class="comment-like-count" *ngIf="comment.like_count">{{ comment.like_count }}</span>
                  </button>
                </div>
              </div>
            </div>
          </div>

          <div class="comment-compose" *ngIf="meId; else commentSignIn">
            <div class="comment-reply" *ngIf="commentReplyTarget[openId] as replyTarget">
              Replying to <span>{{ replyTarget.authorName }}</span>
              <button type="button" class="ghost-link" (click)="cancelCommentReply(openId)">Cancel</button>
            </div>
            <textarea
              class="comment-input"
              placeholder="Write a comment"
              rows="2"
              [disabled]="commentBusy[openId]"
              [(ngModel)]="commentDrafts[openId]"
            ></textarea>
            <button
              class="comment-submit"
              type="button"
              [disabled]="commentBusy[openId]"
              (click)="submitComment(openId)"
            >
              {{ commentBusy[openId] ? 'Sending…' : 'Comment' }}
            </button>
          </div>
          <ng-template #commentSignIn>
            <div class="comment-hint">Sign in to comment.</div>
          </ng-template>
        </div>
      </div>
    </div>
  `,
  styles: [
    `
      :host {
        display: block;
        height: 100%;
        background: #000;
        color: #fff;
      }
      .reels-root {
        position: relative;
        height: 100dvh;
        height: 100svh;
        overflow: hidden;
        background: #000;
      }
      .reels-chrome {
        position: fixed;
        top: 0;
        left: 0;
        right: 0;
        z-index: 8;
        display: grid;
        grid-template-columns: 44px 1fr 44px;
        align-items: center;
        gap: 10px;
        padding: calc(env(safe-area-inset-top) + 8px) 14px 0;
        pointer-events: none;
      }
      .chrome-btn {
        pointer-events: auto;
        width: 40px;
        height: 40px;
        border: 0;
        border-radius: 999px;
        background: rgba(20, 18, 16, 0.45);
        color: #fff;
        display: grid;
        place-items: center;
        cursor: pointer;
        backdrop-filter: blur(10px);
        -webkit-backdrop-filter: blur(10px);
      }
      .chrome-island {
        pointer-events: none;
        justify-self: center;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 1px;
        min-width: 0;
        max-width: min(62vw, 280px);
        padding: 6px 14px;
        border-radius: 999px;
        background: rgba(20, 18, 16, 0.42);
        backdrop-filter: blur(12px);
        -webkit-backdrop-filter: blur(12px);
      }
      .island-label {
        font-size: 10px;
        font-weight: 650;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        color: rgba(255, 255, 255, 0.72);
      }
      .island-place {
        font-family: 'Iowan Old Style', 'Palatino Linotype', Palatino, Georgia, serif;
        font-size: 15px;
        font-weight: 500;
        line-height: 1.15;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        max-width: 100%;
      }
      .progress-rail {
        position: fixed;
        top: calc(env(safe-area-inset-top) + 56px);
        left: 16px;
        right: 16px;
        z-index: 7;
        display: flex;
        gap: 3px;
        pointer-events: none;
      }
      .progress-seg {
        flex: 1 1 0;
        height: 2.5px;
        border-radius: 999px;
        background: rgba(255, 255, 255, 0.28);
        max-width: 18px;
        transition: background 0.18s ease, max-width 0.18s ease;
      }
      .progress-seg.active {
        background: #5eb8ff;
        max-width: 18px;
        flex: 0 0 18px;
      }
      .reels-feed {
        position: relative;
        height: 100%;
        overflow-y: auto;
        scroll-snap-type: y mandatory;
        overscroll-behavior-y: contain;
        -webkit-overflow-scrolling: touch;
        scrollbar-width: none;
      }
      .reels-feed::-webkit-scrollbar {
        width: 0;
        height: 0;
      }
      .reels-state {
        position: relative;
        margin: 28vh auto 0;
        width: min(360px, 86%);
        padding: 18px 16px;
        text-align: center;
        font-size: 14px;
        color: rgba(255, 255, 255, 0.78);
        background: rgba(20, 18, 16, 0.55);
        border-radius: 16px;
      }
      .reels-state.error {
        color: #ffb3a8;
      }
      .reel {
        height: 100%;
        min-height: 100%;
        scroll-snap-align: start;
        scroll-snap-stop: always;
      }
      .reel-frame {
        position: relative;
        width: 100%;
        height: 100%;
        overflow: hidden;
        background: #000;
      }
      .reel-player {
        width: 100%;
        height: 100%;
      }
      :host ::ng-deep app-video-player.reel-player .mute-toggle {
        display: none !important;
      }
      .reel-gradient {
        position: absolute;
        left: 0;
        right: 0;
        bottom: 0;
        height: 42%;
        background: linear-gradient(180deg, transparent, rgba(0, 0, 0, 0.75));
        pointer-events: none;
      }
      .reel-bottom {
        position: absolute;
        left: 0;
        right: 0;
        bottom: 0;
        z-index: 3;
        display: flex;
        align-items: flex-end;
        justify-content: space-between;
        gap: 8px;
        padding: 0 12px calc(28px + env(safe-area-inset-bottom));
        pointer-events: none;
      }
      .reel-meta {
        flex: 1 1 auto;
        min-width: 0;
        max-width: calc(100% - 78px);
        display: flex;
        flex-direction: column;
        align-items: flex-start;
        gap: 10px;
        pointer-events: auto;
        padding-bottom: 4px;
      }
      .reel-author {
        display: inline-flex;
        align-items: center;
        gap: 10px;
        border: 0;
        background: transparent;
        color: #fff;
        padding: 0;
        cursor: pointer;
        text-align: left;
      }
      .author-avatar {
        width: 36px;
        height: 36px;
        border-radius: 50%;
        overflow: hidden;
        background: rgba(255, 255, 255, 0.12);
        display: grid;
        place-items: center;
        font-size: 11px;
        font-weight: 700;
        flex: 0 0 auto;
      }
      .author-avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .author-name {
        font-size: 14px;
        font-weight: 700;
        text-shadow: 0 1px 8px rgba(0, 0, 0, 0.45);
      }
      .reel-caption {
        margin: 0;
        font-size: 14px;
        line-height: 1.35;
        color: rgba(255, 255, 255, 0.92);
        text-shadow: 0 1px 10px rgba(0, 0, 0, 0.5);
        display: -webkit-box;
        -webkit-line-clamp: 4;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .country-chip {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        border: 0;
        border-radius: 999px;
        background: rgba(255, 255, 255, 0.14);
        color: rgba(255, 255, 255, 0.95);
        font-size: 12px;
        font-weight: 650;
        padding: 6px 10px;
        cursor: pointer;
        backdrop-filter: blur(8px);
      }
      .chip-dot {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: #5eb8ff;
      }
      .reel-actions {
        flex: 0 0 auto;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 18px;
        pointer-events: auto;
        padding-right: 4px;
        padding-bottom: 2px;
      }
      .rail-btn {
        border: 0;
        background: transparent;
        color: #fff;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 5px;
        padding: 0;
        cursor: pointer;
        min-width: 48px;
      }
      .rail-btn:disabled {
        opacity: 0.55;
        cursor: not-allowed;
      }
      .rail-btn.liked {
        color: #ff4d6a;
      }
      .rail-icon {
        width: 28px;
        height: 28px;
        filter: drop-shadow(0 2px 8px rgba(0, 0, 0, 0.45));
      }
      .rail-label {
        font-size: 11px;
        font-weight: 650;
        color: rgba(255, 255, 255, 0.9);
        text-shadow: 0 1px 6px rgba(0, 0, 0, 0.5);
      }
      .reel-error {
        position: absolute;
        top: calc(env(safe-area-inset-top) + 72px);
        right: 14px;
        max-width: 200px;
        padding: 8px 10px;
        border-radius: 12px;
        background: rgba(40, 10, 10, 0.78);
        color: #ffb3a8;
        font-size: 12px;
        z-index: 4;
      }
      .comments-backdrop {
        position: fixed;
        inset: 0;
        background: rgba(0, 0, 0, 0.55);
        display: flex;
        align-items: flex-end;
        justify-content: center;
        z-index: 20;
      }
      .comments-panel {
        width: min(720px, 100%);
        max-height: 72vh;
        background: #141210;
        border-top-left-radius: 22px;
        border-top-right-radius: 22px;
        border: 1px solid rgba(255, 255, 255, 0.08);
        padding: 14px 14px calc(16px + env(safe-area-inset-bottom));
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      .comments-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
      }
      .comments-title {
        font-size: 15px;
        font-weight: 700;
      }
      .comments-close {
        width: 32px;
        height: 32px;
        border: 0;
        border-radius: 999px;
        background: rgba(255, 255, 255, 0.08);
        color: #fff;
        font-size: 18px;
        cursor: pointer;
      }
      .comments-meta {
        font-size: 12px;
        color: rgba(255, 255, 255, 0.65);
      }
      .comments-meta-sub {
        margin-top: 2px;
        font-size: 11px;
      }
      .comment-status {
        font-size: 12px;
        color: rgba(255, 255, 255, 0.65);
      }
      .comment-status.error {
        color: #ffb3a8;
      }
      .comments-body {
        flex: 1;
        overflow-y: auto;
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .comment-empty {
        font-size: 12px;
        color: rgba(255, 255, 255, 0.55);
      }
      .comment-row {
        display: flex;
        gap: 10px;
      }
      .comment-avatar {
        width: 34px;
        height: 34px;
        border-radius: 50%;
        overflow: hidden;
        border: 0;
        background: rgba(255, 255, 255, 0.1);
        color: #fff;
        display: grid;
        place-items: center;
        cursor: pointer;
        flex: 0 0 auto;
        font-size: 10px;
        font-weight: 700;
      }
      .comment-avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .comment-core {
        flex: 1;
        min-width: 0;
      }
      .comment-meta {
        display: flex;
        gap: 8px;
        font-size: 11px;
        color: rgba(255, 255, 255, 0.6);
      }
      .comment-name {
        font-weight: 700;
        color: rgba(255, 255, 255, 0.9);
      }
      .comment-text {
        margin-top: 3px;
        font-size: 13px;
        line-height: 1.4;
      }
      .comment-actions {
        display: flex;
        gap: 8px;
        margin-top: 6px;
      }
      .comment-action {
        border: 0;
        border-radius: 999px;
        background: rgba(255, 255, 255, 0.08);
        color: #fff;
        padding: 4px 10px;
        font-size: 11px;
        cursor: pointer;
      }
      .comment-action.active {
        color: #ff9d8c;
      }
      .comment-like-count {
        margin-left: 4px;
        font-weight: 700;
      }
      .comment-compose {
        border-top: 1px solid rgba(255, 255, 255, 0.08);
        padding-top: 10px;
        display: flex;
        flex-direction: column;
        gap: 8px;
      }
      .comment-reply {
        font-size: 12px;
        color: rgba(255, 255, 255, 0.75);
        display: flex;
        gap: 8px;
        align-items: center;
      }
      .comment-reply span {
        color: #8bdcff;
      }
      .ghost-link {
        border: 0;
        background: transparent;
        color: #fff;
        font-size: 11px;
        cursor: pointer;
      }
      .comment-input {
        border-radius: 14px;
        border: 1px solid rgba(255, 255, 255, 0.1);
        background: rgba(255, 255, 255, 0.06);
        color: #fff;
        padding: 10px 12px;
        font-size: 13px;
        resize: vertical;
        font-family: inherit;
      }
      .comment-submit {
        align-self: flex-end;
        border: 0;
        border-radius: 999px;
        background: #fff;
        color: #111;
        padding: 8px 16px;
        font-size: 12px;
        font-weight: 700;
        cursor: pointer;
      }
      .comment-submit:disabled {
        opacity: 0.55;
        cursor: not-allowed;
      }
      .comment-hint {
        font-size: 12px;
        color: rgba(255, 255, 255, 0.6);
        text-align: center;
      }
    `,
  ],
})
export class ReelsPageComponent implements OnInit, OnDestroy {
  @ViewChild('feed') feedRef?: ElementRef<HTMLDivElement>;

  countryCode = '';
  countryName = '';
  loading = false;
  error = '';
  posts: CountryPost[] = [];
  videoPosts: CountryPost[] = [];
  activeIndex = 0;
  reelMuted = false;
  meId: string | null = null;
  likeBusy: Record<string, boolean> = {};
  postActionError: Record<string, string> = {};
  private viewedPostIds = new Set<string>();

  commentOpenPostId: string | null = null;
  commentPost: CountryPost | null = null;
  commentLoading: Record<string, boolean> = {};
  commentBusy: Record<string, boolean> = {};
  commentErrors: Record<string, string> = {};
  commentDrafts: Record<string, string> = {};
  commentItems: Record<string, PostComment[]> = {};
  commentDisplay: Record<string, PostComment[]> = {};
  commentDepth: Record<string, Record<string, number>> = {};
  commentReplyTarget: Record<string, { commentId: string; authorName: string } | null> = {};
  commentLikeBusy: Record<string, Record<string, boolean>> = {};

  private seeded = false;
  private routeSub?: Subscription;
  private querySub?: Subscription;
  private pendingScrollId: string | null = null;
  private muteListener?: (event: Event) => void;

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private auth: AuthService,
    private postsService: PostsService,
    private cdr: ChangeDetectorRef
  ) {}

  private paint(): void {
    try {
      this.cdr.detectChanges();
    } catch {
      // destroyed
    }
  }

  get progressWindow(): CountryPost[] {
    return this.videoPosts.slice(0, Math.min(this.videoPosts.length, 12));
  }

  ngOnInit(): void {
    this.reelMuted = this.readGlobalMute();
    this.muteListener = (event: Event) => {
      this.reelMuted = !!(event as CustomEvent<boolean>).detail;
    };
    window.addEventListener('video-player-mute', this.muteListener);
    void this.loadMe();
    this.routeSub = this.route.paramMap.subscribe((params) => {
      this.countryCode = (params.get('country') || '').toUpperCase();
      this.commentOpenPostId = null;
      this.commentPost = null;
      this.activeIndex = 0;
      this.seeded = this.applySeedFromState();
      if (!this.seeded) {
        void this.loadReels();
      } else {
        this.tryScrollToPending();
      }
    });
    this.querySub = this.route.queryParamMap.subscribe((params) => {
      this.pendingScrollId = params.get('postId') || params.get('post');
      this.tryScrollToPending();
    });
  }

  ngOnDestroy(): void {
    this.routeSub?.unsubscribe();
    this.querySub?.unsubscribe();
    if (this.muteListener) {
      window.removeEventListener('video-player-mute', this.muteListener);
      this.muteListener = undefined;
    }
  }

  trackPostById(_: number, post: CountryPost): string {
    return post.id;
  }

  onFeedScroll(event: Event): void {
    const el = event.target as HTMLElement | null;
    if (!el || !this.videoPosts.length) return;
    const h = el.clientHeight || 1;
    const idx = Math.max(0, Math.min(this.videoPosts.length - 1, Math.round(el.scrollTop / h)));
    if (idx !== this.activeIndex) {
      this.activeIndex = idx;
      const post = this.videoPosts[idx];
      if (post) this.recordView(post);
    }
  }

  goBack(): void {
    if (window.history.length > 1) {
      window.history.back();
      return;
    }
    if (this.countryCode) {
      void this.router.navigate(['/globe'], {
        queryParams: { country: this.countryCode, tab: 'media' },
      });
      return;
    }
    void this.router.navigate(['/hubs']);
  }

  goGlobe(): void {
    void this.router.navigate(['/globe']);
  }

  openPost(post: CountryPost): void {
    void this.router.navigate(['/post', post.id]);
  }

  openCountrySparks(post: CountryPost): void {
    const code = (post.country_code || this.countryCode || '').trim().toUpperCase();
    if (!code || code === this.countryCode) return;
    void this.router.navigate(['/sparks', code]);
  }

  async sharePost(post: CountryPost): Promise<void> {
    const url = `${window.location.origin}/post/${post.id}`;
    const title = post.title || this.captionFor(post) || 'Matterya Spark';
    try {
      if (navigator.share) {
        await navigator.share({ title, url });
        return;
      }
    } catch {
      // fall through to clipboard
    }
    try {
      await navigator.clipboard.writeText(url);
    } catch {
      // ignore
    }
  }

  displayName(post: CountryPost): string {
    return post.author?.display_name || post.author?.username || 'Member';
  }

  initialsFor(post: CountryPost): string {
    return this.displayName(post).slice(0, 2).toUpperCase();
  }

  avatarFor(post: CountryPost): string {
    return resolveAvatarUrl(
      post.author?.avatar_url,
      post.author?.username || post.author?.user_id || post.author_id
    );
  }

  commentAvatar(comment: PostComment): string {
    return resolveAvatarUrl(
      comment.author?.avatar_url,
      comment.author?.username || comment.author?.user_id || comment.author_id
    );
  }

  captionFor(post: CountryPost): string {
    return String(post.media_caption || post.body || post.title || '')
      .split('\n')
      .filter((line) => !line.trim().startsWith('__story__|'))
      .join('\n')
      .trim();
  }

  posterFor(post: CountryPost): string | null {
    const thumb = resolveMediaUrl(post.thumb_url || '');
    return thumb || null;
  }

  openAuthorProfile(
    author: CountryPost['author'] | PostComment['author'] | null | undefined,
    fallbackId?: string | null
  ): void {
    const slug = author?.username?.trim() || fallbackId || author?.user_id;
    if (!slug) return;
    void this.router.navigate(['/user', slug]);
  }

  recordView(post: CountryPost): void {
    if (!post?.id || this.viewedPostIds.has(post.id)) return;
    this.viewedPostIds.add(post.id);
    void this.postsService.recordView(post);
  }

  async togglePostLike(post: CountryPost): Promise<void> {
    if (!this.meId) {
      this.postActionError[post.id] = 'Sign in to like.';
      return;
    }
    if (this.likeBusy[post.id]) return;
    this.likeBusy[post.id] = true;
    this.postActionError[post.id] = '';
    try {
      const updated = post.liked_by_me
        ? await this.postsService.unlikePost(post.id)
        : await this.postsService.likePost(post.id);
      this.applyPostUpdate(updated);
    } catch (e: any) {
      this.postActionError[post.id] = e?.message ?? String(e);
    } finally {
      this.likeBusy[post.id] = false;
    }
  }

  toggleComments(post: CountryPost): void {
    if (this.commentOpenPostId === post.id) {
      this.closeComments();
      return;
    }
    this.commentOpenPostId = post.id;
    this.commentPost = post;
    if (!this.commentItems[post.id] && !this.commentLoading[post.id]) {
      void this.loadComments(post.id);
    }
  }

  closeComments(): void {
    this.commentOpenPostId = null;
    this.commentPost = null;
  }

  startCommentReply(postId: string, comment: PostComment): void {
    if (!postId || !comment?.id) return;
    this.commentReplyTarget[postId] = {
      commentId: comment.id,
      authorName: this.commentAuthorName(comment),
    };
  }

  cancelCommentReply(postId: string): void {
    this.commentReplyTarget[postId] = null;
  }

  async toggleCommentLike(postId: string, comment: PostComment): Promise<void> {
    if (!this.meId) {
      this.commentErrors[postId] = 'Sign in to like comments.';
      return;
    }
    const perPost = { ...(this.commentLikeBusy[postId] ?? {}) };
    if (perPost[comment.id]) return;
    perPost[comment.id] = true;
    this.commentLikeBusy[postId] = perPost;
    this.commentErrors[postId] = '';
    try {
      const updated = comment.liked_by_me
        ? await this.postsService.unlikeComment(comment.id)
        : await this.postsService.likeComment(comment.id);
      this.applyCommentUpdate(postId, updated);
    } catch (e: any) {
      this.commentErrors[postId] = e?.message ?? String(e);
    } finally {
      this.commentLikeBusy[postId] = {
        ...this.commentLikeBusy[postId],
        [comment.id]: false,
      };
    }
  }

  async submitComment(postId: string): Promise<void> {
    if (!this.meId) {
      this.commentErrors[postId] = 'Sign in to comment.';
      return;
    }
    const draft = (this.commentDrafts[postId] ?? '').trim();
    if (!draft) {
      this.commentErrors[postId] = 'Write something before commenting.';
      return;
    }
    if (this.commentBusy[postId]) return;
    this.commentBusy[postId] = true;
    this.commentErrors[postId] = '';
    try {
      const parentId = this.commentReplyTarget[postId]?.commentId ?? null;
      const comment = await this.postsService.addComment(postId, draft, parentId);
      this.applyCommentUpdate(postId, comment);
      this.commentDrafts[postId] = '';
      this.commentReplyTarget[postId] = null;
      this.bumpPostCommentCount(postId, 1);
    } catch (e: any) {
      this.commentErrors[postId] = e?.message ?? String(e);
    } finally {
      this.commentBusy[postId] = false;
    }
  }

  private async loadMe(): Promise<void> {
    try {
      const user = await this.withTimeout(this.auth.getUser(), 3000, 'auth');
      this.meId = user?.id ?? null;
    } catch {
      this.meId = null;
    }
    this.paint();
  }

  private async loadReels(): Promise<void> {
    if (!this.countryCode) {
      this.error = 'Missing country.';
      this.loading = false;
      this.paint();
      return;
    }
    this.loading = true;
    this.error = '';
    this.posts = [];
    this.videoPosts = [];
    this.paint();

    const hardStop = window.setTimeout(() => {
      if (!this.loading) return;
      this.loading = false;
      if (!this.videoPosts.length && !this.error) {
        this.error = 'Sparks is taking too long. Try again.';
      }
      this.paint();
    }, 10000);

    try {
      const posts = await this.withTimeout(
        this.postsService.listByCountry(this.countryCode, 80, {
          demoLimit: 40,
          skipComments: true,
        }),
        8000,
        'sparksCountry'
      ).catch(() => [] as CountryPost[]);

      this.posts = posts ?? [];
      const sparks = this.posts.filter(
        (post) => this.postsService.isSpark(post) && !!this.reelMediaSrc(post)
      );
      const videos = this.posts.filter(
        (post) =>
          !this.postsService.isMoment(post) &&
          !this.postsService.isSpark(post) &&
          !!this.reelMediaSrc(post)
      );
      this.videoPosts = sparks.length ? sparks : videos;
      this.countryName =
        this.posts.find((post) => post.country_name)?.country_name || this.countryCode;
      this.tryScrollToPending();
    } catch (e: any) {
      this.error = e?.message ?? String(e);
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

  private applySeedFromState(): boolean {
    const state = (history.state || {}) as {
      seedPosts?: CountryPost[];
      seedCountry?: string;
      countryName?: string | null;
    };
    const seedCountry = String(state.seedCountry || '').toUpperCase();
    if (seedCountry && seedCountry !== this.countryCode) return false;
    const seedPosts = Array.isArray(state.seedPosts) ? state.seedPosts : [];
    const videos = seedPosts.filter((post) => !!this.reelMediaSrc(post));
    if (!videos.length) return false;
    this.videoPosts = videos;
    this.countryName = state.countryName || this.countryName;
    this.loading = false;
    this.error = '';
    this.paint();
    return true;
  }

  private tryScrollToPending(): void {
    const postId = this.pendingScrollId;
    if (!postId || !this.feedRef?.nativeElement || !this.videoPosts.length) return;
    setTimeout(() => {
      const target = this.feedRef?.nativeElement.querySelector(
        `[data-post-id="${postId}"]`
      ) as HTMLElement | null;
      if (target) {
        target.scrollIntoView({ behavior: 'auto', block: 'start' });
        this.pendingScrollId = null;
        const idx = this.videoPosts.findIndex((p) => p.id === postId);
        if (idx >= 0) this.activeIndex = idx;
      }
    }, 50);
  }

  private applyPostUpdate(updated: CountryPost): void {
    const idx = this.videoPosts.findIndex((post) => post.id === updated.id);
    if (idx >= 0) {
      this.videoPosts[idx] = { ...this.videoPosts[idx], ...updated };
    }
  }

  private readGlobalMute(): boolean {
    try {
      return (window as any).__videoMuted === true;
    } catch {
      return false;
    }
  }

  reelMediaSrc(post: CountryPost): string {
    const urls = this.postMediaUrls(post).map((u) => resolveMediaUrl(u)).filter(Boolean);
    if (!urls.length) return '';
    const types = this.postMediaTypes(post);
    const idx = types.findIndex((t) => t === 'video');
    if (idx >= 0) return urls[idx] || urls[0] || '';
    const media = String(post.media_type || '').toLowerCase();
    if (media === 'video' || media === 'reel' || media === 'spark') return urls[0] || '';
    if (urls.some((u) => /\.(mp4|webm|mov|m4v)(\?|#|$)/i.test(u))) {
      return urls.find((u) => /\.(mp4|webm|mov|m4v)(\?|#|$)/i.test(u)) || urls[0];
    }
    return '';
  }

  private postMediaUrls(post: CountryPost): string[] {
    const raw = String(post?.media_url || '').trim();
    if (!raw) return [];
    if (raw.startsWith('{') || raw.startsWith('[')) {
      try {
        const parsed = JSON.parse(raw) as any;
        if (Array.isArray(parsed)) return parsed.filter(Boolean).map(String);
        if (Array.isArray(parsed?.urls)) return parsed.urls.filter(Boolean);
        if (parsed?.url) return [parsed.url];
      } catch {
        // keep raw
      }
    }
    return [raw];
  }

  private postMediaTypes(post: CountryPost): Array<'image' | 'video'> {
    const raw = String(post?.media_url || '').trim();
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
      } catch {
        // keep fallback
      }
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
    const media = String(fallback || '').toLowerCase();
    if (media === 'video' || media === 'reel' || media === 'spark') return 'video';
    return 'image';
  }

  private bumpPostCommentCount(postId: string, delta: number): void {
    const idx = this.videoPosts.findIndex((post) => post.id === postId);
    if (idx >= 0) {
      const next = { ...this.videoPosts[idx] };
      next.comment_count = Math.max(0, Number(next.comment_count ?? 0) + delta);
      this.videoPosts[idx] = next;
    }
  }

  private async loadComments(postId: string): Promise<void> {
    this.commentLoading[postId] = true;
    this.commentErrors[postId] = '';
    try {
      const comments = await this.postsService.listComments(postId, 60);
      this.commentItems[postId] = comments;
      this.rebuildCommentThread(postId);
    } catch (e: any) {
      this.commentErrors[postId] = e?.message ?? String(e);
    } finally {
      this.commentLoading[postId] = false;
    }
  }

  private rebuildCommentThread(postId: string): void {
    const items = this.commentItems[postId] ?? [];
    const byParent: Record<string, PostComment[]> = {};
    const roots: PostComment[] = [];

    for (const comment of items) {
      const parentId = comment.parent_id ?? '';
      if (parentId) {
        if (!byParent[parentId]) byParent[parentId] = [];
        byParent[parentId].push(comment);
      } else {
        roots.push(comment);
      }
    }

    const ordered: PostComment[] = [];
    const depthMap: Record<string, number> = {};

    const pushWithChildren = (node: PostComment, depth: number) => {
      ordered.push(node);
      depthMap[node.id] = depth;
      const children = byParent[node.id] ?? [];
      for (const child of children) {
        pushWithChildren(child, depth + 1);
      }
    };

    for (const root of roots) {
      pushWithChildren(root, 0);
    }

    this.commentDisplay[postId] = ordered;
    this.commentDepth[postId] = depthMap;
  }

  private applyCommentUpdate(postId: string, comment: PostComment): void {
    const existing = this.commentItems[postId] ?? [];
    const next = [...existing];
    const idx = next.findIndex((item) => item.id === comment.id);
    if (idx >= 0) {
      next[idx] = { ...next[idx], ...comment };
    } else {
      next.push(comment);
    }
    this.commentItems[postId] = next;
    this.rebuildCommentThread(postId);
  }

  private commentAuthorName(comment: PostComment): string {
    return comment.author?.username || comment.author?.display_name || 'Member';
  }
}
