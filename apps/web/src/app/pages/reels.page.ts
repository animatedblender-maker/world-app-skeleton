import { CommonModule } from '@angular/common';
import { Component, ElementRef, OnDestroy, OnInit, ViewChild } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { Subscription } from 'rxjs';

import { VideoPlayerComponent } from '../components/video-player.component';
import { AuthService } from '../core/services/auth.service';
import { PostsService } from '../core/services/posts.service';
import { CountryPost, PostComment } from '../core/models/post.model';

@Component({
  selector: 'app-reels-page',
  standalone: true,
  imports: [CommonModule, FormsModule, VideoPlayerComponent],
  template: `
    <div class="reels-root" [class.comments-open]="!!commentOpenPostId">
      <div class="reels-bg" aria-hidden="true"></div>
      <header class="reels-header">
        <button type="button" class="reels-back" (click)="goBack()">Back</button>
        <div class="reels-title">{{ countryName || countryCode || 'Videos' }}</div>
        <div class="reels-sub">Country reels</div>
      </header>

      <div class="reels-feed" #feed>
        <div class="reels-state" *ngIf="loading">Loading videos...</div>
        <div class="reels-state error" *ngIf="!loading && error">{{ error }}</div>
        <div class="reels-state" *ngIf="!loading && !error && !videoPosts.length">
          No videos yet.
        </div>

        <section
          class="reel"
          *ngFor="let post of videoPosts; trackBy: trackPostById"
          [attr.data-post-id]="post.id"
        >
          <div class="reel-frame">
            <app-video-player
              class="reel-player controls-hidden"
              [src]="post.media_url || ''"
              [poster]="post.thumb_url ?? null"
              preload="auto"
              centerOverlayMode="on-click"
              (viewed)="recordView(post)"
            ></app-video-player>
            <div class="reel-gradient" aria-hidden="true"></div>

            <div class="reel-meta">
              <button
                type="button"
                class="reel-author"
                (click)="openAuthorProfile(post.author, post.author_id)"
              >
                <span class="author-avatar">
                  <img *ngIf="post.author?.avatar_url" [src]="post.author?.avatar_url" alt="avatar" />
                  <span *ngIf="!post.author?.avatar_url">
                    {{ (post.author?.display_name || post.author?.username || 'U').slice(0, 2).toUpperCase() }}
                  </span>
                </span>
                <span class="author-text">
                  <span class="author-name">{{ post.author?.display_name || post.author?.username || 'Member' }}</span>
                  <span class="author-handle">@{{ post.author?.username || post.author?.user_id }}</span>
                </span>
              </button>
              <div class="reel-caption" *ngIf="post.media_caption || post.body">
                {{ post.media_caption || post.body }}
              </div>
            </div>

            <div class="reel-actions" (click)="$event.stopPropagation()">
              <button
                class="reel-action"
                type="button"
                [class.active]="post.liked_by_me"
                [disabled]="likeBusy[post.id]"
                (click)="togglePostLike(post)"
                aria-label="Like"
              >
                <svg class="reel-icon" viewBox="0 0 24 24" aria-hidden="true">
                  <path
                    d="M12 21s-6.7-4.4-9.2-7.4C.9 11.4 1.5 7.6 4.6 6 6.6 5 9 5.6 10.5 7.4L12 9l1.5-1.6C15 5.6 17.4 5 19.4 6c3.1 1.6 3.7 5.4 1.8 7.6C18.7 16.6 12 21 12 21z"
                  ></path>
                </svg>
              </button>
              <div class="reel-count">{{ post.like_count }}</div>

              <button
                class="reel-action"
                type="button"
                [class.active]="commentOpenPostId === post.id"
                (click)="toggleComments(post)"
                aria-label="Comments"
              >
                <svg class="reel-icon" viewBox="0 0 24 24" aria-hidden="true">
                  <path
                    d="M4 4h16a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H9l-5 4v-4H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z"
                  ></path>
                </svg>
              </button>
              <div class="reel-count">{{ post.comment_count }}</div>

              <div class="reel-view" aria-label="Views">
                <svg class="reel-icon reel-view-icon" viewBox="0 0 24 24" aria-hidden="true">
                  <path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6-10-6-10-6z"></path>
                  <circle cx="12" cy="12" r="3"></circle>
                </svg>
                <div class="reel-count">{{ post.view_count }}</div>
              </div>
            </div>

            <div class="reel-error" *ngIf="postActionError[post.id]">
              {{ postActionError[post.id] }}
            </div>
          </div>
        </section>
      </div>
    </div>

    <div class="comments-backdrop" *ngIf="commentOpenPostId as openId" (click)="closeComments()">
      <div class="comments-panel" (click)="$event.stopPropagation()">
        <div class="comments-head">
          <div class="comments-title">Comments</div>
          <button type="button" class="comments-close" (click)="closeComments()" aria-label="Close">
            x
          </button>
        </div>
        <div class="comments-meta" *ngIf="commentPost">
          <div>{{ commentPost.author?.display_name || commentPost.author?.username || 'Member' }}</div>
          <div class="comments-meta-sub">{{ commentPost.created_at | date: 'mediumDate' }}</div>
        </div>
        <div class="comment-status" *ngIf="commentLoading[openId]">Loading comments...</div>
        <div class="comment-status error" *ngIf="commentErrors[openId]">{{ commentErrors[openId] }}</div>
        <div class="comments-body" *ngIf="!commentLoading[openId] && !commentErrors[openId]">
          <div class="comment-empty" *ngIf="!(commentDisplay[openId]?.length)">No comments yet.</div>
          <div
            class="comment-row"
            *ngFor="let comment of (commentDisplay[openId] || [])"
            [style.marginLeft.px]="(commentDepth[openId]?.[comment.id] ?? 0) * 16"
          >
            <button class="comment-avatar" type="button" (click)="openAuthorProfile(comment.author)">
              <img *ngIf="comment.author?.avatar_url" [src]="comment.author?.avatar_url" alt="avatar" />
              <span *ngIf="!comment.author?.avatar_url">
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
            {{ commentBusy[openId] ? 'Sending...' : 'Comment' }}
          </button>
        </div>
        <ng-template #commentSignIn>
          <div class="comment-hint">Sign in to comment.</div>
        </ng-template>
      </div>
      </div>
    `,
  styles: [
    `
      :host {
        display: block;
        height: 100%;
        background: #050608;
        color: #f4f6f8;
      }
      .reels-root {
        position: relative;
        height: 100dvh;
        overflow: hidden;
      }
      .reels-bg {
        position: absolute;
        inset: 0;
        background: radial-gradient(circle at 20% 10%, rgba(0, 150, 200, 0.25), transparent 45%),
          radial-gradient(circle at 90% 15%, rgba(255, 120, 40, 0.18), transparent 40%),
          linear-gradient(160deg, #050608, #0b111c 55%, #090b12);
        z-index: 0;
      }
      .reels-header {
        position: fixed;
        top: 18px;
        left: 18px;
        right: 18px;
        display: flex;
        flex-direction: column;
        gap: 6px;
        z-index: 5;
        pointer-events: none;
      }
      .reels-back {
        pointer-events: auto;
        align-self: flex-end;
        border: 1px solid rgba(255, 255, 255, 0.15);
        background: rgba(10, 12, 18, 0.65);
        color: #fff;
        border-radius: 999px;
        padding: 6px 14px;
        font-weight: 700;
        font-size: 12px;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        cursor: pointer;
      }
      .reels-title {
        font-size: 20px;
        font-weight: 800;
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }
      .reels-sub {
        font-size: 12px;
        letter-spacing: 0.2em;
        text-transform: uppercase;
        opacity: 0.7;
      }
      .reels-feed {
        position: relative;
        height: 100%;
        overflow-y: auto;
        scroll-snap-type: y mandatory;
        z-index: 1;
        padding-bottom: env(safe-area-inset-bottom);
        box-sizing: border-box;
      }
      .reels-feed::-webkit-scrollbar {
        width: 0;
        height: 0;
      }
      .reels-state {
        position: relative;
        margin: 120px auto;
        width: min(420px, 90%);
        padding: 16px;
        background: rgba(8, 10, 14, 0.7);
        border: 1px solid rgba(255, 255, 255, 0.1);
        border-radius: 16px;
        text-align: center;
        font-size: 13px;
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }
      .reels-state.error {
        color: #ffb3a8;
        border-color: rgba(255, 120, 100, 0.35);
      }
      .reel {
        height: 100dvh;
        scroll-snap-align: start;
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
      .reel-gradient {
        position: absolute;
        inset: 0;
        background: linear-gradient(180deg, rgba(0, 0, 0, 0.55), rgba(0, 0, 0, 0) 45%, rgba(0, 0, 0, 0.7));
        pointer-events: none;
      }
      .reel-meta {
        position: absolute;
        left: 18px;
        bottom: 26px;
        max-width: min(70vw, 520px);
        z-index: 2;
        display: flex;
        flex-direction: column;
        gap: 10px;
        pointer-events: auto;
      }
      .reel-author {
        display: inline-flex;
        align-items: center;
        gap: 10px;
        padding: 8px 12px;
        border-radius: 999px;
        background: rgba(10, 12, 18, 0.65);
        border: 1px solid rgba(255, 255, 255, 0.15);
        color: #fff;
        cursor: pointer;
        pointer-events: auto;
      }
      .author-avatar {
        width: 36px;
        height: 36px;
        border-radius: 50%;
        overflow: hidden;
        background: rgba(255, 255, 255, 0.08);
        display: grid;
        place-items: center;
        font-weight: 700;
        letter-spacing: 0.08em;
      }
      .author-avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .author-text {
        display: flex;
        flex-direction: column;
        align-items: flex-start;
      }
      .author-name {
        font-weight: 700;
        font-size: 13px;
      }
      .author-handle {
        font-size: 11px;
        opacity: 0.7;
      }
      .reel-caption {
        font-size: 14px;
        line-height: 1.4;
        color: rgba(255, 255, 255, 0.9);
        text-shadow: 0 2px 12px rgba(0, 0, 0, 0.6);
      }
      .reel-actions {
        position: absolute;
        right: 18px;
        bottom: 120px;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 16px;
        z-index: 2;
      }
      .reel-action {
        width: 52px;
        height: 52px;
        border-radius: 50%;
        border: 1px solid rgba(255, 255, 255, 0.2);
        background: rgba(8, 10, 14, 0.65);
        color: #fff;
        display: grid;
        place-items: center;
        cursor: pointer;
      }
      .reel-action.active {
        border-color: rgba(255, 120, 100, 0.7);
        color: #ff7b7b;
        box-shadow: 0 0 18px rgba(255, 120, 100, 0.4);
      }
      .reel-icon {
        width: 22px;
        height: 22px;
        fill: currentColor;
      }
      .reel-count {
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.08em;
      }
      .reel-view {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 6px;
        color: rgba(255, 255, 255, 0.85);
      }
      .reel-view-icon {
        opacity: 0.85;
      }
      .reel-error {
        position: absolute;
        right: 18px;
        top: 90px;
        max-width: 220px;
        padding: 10px 12px;
        border-radius: 12px;
        background: rgba(20, 8, 8, 0.8);
        border: 1px solid rgba(255, 120, 100, 0.4);
        font-size: 12px;
        color: #ffb3a8;
      }
      .comments-backdrop {
        position: fixed;
        inset: 0;
        background: rgba(6, 8, 12, 0.7);
        backdrop-filter: blur(6px);
        display: flex;
        align-items: flex-end;
        justify-content: center;
        z-index: 10;
      }
      .comments-panel {
        width: min(760px, 100%);
        max-height: 72vh;
        background: rgba(10, 12, 18, 0.95);
        border-top-left-radius: 24px;
        border-top-right-radius: 24px;
        border: 1px solid rgba(255, 255, 255, 0.08);
        padding: 16px 16px 20px;
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .comments-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
      }
      .comments-title {
        font-size: 14px;
        text-transform: uppercase;
        letter-spacing: 0.18em;
        font-weight: 800;
      }
      .comments-close {
        border: 1px solid rgba(255, 255, 255, 0.2);
        background: rgba(8, 10, 14, 0.7);
        color: #fff;
        border-radius: 999px;
        width: 30px;
        height: 30px;
        cursor: pointer;
      }
      .comments-meta {
        font-size: 12px;
        opacity: 0.7;
      }
      .comments-meta-sub {
        font-size: 11px;
        margin-top: 4px;
      }
      .comment-status {
        font-size: 12px;
        opacity: 0.7;
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
        opacity: 0.7;
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
        border: 1px solid rgba(255, 255, 255, 0.12);
        background: rgba(255, 255, 255, 0.08);
        display: grid;
        place-items: center;
        color: #fff;
        cursor: pointer;
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
        align-items: center;
        gap: 8px;
        font-size: 11px;
        opacity: 0.7;
      }
      .comment-name {
        font-weight: 700;
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }
      .comment-text {
        margin-top: 4px;
        font-size: 13px;
        line-height: 1.4;
      }
      .comment-actions {
        display: flex;
        gap: 10px;
        margin-top: 6px;
      }
      .comment-action {
        border: 0;
        background: rgba(255, 255, 255, 0.08);
        color: #fff;
        border-radius: 999px;
        padding: 4px 10px;
        font-size: 11px;
        letter-spacing: 0.06em;
        cursor: pointer;
      }
      .comment-action.active {
        color: #ff9d8c;
      }
      .comment-action:disabled {
        opacity: 0.6;
        cursor: not-allowed;
      }
      .comment-like-count {
        margin-left: 6px;
        font-weight: 700;
      }
      .comment-compose {
        border-top: 1px solid rgba(255, 255, 255, 0.08);
        padding-top: 10px;
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      .comment-reply {
        font-size: 12px;
        opacity: 0.8;
        display: flex;
        align-items: center;
        gap: 8px;
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
        background: rgba(8, 10, 14, 0.7);
        color: #fff;
        padding: 10px 12px;
        font-size: 13px;
        resize: vertical;
      }
      .comment-submit {
        border-radius: 999px;
        border: 1px solid rgba(139, 220, 255, 0.6);
        background: rgba(10, 120, 200, 0.25);
        color: #fff;
        padding: 8px 16px;
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        cursor: pointer;
      }
      .comment-submit:disabled {
        opacity: 0.6;
        cursor: not-allowed;
      }
      .comment-hint {
        font-size: 12px;
        opacity: 0.7;
        text-align: center;
      }
      @media (max-width: 720px) {
        .reel-actions {
          right: 12px;
          bottom: 90px;
        }
        .reel-action {
          width: 46px;
          height: 46px;
        }
        .reels-title {
          font-size: 16px;
        }
        .reel-caption {
          font-size: 13px;
        }
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

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private auth: AuthService,
    private postsService: PostsService
  ) {}

  ngOnInit(): void {
    void this.loadMe();
    this.routeSub = this.route.paramMap.subscribe((params) => {
      this.countryCode = (params.get('country') || '').toUpperCase();
      this.commentOpenPostId = null;
      this.commentPost = null;
      this.seeded = this.applySeedFromState();
      if (!this.seeded) {
        void this.loadReels();
      } else {
        this.tryScrollToPending();
      }
    });
    this.querySub = this.route.queryParamMap.subscribe((params) => {
      this.pendingScrollId = params.get('postId');
      this.tryScrollToPending();
    });
  }

  ngOnDestroy(): void {
    this.routeSub?.unsubscribe();
    this.querySub?.unsubscribe();
  }

  trackPostById(_: number, post: CountryPost): string {
    return post.id;
  }

  goBack(): void {
    if (this.countryCode) {
      void this.router.navigate(['/globe'], {
        queryParams: { country: this.countryCode, tab: 'media' },
      });
      return;
    }
    void this.router.navigate(['/globe']);
  }

  openAuthorProfile(
    author: CountryPost['author'] | PostComment['author'] | null | undefined,
    fallbackId?: string | null
  ): void {
    const slug = author?.username?.trim() || author?.user_id || fallbackId;
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
    const user = await this.auth.getUser();
    this.meId = user?.id ?? null;
  }

  private async loadReels(): Promise<void> {
    if (!this.countryCode) {
      this.error = 'Missing country.';
      return;
    }
    this.loading = true;
    this.error = '';
    this.posts = [];
    this.videoPosts = [];
    try {
      const posts = await this.postsService.listByCountry(this.countryCode, 180, {
        demoLimit: 180,
        skipComments: true,
      });
      this.posts = posts ?? [];
      this.videoPosts = this.posts.filter(
        (post) => post.media_type === 'video' && !!post.media_url
      );
      this.countryName = this.posts.find((post) => post.country_name)?.country_name || this.countryCode;
      this.tryScrollToPending();
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    } finally {
      this.loading = false;
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
    const videos = seedPosts.filter(
      (post) => post?.media_type === 'video' && !!post?.media_url
    );
    if (!videos.length) return false;
    this.videoPosts = videos;
    this.countryName = state.countryName || this.countryName;
    this.loading = false;
    this.error = '';
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
      }
    }, 50);
  }

  private applyPostUpdate(updated: CountryPost): void {
    const idx = this.videoPosts.findIndex((post) => post.id === updated.id);
    if (idx >= 0) {
      this.videoPosts[idx] = { ...this.videoPosts[idx], ...updated };
    }
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
