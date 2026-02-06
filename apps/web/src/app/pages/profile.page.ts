import {
  Component,
  ChangeDetectorRef,
  ElementRef,
  NgZone,
  OnDestroy,
  OnInit,
  ViewChild,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { Subscription } from 'rxjs';

import { ProfileService, type Profile } from '../core/services/profile.service';
import { AuthService } from '../core/services/auth.service';
import { MediaService } from '../core/services/media.service';
import { VideoPlayerComponent } from '../components/video-player.component';
import { PostsService } from '../core/services/posts.service';
import { PresenceService } from '../core/services/presence.service';
import {
  PostEventsService,
  type PostUpdateEvent,
  type PostDeleteEvent,
} from '../core/services/post-events.service';
import { CountryPost, PostComment, PostLike } from '../core/models/post.model';
import { FollowService } from '../core/services/follow.service';
import { LocationService } from '../core/services/location.service';
import { MessagesService } from '../core/services/messages.service';
import { SUPABASE_URL } from '../config/supabase.config';

@Component({
  selector: 'app-profile-page',
  standalone: true,
  imports: [CommonModule, FormsModule, VideoPlayerComponent],
  template: `
    <div class="wrap">
      <div class="card" *ngIf="!loading && !error && profile; else stateTpl">
        <div class="head">
          <div class="head-actions">
            <button class="ghost-link back-link" type="button" (click)="goBack()">Back</button>
          </div>
            <div class="avatar-block" (click)="openAvatarModal()">
              <div class="avatar">
                <img
                  *ngIf="avatarImage"
                  [src]="avatarImage"
                alt="avatar"
                [style.transform]="avatarTransform"
                class="img"
              />
              <div class="init" *ngIf="!avatarImage">{{ initials }}</div>
              <span class="ring"></span>
            </div>
            <div class="avatar-actions" *ngIf="isOwner">
              <button
                type="button"
                class="micro-btn"
                (click)="triggerAvatarUpload($event)"
              >
                Upload
              </button>
              <button
                type="button"
                class="micro-btn outline"
                (click)="saveAvatar()"
                [disabled]="avatarSaving || !draftAvatarUploadUrl"
              >
                {{ avatarSaving ? 'Saving…' : 'Save' }}
              </button>
              <span class="hint" *ngIf="avatarUploading && !draftAvatarUploadUrl">Uploading...</span>
              <span class="hint" *ngIf="!avatarUploading && draftAvatarUrl && !draftAvatarUploadUrl">Selected?</span>
              <small class="hint error" *ngIf="avatarError">{{ avatarError }}</small>
            </div>
          </div>

          <div class="info">
            <div class="title-row" *ngIf="!editingName">
              <div class="title">{{ profile!.display_name || profile!.username || 'User' }}</div>
              <span
                class="presence-dot"
                [class.online]="profileOnline"
                [class.offline]="!profileOnline"
                aria-hidden="true"
              ></span>
            <div class="title-actions">
                <button class="micro-btn" *ngIf="isOwner && profileEditMode" type="button" (click)="startNameEdit()">Refine name</button>
                <button
                  class="micro-btn outline edit-profile-toggle"
                  *ngIf="isOwner"
                  type="button"
                  (click)="onProfileEditAction()"
                  [disabled]="profileEditSaving"
                >
                  <ng-container *ngIf="!profileEditMode">
                    Edit profile
                  </ng-container>
                    <ng-container *ngIf="profileEditMode">
                      <span *ngIf="!profileEditSaved">Save</span>
                      <span *ngIf="profileEditSaved" class="saved-check" aria-live="polite">
                        <span aria-hidden="true">✓</span>
                        <span aria-hidden="true" class="check-arrow">↗</span>
                        Saved
                      </span>
                    </ng-container>
                </button>
              </div>
              <button
                class="share-icon bare share-emoji"
                type="button"
                (click)="copyShareLink()"
                [disabled]="!shareUrl"
                aria-label="Copy profile link"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 -960 960 960"
                  role="img"
                  aria-hidden="true"
                  focusable="false"
                >
                  <path
                    fill="#e3e3e3"
                    d="M680-80q-50 0-85-35t-35-85q0-6 3-28L282-392q-16 15-37 23.5t-45 8.5q-50 0-85-35t-35-85q0-50 35-85t85-35q24 0 45 8.5t37 23.5l281-164q-2-7-2.5-13.5T560-760q0-50 35-85t85-35q50 0 85 35t35 85q0 50-35 85t-85 35q-24 0-45-8.5T598-672L317-508q2 7 2.5 13.5t.5 14.5q0 8-.5 14.5T317-452l281 164q16-15 37-23.5t45-8.5q50 0 85 35t35 85q0 50-35 85t-85 35Zm0-80q17 0 28.5-11.5T720-200q0-17-11.5-28.5T680-240q-17 0-28.5 11.5T640-200q0 17 11.5 28.5T680-160ZM200-440q17 0 28.5-11.5T240-480q0-17-11.5-28.5T200-520q-17 0-28.5 11.5T160-480q0 17 11.5 28.5T200-440Zm480-280q17 0 28.5-11.5T720-760q0-17-11.5-28.5T680-800q-17 0-28.5 11.5T640-760q0 17 11.5 28.5T680-720Zm0 520ZM200-480Zm480-280Z"
                  />
                </svg>
              </button>
            </div>
            <div class="share-feedback" [class.error]="!!shareError" *ngIf="shareCopied || shareError">
              {{ shareError || (shareCopied ? 'Link copied' : '') }}
            </div>

            <div class="edit-row" *ngIf="editingName">
              <input
                class="text-input"
                [(ngModel)]="draftDisplayName"
                maxlength="80"
                placeholder="Display name"
              />
              <div class="edit-actions">
                <button class="btn" type="button" (click)="saveDisplayName()" [disabled]="nameSaving">
                  {{ nameSaving ? 'Saving…' : 'Save' }}
                </button>
                <button class="ghost-link" type="button" (click)="cancelNameEdit()">Cancel</button>
              </div>
            </div>

              <div class="handle-row" *ngIf="!editingUsername">
                <div class="sub handle">
                  @{{ profile!.username || 'username pending' }}
                </div>
                <button
                  class="micro-btn"
                  type="button"
                  *ngIf="isOwner && profileEditMode"
                  (click)="startUsernameEdit()"
                >
                  {{ profile!.username ? 'Edit handle' : 'Set handle' }}
                </button>
              </div>

            <div class="social-row" *ngIf="profile">
              <div class="stat-card">
                <div class="stat-value">
                  {{ followMetaLoading && followersCount === null ? '…' : followersCount ?? '—' }}
                </div>
                <div class="stat-label">Followers</div>
              </div>
              <div class="stat-card">
                <div class="stat-value">
                  {{ followMetaLoading && followingCount === null ? '…' : followingCount ?? '—' }}
                </div>
                <div class="stat-label">Following</div>
              </div>
              <div class="follow-cta" *ngIf="!isOwner">
                <button
                  class="follow-btn"
                  type="button"
                  [class.following]="viewerFollowing"
                  [disabled]="followBusy || followMetaLoading"
                  (click)="toggleFollow()"
                >
                  <span *ngIf="followMetaLoading && !viewerFollowing">Loading</span>
                  <ng-container *ngIf="!followMetaLoading || viewerFollowing">
                    {{ viewerFollowing ? 'Following' : 'Follow' }}
                  </ng-container>
                </button>
                <button
                  class="message-btn"
                  type="button"
                  [disabled]="messageBusy"
                  (click)="startConversation()"
                >
                  {{ messageBusy ? 'Opening...' : 'Message' }}
                </button>
                <small class="hint error" *ngIf="followError">{{ followError }}</small>
                <small class="hint error" *ngIf="messageError">{{ messageError }}</small>
              </div>
            </div>

            <div class="edit-row" *ngIf="editingUsername">
              <input
                class="text-input"
                [(ngModel)]="draftUsername"
                (ngModelChange)="onUsernameDraftChange()"
                maxlength="24"
                placeholder="username"
                autocapitalize="off"
                autocomplete="off"
                spellcheck="false"
              />
              <small class="hint">
                Use 3-24 letters, numbers, dots, or underscores. No spaces.
              </small>
              <div class="edit-actions">
                <button class="btn" type="button" (click)="saveUsername()" [disabled]="usernameSaving">
                  {{ usernameSaving ? 'Saving...' : 'Save handle' }}
                </button>
                <button class="ghost-link" type="button" (click)="cancelUsernameEdit()">Cancel</button>
                <small class="hint error" *ngIf="usernameError">{{ usernameError }}</small>
              </div>
            </div>

            <div class="meta">
              <span *ngIf="profile!.country_name">{{ profile!.country_name }}</span>
              <span *ngIf="profile!.city_name">• {{ profile!.city_name }}</span>
            </div>

            <div class="bio" *ngIf="!editingBio">
              <div>{{ bio || 'No bio yet.' }}</div>
              <button class="micro-btn" *ngIf="isOwner && profileEditMode" type="button" (click)="startBioEdit()">Refine bio</button>
            </div>

            <div class="edit-row" *ngIf="editingBio">
              <textarea
                class="text-input textarea"
                [(ngModel)]="draftBio"
                maxlength="160"
                placeholder="Tell the world about you"
              ></textarea>
              <div class="edit-actions">
                <button class="btn" type="button" (click)="saveBio()" [disabled]="bioSaving">
                  {{ bioSaving ? 'Saving…' : 'Save bio' }}
                </button>
                <button class="ghost-link" type="button" (click)="cancelBioEdit()">Cancel</button>
              </div>
            </div>
          </div>
        </div>

        <div class="composer profile-composer" *ngIf="canPostFromProfile">
          <div class="composer-row">
            <div class="composer-avatar">
              <img
                *ngIf="avatarImage"
                [src]="avatarImage"
                alt="avatar"
              />
              <div class="composer-initials" *ngIf="!avatarImage">{{ initials }}</div>
            </div>
            <div class="composer-main">
              <div class="composer-top">
                <div>
                  <div class="composer-title">Share with {{ profile!.country_name }}</div>
                  <div class="composer-hint">Posts appear in {{ profile!.country_name }}'s live feed.</div>
                </div>
                <div class="composer-cta">
                  <button
                    class="pill-link ghost"
                    type="button"
                    *ngIf="profileComposerOpen"
                    (click)="profileComposerOpen = false; clearProfileMedia()"
                  >
                    Cancel
                  </button>
                </div>
              </div>
              <button
                class="composer-trigger"
                type="button"
                *ngIf="!profileComposerOpen"
                (click)="profileComposerOpen = true"
              >
                What's new in {{ profile!.country_name }}?
              </button>
              <ng-container *ngIf="profileComposerOpen">
                <input
                  class="composer-input"
                  [(ngModel)]="postTitle"
                  maxlength="120"
                  placeholder="Add a headline (optional)"
                />
                <textarea
                  class="composer-textarea"
                  rows="3"
                  maxlength="5000"
                  placeholder="Tell {{ profile!.country_name }} what's happening..."
                  [(ngModel)]="postBody"
                ></textarea>
                <div class="composer-media">
                  <input
                    #profileMediaInput
                    type="file"
                    accept="image/*,video/*"
                    (change)="onProfileMediaSelect($event)"
                    style="display:none;"
                  />
                  <button
                    class="pill-link ghost"
                    type="button"
                    (click)="profileMediaInput.click()"
                  >
                    Add media
                  </button>
                  <button
                    class="pill-link ghost"
                    type="button"
                    *ngIf="postMediaFile"
                    (click)="clearProfileMedia()"
                  >
                    Remove
                  </button>
                  <span class="composer-media-name" *ngIf="postMediaFile">
                    {{ postMediaFile.name }}
                  </span>
                </div>
                <div class="composer-media-error" *ngIf="postMediaError">
                  {{ postMediaError }}
                </div>
                <div class="composer-media-preview" *ngIf="postMediaPreview">
                  <img
                    *ngIf="postMediaType === 'image'"
                    [src]="postMediaPreview"
                    alt="media preview"
                  />
                  <video
                    *ngIf="postMediaType === 'video'"
                    [src]="postMediaPreview"
                    controls
                  ></video>
                </div>
              </ng-container>
            </div>
          </div>

          <div class="composer-actions" *ngIf="profileComposerOpen">
            <button class="btn" type="button" (click)="submitProfilePost()" [disabled]="postBusy || !canPostFromProfile">
              {{ postBusy ? 'Posting…' : ('Post to ' + profile!.country_name) }}
            </button>
            <div class="composer-status" [class.error]="!!postError" *ngIf="postError || postFeedback">
              {{ postError || postFeedback }}
            </div>
          </div>
        </div>

        <div class="composer-posts">
          <div class="sec-title">Posts</div>
          <div class="post-status" *ngIf="loadingProfilePosts">Loading posts…</div>
          <div class="post-status error" *ngIf="!loadingProfilePosts && profilePostsError">
            {{ profilePostsError }}
          </div>
          <div class="post-status" *ngIf="!loadingProfilePosts && !profilePosts.length && !profilePostsError">
            No posts yet.
          </div>
          <div class="post-list" *ngIf="!loadingProfilePosts && profilePosts.length">
            <article
              class="post-card"
              [class.media]="!!post.media_url && post.media_type !== 'none'"
              *ngFor="let post of profilePosts; trackBy: trackProfilePostById"
            >
              <div class="post-author">
                <div class="author-core">
                  <div class="author-avatar">
                    <img
                      *ngIf="post.author?.avatar_url"
                      [src]="post.author?.avatar_url"
                      alt="avatar"
                    />
                    <div class="author-initials" *ngIf="!post.author?.avatar_url">
                      {{ (post.author?.display_name || post.author?.username || profile.display_name || 'You').slice(0, 2).toUpperCase() }}
                    </div>
                  </div>
                  <div class="author-info">
                    <div class="author-name">{{ post.author?.display_name || post.author?.username || 'You' }}</div>
                    <div class="author-meta">
                      @{{ post.author?.username || 'user' }} · {{ post.created_at | date: 'mediumDate' }}
                      <span class="post-visibility" *ngIf="post.visibility !== 'public' && post.visibility !== 'country'">
                        · {{ visibilityLabel(post.visibility) }}
                      </span>
                    </div>
                  </div>
                </div>
                <div
                  class="post-menu"
                  *ngIf="editingPostId !== post.id"
                  (click)="$event.stopPropagation()"
                >
                  <span class="post-visibility-icon">{{ visibilityIcon(post.visibility) }}</span>
                  <button
                    class="post-menu-trigger"
                    type="button"
                    (click)="togglePostMenu(post.id, $event)"
                    aria-label="Post options"
                  >
                    ⋯
                  </button>
                  <div class="post-menu-dropdown" *ngIf="openPostMenuId === post.id">
                    <ng-container *ngIf="isOwner; else reportMenu">
                      <button class="menu-item" type="button" (click)="startPostEdit(post)">Edit</button>
                      <button class="menu-item" type="button" (click)="startPostEdit(post)">Privacy</button>
                      <button class="menu-item danger" type="button" (click)="requestPostDelete(post)">Delete</button>
                      <div class="menu-confirm" *ngIf="confirmDeletePostId === post.id">
                        <div class="menu-confirm-title">Delete this post?</div>
                        <div class="menu-confirm-actions">
                          <button class="menu-item ghost" type="button" (click)="cancelPostDelete()">Cancel</button>
                          <button class="menu-item danger" type="button" (click)="deletePost(post)">Delete</button>
                        </div>
                      </div>
                    </ng-container>
                    <ng-template #reportMenu>
                      <button class="menu-item" type="button" (click)="toggleReport(post.id)">Report</button>
                      <div class="menu-report" *ngIf="reportingPostId === post.id">
                        <textarea
                          class="menu-report-input"
                          rows="2"
                          maxlength="2000"
                          placeholder="Tell us what is wrong"
                          [(ngModel)]="reportReason"
                        ></textarea>
                        <div class="menu-confirm-actions">
                          <button class="menu-item ghost" type="button" (click)="cancelReport()">Cancel</button>
                          <button class="menu-item danger" type="button" (click)="submitReport(post)" [disabled]="reportBusy">
                            {{ reportBusy ? 'Sending...' : 'Send report' }}
                          </button>
                        </div>
                        <div class="menu-report-error" *ngIf="reportError">{{ reportError }}</div>
                        <div class="menu-report-success" *ngIf="reportFeedback">{{ reportFeedback }}</div>
                      </div>
                    </ng-template>
                  </div>
                </div>
              </div>
              <div class="post-body" *ngIf="editingPostId !== post.id">
                <div class="post-title" *ngIf="post.title">{{ post.title }}</div>
                <p class="post-text" [class.clamped]="!isPostExpanded(post.id) && isPostExpandable(post)">{{ post.body }}</p>
              </div>
              <div class="post-caption post-text" [class.clamped]="!isPostExpanded(post.id) && isPostExpandable(post)" *ngIf="editingPostId !== post.id && post.media_caption">
                {{ post.media_caption }}
              </div>
              <button
                class="see-more"
                type="button"
                *ngIf="editingPostId !== post.id && isPostExpandable(post)"
                (click)="togglePostExpanded(post.id)"
              >
                {{ isPostExpanded(post.id) ? 'See less' : 'See more' }}
              </button>
              <div class="post-media" *ngIf="editingPostId !== post.id && post.media_url && post.media_type !== 'none'">
                <img
                  *ngIf="post.media_type === 'image'"
                  class="zoomable"
                  [src]="post.media_url"
                  alt="post media"
                  (click)="openImageLightbox(post.media_url)"
                />
                <app-video-player
                  *ngIf="post.media_type === 'video'"
                  [src]="post.media_url"
                  tapBehavior="emit"
                  (viewed)="recordView(post)"
                  (videoTap)="openReels(post)"
                  ></app-video-player>
              </div>
              <div class="post-actions" *ngIf="editingPostId !== post.id">
                <div class="post-action-group">
                  <button
                    class="post-action like"
                    type="button"
                    [class.active]="post.liked_by_me"
                    [disabled]="likeBusy[post.id]"
                    (click)="togglePostLike(post)"
                  >
                    <span class="icon">{{ post.liked_by_me ? '\u2665' : '\u2661' }}</span>
                  </button>
                  <button
                    class="post-action count"
                    type="button"
                    [class.active]="likeOpen[post.id]"
                    (click)="toggleLikes(post.id)"
                  >
                    <span class="count">{{ post.like_count }}</span>
                  </button>
                </div>
                <button
                  class="post-action comment"
                  type="button"
                  [class.active]="commentOpen[post.id]"
                  (click)="toggleComments(post.id)"
                >
                  <span class="icon">{{ '\u{1F4AC}' }}</span>
                  <span class="count">{{ post.comment_count }}</span>
                </button>
                <div class="post-action view" aria-label="Views">
                  <span class="icon">{{ '\u{1F441}' }}</span>
                  <span class="count">{{ post.view_count }}</span>
                </div>
              </div>
              <div class="post-action-error" *ngIf="postActionError[post.id]">
                {{ postActionError[post.id] }}
              </div>
              <div class="post-likes" *ngIf="likeOpen[post.id] && editingPostId !== post.id">
                <div class="like-status" *ngIf="likeLoading[post.id]">Loading likes...</div>
                <div class="like-status error" *ngIf="likeErrors[post.id]">{{ likeErrors[post.id] }}</div>
                <div class="like-list" *ngIf="!likeLoading[post.id] && !likeErrors[post.id]">
                  <div class="like-empty" *ngIf="!(likeItems[post.id]?.length)">No likes yet.</div>
                  <button
                    class="like-row"
                    type="button"
                    *ngFor="let like of likeItems[post.id]"
                    (click)="openUserProfile(like.user)"
                  >
                    <div class="like-avatar">
                      <img
                        *ngIf="like.user?.avatar_url"
                        [src]="like.user?.avatar_url"
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
              <div class="post-comments" *ngIf="commentOpen[post.id] && editingPostId !== post.id">
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
                        [src]="comment.author?.avatar_url"
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
                          (click)="startCommentReply(post.id, comment)"
                          [disabled]="commentBusy[post.id]"
                        >
                          Reply
                        </button>
                        <button
                          class="comment-action"
                          type="button"
                          (click)="toggleCommentLike(post.id, comment)"
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
                    <button type="button" class="ghost-link" (click)="cancelCommentReply(post.id)">Cancel</button>
                  </div>
                  <input
                    class="comment-input"
                    placeholder="Write a comment"
                    [disabled]="commentBusy[post.id]"
                    [(ngModel)]="commentDrafts[post.id]"
                  />
                  <button
                    class="comment-submit"
                    type="button"
                    [disabled]="commentBusy[post.id]"
                    (click)="submitComment(post)"
                  >
                    {{ commentBusy[post.id] ? 'Sending...' : 'Comment' }}
                  </button>
                </div>
                <ng-template #commentSignIn>
                  <div class="comment-hint">Sign in to comment.</div>
                </ng-template>
              </div>
              <div class="post-edit" *ngIf="editingPostId === post.id">
                <input
                  class="post-edit-title"
                  placeholder="Edit title"
                  [(ngModel)]="editPostTitle"
                />
                <textarea
                  class="post-edit-body"
                  rows="3"
                  maxlength="5000"
                  [(ngModel)]="editPostBody"
                ></textarea>
                <div class="post-edit-footer">
                  <select class="post-edit-visibility" [(ngModel)]="editPostVisibility">
                    <option value="public">Public</option>
                    <option value="followers">Only followers</option>
                    <option value="private">Only me</option>
                  </select>
                  <div class="post-edit-actions">
                    <button class="pill-link ghost" type="button" (click)="cancelPostEdit()" [disabled]="postEditBusy">Cancel</button>
                    <button class="pill-link" type="button" (click)="savePostEdit(post)" [disabled]="postEditBusy">
                      {{ postEditBusy ? 'Saving…' : 'Save' }}
                    </button>
                  </div>
                </div>
                <div class="post-edit-error" *ngIf="postEditError">{{ postEditError }}</div>
              </div>
            </article>
          </div>
        </div>

        <div class="avatar-editor" *ngIf="editingAvatar">
          <div class="editor-head">
            <div>
              <div class="sec-title">Avatar</div>
              <small>Upload a square image (PNG/JPG/WebP). Drag to position inside the circle.</small>
            </div>
            <button class="btn-file" type="button" (click)="avatarInput.click()">Choose image</button>
          </div>

          <div class="editor-preview">
            <div
              class="avatar large"
              (pointerdown)="onAvatarDragStart($event)"
              [class.adjusting]="true"
              *ngIf="draftAvatarUrl"
            >
              <img
                class="img"
                [src]="draftAvatarUrl"
                alt="preview"
                [style.transform]="draftAvatarTransform"
              />
              <span class="ring"></span>
            </div>
            <div class="muted" *ngIf="!draftAvatarUrl">Choose an image to begin.</div>
          </div>

          <div class="edit-actions">
              <span class="hint" *ngIf="avatarUploading && !draftAvatarUploadUrl">Uploading...</span>
              <button class="ghost-link" type="button" (click)="cancelAvatarEdit()">Cancel</button>
              <small class="hint error" *ngIf="avatarError">{{ avatarError }}</small>
            </div>
          </div>
      </div>

      <ng-template #stateTpl>
        <div class="card state">
          <div *ngIf="loading">Loading profile…</div>
          <div *ngIf="!loading">{{ error || 'Profile not found.' }}</div>
        </div>
      </ng-template>
    </div>

    <input
      #avatarInput
      type="file"
      accept="image/*"
      (change)="onAvatar($event)"
      style="display:none;"
    />

    <div class="avatar-modal" *ngIf="avatarModalOpen" (click)="closeAvatarModal()">
      <div class="avatar-modal-card" (click)="$event.stopPropagation()">
        <div class="avatar large">
          <img
            class="img"
            [src]="avatarModalImage"
            alt="avatar"
            [style.transform]="avatarModalTransform"
          />
          <span class="ring"></span>
        </div>
        <button class="ghost-link" type="button" (click)="closeAvatarModal()">Close</button>
      </div>
    </div>

    <div
      class="lightbox"
      *ngIf="lightboxUrl"
      (click)="closeImageLightbox()"
      role="dialog"
      aria-modal="true"
    >
      <button
        class="lightbox-close"
        type="button"
        (click)="closeImageLightbox(); $event.stopPropagation()"
        aria-label="Close"
      >
        ×
      </button>
      <div class="lightbox-frame" (click)="$event.stopPropagation()">
        <img [src]="lightboxUrl" alt="Expanded media" />
      </div>
    </div>
  `,
  styles: [`
    :host{
      position: fixed;
      inset: 0;
      display:block;
      pointer-events:auto;
      z-index:30;
    }
    .wrap{
      position: fixed;
      inset: 0;
      padding: 0;
      box-sizing: border-box;
      overflow-y: auto;
      overflow-x: hidden;
      background: transparent;
      color: rgba(255,255,255,0.92);
    }
    .wrap > .ocean-gradient,
    .wrap > .ocean-dots,
    .wrap > .noise{
      display:none;
    }
    .ocean-gradient{
      z-index:0;
      background:
        radial-gradient(1400px 900px at 38% 20%, rgba(0,255,209,0.18), transparent 60%),
        radial-gradient(1100px 900px at 65% 70%, rgba(140,0,255,0.14), transparent 64%),
        #031421;
      animation: oceanPulse 18s ease-in-out infinite;
    }
    .ocean-dots{
      z-index:1;
      background-image:
        radial-gradient(circle at 20% 20%, rgba(255,255,255,0.35) 0.8px, transparent 2px),
        radial-gradient(circle at 70% 30%, rgba(255,255,255,0.25) 0.6px, transparent 2px),
        radial-gradient(circle at 40% 70%, rgba(255,255,255,0.20) 0.7px, transparent 2.2px);
      background-size: 220px 220px, 340px 340px, 520px 520px;
      opacity:0.45;
      mix-blend-mode: screen;
      animation: driftDots 48s linear infinite;
    }
    .noise{
      z-index:2;
      background-image:
        linear-gradient(0deg, rgba(255,255,255,0.04) 1px, transparent 1px),
        linear-gradient(90deg, rgba(255,255,255,0.04) 1px, transparent 1px);
      background-size: 4px 4px;
      opacity:0.12;
      pointer-events:none;
      animation: drift 18s linear infinite;
    }
    @keyframes oceanPulse{
      0%{ opacity:0.85; transform: scale(1); }
      50%{ opacity:1; transform: scale(1.02); }
      100%{ opacity:0.85; transform: scale(1); }
    }
    @keyframes driftDots{
      0%{ transform: translate3d(0,0,0); }
      50%{ transform: translate3d(-80px,-40px,0); }
      100%{ transform: translate3d(0,0,0); }
    }
    @keyframes drift{
      0%{ transform: translate3d(0,0,0); }
      50%{ transform: translate3d(-10px, 10px,0); }
      100%{ transform: translate3d(0,0,0); }
    }
    .card{
      position: relative;
      z-index:1;
      width: 100%;
      margin: 0;
      border-radius: 0;
      padding: 0;
      background: transparent;
      border: 0;
      box-shadow: none;
      color: rgba(10,12,18,0.92);
      min-height: 100%;
      box-sizing: border-box;
    }
    .state{
      text-align:center;
      font-weight:800;
      font-size:14px;
    }
    .share-row{
      margin-bottom: 18px;
    }
    .share-box{
      border-radius: 18px;
      border: 1px solid rgba(0,0,0,0.08);
      background: rgba(255,255,255,0.94);
      padding: 14px;
    }
    .share-box.empty{
      display:flex;
      flex-direction:column;
      gap:8px;
      align-items:flex-start;
    }
    .share-label{ font-weight: 900; font-size: 12px; letter-spacing: .12em; opacity:.65; }
    .share-link{
      font-family: 'JetBrains Mono','SFMono-Regular','Consolas',monospace;
      font-size:12px;
      word-break: break-all;
      margin-top:6px;
    }
    .share-placeholder{
      font-size:13px;
      opacity:0.7;
    }
    .share-actions{
      margin-top:10px;
      display:flex;
      gap:12px;
      align-items:center;
      flex-wrap:wrap;
    }
    .composer{
      margin:20px auto 0;
      width:100%;
      max-width:none;
      border-radius:20px;
      border:1px solid rgba(0,0,0,0.06);
      background:rgba(255,255,255,0.95);
      padding:16px;
      box-shadow:0 20px 60px rgba(0,0,0,0.10);
    }
    .composer.profile-composer{ margin-bottom:20px; }
    .composer-row{ display:flex; gap:14px; align-items:flex-start; }
    .composer-avatar{
      width:48px;
      height:48px;
      border-radius:999px;
      overflow:hidden;
      border:1px solid rgba(0,0,0,0.08);
      background:rgba(245,247,250,0.9);
      display:grid;
      place-items:center;
      flex:0 0 auto;
    }
    .composer-avatar img{ width:100%; height:100%; object-fit:cover; }
    .composer-initials{ font-weight:900; letter-spacing:0.12em; color:rgba(10,12,18,0.8); }
    .composer-main{ flex:1; }
    .composer-top{ display:flex; justify-content:space-between; gap:12px; flex-wrap:wrap; }
    .composer-cta{ display:flex; gap:8px; align-items:center; }
    .composer-title{ font-weight:900; letter-spacing:0.12em; font-size:12px; }
    .composer-hint{ font-size:12px; opacity:0.7; margin-top:4px; }
    .pill-link{
      border:0;
      border-radius:999px;
      padding:6px 16px;
      font-size:10px;
      letter-spacing:0.18em;
      font-weight:900;
      text-transform:uppercase;
      background:rgba(0,0,0,0.05);
      color:rgba(10,12,18,0.75);
      cursor:pointer;
    }
    .pill-link.ghost{
      background:transparent;
      border:1px solid rgba(10,12,18,0.15);
    }
    .composer-trigger{
      width:100%;
      margin-top:10px;
      border-radius:16px;
      border:1px solid rgba(0,0,0,0.08);
      background:rgba(245,247,250,0.9);
      text-align:left;
      padding:12px;
      font-weight:600;
      color:rgba(10,12,18,0.65);
      cursor:pointer;
    }
    .composer-input,
    .composer-textarea{
      width:100%;
      margin-top:10px;
      border-radius:16px;
      border:1px solid rgba(0,0,0,0.08);
      background:rgba(245,247,250,0.9);
      padding:12px;
      font-family:inherit;
      font-size:14px;
    }
    .composer-textarea{ min-height:90px; resize:vertical; }
    .composer-media{
      margin-top:10px;
      display:flex;
      gap:8px;
      align-items:center;
      flex-wrap:wrap;
    }
    .composer-media-name{
      font-size:11px;
      opacity:0.7;
      font-weight:700;
      letter-spacing:0.06em;
    }
    .composer-media-error{
      margin-top:6px;
      font-size:11px;
      font-weight:700;
      color:#c33;
      letter-spacing:0.06em;
    }
    .composer-media-preview{
      margin-top:10px;
      border-radius:18px;
      overflow:hidden;
      border:1px solid rgba(0,0,0,0.08);
      background:#fff;
    }
    .composer-media-preview img,
    .composer-media-preview video{
      width:100%;
      display:block;
      max-height:420px;
      object-fit:cover;
      background:#000;
    }
    .composer-actions{ margin-top:12px; display:flex; align-items:center; gap:12px; flex-wrap:wrap; }
    .composer-status{ font-size:12px; font-weight:700; letter-spacing:0.08em; color:rgba(0,120,255,0.9); }
    .composer-status.error{ color:#c33; }
    .btn{
      border:0;
      border-radius:16px;
      padding:10px 14px;
      background: linear-gradient(90deg, rgba(0,255,209,0.85), rgba(140,0,255,0.75));
      color: rgba(6,8,14,0.96);
      font-weight:900;
      letter-spacing:0.12em;
      cursor:pointer;
    }
    .btn:disabled{
      opacity:0.6;
      cursor:not-allowed;
    }
    .micro-btn{
      border:0;
      border-radius:999px;
      padding:6px 16px;
      text-transform:uppercase;
      letter-spacing:0.18em;
      font-size:10px;
      font-weight:900;
      background: rgba(10,12,18,0.06);
      color: rgba(10,12,18,0.78);
      box-shadow: inset 0 0 0 1px rgba(10,12,18,0.06), 0 12px 32px rgba(0,0,0,0.08);
      cursor:pointer;
      transition: transform 160ms ease, box-shadow 160ms ease, background 160ms ease;
    }
    .micro-btn:hover{
      transform: translateY(-1px);
      box-shadow: inset 0 0 0 1px rgba(10,12,18,0.12), 0 18px 40px rgba(0,0,0,0.12);
    }
    .micro-btn.outline{
      background: rgba(255,255,255,0.9);
      color: rgba(6,8,14,0.85);
      box-shadow: inset 0 0 0 1px rgba(0,0,0,0.05), 0 10px 30px rgba(0,0,0,0.09);
    }
    .share-icon{
      border:0;
      border-radius:999px;
      width:36px;
      height:36px;
      display:grid;
      place-items:center;
      background:rgba(10,12,18,0.08);
      cursor:pointer;
      font-size:16px;
    }
    .share-icon.bare{
      background:transparent;
      width:auto;
      height:auto;
      font-size:20px;
      line-height:1;
    }
    .share-icon.share-emoji{
      width:24px;
      height:24px;
      padding:0;
      margin-left:auto;
    }
    .edit-profile-toggle .saved-check{
      display:inline-flex;
      align-items:center;
      gap:4px;
      color:#00c781;
      font-weight:700;
      letter-spacing:0.05em;
    }
    .edit-profile-toggle .saved-check .check-arrow{
      font-size:14px;
    }
    .share-icon.share-emoji svg{
      width:100%;
      height:100%;
      display:block;
    }
    .share-icon:disabled{
      opacity:0.4;
      cursor:not-allowed;
    }
    .hint{
      font-size:12px;
      opacity:0.75;
    }
    .hint.error{
      color:#c33;
      opacity:1;
    }
    .sr-only{
      position:absolute;
      width:1px;
      height:1px;
      padding:0;
      margin:-1px;
      overflow:hidden;
      clip:rect(0,0,0,0);
      border:0;
    }
    .head{
      display:flex;
      gap:20px;
      align-items:flex-start;
      flex-wrap:wrap;
    }
    .head-actions{
      margin-left:auto;
      display:flex;
      align-items:flex-start;
    }
    .avatar-block{
      display:flex;
      flex-direction:column;
      align-items:center;
      gap:8px;
      cursor:pointer;
    }
    .avatar-actions{
      display:flex;
      flex-direction:column;
      align-items:flex-start;
      gap:8px;
      width:100%;
    }
    .avatar{
      width: 110px;
      height: 110px;
      border-radius:999px;
      overflow:hidden;
      position:relative;
      border:1px solid rgba(0,255,209,0.24);
      background: rgba(10,12,20,0.12);
      display:grid;
      place-items:center;
    }
    .avatar.large{
      width: 180px;
      height: 180px;
    }
    .img{
      width:120%;
      height:120%;
      object-fit: cover;
      transition: transform 120ms linear;
    }
    .ring{
      position:absolute;
      inset:-2px;
      border-radius:999px;
      background: conic-gradient(from 180deg, rgba(0,255,209,0), rgba(0,255,209,0.55), rgba(140,0,255,0.45), rgba(0,255,209,0));
      filter: blur(12px);
      opacity:0.25;
      pointer-events:none;
    }
    .ghost-link{
      border:0;
      background:transparent;
      color: rgba(0,120,255,0.85);
      font-size:12px;
      text-transform:uppercase;
      letter-spacing:0.12em;
      font-weight:800;
      cursor:pointer;
    }
    .back-link{
      color: rgba(0,0,0,0.75);
      margin-bottom:0;
      display:inline-flex;
      align-items:center;
      gap:6px;
      background:transparent;
    }
    .ghost-link.strong{
      letter-spacing:0.18em;
    }
    .handle-row{
      display:flex;
      align-items:center;
      gap:12px;
      flex-wrap:wrap;
      margin-top:4px;
    }
    .sub.handle{
      margin:0;
    }
    .info{ flex:1; min-width:0; }
    .title{ font-size:20px; font-weight:900; letter-spacing:.08em; text-transform:uppercase; }
    .title-row{
      display:flex;
      align-items:center;
      gap:12px;
      flex-wrap:wrap;
    }
    .presence-dot{
      width: 10px;
      height: 10px;
      border-radius: 999px;
      background: rgba(255,90,90,0.95);
      border: 2px solid rgba(255,255,255,0.9);
      box-shadow: 0 0 10px rgba(255,90,90,0.45);
    }
    .presence-dot.online{
      background: rgba(0,255,156,0.95);
      box-shadow: 0 0 10px rgba(0,255,156,0.45);
    }
    .title-actions{
      display:flex;
      align-items:center;
      gap:10px;
    }
    .sub{
      margin-top:4px;
      font-weight:800;
      opacity:0.75;
    }
    .meta{
      margin-top:6px;
      font-size:13px;
      opacity:0.7;
      font-weight:700;
      display:flex;
      gap:6px;
      flex-wrap:wrap;
    }
    .social-row{
      margin-top:12px;
      display:flex;
      gap:14px;
      flex-wrap:wrap;
      align-items:center;
    }
    .stat-card{
      min-width:110px;
      border-radius:18px;
      padding:12px 14px;
      background: rgba(0,0,0,0.035);
      border:1px solid rgba(0,0,0,0.05);
      box-shadow: 0 18px 40px rgba(0,0,0,0.08);
    }
    .stat-value{
      font-weight:900;
      font-size:18px;
      letter-spacing:0.08em;
      color: rgba(6,8,14,0.88);
    }
    .stat-label{
      font-size:11px;
      letter-spacing:0.18em;
      text-transform:uppercase;
      opacity:0.6;
      font-weight:800;
    }
    .follow-cta{
      margin-left:auto;
      display:flex;
      flex-direction:column;
      gap:6px;
      align-items:flex-end;
    }
    .follow-btn{
      border:0;
      border-radius:999px;
      padding:10px 22px;
      background: linear-gradient(120deg, rgba(0,255,209,0.95), rgba(140,0,255,0.78));
      color: rgba(6,8,14,0.92);
      font-weight:900;
      letter-spacing:0.2em;
      text-transform:uppercase;
      cursor:pointer;
      box-shadow: 0 18px 50px rgba(0,255,209,0.28);
      transition: transform 160ms ease, box-shadow 160ms ease, opacity 160ms ease;
    }
    .follow-btn.following{
      background: rgba(10,12,20,0.9);
      color: rgba(255,255,255,0.9);
      box-shadow: 0 18px 40px rgba(0,0,0,0.24);
    }
    .follow-btn:disabled{
      opacity:0.6;
      cursor:not-allowed;
      box-shadow:none;
      transform:none;
    }
    .message-btn{
      border:1px solid rgba(0,155,220,0.5);
      border-radius:999px;
      padding:8px 20px;
      background: rgba(0,155,220,0.12);
      color: rgba(6,12,20,0.9);
      font-weight:800;
      letter-spacing:0.18em;
      text-transform:uppercase;
      cursor:pointer;
      transition: transform 160ms ease, box-shadow 160ms ease, opacity 160ms ease;
    }
    .message-btn:disabled{
      opacity:0.6;
      cursor:not-allowed;
      box-shadow:none;
      transform:none;
    }
    .bio{
      margin-top:12px;
      line-height:1.5;
      font-size:14px;
    }
    .text-input{
      width:100%;
      border-radius:14px;
      border:1px solid rgba(0,0,0,0.12);
      padding:10px 12px;
      font-size:14px;
      font-family:inherit;
      background: rgba(255,255,255,0.95);
    }
    .textarea{
      min-height:90px;
      resize:vertical;
    }
    .edit-row{
      margin-top:10px;
    }
    .edit-actions{
      margin-top:10px;
      display:flex;
      gap:12px;
      align-items:center;
      flex-wrap:wrap;
    }
    .avatar-editor{
      margin-top:24px;
      border-top:1px solid rgba(0,0,0,0.08);
      padding-top:16px;
    }
    .editor-head{
      display:flex;
      justify-content:space-between;
      align-items:center;
      gap:16px;
      flex-wrap:wrap;
    }
    .sec-title{
      font-weight:900;
      letter-spacing:.12em;
      font-size:12px;
      text-transform:uppercase;
    }
    .btn-file{
      border:1px solid rgba(0,0,0,0.1);
      border-radius:14px;
      padding:10px 12px;
      cursor:pointer;
      background:rgba(255,255,255,0.95);
      font-weight:800;
      letter-spacing:.08em;
    }
    .btn-file input{
      display:none;
    }
    .editor-preview{
      margin-top:18px;
      display:flex;
      justify-content:center;
    }
    .avatar-modal{
      position: fixed;
      inset:0;
      background: rgba(0,0,0,0.55);
      display:grid;
      place-items:center;
      z-index:40;
    }
    .avatar-modal-card{
      background: rgba(10,12,20,0.92);
      border:1px solid rgba(255,255,255,0.12);
      border-radius:24px;
      padding:24px;
      text-align:center;
      color:rgba(255,255,255,0.92);
    }
    .composer-posts{
      width: 100%;
      max-width: none;
      margin: 24px 0 0;
      border-radius: 0;
      padding: 0;
      background: transparent;
      border: 0;
      box-shadow: none;
      color: rgba(6,8,14,0.92);
      box-sizing: border-box;
    }
    .composer-posts .sec-title{
      font-size: 14px;
      letter-spacing: 0.2em;
      font-weight: 900;
      text-transform: uppercase;
      margin-bottom: 12px;
      opacity: 0.7;
    }
    .post-status{
      font-size: 13px;
      margin-bottom: 12px;
      opacity: 0.65;
    }
    .post-status.error{
      color: #c33;
      opacity: 1;
    }
    .post-list{
      display:flex;
      flex-direction:column;
      gap:16px;
      width: 100%;
      box-sizing: border-box;
    }
    .post-card{
      position:relative;
      border-radius:20px;
      border:1px solid rgba(0,0,0,0.06);
      background:rgba(255,255,255,0.98);
      padding:18px;
      box-shadow:0 18px 60px rgba(0,0,0,0.15);
      box-sizing: border-box;
    }
    .post-author{
      margin-bottom:10px;
      display:flex;
      align-items:flex-start;
      gap:12px;
    }
    .author-core{
      display:flex;
      align-items:center;
      gap:12px;
      flex:1;
    }
    .author-avatar{
      width:48px;
      height:48px;
      border-radius:999px;
      overflow:hidden;
      border:1px solid rgba(0,0,0,0.08);
      background:rgba(245,247,250,0.95);
      display:grid;
      place-items:center;
    }
    .author-avatar img{
      width:100%;
      height:100%;
      object-fit:cover;
    }
    .author-initials{
      font-weight:900;
      letter-spacing:0.12em;
      color:rgba(10,12,18,0.8);
    }
    .author-info{
      display:flex;
      flex-direction:column;
      gap:2px;
    }
    .author-name{
      font-weight:700;
      font-size:14px;
    }
    .author-meta{
      font-size:12px;
      letter-spacing:0.08em;
      text-transform:uppercase;
      opacity:0.6;
    }
    .post-title{
      margin:0 0 6px;
      font-size:16px;
      font-weight:700;
      letter-spacing:0.02em;
    }
    .post-body{
      margin:0;
      font-size:14px;
      line-height:1.7;
      opacity:0.85;
      white-space:pre-line;
    }
    .post-caption{
      margin-top:10px;
      font-size:13px;
      line-height:1.45;
      opacity:0.75;
    }
    .post-media{
      margin-top:12px;
      border-radius:18px;
      overflow:hidden;
      border:1px solid rgba(0,0,0,0.06);
      background:#fff;
    }
    .post-media img,
    .post-media video{
      width:100%;
      display:block;
      max-height:520px;
      object-fit:cover;
      background:#000;
    }
    .post-visibility{
      font-weight:800;
      font-size:10px;
      letter-spacing:0.16em;
      text-transform:uppercase;
      opacity:0.7;
    }
    .post-actions{
      margin-top:12px;
      display:flex;
      gap:10px;
      align-items:center;
      flex-wrap:wrap;
    }
    .post-action-group{
      display:inline-flex;
      align-items:center;
      gap:6px;
    }
    .post-action{
      display:flex;
      align-items:center;
      gap:6px;
      border-radius:999px;
      border:1px solid rgba(0,199,255,0.45);
      background:rgba(245,247,250,0.92);
      padding:6px 12px;
      font-size:12px;
      font-weight:800;
      letter-spacing:0.06em;
      color:rgba(10,12,18,0.7);
      cursor:pointer;
    }
    .post-action .icon{ font-size:14px; }
    .post-action .count{ font-size:11px; font-weight:800; }
    .post-action.active{
      border-color:rgba(0,199,255,0.7);
      background:rgba(0,199,255,0.12);
      color:rgba(10,12,18,0.75);
    }
    .post-action.like.active .icon{ color:#c33; }
    .post-action.count{
      padding:6px 10px;
      min-width:36px;
      justify-content:center;
    }
    .post-action:disabled{ opacity:0.6; cursor:not-allowed; }
    .post-action.view{
      cursor:default;
      border-color:rgba(0,0,0,0.12);
      background:rgba(255,255,255,0.9);
    }
    .post-action-error{
      margin-top:6px;
      font-size:11px;
      font-weight:700;
      color:#c33;
      letter-spacing:0.06em;
    }
    .post-comments{
      margin-top:10px;
      padding-top:10px;
      border-top:1px solid rgba(0,0,0,0.06);
      display:flex;
      flex-direction:column;
      gap:10px;
    }
    .comment-status{ font-size:12px; opacity:0.7; }
    .comment-status.error{ color:#c33; }
    .comment-list{ display:flex; flex-direction:column; gap:10px; }
    .comment-empty{ font-size:12px; opacity:0.6; }
    .comment{
      display:flex;
      gap:10px;
      align-items:flex-start;
    }
    .comment-avatar{
      width:30px;
      height:30px;
      border-radius:999px;
      overflow:hidden;
      background:rgba(245,247,250,0.95);
      border:1px solid rgba(0,0,0,0.08);
      display:grid;
      place-items:center;
      font-weight:900;
      font-size:11px;
      color:rgba(10,12,18,0.8);
    }
    .comment-avatar img{ width:100%; height:100%; object-fit:cover; }
    .comment-body{ flex:1; min-width:0; }
    .comment-meta{ display:flex; gap:8px; align-items:center; font-size:11px; opacity:0.65; }
    .comment-name{ font-weight:800; text-transform:uppercase; letter-spacing:0.08em; }
    .comment-text{ font-size:12px; color:rgba(10,12,18,0.85); margin-top:2px; }
    .comment-actions{
      display:flex;
      gap:10px;
      margin-top:4px;
      font-size:11px;
    }
    .comment-action{
      border:0;
      background:transparent;
      padding:0;
      color:rgba(10,12,18,0.58);
      font-weight:800;
      letter-spacing:0.08em;
      text-transform:uppercase;
      display:inline-flex;
      align-items:center;
      gap:6px;
      cursor:pointer;
    }
    .comment-action.active{ color:rgba(0,155,220,0.88); }
    .comment-action:disabled{ opacity:0.5; cursor:not-allowed; }
    .comment-heart{ font-size:12px; line-height:1; }
    .comment-heart.active{ color:rgba(0,155,220,0.95); }
    .comment-like-count{ font-size:11px; font-weight:800; color:rgba(10,12,18,0.75); }
    .comment-reply{
      display:flex;
      align-items:center;
      gap:8px;
      font-size:11px;
      font-weight:800;
      letter-spacing:0.06em;
      color:rgba(10,12,18,0.6);
      text-transform:uppercase;
      width:100%;
    }
    .comment-reply span{ color:rgba(0,155,220,0.85); }
    .comment-compose{
      display:flex;
      gap:8px;
      align-items:center;
      flex-wrap:wrap;
    }
    .comment-input{
      flex:1;
      min-width:180px;
      border-radius:12px;
      border:1px solid rgba(0,0,0,0.08);
      background:rgba(245,247,250,0.9);
      padding:8px 10px;
      font-family:inherit;
      font-size:12px;
      color:rgba(10,12,18,0.85);
    }
    .comment-submit{
      border-radius:999px;
      border:1px solid rgba(0,0,0,0.12);
      background:rgba(255,255,255,0.96);
      padding:6px 12px;
      font-size:11px;
      font-weight:800;
      letter-spacing:0.08em;
      text-transform:uppercase;
      color:rgba(10,12,18,0.7);
      cursor:pointer;
    }
    .post-likes{
      margin-top:10px;
      padding-top:10px;
      border-top:1px solid rgba(0,0,0,0.06);
      display:flex;
      flex-direction:column;
      gap:10px;
    }
    .like-status{ font-size:12px; opacity:0.7; }
    .like-status.error{ color:#c33; }
    .like-list{ display:flex; flex-direction:column; gap:10px; }
    .like-empty{ font-size:12px; opacity:0.6; }
    .like-row{
      display:flex;
      align-items:center;
      gap:10px;
      border:0;
      background:transparent;
      padding:4px 0;
      text-align:left;
      cursor:pointer;
      color:inherit;
    }
    .like-avatar{
      width:30px;
      height:30px;
      border-radius:999px;
      overflow:hidden;
      background:rgba(245,247,250,0.95);
      border:1px solid rgba(0,0,0,0.08);
      display:grid;
      place-items:center;
      font-weight:900;
      font-size:11px;
      color:rgba(10,12,18,0.8);
    }
    .like-avatar img{ width:100%; height:100%; object-fit:cover; }
    .like-body{ flex:1; min-width:0; }
    .like-name{ font-weight:800; text-transform:uppercase; letter-spacing:0.08em; font-size:11px; }
    .like-handle{ font-size:11px; opacity:0.6; }
    .like-time{ font-size:11px; opacity:0.55; }
    .comment-submit:disabled{ opacity:0.6; cursor:not-allowed; }
    .comment-hint{ font-size:12px; opacity:0.6; }
    .post-edit{
      margin-top:12px;
      display:grid;
      gap:10px;
    }
    .post-edit-title,
    .post-edit-body,
    .post-edit-visibility{
      width:100%;
      border-radius:14px;
      border:1px solid rgba(0,0,0,0.08);
      background:rgba(245,247,250,0.9);
      padding:10px 12px;
      font-family:inherit;
      font-size:13px;
      color:rgba(10,12,18,0.9);
    }
    .post-edit-body{ min-height:90px; resize:vertical; }
    .post-edit-footer{
      display:flex;
      align-items:center;
      justify-content:space-between;
      gap:12px;
      flex-wrap:wrap;
    }
    .post-edit-actions{ display:flex; gap:10px; align-items:center; }
    .post-edit-error{ font-size:12px; font-weight:700; color:#ff6b81; letter-spacing:0.08em; }
    .post-menu{
      margin-left:auto;
      display:flex;
      align-items:center;
      gap:6px;
      position:relative;
    }
    .post-visibility-icon{
      font-size:14px;
      line-height:1;
      opacity:0.7;
    }
    .post-menu-trigger{
      width:28px;
      height:28px;
      border-radius:999px;
      border:1px solid rgba(0,0,0,0.12);
      background:rgba(255,255,255,0.9);
      color:rgba(10,12,18,0.7);
      font-size:18px;
      line-height:1;
      cursor:pointer;
    }
    .post-menu-trigger:focus{
      outline:2px solid rgba(10,12,18,0.18);
      outline-offset:2px;
    }
    .post-menu-dropdown{
      position:absolute;
      top:34px;
      right:0;
      min-width:170px;
      background:rgba(255,255,255,0.98);
      border:1px solid rgba(0,0,0,0.08);
      border-radius:14px;
      box-shadow:0 18px 60px rgba(0,0,0,0.12);
      padding:8px;
      display:flex;
      flex-direction:column;
      gap:6px;
      z-index:5;
    }
    .menu-item{
      border:0;
      background:transparent;
      text-align:left;
      padding:6px 8px;
      border-radius:10px;
      font-size:12px;
      font-weight:700;
      letter-spacing:0.08em;
      text-transform:uppercase;
      color:rgba(10,12,18,0.7);
      cursor:pointer;
    }
    .menu-item:hover{
      background:rgba(10,12,18,0.06);
    }
    .menu-item.danger{ color:#c33; }
    .menu-item.ghost{ color:rgba(10,12,18,0.55); }
    .menu-confirm{
      margin-top:6px;
      padding-top:6px;
      border-top:1px solid rgba(0,0,0,0.08);
      display:flex;
      flex-direction:column;
      gap:6px;
    }
    .menu-confirm-title{
      font-size:11px;
      font-weight:700;
      letter-spacing:0.08em;
      text-transform:uppercase;
      color:rgba(10,12,18,0.6);
    }
    .menu-confirm-actions{
      display:flex;
      justify-content:flex-end;
      gap:8px;
    }
    .menu-report{
      margin-top:6px;
      padding-top:6px;
      border-top:1px solid rgba(0,0,0,0.08);
      display:grid;
      gap:8px;
    }
    .menu-report-input{
      width:100%;
      border-radius:10px;
      border:1px solid rgba(0,0,0,0.1);
      background:rgba(245,247,250,0.94);
      padding:8px;
      font-family:inherit;
      font-size:12px;
      color:rgba(10,12,18,0.85);
    }
    .menu-report-error{
      font-size:11px;
      font-weight:700;
      color:#c33;
      letter-spacing:0.06em;
    }
    .menu-report-success{
      font-size:11px;
      font-weight:700;
      color:rgba(10,12,18,0.7);
      letter-spacing:0.06em;
    }
    @media (max-width: 900px){
      .card{ padding:20px; }
    }
    @media (max-width: 700px){
      .wrap{
        padding: 72px max(12px, env(safe-area-inset-left)) 24px max(12px, env(safe-area-inset-right));
      }
      .card{ padding:18px; border-radius:22px; }
      .head{ gap:16px; }
      .title-row{ flex-direction:column; align-items:flex-start; }
      .title-actions{ width:100%; flex-wrap:wrap; }
    }
    @media (max-width: 520px){
      .avatar{ width:96px; height:96px; }
      .avatar.large{ width:150px; height:150px; }
      .composer-row{ flex-direction:column; }
      .composer-avatar{ width:42px; height:42px; }
      .author-avatar{ width:40px; height:40px; }
      .post-card{ padding:16px; }
      .post-actions{ gap:8px; }
    }
  `],
})
export class ProfilePageComponent implements OnInit, OnDestroy {
  profile: Profile | null = null;
  loading = false;
  error = '';
  private sub?: Subscription;
  private postEventsCreatedSub?: Subscription;
  private postEventsInsertSub?: Subscription;
  private postEventsUpdatedSub?: Subscription;
  private postEventsUpdateSub?: Subscription;
  private postEventsDeleteSub?: Subscription;
  private locationRefreshTimer: number | null = null;
  private locationRefreshInFlight = false;
  private readonly LOCATION_REFRESH_MS = 10 * 60_000;

  shareUrl = '';
  shareCopied = false;
  shareError = '';
  private shareTimer: any = null;

  isOwner = false;
  meId: string | null = null;
  meEmail: string | null = null;
  private currentSlug = '';
  followersCount: number | null = null;
  followingCount: number | null = null;
  followMetaLoading = false;
  viewerFollowing = false;
  followBusy = false;
  followError = '';
  messageBusy = false;
  messageError = '';
  private followProfileId: string | null = null;
  postTitle = '';
  postBody = '';
  postMediaFile: File | null = null;
  postMediaPreview = '';
  postMediaType: 'image' | 'video' | null = null;
  postMediaError = '';
  postBusy = false;
  postError = '';
  postFeedback = '';
  profileComposerOpen = false;
  editingPostId: string | null = null;
  editPostTitle = '';
  editPostBody = '';
  editPostVisibility: 'public' | 'followers' | 'private' = 'public';
  postEditBusy = false;
  postEditError = '';
  lightboxUrl: string | null = null;
  private readonly POST_TEXT_LIMIT = 220;
  private expandedPosts = new Set<string>();
  private viewedPostIds = new Set<string>();
  openPostMenuId: string | null = null;
  confirmDeletePostId: string | null = null;
  likeBusy: Record<string, boolean> = {};
  likeOpen: Record<string, boolean> = {};
  likeLoading: Record<string, boolean> = {};
  likeErrors: Record<string, string> = {};
  likeItems: Record<string, PostLike[]> = {};
  postActionError: Record<string, string> = {};
  commentOpen: Record<string, boolean> = {};
  commentLoading: Record<string, boolean> = {};
  commentBusy: Record<string, boolean> = {};
  commentErrors: Record<string, string> = {};
  commentDrafts: Record<string, string> = {};
  commentItems: Record<string, PostComment[]> = {};
  commentDisplay: Record<string, PostComment[]> = {};
  commentDepth: Record<string, Record<string, number>> = {};
  commentReplyTarget: Record<string, { commentId: string; authorName: string } | null> = {};
  commentLikeBusy: Record<string, Record<string, boolean>> = {};
  reportingPostId: string | null = null;
  reportReason = '';
  reportBusy = false;
  reportError = '';
  reportFeedback = '';

  profilePosts: CountryPost[] = [];
  loadingProfilePosts = false;
  profilePostsError = '';
  profileOnline = false;
  private onlineIds = new Set<string>();
  private presenceStarted = false;

  avatarImage = '';
  avatarNormX = 0;
  avatarNormY = 0;
  avatarModalOpen = false;
  @ViewChild('avatarInput') avatarInputRef?: ElementRef<HTMLInputElement>;
  private avatarBeforeEdit = '';

  editingName = false;
  nameSaving = false;
  draftDisplayName = '';

  editingUsername = false;
  usernameSaving = false;
  draftUsername = '';
  usernameError = '';

  editingBio = false;
  bioSaving = false;
  draftBio = '';
  bio = '';
  profileEditMode = false;
  profileEditSaving = false;
  profileEditSaved = false;
  private profileEditCloseTimer: any = null;

  editingAvatar = false;
  avatarSaving = false;
  avatarUploading = false;
  avatarError = '';
  draftAvatarUrl = '';
  draftAvatarUploadUrl = '';
  private avatarPreviewUrl = '';

  private readonly AVATAR_OUT_SIZE = 512;
  private readonly EDIT_SIZE = 180;
  private readonly EDIT_SCALE = 1.25;
  private readonly USERNAME_PATTERN = /^[a-z0-9._]{3,24}$/;

  private draftNormX = 0;
  private draftNormY = 0;
  private dragging = false;
  private startX = 0;
  private startY = 0;
  private basePxX = 0;
  private basePxY = 0;
  private pendingPxX = 0;
  private pendingPxY = 0;
  private raf = 0;

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private profiles: ProfileService,
    private auth: AuthService,
    private media: MediaService,
    private posts: PostsService,
    private postEvents: PostEventsService,
    private follows: FollowService,
    private messagesService: MessagesService,
    private presence: PresenceService,
    private location: LocationService,
    private zone: NgZone,
    private cdr: ChangeDetectorRef
  ) {}

  async ngOnInit(): Promise<void> {
    this.postEventsCreatedSub = this.postEvents.createdPost$.subscribe((post) => {
      this.zone.run(() => this.handleNewProfilePost(post));
    });
    this.postEventsInsertSub = this.postEvents.insert$.subscribe((event) => {
      if (!this.profile || event.author_id !== this.profile.user_id) return;
      void this.loadProfilePosts(this.profile.user_id);
    });
    this.postEventsUpdatedSub = this.postEvents.updatedPost$.subscribe((post) => {
      this.zone.run(() => this.handleProfilePostUpdated(post));
    });
    this.postEventsUpdateSub = this.postEvents.update$.subscribe((event) => {
      this.zone.run(() => this.handleProfilePostUpdateEvent(event));
    });
    this.postEventsDeleteSub = this.postEvents.delete$.subscribe((event) => {
      this.zone.run(() => this.handleProfilePostDeleteEvent(event));
    });
    const user = await this.auth.getUser();
    this.meId = user?.id ?? null;
    this.meEmail = user?.email ?? null;
    void this.startPresenceStatus();

    this.sub = this.route.paramMap.subscribe((params) => {
      const slug = params.get('slug') ?? '';
      this.loadProfile(slug);
    });
  }

  ngOnDestroy(): void {
    this.sub?.unsubscribe();
    this.postEventsCreatedSub?.unsubscribe();
    this.postEventsInsertSub?.unsubscribe();
    this.postEventsUpdatedSub?.unsubscribe();
    this.postEventsUpdateSub?.unsubscribe();
    this.postEventsDeleteSub?.unsubscribe();
    try { this.presence.stop(); } catch {}
    this.stopLocationRefresh();
    if (this.shareTimer) clearTimeout(this.shareTimer);
    if (this.profileEditCloseTimer) clearTimeout(this.profileEditCloseTimer);
  }

  get initials(): string {
    const name = (this.profile?.display_name || this.profile?.username || 'U').trim();
    const parts = name.split(/\s+/).filter(Boolean);
    const a = parts[0]?.[0] ?? 'U';
    const b = parts.length > 1 ? (parts[parts.length - 1]?.[0] ?? '') : '';
    return (a + b).toUpperCase();
  }

  get avatarTransform(): string {
    const mo = this.maxOffset(110, 1.2);
    return `translate3d(${this.avatarNormX * mo}px, ${this.avatarNormY * mo}px, 0)`;
  }

  get draftAvatarTransform(): string {
    const mo = this.maxOffset(this.EDIT_SIZE, this.EDIT_SCALE);
    return `translate3d(${this.draftNormX * mo}px, ${this.draftNormY * mo}px, 0)`;
  }

  get avatarModalImage(): string {
    return this.draftAvatarUrl || this.avatarImage;
  }

  get avatarModalTransform(): string {
    const mo = this.maxOffset(180, 1.2);
    return `translate3d(${this.avatarNormX * mo}px, ${this.avatarNormY * mo}px, 0)`;
  }

  get canPostFromProfile(): boolean {
    if (!this.isOwner || !this.profile) return false;
    const code = (this.profile as any)?.country_code;
    const name = this.profile.country_name;
    return !!code && !!name;
  }

  async goHome(): Promise<void> {
    await this.router.navigateByUrl('/');
  }

  private async loadProfile(slugRaw: string): Promise<void> {
    this.loading = true;
    this.error = '';
    this.profile = null;
    this.resetFollowState();
    this.messageBusy = false;
    this.messageError = '';
    this.forceUi();

    try {
    const slug = (slugRaw || '').trim();
    if (!slug) throw new Error('Profile not found.');

    const username = slug.startsWith('@') ? slug.slice(1) : slug;
    this.currentSlug = username.toLowerCase();

    let profile: Profile | null = null;

    if (username) {
      const byUsername = await this.profiles.profileByUsername(username);
      profile = byUsername.profileByUsername ?? null;
    }

    if (!profile && this.meId) {
      const byMe = await this.profiles.profileById(this.meId);
      const meProfile = byMe.profileById ?? null;
      if (meProfile) {
        const slugLower = this.currentSlug;
        const meUsername = (meProfile.username || '').toLowerCase();
        const meDisplay = (meProfile.display_name || '').toLowerCase();
        const meEmailLocal = (meProfile.email || '').split('@')[0].toLowerCase();
        if (slugLower === meUsername || slugLower === meDisplay || slugLower === meEmailLocal) {
          profile = meProfile;
        }
      }
    }

    if (!profile) {
      const byId = await this.profiles.profileById(slug);
      profile = byId.profileById ?? null;
    }

      if (!profile) {
        this.error = 'Profile not found.';
      } else {
        this.applyProfile(profile);
      }
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    } finally {
      this.loading = false;
      this.forceUi();
    }
  }

  private applyProfile(profile: Profile): void {
    this.profile = profile;
    this.avatarImage = this.normalizeAvatarUrl((profile as any)?.avatar_url ?? '');
    this.bio = (profile as any)?.bio ?? '';
    this.draftDisplayName = profile.display_name ?? '';
    this.draftBio = this.bio ?? '';
    this.draftUsername = profile.username ?? '';
    this.usernameError = '';
    this.shareUrl = this.buildShareUrl(profile);
    this.shareCopied = false;
    this.shareError = '';
    const emailLocal = (this.meEmail || '').split('@')[0].toLowerCase();
    const profileUsername = (profile.username || '').toLowerCase();
    const profileEmail = (profile.email || '').toLowerCase();
    const slugMatch = !!this.currentSlug && (profileUsername === this.currentSlug || emailLocal === this.currentSlug);
    this.isOwner =
      (!!this.meId && profile.user_id === this.meId) ||
      (!!this.meEmail && profileEmail && profileEmail === (this.meEmail || '').toLowerCase()) ||
      (!!this.meEmail && slugMatch);
    this.updateProfileOnline();
    this.stopLocationRefresh();
    if (this.isOwner) this.startLocationRefresh();
    this.resetFollowState();
    this.messageBusy = false;
    this.messageError = '';
    if (!this.canPostFromProfile) this.profileComposerOpen = false;
    void this.loadFollowMeta(profile);
    void this.loadProfilePosts(profile.user_id);
  }

  private updateProfileOnline(): void {
    if (!this.profile?.user_id) {
      this.profileOnline = false;
      return;
    }
    this.profileOnline = this.onlineIds.has(this.profile.user_id);
  }

  private resetFollowState(): void {
    this.followersCount = null;
    this.followingCount = null;
    this.viewerFollowing = false;
    this.followError = '';
    this.followMetaLoading = false;
    this.followProfileId = null;
    this.followBusy = false;
  }

  private async startPresenceStatus(): Promise<void> {
    if (this.presenceStarted) return;
    this.presenceStarted = true;
    try {
      await this.presence.start({
        countries: [],
        loadProfiles: false,
        onUpdate: (snap) => {
          this.onlineIds = new Set(snap.onlineIds ?? []);
          this.updateProfileOnline();
          this.forceUi();
        },
      });
    } catch {
      this.presenceStarted = false;
    }
  }

  private startLocationRefresh(): void {
    if (this.locationRefreshTimer || !this.isOwner || !this.profile) return;
    void this.refreshLocationIfMoved();
    this.locationRefreshTimer = window.setInterval(() => {
      void this.refreshLocationIfMoved();
    }, this.LOCATION_REFRESH_MS);
  }

  private stopLocationRefresh(): void {
    if (!this.locationRefreshTimer) return;
    window.clearInterval(this.locationRefreshTimer);
    this.locationRefreshTimer = null;
  }

  private async refreshLocationIfMoved(): Promise<void> {
    if (this.locationRefreshInFlight || !this.isOwner || !this.profile) return;
    this.locationRefreshInFlight = true;

    try {
      const detected = await this.location.detectViaGpsThenServer(9000);
      if (!detected) return;

      const nextCode = String(detected.countryCode ?? '').trim().toUpperCase();
      const nextName = String(detected.countryName ?? '').trim();
      const nextCity = String(detected.cityName ?? '').trim();

      const currentCode = String((this.profile as any)?.country_code ?? '').trim().toUpperCase();
      const currentName = String(this.profile.country_name ?? '').trim();
      const currentCity = String((this.profile as any)?.city_name ?? '').trim();

      const updates: { country_code?: string; country_name?: string; city_name?: string } = {};

      if (nextCode && nextCode !== currentCode) updates.country_code = nextCode;
      if (nextName && nextName.toLowerCase() !== currentName.toLowerCase()) {
        updates.country_name = nextName;
      }
      if (nextCity && nextCity.toLowerCase() !== currentCity.toLowerCase()) {
        updates.city_name = nextCity;
      }

      if (!Object.keys(updates).length) return;

      const res = await this.profiles.updateProfile(updates);
      this.profile = res.updateProfile;
      if (!this.canPostFromProfile) this.profileComposerOpen = false;
      this.forceUi();
    } catch (e) {
      console.warn('location refresh failed', e);
    } finally {
      this.locationRefreshInFlight = false;
    }
  }

  private async loadFollowMeta(profile: Profile): Promise<void> {
    if (!profile?.user_id) {
      this.resetFollowState();
      return;
    }

    const targetId = profile.user_id;
    this.followProfileId = targetId;
    this.followMetaLoading = true;
    this.followError = '';
    this.forceUi();

    try {
      const [counts, viewerFollows] = await Promise.all([
        this.follows.counts(targetId),
        !this.isOwner && this.meId ? this.follows.isFollowing(this.meId, targetId) : Promise.resolve(false),
      ]);
      if (this.followProfileId !== targetId) return;
      this.followersCount = counts.followers;
      this.followingCount = counts.following;
      this.viewerFollowing = viewerFollows;
    } catch (e: any) {
      if (this.followProfileId === targetId) {
        this.followError = e?.message ?? String(e);
      }
    } finally {
      if (this.followProfileId === targetId) {
        this.followMetaLoading = false;
        this.forceUi();
      }
    }
  }

  async toggleFollow(): Promise<void> {
    if (!this.profile || this.isOwner) return;

    if (!this.meId) {
      await this.router.navigate(['/auth']);
      return;
    }

    if (this.followMetaLoading || this.followBusy) return;

    this.followBusy = true;
    this.followError = '';
    this.forceUi();

    try {
      if (this.viewerFollowing) {
        await this.follows.unfollow(this.meId, this.profile.user_id);
        this.viewerFollowing = false;
        const next = (this.followersCount ?? 1) - 1;
        this.followersCount = next < 0 ? 0 : next;
      } else {
        await this.follows.follow(this.meId, this.profile.user_id);
        this.viewerFollowing = true;
        this.followersCount = (this.followersCount ?? 0) + 1;
      }
    } catch (e: any) {
      this.followError = e?.message ?? String(e);
    } finally {
      this.followBusy = false;
      this.forceUi();
    }
  }

  async startConversation(): Promise<void> {
    if (!this.profile || this.isOwner || this.messageBusy) return;

    this.messageBusy = true;
    this.messageError = '';
    this.forceUi();

    try {
      const convo = await this.messagesService.startConversation(this.profile.user_id);
      this.messagesService.setPendingConversation(convo);
      void this.router.navigate(['/messages'], {
        queryParams: { c: convo.id },
        state: { convo },
      });
    } catch (e: any) {
      this.messageError = e?.message ?? String(e);
    } finally {
      this.messageBusy = false;
      this.forceUi();
    }
  }

  openUserProfile(user: { username?: string | null; user_id?: string | null } | null | undefined): void {
    if (!user) return;
    const slug = user.username?.trim() || user.user_id;
    if (!slug) return;
    void this.router.navigate(['/user', slug]);
  }

  openReels(post: CountryPost): void {
    if (!post) return;
    const code =
      post.country_code?.toUpperCase() ||
      post.author?.country_code?.toUpperCase() ||
      this.profile?.country_code?.toUpperCase();
    if (!code) return;
    const seedPosts = this.buildReelSeedPosts(post);
    void this.router.navigate(['/reels', code], {
      queryParams: { postId: post.id },
      state: {
        seedPosts,
        seedCountry: code,
        countryName: this.profile?.country_name || post.country_name || null,
      },
    });
  }

  private buildReelSeedPosts(post: CountryPost): CountryPost[] {
    const videos = (this.profilePosts || []).filter(
      (item) => item.media_type === 'video' && !!item.media_url
    );
    const combined = [post, ...videos];
    const seen = new Set<string>();
    const deduped: CountryPost[] = [];
    for (const item of combined) {
      if (!item?.id || seen.has(item.id)) continue;
      seen.add(item.id);
      deduped.push(item);
      if (deduped.length >= 50) break;
    }
    return deduped;
  }

  onProfileMediaSelect(event: Event): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0] ?? null;
    if (!file) return;

    const isImage = file.type.startsWith('image/');
    const isVideo = file.type.startsWith('video/');
    if (!isImage && !isVideo) {
      this.postMediaError = 'Only images or videos are allowed.';
      input.value = '';
      return;
    }

    const maxBytes = isVideo ? 40 * 1024 * 1024 : 12 * 1024 * 1024;
    if (file.size > maxBytes) {
      this.postMediaError = `File too large. Max ${isVideo ? '40MB' : '12MB'}.`;
      input.value = '';
      return;
    }

    this.clearProfileMedia();
    this.postMediaFile = file;
    this.postMediaType = isVideo ? 'video' : 'image';
    this.postMediaPreview = URL.createObjectURL(file);
    this.postMediaError = '';
  }

  clearProfileMedia(): void {
    if (this.postMediaPreview) {
      try { URL.revokeObjectURL(this.postMediaPreview); } catch {}
    }
    this.postMediaFile = null;
    this.postMediaPreview = '';
    this.postMediaType = null;
    this.postMediaError = '';
  }

  async submitProfilePost(): Promise<void> {
    if (!this.profile || !this.meId || !this.canPostFromProfile) return;
    const body = this.postBody.trim();
    if (!body) {
      this.postError = 'Write something before posting.';
      return;
    }

    this.postBusy = true;
    this.postError = '';
    this.postFeedback = '';
    this.forceUi();

    try {
      const title = this.postTitle.trim();
      const countryCode = String((this.profile as any)?.country_code || '').toUpperCase();
      const countryName = this.profile.country_name;
      if (!countryCode || !countryName) throw new Error('Country details missing.');

      let mediaType: string | null = null;
      let mediaUrl: string | null = null;
      if (this.postMediaFile) {
        const upload = await this.media.uploadPostMedia(this.postMediaFile);
        mediaUrl = upload.publicUrl;
        mediaType = this.postMediaType || (this.postMediaFile.type.startsWith('video/') ? 'video' : 'image');
      }

      await this.posts.createPost({
        authorId: this.meId,
        title: title || null,
        body,
        countryCode,
        countryName,
        cityName: (this.profile as any)?.city_name ?? null,
        mediaType,
        mediaUrl,
      });

      this.postTitle = '';
      this.postBody = '';
      this.clearProfileMedia();
      this.profileComposerOpen = false;
      this.postFeedback = mediaUrl
        ? 'Posted to Media (your country + followers feed).'
        : `Shared with ${countryName}.`;
      this.forceUi();
      setTimeout(() => {
        this.postFeedback = '';
        this.cdr.detectChanges();
      }, 2000);
    } catch (e: any) {
      this.postError = e?.message ?? String(e);
    } finally {
      this.postBusy = false;
      this.forceUi();
    }
  }

  startNameEdit(): void {
    this.draftDisplayName = this.profile?.display_name ?? '';
    this.editingName = true;
  }

  cancelNameEdit(): void {
    this.editingName = false;
    this.draftDisplayName = this.profile?.display_name ?? '';
  }

  async saveDisplayName(): Promise<void> {
    if (!this.profile) return;
    const name = this.draftDisplayName.trim();
    if (!name) return;

    this.nameSaving = true;
    this.forceUi();

    try {
      const res = await this.profiles.updateProfile({ display_name: name });
      this.applyProfile(res.updateProfile);
      this.editingName = false;
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    } finally {
      this.nameSaving = false;
      this.forceUi();
    }
  }

  startUsernameEdit(): void {
    if (!this.isOwner) return;
    this.usernameError = '';
    this.draftUsername = this.profile?.username ?? '';
    this.editingUsername = true;
  }

  cancelUsernameEdit(): void {
    this.editingUsername = false;
    this.usernameError = '';
    this.draftUsername = this.profile?.username ?? '';
  }

  onUsernameDraftChange(): void {
    if (this.usernameError) {
      this.usernameError = '';
      this.forceUi();
    }
  }

  async saveUsername(): Promise<void> {
    if (!this.profile || !this.isOwner) return;
    const normalized = this.normalizeUsername(this.draftUsername);
    if (!normalized) {
      this.usernameError = 'Username is required.';
      return;
    }
    if (!this.USERNAME_PATTERN.test(normalized)) {
      this.usernameError = 'Use 3-24 letters, numbers, dots, or underscores.';
      return;
    }
    if ((this.profile.username ?? '') === normalized) {
      this.editingUsername = false;
      return;
    }

    this.usernameSaving = true;
    this.usernameError = '';
    this.forceUi();

    try {
      const res = await this.profiles.updateProfile({ username: normalized });
      this.applyProfile(res.updateProfile);
      this.editingUsername = false;
    } catch (e: any) {
      const message = (e?.message ?? String(e)).toLowerCase();
      if (message.includes('duplicate') || message.includes('unique')) {
        this.usernameError = 'Handle already taken.';
      } else {
        this.usernameError = e?.message ?? String(e);
      }
    } finally {
      this.usernameSaving = false;
      this.forceUi();
    }
  }

  startBioEdit(): void {
    this.draftBio = this.bio ?? '';
    this.editingBio = true;
  }

  cancelBioEdit(): void {
    this.editingBio = false;
    this.draftBio = this.bio ?? '';
  }

  async saveBio(): Promise<void> {
    const text = this.draftBio.trim();
    this.bioSaving = true;
    this.forceUi();

    try {
      const res = await this.profiles.updateProfile({
        bio: text ? text.slice(0, 160) : null,
      });
      this.applyProfile(res.updateProfile);
      this.editingBio = false;
    } catch (e: any) {
      this.error = e?.message ?? String(e);
    } finally {
      this.bioSaving = false;
      this.forceUi();
    }
  }

  toggleAvatarEditor(event: Event): void {
    event.stopPropagation();
    this.editingAvatar = !this.editingAvatar;
    this.avatarError = '';
    if (this.editingAvatar) {
      this.draftAvatarUrl = this.avatarImage || '';
      this.draftAvatarUploadUrl = this.avatarImage || '';
      this.draftNormX = this.avatarNormX;
      this.draftNormY = this.avatarNormY;
    }
    this.forceUi();
  }

  triggerAvatarUpload(event: Event): void {
    this.openAvatarUpload(event);
    const input = this.avatarInputRef?.nativeElement;
    if (input) {
      input.click();
    }
  }

  openAvatarUpload(event: Event): void {
    event.stopPropagation();
    if (!this.editingAvatar) {
      this.avatarBeforeEdit = this.avatarImage || '';
      this.editingAvatar = true;
      this.draftAvatarUrl = this.avatarImage || '';
      this.draftAvatarUploadUrl = '';
      this.draftNormX = this.avatarNormX;
      this.draftNormY = this.avatarNormY;
      this.forceUi();
    }
  }

  cancelAvatarEdit(): void {
    this.editingAvatar = false;
    this.avatarError = '';
    this.draftAvatarUrl = '';
    this.draftAvatarUploadUrl = '';
    this.avatarImage = this.avatarBeforeEdit || this.normalizeAvatarUrl(this.profile?.avatar_url ?? '');
    this.avatarBeforeEdit = '';
    if (this.avatarPreviewUrl) {
      try { URL.revokeObjectURL(this.avatarPreviewUrl); } catch {}
      this.avatarPreviewUrl = '';
    }
    this.draftNormX = this.avatarNormX;
    this.draftNormY = this.avatarNormY;
  }

  openAvatarModal(): void {
    if (!this.avatarImage && !this.draftAvatarUrl) return;
    this.avatarModalOpen = true;
  }

  closeAvatarModal(): void {
    this.avatarModalOpen = false;
  }

  goBack(): void {
    void this.router.navigate(['/'], {
      state: { resetGlobe: true },
      replaceUrl: true,
      queryParams: { resetGlobe: '1' },
    });
  }

  async onAvatar(event: Event): Promise<void> {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;

    if (!this.editingAvatar) {
      this.avatarBeforeEdit = this.avatarImage || '';
      this.editingAvatar = true;
    }
    this.avatarError = '';
    this.avatarSaving = false;
    this.avatarUploading = true;
    this.forceUi();

    try {
      let uploadFile = file;
      try {
        uploadFile = await this.cropAvatarToSquare(file);
      } catch {
        // Fallback to original file if crop fails (e.g. HEIC decode issues)
        this.avatarError = 'Crop failed, using original image.';
      }
      if (this.avatarPreviewUrl) {
        try { URL.revokeObjectURL(this.avatarPreviewUrl); } catch {}
        this.avatarPreviewUrl = '';
      }
      this.avatarPreviewUrl = URL.createObjectURL(uploadFile);
      this.draftAvatarUrl = this.avatarPreviewUrl;
      this.avatarImage = this.draftAvatarUrl;
      this.draftAvatarUploadUrl = '';
      this.draftNormX = 0;
      this.draftNormY = 0;

      const upload = await this.media.uploadAvatar(uploadFile);
      if (!upload.url) throw new Error('Upload returned no URL.');

      // Keep the same logic as profile creation: save the public URL
      this.draftAvatarUploadUrl = upload.url;
      this.draftAvatarUrl = upload.url;
      this.avatarImage = this.draftAvatarUrl;
      if (this.avatarPreviewUrl) {
        try { URL.revokeObjectURL(this.avatarPreviewUrl); } catch {}
        this.avatarPreviewUrl = '';
      }
    } catch (e: any) {
      this.avatarError = e?.message ?? String(e);
    } finally {
      input.value = '';
      this.avatarUploading = false;
      this.forceUi();
    }
  }

  async saveAvatar(): Promise<void> {
    if (!this.draftAvatarUploadUrl) {
      this.avatarError = 'Upload pending. Please wait for the image to finish uploading.';
      this.forceUi();
      return;
    }
    this.avatarSaving = true;
    this.avatarError = '';
    this.forceUi();

      try {
        const res = await this.profiles.updateProfile({
          avatar_url: this.draftAvatarUploadUrl,
        });
        this.applyProfile(res.updateProfile);
        this.avatarImage = this.normalizeAvatarUrl(this.profile?.avatar_url ?? '');
        this.avatarNormX = this.draftNormX;
        this.avatarNormY = this.draftNormY;
        this.editingAvatar = false;
        this.avatarBeforeEdit = '';
      } catch (e: any) {
        this.avatarError = e?.message ?? String(e);
      } finally {
      this.avatarSaving = false;
      this.forceUi();
    }
  }

  onAvatarDragStart(ev: PointerEvent): void {
    if (!this.draftAvatarUrl) return;
    this.dragging = true;
    this.startX = ev.clientX;
    this.startY = ev.clientY;

    const mo = this.maxOffset(this.EDIT_SIZE, this.EDIT_SCALE);
    this.basePxX = this.draftNormX * mo;
    this.basePxY = this.draftNormY * mo;

    (ev.target as HTMLElement).setPointerCapture?.(ev.pointerId);

    const move = (e: PointerEvent) => this.onAvatarDragMove(e);
    const up = () => this.onAvatarDragEnd(move, up);

    window.addEventListener('pointermove', move, { passive: true });
    window.addEventListener('pointerup', up, { passive: true });
  }

  private onAvatarDragMove(ev: PointerEvent): void {
    if (!this.dragging) return;
    const dx = ev.clientX - this.startX;
    const dy = ev.clientY - this.startY;
    const mo = this.maxOffset(this.EDIT_SIZE, this.EDIT_SCALE);

    const clamp = (v: number) => Math.max(-mo, Math.min(mo, v));

    this.pendingPxX = clamp(this.basePxX + dx);
    this.pendingPxY = clamp(this.basePxY + dy);

    if (!this.raf) {
      this.raf = requestAnimationFrame(() => {
        this.draftNormX = this.clampNorm(mo ? this.pendingPxX / mo : 0);
        this.draftNormY = this.clampNorm(mo ? this.pendingPxY / mo : 0);
        this.raf = 0;
      });
    }
  }

  private onAvatarDragEnd(move: (e: PointerEvent) => void, up: () => void): void {
    this.dragging = false;
    window.removeEventListener('pointermove', move as any);
    window.removeEventListener('pointerup', up as any);
  }

  async copyShareLink(): Promise<void> {
    if (!this.shareUrl) return;
    this.shareError = '';
    this.shareCopied = false;
    this.forceUi();

    try {
      if (typeof navigator !== 'undefined' && navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(this.shareUrl);
      } else {
        throw new Error('Clipboard unavailable.');
      }

      this.shareCopied = true;
      this.forceUi();

      if (typeof window !== 'undefined') {
        if (this.shareTimer) clearTimeout(this.shareTimer);
        this.shareTimer = window.setTimeout(() => {
          this.zone.run(() => {
            this.shareCopied = false;
            this.cdr.detectChanges();
          });
        }, 1600);
      }
    } catch (e: any) {
      this.shareError = e?.message ?? String(e);
      this.forceUi();
    }
  }

  onProfileEditAction(): void {
    if (!this.isOwner) return;
    if (!this.profileEditMode) {
      this.profileEditMode = true;
      this.profileEditSaved = false;
      this.profileEditSaving = false;
      return;
    }
    if (this.profileEditSaving) return;

    this.profileEditSaving = true;
    this.profileEditSaved = true;
    this.forceUi();

    if (this.profileEditCloseTimer) {
      clearTimeout(this.profileEditCloseTimer);
    }

    this.profileEditCloseTimer = window.setTimeout(() => {
      this.completeProfileEditClose();
    }, 700);
  }

  private completeProfileEditClose(): void {
    this.profileEditMode = false;
    this.profileEditSaving = false;
    this.profileEditSaved = false;
    this.profileEditCloseTimer = null;
    this.cancelNameEdit();
    this.cancelUsernameEdit();
    this.cancelBioEdit();
    if (this.editingAvatar) {
      this.cancelAvatarEdit();
    }
    this.forceUi();
  }

  private buildShareUrl(profile: Profile | null): string {
    if (!profile) return '';
    const slug = profile.username?.trim();
    if (!slug) return '';

    const base =
      typeof window !== 'undefined' && window.location ? window.location.origin : '';
    return base ? `${base}/user/${encodeURIComponent(slug)}` : `/user/${encodeURIComponent(slug)}`;
  }

  private normalizeUsername(value: string): string {
    return value.trim().replace(/^@+/, '').toLowerCase();
  }

  private clampNorm(v: number): number {
    return Math.max(-1, Math.min(1, v));
  }

  private normalizeAvatarUrl(url: string | null | undefined): string {
    const raw = String(url || '').trim();
    if (!raw) return '';
    if (/^https?:\/\//i.test(raw) || raw.startsWith('data:') || raw.startsWith('blob:') || raw.startsWith('/')) {
      return raw;
    }
    if (raw.includes('/storage/v1/object/')) return raw;
    const normalized = raw.replace(/^\/+/, '');
    return `${SUPABASE_URL}/storage/v1/object/public/avatars/${normalized}`;
  }

  private maxOffset(size: number, scale: number): number {
    const scaled = size * scale;
    return Math.max(0, (scaled - size) / 2);
  }

  formatDate(value: string): string {
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) return value;
    return parsed.toLocaleString(undefined, {
      dateStyle: 'medium',
      timeStyle: 'short',
    });
  }

  private async loadProfilePosts(userId: string): Promise<void> {
    if (!userId) {
      this.profilePosts = [];
      return;
    }

    this.loadingProfilePosts = true;
    this.profilePostsError = '';
    this.forceUi();

    try {
    this.profilePosts = this.sortPostsDesc(await this.posts.listForAuthor(userId));
    } catch (e: any) {
      this.profilePostsError = e?.message ?? String(e);
    } finally {
      this.loadingProfilePosts = false;
      this.forceUi();
    }
  }

  private handleNewProfilePost(post: CountryPost): void {
    if (!this.profile || post.author_id !== this.profile.user_id) {
      return;
    }
    if (this.profilePosts.some((existing) => existing.id === post.id)) {
      return;
    }
    this.profilePosts = [post, ...this.profilePosts];
    this.forceUi();
  }

  private handleProfilePostUpdated(post: CountryPost): void {
    if (!this.profile || post.author_id !== this.profile.user_id) return;
    if (!this.isOwner) {
      void this.loadProfilePosts(this.profile.user_id);
      return;
    }
    this.applyProfilePostUpdate(post);
  }

  private handleProfilePostUpdateEvent(event: PostUpdateEvent): void {
    if (!this.profile || event.author_id !== this.profile.user_id) return;
    void this.loadProfilePosts(this.profile.user_id);
  }

  private handleProfilePostDeleteEvent(event: PostDeleteEvent): void {
    if (!this.profile || event.author_id !== this.profile.user_id) return;
    const next = this.profilePosts.filter((post) => post.id !== event.id);
    if (next.length !== this.profilePosts.length) {
      this.profilePosts = next;
      if (this.editingPostId === event.id) this.cancelPostEdit();
      if (this.openPostMenuId === event.id) this.openPostMenuId = null;
      if (this.confirmDeletePostId === event.id) this.confirmDeletePostId = null;
      this.forceUi();
    }
  }

  private applyProfilePostUpdate(post: CountryPost): void {
    const index = this.profilePosts.findIndex((existing) => existing.id === post.id);
    if (index >= 0) {
      const next = [...this.profilePosts];
      next[index] = post;
      this.profilePosts = this.sortPostsDesc(next);
      this.forceUi();
      return;
    }
    this.profilePosts = this.sortPostsDesc([post, ...this.profilePosts]);
    this.forceUi();
  }

  visibilityLabel(value: string): string {
    const normalized = String(value || '').toLowerCase();
    if (normalized === 'private') return 'Only me';
    if (normalized === 'followers') return 'Followers';
    return 'Public';
  }

  visibilityIcon(value: string): string {
    const normalized = String(value || '').toLowerCase();
    if (normalized === 'private') return '\u{1F512}';
    if (normalized === 'followers') return '\u{1F512}';
    return '\u{1F512}';
  }

  startPostEdit(post: CountryPost): void {
    if (!this.isOwner) return;
    this.openPostMenuId = null;
    this.confirmDeletePostId = null;
    this.editingPostId = post.id;
    this.editPostTitle = post.title ?? '';
    this.editPostBody = post.body ?? '';
    const visibility = post.visibility === 'country' ? 'public' : post.visibility;
    this.editPostVisibility =
      visibility === 'followers' || visibility === 'private' ? visibility : 'public';
    this.postEditError = '';
    this.forceUi();
  }

  cancelPostEdit(): void {
    this.editingPostId = null;
    this.editPostTitle = '';
    this.editPostBody = '';
    this.editPostVisibility = 'public';
    this.postEditError = '';
    this.openPostMenuId = null;
    this.confirmDeletePostId = null;
    this.forceUi();
  }

  async savePostEdit(post: CountryPost): Promise<void> {
    if (!this.isOwner || this.postEditBusy) return;
    const body = this.editPostBody.trim();
    if (!body) {
      this.postEditError = 'Body is required.';
      this.forceUi();
      return;
    }

    this.postEditBusy = true;
    this.postEditError = '';
    this.forceUi();

    try {
      const updated = await this.posts.updatePost(post.id, {
        title: this.editPostTitle.trim() || null,
        body,
        visibility: this.editPostVisibility,
      });
      this.applyProfilePostUpdate(updated);
      this.cancelPostEdit();
    } catch (e: any) {
      this.postEditError = e?.message ?? String(e);
    } finally {
      this.postEditBusy = false;
      this.forceUi();
    }
  }

  togglePostMenu(postId: string, event?: Event): void {
    event?.stopPropagation();
    if (this.openPostMenuId === postId) {
      this.openPostMenuId = null;
      this.confirmDeletePostId = null;
      this.reportingPostId = null;
    } else {
      this.openPostMenuId = postId;
      this.confirmDeletePostId = null;
      this.reportingPostId = null;
    }
    this.reportReason = '';
    this.reportError = '';
    this.reportFeedback = '';
    this.forceUi();
  }

  requestPostDelete(post: CountryPost): void {
    if (!this.isOwner) return;
    this.confirmDeletePostId = post.id;
    this.reportingPostId = null;
    this.reportReason = '';
    this.reportError = '';
    this.reportFeedback = '';
    this.forceUi();
  }

  cancelPostDelete(): void {
    this.confirmDeletePostId = null;
    this.forceUi();
  }

  async deletePost(post: CountryPost): Promise<void> {
    if (!this.isOwner || this.postEditBusy) return;
    this.openPostMenuId = null;
    this.confirmDeletePostId = null;
    this.postEditBusy = true;
    this.postEditError = '';
    this.forceUi();

    try {
      const deleted = await this.posts.deletePost(post.id, {
        country_code: post.country_code ?? null,
        author_id: post.author_id ?? null,
      });
      if (deleted) {
        this.profilePosts = this.profilePosts.filter((existing) => existing.id !== post.id);
        if (this.editingPostId === post.id) this.cancelPostEdit();
      }
    } catch (e: any) {
      this.postEditError = e?.message ?? String(e);
    } finally {
      this.postEditBusy = false;
      this.forceUi();
    }
  }

  recordView(post: CountryPost): void {
    if (!post?.id || this.viewedPostIds.has(post.id)) return;
    this.viewedPostIds.add(post.id);
    void this.posts.recordView(post);
    this.forceUi();
  }

  async togglePostLike(post: CountryPost): Promise<void> {
    if (!this.meId || !post?.id) {
      this.postActionError[post.id] = 'Sign in to like posts.';
      this.forceUi();
      return;
    }
    if (this.likeBusy[post.id]) return;
    this.likeBusy[post.id] = true;
    this.postActionError[post.id] = '';
    this.forceUi();

    try {
      const updated = post.liked_by_me
        ? await this.posts.unlikePost(post.id)
        : await this.posts.likePost(post.id);
      this.applyProfilePostUpdate(updated);
      if (this.likeOpen[post.id]) {
        void this.loadLikes(post.id);
      }
    } catch (e: any) {
      this.postActionError[post.id] = e?.message ?? String(e);
    } finally {
      this.likeBusy[post.id] = false;
      this.forceUi();
    }
  }

  toggleLikes(postId: string): void {
    if (!postId) return;
    const next = !this.likeOpen[postId];
    this.likeOpen[postId] = next;
    if (next && !this.likeItems[postId] && !this.likeLoading[postId]) {
      void this.loadLikes(postId);
    }
    this.forceUi();
  }

  private async loadLikes(postId: string): Promise<void> {
    if (!postId) return;
    this.likeLoading[postId] = true;
    this.likeErrors[postId] = '';
    this.forceUi();

    try {
      const likes = await this.posts.listLikes(postId, 40);
      this.likeItems[postId] = likes;
    } catch (e: any) {
      this.likeErrors[postId] = e?.message ?? String(e);
    } finally {
      this.likeLoading[postId] = false;
      this.forceUi();
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
    this.forceUi();
  }

  private async loadComments(postId: string): Promise<void> {
    if (!postId) return;
    this.commentLoading[postId] = true;
    this.commentErrors[postId] = '';
    this.forceUi();

    try {
      const comments = await this.posts.listComments(postId, 40);
      this.commentItems[postId] = comments;
      this.rebuildCommentThread(postId);
    } catch (e: any) {
      this.commentErrors[postId] = e?.message ?? String(e);
    } finally {
      this.commentLoading[postId] = false;
      this.forceUi();
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
    this.forceUi();
  }

  cancelCommentReply(postId: string): void {
    if (!postId) return;
    this.commentReplyTarget[postId] = null;
    this.forceUi();
  }

  async toggleCommentLike(postId: string, comment: PostComment): Promise<void> {
    if (!postId || !comment?.id) return;
    if (!this.meId) {
      this.commentErrors[postId] = 'Sign in to like comments.';
      this.forceUi();
      return;
    }

    const perPost = { ...(this.commentLikeBusy[postId] ?? {}) };
    if (perPost[comment.id]) return;
    perPost[comment.id] = true;
    this.commentLikeBusy[postId] = perPost;
    this.commentErrors[postId] = '';
    this.forceUi();

    try {
      const updated = comment.liked_by_me
        ? await this.posts.unlikeComment(comment.id)
        : await this.posts.likeComment(comment.id);
      this.applyCommentUpdate(postId, updated);
    } catch (e: any) {
      this.commentErrors[postId] = e?.message ?? String(e);
    } finally {
      this.commentLikeBusy[postId] = {
        ...perPost,
        [comment.id]: false,
      };
      this.forceUi();
    }
  }

  async submitComment(post: CountryPost): Promise<void> {
    if (!post?.id) return;
    if (!this.meId) {
      this.commentErrors[post.id] = 'Sign in to comment.';
      this.forceUi();
      return;
    }

    const draft = (this.commentDrafts[post.id] ?? '').trim();
    if (!draft) {
      this.commentErrors[post.id] = 'Write something before commenting.';
      this.forceUi();
      return;
    }

    if (this.commentBusy[post.id]) return;
    this.commentBusy[post.id] = true;
    this.commentErrors[post.id] = '';
    this.forceUi();

    try {
      const parentId = this.commentReplyTarget[post.id]?.commentId ?? null;
      const comment = await this.posts.addComment(post.id, draft, parentId);
      this.applyCommentUpdate(post.id, comment);
      this.commentDrafts[post.id] = '';
      this.commentReplyTarget[post.id] = null;
      const updated = { ...post, comment_count: post.comment_count + 1 };
      this.applyProfilePostUpdate(updated);
    } catch (e: any) {
      this.commentErrors[post.id] = e?.message ?? String(e);
    } finally {
      this.commentBusy[post.id] = false;
      this.forceUi();
    }
  }

  toggleReport(postId: string): void {
    if (!postId) return;
    if (this.reportingPostId === postId) {
      this.cancelReport();
      return;
    }
    this.reportingPostId = postId;
    this.reportReason = '';
    this.reportError = '';
    this.reportFeedback = '';
    this.confirmDeletePostId = null;
    this.forceUi();
  }

  cancelReport(): void {
    this.reportingPostId = null;
    this.reportReason = '';
    this.reportError = '';
    this.reportFeedback = '';
    this.forceUi();
  }

  async submitReport(post: CountryPost): Promise<void> {
    if (!post?.id) return;
    if (!this.meId) {
      this.reportError = 'Sign in to report posts.';
      this.forceUi();
      return;
    }

    const reason = this.reportReason.trim();
    if (!reason) {
      this.reportError = 'Tell us what is wrong.';
      this.forceUi();
      return;
    }

    if (this.reportBusy) return;
    this.reportBusy = true;
    this.reportError = '';
    this.reportFeedback = '';
    this.forceUi();

    try {
      await this.posts.reportPost(post.id, reason);
      this.reportFeedback = 'Report sent.';
      this.reportReason = '';
      setTimeout(() => {
        if (this.reportingPostId === post.id) {
          this.reportingPostId = null;
          this.openPostMenuId = null;
          this.reportFeedback = '';
          this.forceUi();
        }
      }, 900);
    } catch (e: any) {
      this.reportError = e?.message ?? String(e);
    } finally {
      this.reportBusy = false;
      this.forceUi();
    }
  }

  trackProfilePostById(index: number, post: CountryPost): string {
    return post?.id ?? String(index);
  }

  private sortPostsDesc(posts: CountryPost[]): CountryPost[] {
    return [...posts].sort((a, b) => {
      return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
    });
  }

  private async cropAvatarToSquare(file: File): Promise<File> {
    const type = (file.type || '').toLowerCase();
    if (type === 'image/gif') throw new Error('GIF avatars are disabled.');
    if (!type.startsWith('image/')) throw new Error('Please choose an image file.');

    const outType =
      type === 'image/png' || type === 'image/webp' ? 'image/png' : 'image/jpeg';
    const outExt = outType === 'image/png' ? 'png' : 'jpg';

    let bitmap: ImageBitmap | null = null;
    let width = 0;
    let height = 0;
    try {
      bitmap = await createImageBitmap(file);
      width = bitmap.width;
      height = bitmap.height;
    } catch {
      bitmap = null;
    }

    const canvas = document.createElement('canvas');
    canvas.width = this.AVATAR_OUT_SIZE;
    canvas.height = this.AVATAR_OUT_SIZE;

    const ctx = canvas.getContext('2d', { alpha: true });
    if (!ctx) throw new Error('Canvas not supported.');

    (ctx as any).imageSmoothingEnabled = true;
    (ctx as any).imageSmoothingQuality = 'high';

    ctx.clearRect(0, 0, canvas.width, canvas.height);
    if (bitmap) {
      const side = Math.min(width, height);
      const sx = Math.floor((width - side) / 2);
      const sy = Math.floor((height - side) / 2);
      ctx.drawImage(bitmap, sx, sy, side, side, 0, 0, canvas.width, canvas.height);
      bitmap.close?.();
    } else {
      const img = await new Promise<HTMLImageElement>((resolve, reject) => {
        const el = new Image();
        el.onload = () => resolve(el);
        el.onerror = () => reject(new Error('Image decode failed.'));
        el.src = URL.createObjectURL(file);
      });
      const side = Math.min(img.naturalWidth, img.naturalHeight);
      const sx = Math.floor((img.naturalWidth - side) / 2);
      const sy = Math.floor((img.naturalHeight - side) / 2);
      ctx.drawImage(img, sx, sy, side, side, 0, 0, canvas.width, canvas.height);
      try { URL.revokeObjectURL(img.src); } catch {}
    }

    const blob: Blob = await new Promise((resolve, reject) => {
      canvas.toBlob(
        (b) => (b ? resolve(b) : reject(new Error('Failed to crop image.'))),
        outType,
        outType === 'image/jpeg' ? 0.92 : undefined
      );
    });

    return new File([blob], `avatar.${outExt}`, { type: outType });
  }

  openImageLightbox(url: string | null): void {
    const next = String(url || '').trim();
    if (!next) return;
    this.lightboxUrl = next;
    this.forceUi();
  }

  closeImageLightbox(): void {
    if (!this.lightboxUrl) return;
    this.lightboxUrl = null;
    this.forceUi();
  }

  private forceUi(): void {
    this.zone.run(() => this.cdr.detectChanges());
  }

  isPostExpanded(postId: string): boolean {
    return this.expandedPosts.has(postId);
  }

  isPostExpandable(post: CountryPost): boolean {
    if (!post) return false;
    const text = [post.title, post.body, post.media_caption]
      .filter((value) => !!value)
      .join(' ')
      .trim();
    return text.length > this.POST_TEXT_LIMIT;
  }

  togglePostExpanded(postId: string): void {
    if (!postId) return;
    if (this.expandedPosts.has(postId)) {
      this.expandedPosts.delete(postId);
    } else {
      this.expandedPosts.add(postId);
    }
    this.forceUi();
  }
}





