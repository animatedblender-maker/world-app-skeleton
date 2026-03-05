
import { CommonModule } from '@angular/common';
import { Component, OnDestroy, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';

import { CountriesService, type CountryModel } from '../data/countries.service';
import { SearchService } from '../search/search.service';
import { AuthService } from '../core/services/auth.service';
import { PostsService } from '../core/services/posts.service';
import { ProfileService, type Profile } from '../core/services/profile.service';
import { FollowService } from '../core/services/follow.service';
import { VideoPlayerComponent } from '../components/video-player.component';
import { BottomTabsComponent } from '../components/bottom-tabs.component';
import { SUPABASE_URL } from '../config/supabase.config';
import type { CountryPost, PostComment, PostLike } from '../core/models/post.model';

@Component({
  selector: 'app-search-page',
  standalone: true,
  imports: [CommonModule, FormsModule, VideoPlayerComponent, BottomTabsComponent],
  template: `
    <div class="search-shell">
      <header class="search-header">
        <button class="logo-btn" type="button" (click)="goHome()" aria-label="Go to globe">
          <img src="/logo.png?v=3" alt="Matterya" />
        </button>
        <div class="search-field">
          <input
            type="search"
            placeholder="Search posts, people, countries"
            autocomplete="off"
            [(ngModel)]="searchTerm"
            (input)="onSearchInput(searchTerm)"
            name="searchTerm"
          />
        </div>
      </header>

      <div class="search-body">
        <div class="search-state" *ngIf="searchBusy">Searching...</div>
        <div class="search-state error" *ngIf="!searchBusy && searchError">{{ searchError }}</div>
        <div class="search-state" *ngIf="!searchBusy && !searchTerm">Type to search posts, people, or countries.</div>

        <section class="results-section" *ngIf="countryResults.length">
          <div class="section-title">Countries</div>
          <div class="country-list">
            <button
              type="button"
              class="country-row"
              *ngFor="let country of countryResults"
              (click)="focusCountry(country)"
            >
              <span>{{ country.name }}</span>
              <small>{{ country.code || country.name }}</small>
            </button>
          </div>
        </section>

        <section class="results-section" *ngIf="peopleResults.length">
          <div class="section-title">People</div>
          <div class="people-list">
            <div class="person-card" *ngFor="let person of peopleResults">
              <button
                class="author-core clickable"
                type="button"
                (click)="openUserProfile(person); $event.stopPropagation()"
              >
                <div class="author-avatar">
                  <img *ngIf="person.avatar_url" [src]="normalizeAvatarUrl(person.avatar_url)" alt="avatar" />
                  <div class="author-initials" *ngIf="!person.avatar_url">
                    {{ (person.display_name || person.username || 'User').slice(0, 2).toUpperCase() }}
                  </div>
                </div>
                <div class="author-info">
                  <div class="author-name">{{ person.display_name || person.username || 'Member' }}</div>
                  <div class="author-meta">
                    @{{ person.username || 'user' }}
                    <span *ngIf="person.country_name"> - {{ person.country_name }}</span>
                  </div>
                </div>
              </button>
              <button
                *ngIf="meId && !isAuthorSelf(person.user_id)"
                class="follow-chip"
                type="button"
                [class.following]="isFollowingAuthor(person.user_id)"
                (click)="toggleFollowAuthor(person.user_id); $event.stopPropagation()"
                [disabled]="followBusyFor(person.user_id)"
              >
                {{ isFollowingAuthor(person.user_id) ? 'Following' : 'Follow' }}
              </button>
            </div>
          </div>
        </section>

        <section class="results-section">
          <div class="section-title">Posts</div>
          <div class="posts-state" *ngIf="!searchBusy && searchTerm && !postResults.length">
            No posts found.
          </div>
          <div class="posts-list" *ngIf="postResults.length">
            <div
              class="post-card"
              [class.media]="!!post.media_url && post.media_type !== 'none'"
              *ngFor="let post of postResults; trackBy: trackPostById"
              (click)="openPost(post, $event)"
            >
              <div class="post-author">
                <div
                  class="author-core clickable"
                  role="button"
                  tabindex="0"
                  (click)="openAuthorProfile(post.author, post.author_id); $event.stopPropagation()"
                  (keyup.enter)="openAuthorProfile(post.author, post.author_id); $event.stopPropagation()"
                >
                  <div class="author-avatar">
                    <img
                      *ngIf="post.author?.avatar_url"
                      [src]="normalizeAvatarUrl(post.author?.avatar_url)"
                      alt="avatar"
                    />
                    <div class="author-initials" *ngIf="!post.author?.avatar_url">
                      {{ (post.author?.display_name || post.author?.username || 'User').slice(0, 2).toUpperCase() }}
                    </div>
                  </div>
                  <div class="author-info">
                    <div class="author-name">{{ post.author?.display_name || post.author?.username || 'Member' }}</div>
                    <div class="author-meta">
                      @{{ post.author?.username || 'user' }} - {{ post.created_at | date: 'mediumDate' }}
                      <span class="post-visibility" *ngIf="post.visibility !== 'public' && post.visibility !== 'country'">
                        - {{ visibilityLabel(post.visibility) }}
                      </span>
                      <span *ngIf="post.country_name || post.country_code"> - {{ post.country_name || post.country_code }}</span>
                    </div>
                  </div>
                </div>
                <button
                  *ngIf="meId && !isAuthorSelf(post.author_id)"
                  class="follow-chip"
                  type="button"
                  [class.following]="isFollowingAuthor(post.author_id)"
                  (click)="toggleFollowAuthor(post.author_id); $event.stopPropagation()"
                  [disabled]="followBusyFor(post.author_id)"
                >
                  {{ isFollowingAuthor(post.author_id) ? 'Following' : 'Follow' }}
                </button>
              </div>

              <div class="post-body">
                <div class="post-title" *ngIf="post.title">{{ post.title }}</div>
                <p
                  class="post-text"
                  *ngIf="post.body && (!post.media_url || post.media_type === 'none' || !postHasVideo(post))"
                  [class.clamped]="!isPostExpanded(post.id) && isTextExpandable(post.body)"
                  (click)="onPostTextClick(post.id, $event)"
                >
                  <span>{{ isPostExpanded(post.id) ? post.body : postPreview(post.body) }}</span>
                  <button
                    class="see-more inline"
                    type="button"
                    *ngIf="!isPostExpanded(post.id) && isTextExpandable(post.body)"
                    (click)="togglePostExpanded(post.id, $event)"
                  >
                    See more
                  </button>
                </p>
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
                      <img *ngIf="shared.author?.avatar_url" [src]="normalizeAvatarUrl(shared.author?.avatar_url)" alt="avatar" />
                      <div class="shared-initials" *ngIf="!shared.author?.avatar_url">
                        {{ (shared.author?.display_name || shared.author?.username || 'User').slice(0, 2).toUpperCase() }}
                      </div>
                    </div>
                    <div class="shared-info">
                      <div class="shared-name">{{ shared.author?.display_name || shared.author?.username || 'Member' }}</div>
                      <div class="shared-meta">
                        @{{ shared.author?.username || 'user' }} · {{ shared.created_at | date: 'mediumDate' }}
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
              <div class="post-media" *ngIf="post.media_url && post.media_type !== 'none'">
                <ng-container *ngIf="postMediaUrls(post) as mediaUrls">
                  <ng-container *ngIf="postMediaTypes(post) as mediaTypes">
                    <ng-container *ngIf="mediaUrls.length <= 1; else mediaGallery">
                      <img
                        *ngIf="mediaTypes[0] === 'image'"
                        class="zoomable"
                        [src]="mediaUrls[0]"
                        alt="post media"
                        (click)="openImageLightbox(mediaUrls[0]); $event.stopPropagation()"
                      />
                      <app-video-player
                        *ngIf="mediaTypes[0] === 'video'"
                        [src]="mediaUrls[0]"
                        [adPlacement]="postIsReel(post) ? 'reel' : 'video'"
                        [adCountryCode]="post.country_code"
                        [adContentCountryCode]="post.country_code"
                        [adPostId]="post.id"
                        [tapBehavior]="postIsReel(post) ? 'emit' : 'toggle'"
                        (viewed)="recordView(post)"
                        (videoTap)="onPostVideoTap(post)"
                      ></app-video-player>
                    </ng-container>
                    <ng-template #mediaGallery>
                      <div class="media-gallery">
                        <div class="media-strip" (scroll)="onPostMediaScroll(post, $event)">
                          <div class="media-item" *ngFor="let url of mediaUrls; let idx = index">
                            <app-video-player
                              *ngIf="mediaTypes[idx] === 'video'"
                              [src]="url"
                              [adPlacement]="postIsReel(post) ? 'reel' : 'video'"
                              [adCountryCode]="post.country_code"
                              [adContentCountryCode]="post.country_code"
                              [adPostId]="post.id"
                              [tapBehavior]="postIsReel(post) ? 'emit' : 'toggle'"
                              (viewed)="recordView(post)"
                              (videoTap)="onPostVideoTap(post)"
                            ></app-video-player>
                            <img
                              *ngIf="mediaTypes[idx] === 'image'"
                              class="zoomable"
                              [src]="url"
                              alt="post media"
                              (click)="openImageLightbox(url); $event.stopPropagation()"
                            />
                          </div>
                        </div>
                        <div class="media-dots">
                          <span
                            *ngFor="let _ of mediaUrls; let dotIndex = index"
                            [class.active]="dotIndex === postMediaIndexValue(post)"
                          ></span>
                          <span class="media-count">{{ postMediaIndexValue(post) + 1 }}/{{ mediaUrls.length }}</span>
                        </div>
                      </div>
                    </ng-template>
                  </ng-container>
                </ng-container>
              </div>

              <div
                class="post-caption post-text"
                *ngIf="post.media_url && post.media_type !== 'none' && postCaptionText(post) as caption"
                [class.clamped]="!isPostExpanded(post.id) && isTextExpandable(caption)"
                (click)="onPostTextClick(post.id, $event)"
              >
                <span>{{ isPostExpanded(post.id) ? caption : postPreview(caption) }}</span>
                <button
                  class="see-more inline"
                  type="button"
                  *ngIf="!isPostExpanded(post.id) && isTextExpandable(caption)"
                  (click)="togglePostExpanded(post.id, $event)"
                >
                  See more
                </button>
              </div>
              <div class="post-actions">
                <div class="post-action-group">
                  <button
                    class="post-action like"
                    type="button"
                    [class.active]="post.liked_by_me"
                    [disabled]="likeBusy[post.id]"
                    (click)="togglePostLike(post); $event.stopPropagation()"
                  >
                    <span class="icon">{{ post.liked_by_me ? '\u2665' : '\u2661' }}</span>
                  </button>
                  <button
                    class="post-action count"
                    type="button"
                    [class.active]="likeOpen[post.id]"
                    (click)="toggleLikes(post.id); $event.stopPropagation()"
                  >
                    <span class="count">{{ post.like_count }}</span>
                  </button>
                </div>
                <button
                  class="post-action comment"
                  type="button"
                  [class.active]="commentOpen[post.id]"
                  (click)="toggleComments(post.id); $event.stopPropagation()"
                >
                  <span class="icon">{{ '\u{1F4AC}' }}</span>
                  <span class="count">{{ post.comment_count }}</span>
                </button>
                <button
                  class="post-action share"
                  type="button"
                  (click)="sharePostToCountry(post, $event)"
                  aria-label="Share to your country"
                >
                  <span class="icon">{{ '\u{1F517}' }}</span>
                </button>
                <span class="post-share-feedback" *ngIf="postShareFeedback[post.id]">
                  {{ postShareFeedback[post.id] }}
                </span>
                <div class="post-action view" aria-label="Views">
                  <span class="icon">{{ '\u{1F441}' }}</span>
                  <span class="count">{{ post.view_count }}</span>
                </div>
              </div>

              <div class="post-action-error" *ngIf="postActionError[post.id]">
                {{ postActionError[post.id] }}
              </div>

              <div class="post-likes" *ngIf="likeOpen[post.id]">
                <div class="like-status" *ngIf="likeLoading[post.id]">Loading likes...</div>
                <div class="like-status error" *ngIf="likeErrors[post.id]">{{ likeErrors[post.id] }}</div>
                <div class="like-list" *ngIf="!likeLoading[post.id] && !likeErrors[post.id]">
                  <div class="like-empty" *ngIf="!(likeItems[post.id]?.length)">No likes yet.</div>
                  <button
                    class="like-row"
                    type="button"
                    *ngFor="let like of likeItems[post.id]"
                    (click)="openAuthorProfile(like.user); $event.stopPropagation()"
                  >
                    <div class="like-avatar">
                      <img
                        *ngIf="like.user?.avatar_url"
                        [src]="normalizeAvatarUrl(like.user?.avatar_url)"
                        alt="avatar"
                      />
                      <div class="like-initials" *ngIf="!like.user?.avatar_url">
                        {{ (like.user?.display_name || like.user?.username || 'U').slice(0, 2).toUpperCase() }}
                      </div>
                    </div>
                    <div class="like-body">
                      <div class="like-name">{{ like.user?.display_name || like.user?.username || 'Member' }}</div>
                      <div class="like-handle">@{{ like.user?.username || 'user' }}</div>
                    </div>
                    <div class="like-time">{{ like.created_at | date: 'mediumDate' }}</div>
                  </button>
                </div>
              </div>

              <div class="post-comments" *ngIf="commentOpen[post.id]">
                <div class="comment-status" *ngIf="commentLoading[post.id]">Loading comments...</div>
                <div class="comment-status error" *ngIf="commentErrors[post.id]">{{ commentErrors[post.id] }}</div>
                <div class="comment-list" *ngIf="!commentLoading[post.id] && !commentErrors[post.id]">
                  <div class="comment-empty" *ngIf="!(commentDisplay[post.id]?.length)">No comments yet.</div>
                  <div
                    class="comment"
                    *ngFor="let comment of (commentDisplay[post.id] || [])"
                    [style.marginLeft.px]="(commentDepth[post.id]?.[comment.id] ?? 0) * 18"
                  >
                    <div class="comment-avatar">
                      <img
                        *ngIf="comment.author?.avatar_url"
                        [src]="normalizeAvatarUrl(comment.author?.avatar_url)"
                        alt="avatar"
                      />
                      <div class="comment-initials" *ngIf="!comment.author?.avatar_url">
                        {{ (comment.author?.display_name || comment.author?.username || 'U').slice(0, 2).toUpperCase() }}
                      </div>
                    </div>
                    <div class="comment-body">
                      <div class="comment-meta">
                        <span class="comment-name">{{ comment.author?.display_name || comment.author?.username || 'Member' }}</span>
                        <span class="comment-time">{{ comment.created_at | date: 'mediumDate' }}</span>
                      </div>
                      <div class="comment-text">{{ comment.body }}</div>
                      <div class="comment-actions">
                        <button
                          class="comment-action"
                          type="button"
                          (click)="startCommentReply(post.id, comment); $event.stopPropagation()"
                          [disabled]="commentBusy[post.id]"
                        >
                          Reply
                        </button>
                        <button
                          class="comment-action"
                          type="button"
                          (click)="toggleCommentLike(post.id, comment); $event.stopPropagation()"
                          [class.active]="comment.liked_by_me"
                          [disabled]="commentLikeBusy[post.id]?.[comment.id]"
                        >
                          <span class="comment-heart" *ngIf="!comment.liked_by_me" aria-hidden="true">&#9825;</span>
                          <span class="comment-heart active" *ngIf="comment.liked_by_me" aria-hidden="true">&#9829;</span>
                          <span class="comment-like-count" *ngIf="comment.like_count">
                            {{ comment.like_count }}
                          </span>
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
                <div class="comment-compose" *ngIf="meId; else commentSignIn">
                  <div class="comment-reply" *ngIf="commentReplyTarget[post.id] as replyTarget">
                    Replying to <span>@{{ replyTarget.authorName }}</span>
                    <button type="button" class="ghost-link" (click)="cancelCommentReply(post.id); $event.stopPropagation()">Cancel</button>
                  </div>
                  <input
                    class="comment-input"
                    placeholder="Write a comment"
                    [disabled]="commentBusy[post.id]"
                    [(ngModel)]="commentDrafts[post.id]"
                    (click)="$event.stopPropagation()"
                  />
                  <button
                    class="comment-submit"
                    type="button"
                    [disabled]="commentBusy[post.id]"
                    (click)="submitComment(post); $event.stopPropagation()"
                  >
                    {{ commentBusy[post.id] ? 'Sending...' : 'Comment' }}
                  </button>
                </div>
                <ng-template #commentSignIn>
                  <div class="comment-hint">Sign in to comment.</div>
                </ng-template>
              </div>
            </div>
          </div>
        </section>
      </div>
    </div>

    <div class="lightbox" *ngIf="lightboxUrl" (click)="closeImageLightbox()">
      <div class="lightbox-frame">
        <img [src]="lightboxUrl" alt="Full size" />
      </div>
      <button class="lightbox-close" type="button" aria-label="Close" (click)="closeImageLightbox()">×</button>
    </div>

    <app-bottom-tabs></app-bottom-tabs>
  `,
  styles: [
    `
      :host {
        display: block;
        min-height: 100dvh;
        height: 100dvh;
        background: #f5f7fa;
        color: #0b0f18;
        overflow: hidden;
      }
      .search-shell {
        min-height: 100dvh;
        display: flex;
        flex-direction: column;
      }
      .search-header {
        position: sticky;
        top: 0;
        z-index: 5;
        display: flex;
        align-items: center;
        gap: 14px;
        padding: calc(14px + env(safe-area-inset-top)) 16px 12px;
        background: #fff;
        box-shadow: 0 10px 28px rgba(0, 0, 0, 0.08);
      }
      .logo-btn {
        width: 44px;
        height: 44px;
        border-radius: 14px;
        border: 1px solid rgba(0, 0, 0, 0.08);
        background: transparent;
        display: grid;
        place-items: center;
        cursor: pointer;
        padding: 0;
      }
      .logo-btn img {
        width: 34px;
        height: 34px;
      }
      .search-field {
        flex: 1;
      }
      .search-field input {
        width: 100%;
        border-radius: 14px;
        border: 1px solid rgba(0, 0, 0, 0.12);
        padding: 12px 14px;
        font-size: 14px;
        background: rgba(248, 249, 251, 0.95);
        outline: none;
      }
      .search-body {
        flex: 1;
        overflow-y: auto;
        padding: 16px 16px calc(24px + var(--tabs-safe, 64px));
      }
      .search-state {
        font-size: 12px;
        font-weight: 700;
        opacity: 0.7;
        margin-bottom: 12px;
      }
      .search-state.error {
        color: #c33;
        opacity: 0.9;
      }
      .results-section {
        margin-bottom: 20px;
      }
      .section-title {
        font-size: 11px;
        letter-spacing: 0.16em;
        font-weight: 800;
        text-transform: uppercase;
        color: rgba(10, 12, 18, 0.6);
        margin-bottom: 10px;
      }
      .country-list,
      .people-list {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      .country-row {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 12px 14px;
        border-radius: 14px;
        border: 1px solid rgba(0, 0, 0, 0.08);
        background: #fff;
        font-size: 14px;
        cursor: pointer;
      }
      .country-row small {
        font-size: 11px;
        opacity: 0.6;
        text-transform: uppercase;
        letter-spacing: 0.08em;
      }
      .person-card {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        padding: 12px 14px;
        border-radius: 16px;
        border: 1px solid rgba(0, 0, 0, 0.08);
        background: #fff;
      }
      .person-card .author-core {
        flex: 1;
        border: 0;
        background: transparent;
        padding: 0;
      }

      .posts-state { font-size: 13px; font-weight: 700; opacity: 0.7; }
      .posts-state.error { color: #ff6b81; }
      .posts-list { display: flex; flex-direction: column; gap: 10px; box-sizing: border-box; padding-bottom: 10px; overflow-x: hidden; }
      .posts-empty { text-align: center; font-size: 13px; opacity: 0.65; }
      .post-card {
        position: relative;
        border-radius: 20px;
        border: 1px solid rgba(0, 0, 0, 0.06);
        background: rgba(255, 255, 255, 0.98);
        --post-pad-x: 16px;
        padding: var(--post-pad-x);
        box-shadow: 0 18px 60px rgba(0, 0, 0, 0.15);
        box-sizing: border-box;
        overflow-x: hidden;
      }
      .post-author {
        display: flex;
        align-items: flex-start;
        gap: 12px;
        flex-wrap: wrap;
      }
      .author-core {
        display: flex;
        align-items: center;
        gap: 12px;
        flex: 1;
        cursor: default;
      }
      .author-core.clickable { cursor: pointer; }
      .author-avatar {
        width: 42px;
        height: 42px;
        border-radius: 999px;
        overflow: hidden;
        background: rgba(245, 247, 250, 0.95);
        border: 1px solid rgba(0, 0, 0, 0.08);
        box-shadow: 0 10px 24px rgba(0, 0, 0, 0.12);
        display: grid;
        place-items: center;
        color: rgba(10, 12, 18, 0.8);
        font-weight: 900;
        letter-spacing: 0.08em;
      }
      .author-avatar img { width: 100%; height: 100%; object-fit: cover; }
      .author-info { flex: 1; min-width: 0; }
      .author-name { font-weight: 900; font-size: 13px; letter-spacing: 0.04em; }
      .author-meta { font-size: 12px; opacity: 0.7; }
      .follow-chip {
        border: 1px solid rgba(0, 0, 0, 0.18);
        border-radius: 999px;
        padding: 6px 14px;
        background: transparent;
        color: rgba(0, 0, 0, 0.75);
        font-size: 11px;
        font-weight: 900;
        letter-spacing: 0.12em;
        text-transform: uppercase;
        cursor: pointer;
      }
      .follow-chip.following {
        background: rgba(10, 12, 18, 0.06);
        color: rgba(10, 12, 18, 0.78);
        border-color: rgba(0, 0, 0, 0.12);
        box-shadow: none;
      }
      .follow-chip:disabled { opacity: 0.6; cursor: not-allowed; }
      .post-body { margin-top: 12px; font-size: 14px; line-height: 1.4; color: rgba(10, 12, 18, 0.85); }
      .post-shared { margin-top: 12px; }
      .shared-label {
        font-size: 11px;
        font-weight: 800;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: rgba(10, 12, 18, 0.55);
        margin-bottom: 6px;
      }
      .shared-card {
        border: 1px solid rgba(10, 12, 18, 0.08);
        border-radius: 14px;
        padding: 12px;
        background: #f5f7fb;
        cursor: pointer;
        transition: transform .2s ease, box-shadow .2s ease;
      }
      .shared-card:hover {
        transform: translateY(-1px);
        box-shadow: 0 10px 24px rgba(0, 0, 0, 0.12);
      }
      .shared-author { display: flex; gap: 10px; align-items: center; }
      .shared-avatar {
        width: 34px;
        height: 34px;
        border-radius: 50%;
        overflow: hidden;
        background: rgba(10, 12, 18, 0.1);
        display: grid;
        place-items: center;
        flex-shrink: 0;
      }
      .shared-avatar img { width: 100%; height: 100%; object-fit: cover; }
      .shared-initials { font-weight: 800; font-size: 12px; letter-spacing: .08em; }
      .shared-info { min-width: 0; }
      .shared-name { font-weight: 800; font-size: 13px; }
      .shared-meta { font-size: 11px; opacity: .7; }
      .shared-title { margin-top: 10px; font-weight: 800; font-size: 12px; letter-spacing: .06em; text-transform: uppercase; }
      .shared-body { margin-top: 6px; font-size: 13px; line-height: 1.4; color: rgba(10, 12, 18, 0.8); }
      .shared-media { margin-top: 10px; border-radius: 12px; overflow: hidden; background: #000; }
      .shared-media img { width: 100%; height: auto; display: block; }
      .shared-video {
        position: relative;
        display: grid;
        place-items: center;
        min-height: 120px;
        background: #0b0f18;
        color: #e6eefc;
        font-size: 12px;
        letter-spacing: .08em;
        text-transform: uppercase;
      }
      .shared-video img { width: 100%; height: auto; display: block; }
      .shared-video-tag {
        position: absolute;
        right: 8px;
        bottom: 8px;
        background: rgba(0, 0, 0, 0.65);
        color: #fff;
        padding: 4px 6px;
        border-radius: 8px;
        font-size: 10px;
        letter-spacing: .12em;
        text-transform: uppercase;
      }
      .post-text { display: inline; line-height: 1.4; margin: 0; }
      .post-text.clamped { display: inline; padding-bottom: 0; }
      .post-caption { margin-top: 10px; font-size: 13px; line-height: 1.45; color: rgba(10, 12, 18, 0.75); }
      .post-text .see-more.inline {
        margin-left: 6px;
        padding: 0;
        border: 0;
        background: transparent;
        font-size: 12px;
        font-weight: 800;
        letter-spacing: 0.02em;
        color: rgba(10, 12, 18, 0.6);
        text-decoration: underline;
        cursor: pointer;
        white-space: nowrap;
      }
      .post-media {
        margin-top: 12px;
        margin-left: calc(-1 * var(--post-pad-x));
        margin-right: calc(-1 * var(--post-pad-x));
        border-radius: 0;
        overflow: hidden;
        border: 1px solid rgba(0, 0, 0, 0.06);
        background: #fff;
        position: relative;
        width: calc(100% + (var(--post-pad-x) * 2));
      }
      .post-media img,
      .post-media video {
        width: 100%;
        display: block;
        height: auto;
        max-height: none;
        object-fit: contain;
        background: #000;
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
      .media-strip::-webkit-scrollbar { display: none; }
      .media-item {
        min-width: 100%;
        flex: 0 0 100%;
        scroll-snap-align: center;
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
      .media-dots span.active { background: #fff; }
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
      .post-title { font-weight: 900; margin-bottom: 6px; letter-spacing: 0.06em; text-transform: uppercase; font-size: 12px; }
      .post-visibility { font-weight: 800; font-size: 10px; letter-spacing: 0.16em; text-transform: uppercase; opacity: 0.7; }
      .post-actions {
        margin-top: 12px;
        display: flex;
        gap: 10px;
        align-items: center;
        flex-wrap: wrap;
      }
      .post-action-group {
        display: inline-flex;
        align-items: center;
        gap: 6px;
      }
      .post-action {
        display: flex;
        align-items: center;
        gap: 6px;
        border-radius: 999px;
        border: 1px solid rgba(0, 199, 255, 0.45);
        background: rgba(245, 247, 250, 0.92);
        padding: 6px 12px;
        font-size: 12px;
        font-weight: 800;
        letter-spacing: 0.06em;
        color: rgba(10, 12, 18, 0.7);
        cursor: pointer;
      }
      .post-action .icon { font-size: 14px; }
      .post-action .count { font-size: 11px; font-weight: 800; }
      .post-action.active {
        border-color: rgba(0, 199, 255, 0.7);
        background: rgba(0, 199, 255, 0.12);
        color: rgba(10, 12, 18, 0.75);
      }
      .post-action.like.active .icon { color: #c33; }
      .post-action.count {
        padding: 6px 10px;
        min-width: 36px;
        justify-content: center;
      }
      .post-action.share { padding: 6px 10px; }
      .post-share-feedback {
        font-size: 11px;
        font-weight: 800;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: rgba(10, 12, 18, 0.65);
      }
      .post-action:disabled { opacity: 0.6; cursor: not-allowed; }
      .post-action-error {
        margin-top: 6px;
        font-size: 11px;
        font-weight: 700;
        color: #c33;
        letter-spacing: 0.06em;
      }
      .post-comments {
        margin-top: 10px;
        padding-top: 10px;
        border-top: 1px solid rgba(0, 0, 0, 0.06);
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      .comment-status { font-size: 12px; opacity: 0.7; }
      .comment-status.error { color: #c33; }
      .comment-list { display: flex; flex-direction: column; gap: 10px; }
      .comment-empty { font-size: 12px; opacity: 0.6; }
      .comment {
        display: flex;
        gap: 10px;
        align-items: flex-start;
      }
      .comment-avatar {
        width: 30px;
        height: 30px;
        border-radius: 999px;
        overflow: hidden;
        background: rgba(245, 247, 250, 0.95);
        border: 1px solid rgba(0, 0, 0, 0.08);
        display: grid;
        place-items: center;
        font-weight: 900;
        font-size: 11px;
        color: rgba(10, 12, 18, 0.8);
      }
      .comment-avatar img { width: 100%; height: 100%; object-fit: cover; }
      .comment-body { flex: 1; min-width: 0; }
      .comment-meta { display: flex; gap: 8px; align-items: center; font-size: 11px; opacity: 0.65; }
      .comment-name { font-weight: 800; text-transform: uppercase; letter-spacing: 0.08em; }
      .comment-text { font-size: 12px; color: rgba(10, 12, 18, 0.85); margin-top: 2px; }
      .comment-actions {
        display: flex;
        gap: 10px;
        margin-top: 4px;
        font-size: 11px;
      }
      .comment-action {
        border: 0;
        background: transparent;
        padding: 0;
        color: rgba(10, 12, 18, 0.58);
        font-weight: 800;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        display: inline-flex;
        align-items: center;
        gap: 6px;
        cursor: pointer;
      }
      .comment-action.active { color: rgba(0, 155, 220, 0.88); }
      .comment-action:disabled { opacity: 0.5; cursor: not-allowed; }
      .comment-heart { font-size: 12px; line-height: 1; }
      .comment-heart.active { color: rgba(0, 155, 220, 0.95); }
      .comment-like-count { font-size: 11px; font-weight: 800; color: rgba(10, 12, 18, 0.75); }
      .comment-reply {
        display: flex;
        align-items: center;
        gap: 8px;
        font-size: 11px;
        font-weight: 800;
        letter-spacing: 0.06em;
        color: rgba(10, 12, 18, 0.6);
        text-transform: uppercase;
      }
      .comment-reply span { color: rgba(0, 155, 220, 0.85); }
      .comment-compose {
        display: flex;
        gap: 8px;
        align-items: center;
        flex-wrap: wrap;
      }
      .comment-input {
        flex: 1;
        min-width: 180px;
        border-radius: 12px;
        border: 1px solid rgba(0, 0, 0, 0.08);
        background: rgba(245, 247, 250, 0.9);
        padding: 8px 10px;
        font-family: inherit;
        font-size: 12px;
        color: rgba(10, 12, 18, 0.85);
      }
      .comment-submit {
        border-radius: 999px;
        border: 1px solid rgba(0, 0, 0, 0.12);
        background: rgba(255, 255, 255, 0.96);
        padding: 6px 12px;
        font-size: 11px;
        font-weight: 800;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: rgba(10, 12, 18, 0.7);
        cursor: pointer;
      }
      .post-likes {
        margin-top: 10px;
        padding-top: 10px;
        border-top: 1px solid rgba(0, 0, 0, 0.06);
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      .like-status { font-size: 12px; opacity: 0.7; }
      .like-status.error { color: #c33; }
      .like-list { display: flex; flex-direction: column; gap: 10px; }
      .like-empty { font-size: 12px; opacity: 0.6; }
      .like-row {
        display: flex;
        align-items: center;
        gap: 10px;
        border: 0;
        background: transparent;
        padding: 4px 0;
        text-align: left;
        cursor: pointer;
        color: inherit;
      }
      .like-avatar {
        width: 30px;
        height: 30px;
        border-radius: 999px;
        overflow: hidden;
        background: rgba(245, 247, 250, 0.95);
        border: 1px solid rgba(0, 0, 0, 0.08);
        display: grid;
        place-items: center;
        font-weight: 900;
        font-size: 11px;
        color: rgba(10, 12, 18, 0.8);
      }
      .like-avatar img { width: 100%; height: 100%; object-fit: cover; }
      .like-body { flex: 1; min-width: 0; }
      .like-name { font-weight: 800; text-transform: uppercase; letter-spacing: 0.08em; font-size: 11px; }
      .like-handle { font-size: 11px; opacity: 0.6; }
      .like-time { font-size: 11px; opacity: 0.55; }
      .comment-submit:disabled { opacity: 0.6; cursor: not-allowed; }
      .comment-hint { font-size: 12px; opacity: 0.6; }
    `,
  ],
})
export class SearchPageComponent implements OnInit, OnDestroy {
  searchTerm = '';
  searchBusy = false;
  searchError = '';
  countries: CountryModel[] = [];
  countryResults: CountryModel[] = [];
  peopleResults: Profile[] = [];
  postResults: CountryPost[] = [];
  lightboxUrl: string | null = null;

  meId: string | null = null;
  profile: Profile | null = null;

  likeOpen: Record<string, boolean> = {};
  likeItems: Record<string, PostLike[]> = {};
  likeLoading: Record<string, boolean> = {};
  likeErrors: Record<string, string> = {};
  likeBusy: Record<string, boolean> = {};

  commentOpen: Record<string, boolean> = {};
  commentItems: Record<string, PostComment[]> = {};
  commentLoading: Record<string, boolean> = {};
  commentErrors: Record<string, string> = {};
  commentBusy: Record<string, boolean> = {};
  commentLikeBusy: Record<string, Record<string, boolean>> = {};
  commentDrafts: Record<string, string> = {};
  commentReplyTarget: Record<string, { commentId: string; authorName: string } | null> = {};
  commentDisplay: Record<string, PostComment[]> = {};
  commentDepth: Record<string, Record<string, number>> = {};

  postActionError: Record<string, string> = {};
  postShareFeedback: Record<string, string> = {};
  postShareBusy: Record<string, boolean> = {};

  postMediaIndex: Record<string, number> = {};
  private mediaUrlsCache = new Map<string, string[]>();
  private mediaTypesCache = new Map<string, Array<'image' | 'video'>>();
  expandedPosts = new Set<string>();

  private followingIds = new Set<string>();
  private followBusyMap = new Map<string, boolean>();
  private readonly POST_TEXT_PREVIEW = 140;
  private searchSeq = 0;

  constructor(
    private router: Router,
    private route: ActivatedRoute,
    private countriesService: CountriesService,
    private searchService: SearchService,
    private auth: AuthService,
    private postsService: PostsService,
    private profiles: ProfileService,
    private followService: FollowService
  ) {}

  async ngOnInit(): Promise<void> {
    this.setAppBackground('feed');
    const user = await this.auth.getUser();
    this.meId = user?.id ?? null;
    try {
      const { meProfile } = await this.profiles.meProfile();
      this.profile = meProfile ?? null;
    } catch {
      this.profile = null;
    }
    void this.refreshFollowingSnapshot();
    await this.loadCountries();

    const q = String(this.route.snapshot.queryParamMap.get('q') || '').trim();
    if (q) {
      this.searchTerm = q;
      void this.runSearch(q);
    }
  }

  ngOnDestroy(): void {
    this.setAppBackground('light');
  }

  private setAppBackground(mode: 'feed' | 'light'): void {
    try {
      const root = document.documentElement;
      root.classList.remove('app-bg-globe', 'app-bg-feed', 'app-bg-light');
      const cls = mode === 'feed' ? 'app-bg-feed' : 'app-bg-light';
      root.classList.add(cls);
      const computed = getComputedStyle(root).getPropertyValue('--app-bg').trim();
      const bg = computed || (mode === 'feed' ? '#ffffff' : '#f5f6f8');
      document.body.style.backgroundColor = bg;
      document.documentElement.style.backgroundColor = bg;
      const themeMeta = document.querySelector('meta[name="theme-color"]') as HTMLMetaElement | null;
      if (themeMeta) {
        themeMeta.setAttribute('content', bg);
      }
    } catch {}
  }

  async loadCountries(): Promise<void> {
    try {
      const data = await this.countriesService.loadCountries();
      this.countries = data.countries ?? [];
    } catch {
      this.countries = [];
    }
  }

  onSearchInput(value: string): void {
    this.searchTerm = value;
    const term = String(value || '').trim();
    if (!term) {
      this.searchSeq++;
      this.searchBusy = false;
      this.searchError = '';
      this.countryResults = [];
      this.peopleResults = [];
      this.postResults = [];
      return;
    }
    void this.runSearch(term);
  }

  private async runSearch(term: string): Promise<void> {
    const seq = ++this.searchSeq;
    this.searchBusy = true;
    this.searchError = '';
    const normalized = this.searchService.normalizeName(term);
    this.countryResults = normalized
      ? this.countries.filter((c) => c.norm.includes(normalized)).slice(0, 12)
      : [];

    try {
      const [posts, people] = await Promise.all([
        this.postsService.searchPosts(term, 40),
        this.profiles.searchProfilesReal(term, 20),
      ]);
      if (seq !== this.searchSeq) return;
      this.postResults = posts ?? [];
      this.peopleResults = people.searchProfiles ?? [];
    } catch (e: any) {
      if (seq !== this.searchSeq) return;
      this.searchError = e?.message ?? 'Search failed.';
      this.postResults = [];
      this.peopleResults = [];
    } finally {
      if (seq === this.searchSeq) {
        this.searchBusy = false;
      }
    }
  }

  goHome(): void {
    void this.router.navigate(['/globe']);
  }

  focusCountry(country: CountryModel): void {
    if (!country) return;
    const code = country.code || String(country.id);
    void this.router.navigate(['/globe'], {
      queryParams: { country: code, tab: 'posts', panel: null },
    });
  }

  openPost(post: CountryPost, event?: Event): void {
    if (!post?.id) return;
    const target = event?.target as HTMLElement | null;
    if (target && (target.closest('button') || target.closest('input') || target.closest('textarea'))) {
      return;
    }
    void this.router.navigate(['/globe'], {
      queryParams: { post: post.id, tab: 'posts', panel: null },
    });
  }

  openUserProfile(profile: Profile): void {
    if (!profile) return;
    const slug = profile.username?.trim() || profile.user_id;
    if (!slug) return;
    void this.router.navigate(['/user', slug]);
  }

  openAuthorProfile(author: CountryPost['author'] | null | undefined, fallbackId?: string | null): void {
    const slug = fallbackId || author?.user_id || author?.username?.trim();
    if (!slug) return;
    void this.router.navigate(['/user', slug]);
  }

  visibilityLabel(value: string): string {
    const normalized = String(value || '').toLowerCase();
    if (normalized === 'private') return 'Only me';
    if (normalized === 'followers') return 'Followers';
    return 'Public';
  }

  normalizeAvatarUrl(url: string | null | undefined): string {
    const raw = String(url || '').trim();
    if (!raw) return '';
    if (/^https?:\/\//i.test(raw) || raw.startsWith('data:') || raw.startsWith('blob:') || raw.startsWith('/')) {
      return raw;
    }
    if (raw.includes('/storage/v1/object/')) return raw;
    const normalized = raw.replace(/^\/+/, '');
    return `${SUPABASE_URL}/storage/v1/object/public/avatars/${normalized}`;
  }

  isAuthorSelf(authorId?: string | null): boolean {
    return !!authorId && this.meId === authorId;
  }

  isFollowingAuthor(authorId?: string | null): boolean {
    return !!authorId && this.followingIds.has(authorId);
  }

  followBusyFor(authorId: string): boolean {
    return this.followBusyMap.get(authorId) === true;
  }

  async toggleFollowAuthor(authorId: string | null | undefined): Promise<void> {
    if (!this.meId || !authorId || this.meId === authorId) return;
    if (this.followBusyFor(authorId)) return;

    this.followBusyMap.set(authorId, true);
    try {
      if (this.followingIds.has(authorId)) {
        await this.followService.unfollow(this.meId, authorId);
        this.followingIds.delete(authorId);
      } else {
        await this.followService.follow(this.meId, authorId);
        this.followingIds.add(authorId);
      }
    } catch {}
    this.followBusyMap.delete(authorId);
  }

  private async refreshFollowingSnapshot(): Promise<void> {
    if (!this.meId) {
      this.followingIds.clear();
      return;
    }
    try {
      const ids = await this.followService.listFollowingIds(this.meId);
      this.followingIds = new Set(ids);
    } catch {
      this.followingIds.clear();
    }
  }

  trackPostById(index: number, post: CountryPost): string {
    return post?.id ?? String(index);
  }

  postHasVideo(post: CountryPost): boolean {
    if (!post) return false;
    if (String(post.media_type || '').toLowerCase() === 'video') return true;
    const types = this.postMediaTypes(post);
    return types.includes('video');
  }

  postCaptionText(post: CountryPost): string {
    if (!post) return '';
    const caption = String(post.media_caption || '').trim();
    if (caption) return caption;
    if (this.postHasVideo(post)) {
      return String(post.body || '').trim();
    }
    return '';
  }

  postMediaUrls(post: CountryPost): string[] {
    const raw = String(post?.media_url || '').trim();
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

  postMediaTypes(post: CountryPost): Array<'image' | 'video'> {
    const raw = String(post?.media_url || '').trim();
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

  private inferMediaTypeFromUrl(url: string, fallback: string | null | undefined): 'image' | 'video' {
    const lower = String(url || '').toLowerCase();
    if (/\.(mp4|webm|mov|m4v|avi|mkv)(\?|#|$)/.test(lower)) return 'video';
    if (/\.(jpg|jpeg|png|gif|webp|avif)(\?|#|$)/.test(lower)) return 'image';
    return String(fallback || '').toLowerCase() === 'video' ? 'video' : 'image';
  }

  postIsReel(post: CountryPost): boolean {
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

  postMediaIndexValue(post: CountryPost): number {
    return this.postMediaIndex[post.id] ?? 0;
  }

  onPostMediaScroll(post: CountryPost, event: Event): void {
    const target = event?.target as HTMLElement | null;
    if (!target) return;
    const width = target.clientWidth || 1;
    const max = Math.max(0, target.children.length - 1);
    const idx = Math.round(target.scrollLeft / width);
    this.postMediaIndex[post.id] = Math.min(Math.max(idx, 0), max);
  }

  onPostVideoTap(post: CountryPost): void {
    if (this.postIsReel(post)) {
      this.openReels(post);
    }
  }

  openReels(post: CountryPost): void {
    if (!post) return;
    const code = post.country_code?.toUpperCase() || post.author?.country_code?.toUpperCase();
    if (!code) return;
    void this.router.navigate(['/reels', code], {
      queryParams: { postId: post.id },
      state: {
        seedPosts: [post],
        seedCountry: code,
        countryName: post.country_name || null,
      },
    });
  }

  recordView(post: CountryPost): void {
    if (!post?.id) return;
    void this.postsService.recordView(post);
  }

  isPostExpanded(postId: string): boolean {
    return this.expandedPosts.has(postId);
  }

  isTextExpandable(text: string | null | undefined): boolean {
    const value = String(text || '').replace(/\s+/g, ' ').trim();
    if (!value) return false;
    return value.length > this.getPostPreviewLimit();
  }

  postPreview(text: string | null | undefined): string {
    const value = String(text || '').replace(/\s+/g, ' ').trim();
    if (!value) return '';
    const limit = this.getPostPreviewLimit();
    if (value.length <= limit) return value;
    const slice = value.slice(0, limit);
    const lastSpace = slice.lastIndexOf(' ');
    return (lastSpace > 40 ? slice.slice(0, lastSpace) : slice).trim();
  }

  togglePostExpanded(postId: string, event?: Event): void {
    if (event) {
      event.stopPropagation();
      event.preventDefault();
    }
    if (!postId) return;
    if (this.expandedPosts.has(postId)) {
      this.expandedPosts.delete(postId);
    } else {
      this.expandedPosts.add(postId);
    }
  }

  onPostTextClick(postId: string, event: Event): void {
    if (!this.expandedPosts.has(postId)) return;
    const target = event.target as HTMLElement | null;
    if (target?.closest('button')) return;
    event.stopPropagation();
    this.expandedPosts.delete(postId);
  }

  private getPostPreviewLimit(): number {
    if (typeof window === 'undefined') return this.POST_TEXT_PREVIEW;
    const width = window.innerWidth || 0;
    if (width < 480) return 60;
    if (width < 720) return 80;
    if (width < 1024) return 105;
    return this.POST_TEXT_PREVIEW;
  }

  openImageLightbox(url: string | null): void {
    const next = String(url || '').trim();
    if (!next) return;
    this.lightboxUrl = next;
  }

  closeImageLightbox(): void {
    if (!this.lightboxUrl) return;
    this.lightboxUrl = null;
  }

  async togglePostLike(post: CountryPost): Promise<void> {
    if (!this.meId || !post?.id) {
      this.postActionError[post.id] = 'Sign in to like posts.';
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
      if (this.likeOpen[post.id]) {
        void this.loadLikes(post.id);
      }
    } catch (e: any) {
      this.postActionError[post.id] = e?.message ?? String(e);
    } finally {
      this.likeBusy[post.id] = false;
    }
  }

  toggleLikes(postId: string): void {
    if (!postId) return;
    const next = !this.likeOpen[postId];
    this.likeOpen[postId] = next;
    if (next && !this.likeItems[postId] && !this.likeLoading[postId]) {
      void this.loadLikes(postId);
    }
  }

  private async loadLikes(postId: string): Promise<void> {
    if (!postId) return;
    this.likeLoading[postId] = true;
    this.likeErrors[postId] = '';

    try {
      const likes = await this.postsService.listLikes(postId, 40);
      this.likeItems[postId] = likes;
    } catch (e: any) {
      this.likeErrors[postId] = e?.message ?? String(e);
    } finally {
      this.likeLoading[postId] = false;
    }
  }

  toggleComments(postId: string): void {
    if (!postId) return;
    const next = !this.commentOpen[postId];
    this.commentOpen[postId] = next;
    if (next && !this.commentItems[postId] && !this.commentLoading[postId]) {
      void this.loadComments(postId);
    }
    if (!next) {
      this.commentReplyTarget[postId] = null;
    }
  }

  private async loadComments(postId: string): Promise<void> {
    if (!postId) return;
    this.commentLoading[postId] = true;
    this.commentErrors[postId] = '';

    try {
      const comments = await this.postsService.listComments(postId, 40);
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

  startCommentReply(postId: string, comment: PostComment): void {
    if (!postId || !comment?.id) return;
    this.commentReplyTarget[postId] = {
      commentId: comment.id,
      authorName: this.commentAuthorName(comment),
    };
  }

  cancelCommentReply(postId: string): void {
    if (!postId) return;
    this.commentReplyTarget[postId] = null;
  }

  async toggleCommentLike(postId: string, comment: PostComment): Promise<void> {
    if (!postId || !comment?.id) return;
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
        ...perPost,
        [comment.id]: false,
      };
    }
  }

  async submitComment(post: CountryPost): Promise<void> {
    if (!post?.id) return;
    if (!this.meId) {
      this.commentErrors[post.id] = 'Sign in to comment.';
      return;
    }

    const draft = (this.commentDrafts[post.id] ?? '').trim();
    if (!draft) {
      this.commentErrors[post.id] = 'Write something before commenting.';
      return;
    }

    if (this.commentBusy[post.id]) return;
    this.commentBusy[post.id] = true;
    this.commentErrors[post.id] = '';

    try {
      const parentId = this.commentReplyTarget[post.id]?.commentId ?? null;
      const comment = await this.postsService.addComment(post.id, draft, parentId);
      this.applyCommentUpdate(post.id, comment);
      this.commentDrafts[post.id] = '';
      this.commentReplyTarget[post.id] = null;
      const updated = { ...post, comment_count: post.comment_count + 1 };
      this.applyPostUpdate(updated);
    } catch (e: any) {
      this.commentErrors[post.id] = e?.message ?? String(e);
    } finally {
      this.commentBusy[post.id] = false;
    }
  }

  async sharePostToCountry(post: CountryPost, event?: Event): Promise<void> {
    event?.stopPropagation?.();
    if (!post?.id) return;
    if (!this.profile || !this.meId) {
      this.postShareFeedback[post.id] = 'Sign in to share';
      return;
    }
    const countryCode = String(this.profile.country_code || '').trim();
    const countryName = String(this.profile.country_name || '').trim();
    if (!countryCode || !countryName) {
      this.postShareFeedback[post.id] = 'Set your country to share';
      return;
    }
    if (this.postShareBusy[post.id]) return;
    this.postShareBusy[post.id] = true;
    const originalId = post.shared_post_id || post.id;
    try {
      await this.postsService.createPost({
        authorId: this.meId,
        title: null,
        body: '',
        countryName,
        countryCode,
        cityName: this.profile.city_name ?? null,
        visibility: 'country',
        mediaType: 'none',
        mediaUrl: null,
        thumbUrl: null,
        sharedPostId: originalId,
      });
      this.postShareFeedback[post.id] = 'Shared to your country';
    } catch (e: any) {
      this.postShareFeedback[post.id] = e?.message ?? 'Share failed';
    } finally {
      delete this.postShareBusy[post.id];
      window.setTimeout(() => {
        if (this.postShareFeedback[post.id]) {
          delete this.postShareFeedback[post.id];
        }
      }, 1800);
    }
  }

  openSharedPost(post: CountryPost, event?: Event): void {
    event?.stopPropagation?.();
    if (!post?.id) return;
    const targetId = post.shared_post_id || post.id;
    void this.router.navigate(['/globe'], {
      queryParams: { post: targetId, tab: 'posts', panel: null },
    });
  }

  private applyPostUpdate(post: CountryPost): void {
    if (!post?.id) return;
    const next = [...this.postResults];
    const idx = next.findIndex((item) => item.id === post.id);
    if (idx >= 0) {
      next[idx] = { ...next[idx], ...post };
      this.postResults = next;
    }
  }
}
