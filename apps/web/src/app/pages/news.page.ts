import { CommonModule } from '@angular/common';
import { Component, OnDestroy, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { Subscription } from 'rxjs';

import { BottomTabsComponent } from '../components/bottom-tabs.component';
import type { ExternalNewsComment, ExternalNewsItem } from '../core/models/post.model';
import { NewsService } from '../core/services/news.service';

@Component({
  selector: 'app-news-page',
  standalone: true,
  imports: [CommonModule, FormsModule, BottomTabsComponent],
  template: `
    <div class="news-shell">
      <button class="logo-btn" type="button" (click)="goHome()">
        <img src="/logo.png" alt="Matterya" />
      </button>

      <div class="news-card" *ngIf="loading">Loading news...</div>
      <div class="news-card error" *ngIf="!loading && error">{{ error }}</div>

      <div class="news-card" *ngIf="!loading && item as article">
        <div class="news-kicker-row">
          <span class="news-kicker">{{ article.source_name || 'ReliefWeb' }}</span>
          <span class="news-date">{{ article.published_at ? (article.published_at | date: 'medium') : '' }}</span>
        </div>

        <div class="news-title">{{ article.title }}</div>

        <div class="news-tags" *ngIf="article.theme_names.length || article.disaster_types.length">
          <span class="tag" *ngFor="let tag of article.theme_names.slice(0, 3)">{{ tag }}</span>
          <span class="tag" *ngFor="let tag of article.disaster_types.slice(0, 3)">{{ tag }}</span>
        </div>

        <div class="news-media" *ngIf="article.image_url">
          <img [src]="article.image_url" [alt]="article.title" />
        </div>

        <div class="news-summary" *ngIf="article.snippet">{{ article.snippet }}</div>

        <div class="news-country-line" *ngIf="article.country_names.length">
          {{ article.country_names.join(' • ') }}
        </div>

        <div class="news-actions">
          <button class="action" type="button" [class.active]="article.liked_by_me" [disabled]="likeBusy" (click)="toggleLike()">
            {{ article.liked_by_me ? 'Unlike' : 'Like' }} · {{ article.like_count }}
          </button>
          <button class="action" type="button" (click)="toggleComments()">
            {{ commentsOpen ? 'Hide comments' : 'Comments' }} · {{ article.comment_count }}
          </button>
          <a class="action source" [href]="sourceUrl(article)" target="_blank" rel="noreferrer">Go to source</a>
        </div>

        <div class="share-panel">
          <div class="panel-title">Share This News To Your Feed</div>
          <textarea
            class="panel-input"
            rows="3"
            maxlength="5000"
            placeholder="Add your caption before sharing..."
            [(ngModel)]="shareDraft"
          ></textarea>
          <button class="panel-button" type="button" [disabled]="shareBusy" (click)="shareToFeed()">
            {{ shareBusy ? 'Sharing...' : 'Share to country feed' }}
          </button>
          <div class="panel-message" *ngIf="shareFeedback">{{ shareFeedback }}</div>
        </div>

        <div class="comment-panel" *ngIf="commentsOpen">
          <div class="panel-title">Comments</div>
          <div class="comment-list" *ngIf="comments.length; else noComments">
            <article class="comment" *ngFor="let comment of comments">
              <div class="comment-head">
                <span class="comment-author">{{ comment.author?.display_name || comment.author?.username || 'Member' }}</span>
                <span class="comment-date">{{ comment.created_at | date: 'mediumDate' }}</span>
              </div>
              <div class="comment-body">{{ comment.body }}</div>
            </article>
          </div>
          <ng-template #noComments>
            <div class="comment-empty">No comments yet.</div>
          </ng-template>

          <textarea
            class="panel-input"
            rows="3"
            maxlength="5000"
            placeholder="Add a comment..."
            [(ngModel)]="commentDraft"
          ></textarea>
          <button class="panel-button" type="button" [disabled]="commentBusy" (click)="submitComment()">
            {{ commentBusy ? 'Posting...' : 'Post comment' }}
          </button>
          <div class="panel-message error" *ngIf="commentError">{{ commentError }}</div>
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
        background: #eef2f5;
        color: #16191f;
      }
      .news-shell {
        height: 100dvh;
        overflow-y: auto;
        overflow-x: hidden;
        min-height: 100dvh;
        padding: 92px 18px calc(24px + var(--tabs-safe, 64px));
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 18px;
      }
      .logo-btn {
        position: fixed;
        top: 18px;
        left: 18px;
        width: 48px;
        height: 48px;
        border: 0;
        border-radius: 50%;
        background: rgba(255, 255, 255, 0.9);
        box-shadow: 0 12px 30px rgba(16, 24, 40, 0.12);
        display: grid;
        place-items: center;
        cursor: pointer;
        z-index: 10;
      }
      .logo-btn img {
        width: 40px;
        height: 40px;
        object-fit: contain;
      }
      .news-card {
        width: min(780px, 100%);
        background: #fff;
        border-radius: 28px;
        padding: 22px;
        box-shadow: 0 20px 55px rgba(17, 24, 39, 0.08);
      }
      .news-card.error,
      .panel-message.error {
        color: #b42318;
      }
      .news-kicker-row {
        display: flex;
        justify-content: space-between;
        gap: 12px;
        font-size: 12px;
        color: #667085;
        margin-bottom: 10px;
      }
      .news-kicker {
        font-weight: 800;
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }
      .news-title {
        font-size: clamp(28px, 3vw, 42px);
        line-height: 1.05;
        font-weight: 900;
        letter-spacing: -0.04em;
        margin-bottom: 14px;
      }
      .news-tags {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
        margin-bottom: 14px;
      }
      .tag {
        padding: 6px 10px;
        border-radius: 999px;
        background: #eef2f6;
        color: #344054;
        font-size: 12px;
        font-weight: 700;
      }
      .news-media {
        border-radius: 22px;
        overflow: hidden;
        margin-bottom: 16px;
        background: #d9dde3;
      }
      .news-media img {
        width: 100%;
        display: block;
        object-fit: cover;
      }
      .news-summary {
        font-size: 16px;
        line-height: 1.7;
        color: #344054;
        margin-bottom: 14px;
      }
      .news-country-line {
        color: #475467;
        font-size: 13px;
        margin-bottom: 18px;
      }
      .news-actions {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
        margin-bottom: 20px;
      }
      .action {
        border: 1px solid #d0d5dd;
        background: #fff;
        color: #101828;
        border-radius: 999px;
        padding: 10px 14px;
        font-weight: 700;
        cursor: pointer;
        text-decoration: none;
      }
      .action.active {
        background: #101828;
        color: #fff;
      }
      .share-panel,
      .comment-panel {
        border-top: 1px solid #eaecf0;
        padding-top: 18px;
        margin-top: 18px;
      }
      .panel-title {
        font-size: 13px;
        font-weight: 900;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        margin-bottom: 10px;
        color: #475467;
      }
      .panel-input {
        width: 100%;
        border: 1px solid #d0d5dd;
        border-radius: 18px;
        padding: 14px 16px;
        resize: vertical;
        font: inherit;
        box-sizing: border-box;
        background: #fff;
      }
      .panel-button {
        margin-top: 10px;
        border: 0;
        border-radius: 999px;
        background: #101828;
        color: #fff;
        padding: 12px 18px;
        font-weight: 800;
        cursor: pointer;
      }
      .panel-message {
        margin-top: 10px;
        font-size: 13px;
        color: #475467;
      }
      .comment-list {
        display: grid;
        gap: 12px;
        margin-bottom: 14px;
      }
      .comment {
        padding: 14px 16px;
        border-radius: 18px;
        background: #f8fafc;
      }
      .comment-head {
        display: flex;
        justify-content: space-between;
        gap: 10px;
        margin-bottom: 6px;
        font-size: 12px;
        color: #667085;
      }
      .comment-author {
        font-weight: 800;
        color: #101828;
      }
      .comment-body {
        color: #344054;
        line-height: 1.6;
      }
      .comment-empty {
        color: #667085;
        margin-bottom: 14px;
      }
    `,
  ],
})
export class NewsPageComponent implements OnInit, OnDestroy {
  item: ExternalNewsItem | null = null;
  comments: ExternalNewsComment[] = [];
  loading = true;
  error = '';
  commentsOpen = true;
  commentDraft = '';
  commentBusy = false;
  commentError = '';
  shareDraft = '';
  shareBusy = false;
  shareFeedback = '';
  likeBusy = false;
  private routeSub?: Subscription;

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private newsService: NewsService
  ) {}

  ngOnInit(): void {
    this.routeSub = this.route.paramMap.subscribe((params) => {
      const id = String(params.get('id') ?? '').trim();
      void this.loadArticle(id);
    });
  }

  ngOnDestroy(): void {
    this.routeSub?.unsubscribe();
  }

  goHome(): void {
    void this.router.navigateByUrl('/globe');
  }

  async loadComments(): Promise<void> {
    if (!this.item) return;
    this.comments = await this.newsService.comments(this.item.id);
  }

  private getRouteStateItem(expectedId: string): ExternalNewsItem | null {
    const stateItem = history.state?.newsItem as ExternalNewsItem | undefined;
    return stateItem?.id === expectedId ? stateItem : null;
  }

  private async loadArticle(id: string): Promise<void> {
    this.error = '';
    this.comments = [];
    this.commentDraft = '';
    this.commentError = '';
    this.shareFeedback = '';

    if (!id) {
      this.item = null;
      this.loading = false;
      this.error = 'News item not found.';
      return;
    }

    const stateItem = this.getRouteStateItem(id);
    if (stateItem) {
      this.item = stateItem;
      this.loading = false;
      void this.loadComments().catch(() => undefined);
    } else {
      this.item = null;
      this.loading = true;
    }

    try {
      const freshItem = await this.newsService.item(id);
      if (!freshItem) {
        this.item = null;
        this.error = 'News item not found.';
        return;
      }
      this.item = freshItem;
      await this.loadComments();
    } catch (error: any) {
      if (!this.item) {
        this.error = error?.message ?? 'Failed to load this news item.';
      }
    } finally {
      this.loading = false;
    }
  }

  toggleComments(): void {
    this.commentsOpen = !this.commentsOpen;
  }

  async submitComment(): Promise<void> {
    if (!this.item || this.commentBusy) return;
    const body = this.commentDraft.trim();
    if (!body) return;
    this.commentBusy = true;
    this.commentError = '';
    try {
      const created = await this.newsService.addComment(this.item.id, body);
      this.comments = [...this.comments, created];
      this.commentDraft = '';
      this.item = {
        ...this.item,
        comment_count: (this.item.comment_count ?? 0) + 1,
      };
    } catch (error: any) {
      this.commentError = error?.message ?? 'Failed to post comment.';
    } finally {
      this.commentBusy = false;
    }
  }

  async toggleLike(): Promise<void> {
    if (!this.item || this.likeBusy) return;
    this.likeBusy = true;
    try {
      this.item = this.item.liked_by_me
        ? await this.newsService.unlike(this.item.id)
        : await this.newsService.like(this.item.id);
    } catch (error: any) {
      this.error = error?.message ?? 'Failed to update like.';
    } finally {
      this.likeBusy = false;
    }
  }

  async shareToFeed(): Promise<void> {
    if (!this.item || this.shareBusy) return;
    this.shareBusy = true;
    this.shareFeedback = '';
    try {
      await this.newsService.shareToCountry(this.item.id, this.shareDraft.trim() || null);
      this.shareDraft = '';
      this.item = {
        ...this.item,
        shared_post_count: (this.item.shared_post_count ?? 0) + 1,
      };
      this.shareFeedback = 'Shared to your country feed.';
    } catch (error: any) {
      this.shareFeedback = error?.message ?? 'Failed to share.';
    } finally {
      this.shareBusy = false;
    }
  }

  sourceUrl(article: ExternalNewsItem): string {
    const raw = String(article?.url ?? '').trim();
    if (/^https?:\/\/api\.reliefweb\.int\/v2\/reports\b/i.test(raw) && article?.provider_item_id) {
      return `https://reliefweb.int/node/${encodeURIComponent(article.provider_item_id)}`;
    }
    if (raw) return raw;
    if (article?.provider === 'reliefweb' && article?.provider_item_id) {
      return `https://reliefweb.int/node/${encodeURIComponent(article.provider_item_id)}`;
    }
    return '#';
  }
}
