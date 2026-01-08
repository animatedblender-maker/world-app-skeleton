import { AfterViewInit, Component, ChangeDetectorRef, NgZone, OnDestroy, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router } from '@angular/router';
import { Subscription } from 'rxjs';

import { CountriesService, type CountryModel } from '../data/countries.service';
import { GlobeService } from '../globe/globe.service';
import { UiStateService } from '../state/ui-state.service';
import { SearchService } from '../search/search.service';
import { AuthService } from '../core/services/auth.service';
import { GraphqlService } from '../core/services/graphql.service';
import { MediaService } from '../core/services/media.service';
import { ProfileService, type Profile } from '../core/services/profile.service';
import { LocationService } from '../core/services/location.service';
import { PresenceService, type PresenceSnapshot } from '../core/services/presence.service';
import { PostsService } from '../core/services/posts.service';
import { FollowService } from '../core/services/follow.service';
import { NotificationsService, type NotificationItem } from '../core/services/notifications.service';
import { NotificationEventsService } from '../core/services/notification-events.service';
import {
  PostEventsService,
  type PostInsertEvent,
  type PostUpdateEvent,
  type PostDeleteEvent,
} from '../core/services/post-events.service';
import { CountryPost, PostComment, PostLike } from '../core/models/post.model';

type Panel = 'presence' | 'posts' | 'notifications' | null;
type CountryTab = 'posts' | 'stats' | 'media';
type SearchTab = 'people' | 'travel';
type RouteState = {
  country: string | null;
  tab: CountryTab | null;
  panel: Exclude<Panel, null> | null;
};

@Component({
  selector: 'app-globe-page',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="top-overlay">
      <div class="overlay-inner">
        <div class="top-actions">
          <button *ngIf="selectedCountry" class="ghost-btn" type="button" (click)="clearSelectedCountry()">
            Return to globe
          </button>
          <div class="tab-row">
            <button
              *ngFor="let tab of searchTabs"
              type="button"
              class="tab"
              [class.active]="tab.id === activeTab"
              (click)="setActiveTab(tab.id)"
            >
              {{ tab.label }}
            </button>
          </div>
        </div>
        <div class="search-control">
          <input
            type="text"
            [placeholder]="activeTab === 'people' ? 'Search @handle, display name, or ID' : 'Search countries...'"
            autocomplete="off"
            [(ngModel)]="searchInputValue"
            (ngModelChange)="onUnifiedSearchInput($event)"
            (keydown)="handleSearchKeydown($event)"
            name="globalSearch"
          />
          <div class="user-loader" *ngIf="userSuggestionsLoading"></div>
          <div class="tab-banner" *ngIf="activeTab !== 'people'">
            {{ activeTab === 'travel' ? 'Travel search still improving.' : 'More search verticals soon.' }}
          </div>
          <div class="user-suggestions" *ngIf="activeTab === 'people' && userSuggestions.length">
            <button
              type="button"
              class="user-suggestion"
              *ngFor="let profile of userSuggestions"
              (click)="selectUserSuggestion(profile)"
            >
              <div class="suggestion-avatar">
                <img *ngIf="profile.avatar_url" [src]="profile.avatar_url" alt="avatar" />
                <span *ngIf="!profile.avatar_url">
                  {{ (profile.display_name || profile.username || 'U').slice(0, 2).toUpperCase() }}
                </span>
              </div>
              <div class="suggestion-info">
                <div class="profile-name">{{ profile.display_name || profile.username || 'Member' }}</div>
                <div class="profile-handle">@{{ profile.username || profile.user_id }}</div>
              </div>
            </button>
          </div>
          <div class="country-suggestions" *ngIf="activeTab === 'travel' && countrySuggestions.length">
            <div
              class="country-option"
              *ngFor="let country of countrySuggestions"
              (click)="focusCountry(country)"
              role="button"
              tabindex="0"
              (keyup.enter)="focusCountry(country)"
            >
              <span>{{ country.name }}</span>
              <small>{{ country.code || country.name }}</small>
            </div>
          </div>
          <div class="user-search-error" *ngIf="userSearchError && activeTab === 'people'">
            {{ userSearchError }}
          </div>
        </div>
      </div>
    </div>

    <!-- ✅ Ocean map ALWAYS full background -->
    <div id="globe" class="globe-bg"></div>

    <!-- ✅ Foreground layout that appears on focus (doesn't replace ocean background) -->
    <div class="stage" [class.focus]="!!selectedCountry">
      <div class="map-pane" *ngIf="selectedCountry">
        <div class="map-glass">
          <!-- left info block -->
          <div class="left-info">
            <div class="li-title">{{ selectedCountry!.name }}</div>
            <div class="li-sub">{{ selectedCountry!.code || '—' }}</div>

            <div class="li-box">
              <div class="li-row">
                <span class="k">ONLINE</span>
                <span class="v">{{ localOnline ?? 0 }}</span>
              </div>
              <div class="li-row">
                <span class="k">TOTAL</span>
                <span class="v">{{ localTotal ?? 0 }}</span>
              </div>
              <div class="li-hint">Country analytics will live here.</div>
            </div>
          </div>
        </div>
      </div>

      <!-- RIGHT: Main pane (expensive white card) -->
      <div class="main-pane" *ngIf="selectedCountry">
        <div class="main-card white-card">
          <div class="main-head">
            <div class="mh-title">COUNTRY FEED</div>
            <div class="mh-sub">{{ selectedCountry.name }} • public space</div>
          </div>

          <div class="tabs">
            <button class="tab" [class.active]="countryTab==='posts'" (click)="setCountryTab('posts')">POSTS</button>
            <button class="tab" [class.active]="countryTab==='stats'" (click)="setCountryTab('stats')">STATS</button>
            <button class="tab" [class.active]="countryTab==='media'" (click)="setCountryTab('media')">MEDIA</button>
          </div>

          <div class="tab-body">
            <ng-container [ngSwitch]="countryTab">
              <div *ngSwitchCase="'posts'" class="posts-pane">
                <div class="composer" *ngIf="profile && selectedCountry">
                  <div class="composer-row">
                    <div class="composer-avatar">
                      <img
                        *ngIf="profileAvatar"
                        [src]="profileAvatar"
                        alt="me"
                      />
                      <div class="composer-initials" *ngIf="!profileAvatar">
                        {{ composerInitial }}
                      </div>
                    </div>
                    <div class="composer-main">
                      <div class="composer-top">
                        <div>
                          <div class="composer-title">Share with {{ selectedCountry.name }}</div>
                          <div class="composer-hint" *ngIf="canPostHere">
                            What is happening where you are? Add your experience to the collective.
                          </div>
                          <div class="composer-hint" *ngIf="!canPostHere">
                            Posts publish to {{ profile!.country_name || 'your country' }}. Switch to the country where you post from to post.
                          </div>
                        </div>
                        <div class="composer-cta">
                          <button
                            *ngIf="canPostHere && composerOpen"
                            class="pill-link ghost"
                            type="button"
                            (click)="composerOpen = false"
                          >
                            Cancel
                          </button>
                          <button
                            *ngIf="!canPostHere"
                            class="pill-link"
                            type="button"
                            (click)="clearSelectedCountry()"
                          >
                            GO TO MY COUNTRY
                          </button>
                        </div>
                      </div>
                      <button
                        class="composer-trigger"
                        type="button"
                        *ngIf="canPostHere && !composerOpen"
                        (click)="composerOpen = true"
                      >
                        What's happening in {{ selectedCountry.name }}?
                      </button>
                      <div class="composer-note" *ngIf="!canPostHere">
                        You can read posts in {{ selectedCountry.name }}, but only share to the country where you are located.
                      </div>
                      <ng-container *ngIf="composerOpen && canPostHere">
                        <input
                          class="composer-input"
                          placeholder="Add a headline (optional)"
                          [(ngModel)]="newPostTitle"
                        />
                        <textarea
                          class="composer-textarea"
                          rows="3"
                          maxlength="5000"
                          placeholder="Share a story from {{ profile!.country_name || 'your home' }}..."
                          [(ngModel)]="newPostBody"
                        ></textarea>
                      </ng-container>
                    </div>
                  </div>
                  <div class="composer-actions" *ngIf="composerOpen && canPostHere">
                    <button class="btn" type="button" (click)="submitPost()" [disabled]="postBusy || !canPostHere">
                      {{ postBusy ? 'Posting…' : 'Post' }}
                    </button>
                    <div
                      class="composer-status"
                      *ngIf="postComposerError || postFeedback"
                      [class.error]="!!postComposerError"
                    >
                      {{ postComposerError || postFeedback }}
                    </div>
                  </div>
                </div>

                <div class="posts-state" *ngIf="postsLoading">Loading posts…</div>
                <div class="posts-state error" *ngIf="!postsLoading && postsError">{{ postsError }}</div>

                <div class="posts-list" *ngIf="!postsLoading && !postsError">
                  <div class="posts-empty" *ngIf="!posts.length">No posts yet.</div>
                  <div
                    class="post-card"
                    [class.post-highlight]="highlightedPostId === post.id"
                    [attr.id]="'post-' + post.id"
                    *ngFor="let post of posts"
                  >
                    <div class="post-author">
                      <div
                        class="author-core"
                        [class.clickable]="!!post.author"
                        role="button"
                        tabindex="0"
                        (click)="openAuthorProfile(post.author); $event.stopPropagation()"
                        (keyup.enter)="openAuthorProfile(post.author); $event.stopPropagation()"
                      >
                        <div class="author-avatar">
                          <img
                            *ngIf="post.author?.avatar_url"
                            [src]="post.author?.avatar_url"
                            alt="avatar"
                          />
                          <div class="author-initials" *ngIf="!post.author?.avatar_url">
                            {{ (post.author?.display_name || post.author?.username || 'User').slice(0, 2).toUpperCase() }}
                          </div>
                        </div>
                        <div class="author-info">
                          <div class="author-name">{{ post.author?.display_name || post.author?.username || 'Member' }}</div>
                          <div class="author-meta">
                            @{{ post.author?.username || 'user' }} · {{ post.created_at | date: 'mediumDate' }}
                            <span class="post-visibility" *ngIf="post.visibility !== 'public' && post.visibility !== 'country'">
                              · {{ visibilityLabel(post.visibility) }}
                            </span>
                          </div>
                        </div>
                      </div>
                      <button
                        *ngIf="meId && !isAuthorSelf(post.author_id)"
                        class="follow-chip"
                        type="button"
                        [class.following]="isFollowingAuthor(post.author_id)"
                        (click)="toggleFollowAuthor(post.author_id)"
                        [disabled]="followBusyFor(post.author_id)"
                      >
                        {{ isFollowingAuthor(post.author_id) ? 'Following' : 'Follow' }}
                      </button>
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
                          <ng-container *ngIf="isAuthorSelf(post.author_id); else reportMenu">
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
                      <p>{{ post.body }}</p>
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
                          (click)="openAuthorProfile(like.user); $event.stopPropagation()"
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
                        <div class="comment-empty" *ngIf="!(commentItems[post.id]?.length)">No comments yet.</div>
                        <div class="comment" *ngFor="let comment of commentItems[post.id]">
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
                          </div>
                        </div>
                      </div>
                      <div class="comment-compose" *ngIf="meId; else commentSignIn">
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
                  </div>
                </div>
              </div>

              <div *ngSwitchCase="'stats'" class="placeholder light">
                <div class="ph-title">Stats (later)</div>
                <div class="ph-sub">Country analytics panel will live here.</div>
              </div>

              <div *ngSwitchCase="'media'" class="placeholder light">
                <div class="ph-title">Media (later)</div>
                <div class="ph-sub">Images / videos / curated content later.</div>
              </div>
            </ng-container>
          </div>
        </div>
      </div>
    </div>

    <!-- ✅ Stats pill back to showing local line again -->
    <div class="stats-pill">
      <div class="pill-row">
        <small>Total users: <b>{{ totalUsers ?? '—' }}</b></small>
        <small>Online now: <b>{{ onlineUsers ?? '—' }}</b></small>
      </div>

      <div class="pill-row" *ngIf="selectedCountry">
        <small class="muted">
          Local ({{ selectedCountry.name }}{{ selectedCountry.code ? ' (' + selectedCountry.code + ')' : '' }}):
          <b>{{ localOnline ?? 0 }}</b> online /
          <b>{{ localTotal ?? 0 }}</b> total
        </small>
      </div>

      <div class="pill-row">
        <small id="heartbeatState">{{ heartbeatText || '—' }}</small>
      </div>

      <div class="pill-row">
        <small id="authState">
          {{ userEmail ? ('Logged in: ' + userEmail) : 'Logged out' }}
        </small>
      </div>

      <div class="pill-row" *ngIf="loadingProfile">
        <small style="opacity:.75">Loading profile…</small>
      </div>
      <div class="pill-row" *ngIf="profileError">
        <small style="color:#ff8b8b; font-weight:800; letter-spacing:.08em;">
          {{ profileError }}
        </small>
      </div>
    </div>

    <div class="node-backdrop" *ngIf="menuOpen" (click)="closeMenu()"></div>

    <!-- ✅ Avatar orb overlay fixed (restored) -->
    <div class="user-node">
      <button class="node-bell" type="button" (click)="openPanel('notifications')" [class.pulse]="bellPulse">
        🔔
        <span class="bell-badge" *ngIf="notificationsUnreadCount" [class.pulse]="bellPulse">{{ notificationsUnreadCount }}</span>
      </button>

      <button class="node-orb" type="button" (click)="toggleMenu()" [attr.aria-expanded]="menuOpen">
        <ng-container *ngIf="nodeAvatarUrl; else initialsTpl">
          <img
            class="orb-img"
            [src]="nodeAvatarUrl"
            alt="avatar"
            [style.transform]="nodeAvatarTransform"
          />
        </ng-container>

        <ng-template #initialsTpl>
          <div class="orb-initials">{{ initials }}</div>
        </ng-template>

        <span class="orb-pulse"></span>
        <span class="orb-ring"></span>
      </button>

      <div class="node-menu" *ngIf="menuOpen" (click)="$event.stopPropagation()">
        <div class="node-head">
          <div class="node-title">YOUR NODE</div>
          <div class="node-sub">{{ profile?.display_name || 'Unnamed' }}</div>
          <div class="node-sub2">{{ userEmail || '—' }}</div>

          <div class="node-sub2" *ngIf="profileError" style="color: rgba(255,120,120,0.95); opacity:1;">
            {{ profileError }}
          </div>
        </div>

        <div class="node-actions">
          <button class="node-btn" type="button" (click)="goToMe()">
            <span class="dot"></span><span>MY PROFILE</span>
          </button>
          <button class="node-btn" type="button" (click)="openPanel('presence')">
            <span class="dot"></span><span>MY PRESENCE</span>
          </button>

          <button class="node-btn" type="button" (click)="openPanel('posts')">
            <span class="dot"></span><span>MY POSTS</span>
          </button>

          <button class="node-btn danger" type="button" (click)="logout()">
            <span class="dot"></span><span>LOGOUT</span>
          </button>
        </div>

        <div class="node-foot">
          <button class="ghost" type="button" (click)="closeMenu()">CLOSE</button>
        </div>
      </div>
    </div>

    <!-- ✅ Panel overlay (profile editor restored fully) -->
    <div class="overlay" *ngIf="panel" (click)="closePanel()">
      <div class="panel" (click)="$event.stopPropagation()">
        <div class="panel-head">
          <div class="panel-title">
            {{
              panel === 'presence'
                ? 'MY PRESENCE'
                : panel === 'posts'
                  ? 'MY POSTS'
                  : 'NOTIFICATIONS'
            }}
          </div>
          <button class="x" type="button" (click)="closePanel()">×</button>
        </div>

        <div class="panel-body" *ngIf="panel === 'presence'">
          <div class="presence-box">
            <div class="presence-line"><span class="k">STATUS</span><span class="v">ONLINE</span></div>
            <div class="presence-line"><span class="k">COUNTRY</span><span class="v">{{ profile?.country_name || '—' }}</span></div>
            <div class="presence-line"><span class="k">CODE</span><span class="v">{{ (profile?.country_code || '—') }}</span></div>
            <div class="presence-line"><span class="k">CITY</span><span class="v">{{ cityName }}</span></div>
          </div>
        </div>

        <div class="panel-body" *ngIf="panel === 'posts'">
          <div class="presence-box">
            <div class="presence-line"><span class="k">POSTS</span><span class="v">0</span></div>
            <div class="presence-line"><span class="k">STATE</span><span class="v">COMING SOON</span></div>
          </div>
        </div>

        <div class="panel-body" *ngIf="panel === 'notifications'">
          <div class="notif-actions">
            <div class="notif-count">Unread: {{ notificationsUnreadCount }}</div>
            <button
              class="ghost"
              type="button"
              (click)="markAllNotificationsRead()"
              [disabled]="notificationsLoading || notificationsActionBusy || !notifications.length"
            >
              Mark all read
            </button>
          </div>
          <div class="notif-state" *ngIf="notificationsLoading">Loading notifications…</div>
          <div class="notif-state error" *ngIf="!notificationsLoading && notificationsError">
            {{ notificationsError }}
          </div>
          <div class="notif-list" *ngIf="!notificationsLoading && !notificationsError">
            <div class="notif-empty" *ngIf="!notifications.length">No notifications yet.</div>
            <button
              class="notif-item"
              type="button"
              *ngFor="let notif of notifications"
              (click)="openNotification(notif)"
            >
              <div class="notif-avatar">
                <img *ngIf="notif.actor?.avatar_url" [src]="notif.actor?.avatar_url" alt="avatar" />
                <span *ngIf="!notif.actor?.avatar_url">
                  {{ (notif.actor?.display_name || notif.actor?.username || 'U').slice(0, 2).toUpperCase() }}
                </span>
              </div>
              <div class="notif-body">
                <div class="notif-line">
                  <span class="notif-name">{{ notificationActorName(notif) }}</span>
                  <span class="notif-text">{{ notificationMessage(notif) }}</span>
                  <span class="notif-time">{{ formatDate(notif.created_at) }}</span>
                </div>
              </div>
              <span class="notif-unread" *ngIf="!notif.read_at"></span>
            </button>
          </div>
        </div>
      </div>
    </div>

  `,
  styles: [`
    /* =============== TOPBAR =============== */
    .top-overlay{
      position: fixed;
      top: 16px;
      left: 50%;
      transform: translateX(-50%);
      width: min(520px, calc(100vw - 48px));
      padding: 4px 10px;
      border-radius: 20px;
      background: rgba(5,9,20,0.25);
      border: 1px solid rgba(0,199,255,0.35);
      display:flex;
      justify-content:center;
      z-index: 12000;
      box-shadow: 0 10px 25px rgba(0,0,0,0.35);
      pointer-events:auto;
      backdrop-filter: blur(18px);
      gap: 4px;
    }
    .overlay-inner{
      width: 100%;
      display:flex;
      flex-direction:column;
      gap: 4px;
    }
    .top-actions{
      display:flex;
      align-items:center;
      justify-content:space-between;
      gap: 8px;
      font-size: 12px;
    }
    .ghost-btn{
      border: 1px solid rgba(255,255,255,0.4);
      background: transparent;
      color: white;
      border-radius: 999px;
      padding: 6px 14px;
      letter-spacing: 0.2em;
      font-size: 10px;
      text-transform: uppercase;
      cursor: pointer;
      opacity: 0.8;
    }
    .tab-row{
      display:flex;
      gap: 6px;
      flex-wrap: wrap;
    }
    .tab{
      border: 1px solid transparent;
      border-radius: 999px;
      padding: 6px 16px;
      letter-spacing: 0.2em;
      font-size: 10px;
      text-transform: uppercase;
      color: rgba(255,255,255,0.7);
      background: transparent;
      cursor: pointer;
      transition: background 0.2s ease, color 0.2s ease;
    }
    .tab:hover{
      background: rgba(255,255,255,0.08);
      color: rgba(255,255,255,0.9);
    }
    .tab.active{
      background: rgba(255,255,255,0.12);
      color: rgba(255,255,255,0.95);
    }
    .search-control{
      position: relative;
    }
    .search-control input{
      width: min(420px, 100%);
      border: none;
      border-radius: 14px;
      padding: 12px 14px;
      font-size: 14px;
      background: rgba(255,255,255,0.06);
      color: rgba(255,255,255,0.92);
      outline: none;
      font-weight: 500;
    }
    .search-control input:focus{
      box-shadow: 0 0 0 2px rgba(0,255,209,0.4);
    }
    .user-loader{
      position: absolute;
      top: 12px;
      right: 14px;
      width: 10px;
      height: 10px;
      border-radius: 50%;
      border: 2px solid rgba(255,255,255,0.6);
      border-top-color: rgba(255,255,255,0);
      animation: spin 0.9s linear infinite;
    }
    @keyframes spin{
      to { transform: rotate(360deg); }
    }
    .tab-banner{
      margin-top: 6px;
      font-size: 11px;
      color: rgba(255,255,255,0.75);
    }
    .user-suggestions,
    .country-suggestions{
      position:absolute;
      top: calc(100% + 8px);
      left: 0;
      right: 0;
      z-index: 12001;
      border-radius: 16px;
      border: 1px solid rgba(0,199,255,0.35);
      background: rgba(5,9,20,0.28);
      box-shadow: 0 20px 40px rgba(0,0,0,0.45);
      padding: 6px;
      display:grid;
      gap: 6px;
      overflow: hidden;
      backdrop-filter: blur(18px);
      -webkit-backdrop-filter: blur(18px);
      background-clip: padding-box;
    }
    .user-suggestion{
      display:flex;
      align-items:center;
      gap: 10px;
      border-radius: 12px;
      padding: 10px;
      border: 1px solid rgba(0,199,255,0.6);
      background: rgba(0,155,255,0.12);
      color: #fff;
      cursor: pointer;
      text-align:left;
    }
    .suggestion-avatar{
      width: 36px;
      height: 36px;
      border-radius: 50%;
      border: 1px solid rgba(255,255,255,0.12);
      display:grid;
      place-items:center;
      background: rgba(255,255,255,0.08);
      font-size: 12px;
      color: rgba(255,255,255,0.9);
    }
    .suggestion-avatar img{
      width: 100%;
      height: 100%;
      border-radius: 50%;
      object-fit: cover;
    }
    .suggestion-info{
      display:flex;
      flex-direction:column;
      gap: 2px;
    }
    .profile-name{
      font-weight: 700;
      font-size: 14px;
      color: #fff;
    }
    .profile-handle{
      font-size: 12px;
      opacity: 0.75;
      letter-spacing: 0.08em;
      color: rgba(255,255,255,0.75);
    }
    .user-search-error{
      margin-top: 6px;
      font-size: 12px;
      color: #ff7a93;
      letter-spacing: 0.08em;
    }
    .country-option{
      display:flex;
      justify-content:space-between;
      align-items:center;
      padding: 10px 14px;
      border-bottom: 1px solid rgba(255,255,255,0.08);
      cursor: pointer;
      transition: background 0.2s ease;
    }
    .country-option:last-child{
      border-bottom: none;
    }
    .country-option:hover{
      background: rgba(255,255,255,0.06);
    }
    .country-option span{
      font-weight: 600;
      color: #fff;
    }
    .country-option small{
      font-size: 11px;
      opacity: 0.6;
      letter-spacing: 0.1em;
      color: #fff;
    }
    .country-hint{
      margin-top: 10px;
      font-size: 12px;
      opacity: 0.6;
    }
    /* =============== MAP BG ALWAYS FULL =============== */
    .globe-bg{
      position: fixed;
      inset: 0;
      width: 100%;
      height: 100%;
      z-index: 1;
    }

    /* =============== FOREGROUND STAGE =============== */
    .stage{
      position: fixed;
      inset: 0;
      z-index: 5;
      pointer-events: none;
    }
    .stage.focus{
      pointer-events: none;
      padding-top: 150px; /* ✅ more space so search doesn't cover */
      padding-left: 16px;
      padding-right: 16px;
      padding-bottom: 16px;
      box-sizing: border-box;
      display: grid;
      grid-template-columns: min(420px, 34vw) 1fr;
      gap: 14px;
    }

    /* left pane is just overlay glass (map is still in background) */
    .map-pane{
      position: relative;
      min-height: 0;
    }
    .map-glass{
      position: relative;
      height: 100%;
      border-radius: 22px;
      border: 1px solid rgba(255,255,255,0.12);
      background: rgba(10,12,20,0.18);
      backdrop-filter: blur(10px);
      box-shadow: 0 30px 90px rgba(0,0,0,0.45);
      overflow: hidden;
      pointer-events: none;
    }

    /* visually "raise the map" slightly (the background stays fixed) */
    .stage.focus .globe-bg{
      transform: translateY(-10px);
    }

    .left-info{
      position: absolute;
      left: 12px;
      top: 12px;
      width: calc(100% - 24px);
      z-index: 6;
      pointer-events: none;
    }
    .li-title{ font-weight: 900; letter-spacing: .12em; font-size: 11px; color: rgba(255,255,255,0.94); text-transform: uppercase; }
    .li-sub{ margin-top: 2px; font-size: 11px; opacity: .75; color: rgba(255,255,255,0.86); font-weight: 800; letter-spacing: .08em; }
    .li-box{ margin-top: 10px; border-radius: 16px; background: rgba(10,12,20,0.40); border: 1px solid rgba(255,255,255,0.10); backdrop-filter: blur(10px); padding: 10px; }
    .li-row{ display:flex; justify-content:space-between; align-items:center; gap: 12px; margin-bottom: 8px; }
    .li-row .k{ opacity:.65; letter-spacing:.16em; font-weight: 900; font-size: 10px; color: rgba(255,255,255,0.86); }
    .li-row .v{ color: rgba(0,255,209,0.92); font-weight: 900; letter-spacing: .10em; font-size: 12px; }
    .li-hint{ margin-top: 4px; opacity: .72; font-size: 11px; color: rgba(255,255,255,0.86); line-height: 1.35; }

    .main-pane{
      pointer-events: auto;
      min-width: 0;
      min-height: 0;
    }

    .main-card{
      height: 100%;
      border-radius: 26px;
      padding: 16px;
      box-shadow: 0 30px 90px rgba(0,0,0,0.40);
      overflow: hidden;
      display:flex;
      flex-direction: column;
    }

    /* ✅ "expensive white" posts container */
    .white-card{
      background: rgba(245, 247, 250, 0.92);
      border: 1px solid rgba(0,0,0,0.08);
      backdrop-filter: blur(14px);
      color: rgba(10,12,18,0.90);
    }

    .main-head{ margin-bottom: 10px; }
    .mh-title{ font-weight: 900; letter-spacing: .16em; font-size: 12px; text-transform: uppercase; }
    .mh-sub{ margin-top: 4px; opacity: .72; font-weight: 800; letter-spacing: .08em; font-size: 12px; }

    .tabs{ display:flex; gap: 8px; margin: 12px 0; flex-wrap: wrap; }
    .tab{
      border: 1px solid rgba(0,0,0,0.10);
      background: rgba(255,255,255,0.70);
      color: rgba(10,12,18,0.86);
      padding: 10px 12px;
      border-radius: 14px;
      font-weight: 900;
      letter-spacing: .14em;
      font-size: 11px;
      cursor: pointer;
    }
    .tab.active{
      border-color: rgba(0,255,209,0.28);
      background: rgba(0,255,209,0.10);
      box-shadow: 0 0 0 1px rgba(0,255,209,0.12) inset;
    }

    .tab-body{ flex: 1; min-height: 0; overflow: auto; }
    .placeholder{ border-radius: 18px; padding: 14px; }
    .placeholder.light{
      border: 1px solid rgba(0,0,0,0.08);
      background: rgba(255,255,255,0.82);
    }
    .ph-title{ font-weight: 900; letter-spacing: .10em; font-size: 12px; text-transform: uppercase; }
    .ph-sub{ margin-top: 6px; opacity: .75; font-size: 12px; line-height: 1.4; }
    .posts-pane{ display:flex; flex-direction:column; gap:18px; }
    .composer{
      border-radius:20px;
      border:1px solid rgba(0,0,0,0.06);
      background:rgba(255,255,255,0.95);
      padding:16px;
      box-shadow:0 20px 60px rgba(0,0,0,0.10);
    }
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
    .composer-note{
      margin-top:10px;
      font-size:12px;
      opacity:0.72;
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
      color:rgba(10,12,18,0.9);
    }
    .composer-textarea{ min-height:90px; resize:vertical; }
    .composer-actions{ margin-top:12px; display:flex; align-items:center; gap:12px; flex-wrap:wrap; }
    .composer-status{ font-size:12px; font-weight:700; letter-spacing:0.08em; color:rgba(0,120,255,0.9); }
    .composer-status.error{ color:#ff6b81; }
    .posts-state{ font-size:13px; font-weight:700; opacity:0.7; }
    .posts-state.error{ color:#ff6b81; }
    .posts-list{ display:flex; flex-direction:column; gap:16px; }
    .posts-empty{ text-align:center; font-size:13px; opacity:0.65; }
    .post-card{
      position:relative;
      border-radius:20px;
      border:1px solid rgba(0,0,0,0.06);
      background:rgba(255,255,255,0.98);
      padding:16px;
      box-shadow:0 18px 60px rgba(0,0,0,0.15);
    }
    .post-author{
      display:flex;
      align-items:flex-start;
      gap:12px;
      flex-wrap:wrap;
    }
    .author-core{
      display:flex;
      align-items:center;
      gap:12px;
      flex:1;
      cursor:default;
    }
    .author-core.clickable{
      cursor:pointer;
    }
    .author-core:focus{
      outline:2px solid rgba(10,12,18,0.18);
      outline-offset:2px;
    }
    .author-avatar{
      width:42px;
      height:42px;
      border-radius:999px;
      overflow:hidden;
      background:rgba(245,247,250,0.95);
      border:1px solid rgba(0,0,0,0.08);
      box-shadow:0 10px 24px rgba(0,0,0,0.12);
      display:grid;
      place-items:center;
      color:rgba(10,12,18,0.8);
      font-weight:900;
      letter-spacing:0.08em;
    }
    .author-avatar img{ width:100%; height:100%; object-fit:cover; }
    .author-info{ flex:1; min-width:0; }
    .author-name{ font-weight:900; font-size:13px; letter-spacing:0.04em; }
    .author-meta{ font-size:12px; opacity:0.7; }
    .follow-chip{
      border:1px solid rgba(0,0,0,0.18);
      border-radius:999px;
      padding:6px 14px;
      background:transparent;
      color:rgba(0,0,0,0.75);
      font-size:11px;
      font-weight:900;
      letter-spacing:0.12em;
      text-transform:uppercase;
      cursor:pointer;
    }
    .follow-chip.following{
      background:rgba(10,12,18,0.06);
      color:rgba(10,12,18,0.78);
      border-color:rgba(0,0,0,0.12);
      box-shadow:none;
    }
    .follow-chip:disabled{ opacity:0.6; cursor:not-allowed; }
    .post-body{ margin-top:12px; font-size:14px; line-height:1.5; color:rgba(10,12,18,0.85); }
    .post-title{ font-weight:900; margin-bottom:6px; letter-spacing:0.06em; text-transform:uppercase; font-size:12px; }
    .post-visibility{ font-weight:800; font-size:10px; letter-spacing:0.16em; text-transform:uppercase; opacity:0.7; }
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
    .post-card.post-highlight{
      box-shadow:0 0 0 2px rgba(0,199,255,0.35), 0 18px 60px rgba(0,0,0,0.15);
    }
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

    /* =============== STATS PILL =============== */
    .stats-pill{
      position: fixed;
      left: 16px;
      bottom: 16px;
      z-index: 12000;
      width: min(380px, calc(100vw - 32px));
      border-radius: 16px;
      padding: 10px 12px;
      background: rgba(220, 228, 235, 0.88);
      border: 1px solid rgba(0,0,0,0.06);
      box-shadow: 0 18px 60px rgba(0,0,0,0.16);
      backdrop-filter: blur(10px);
      pointer-events: none;
    }
    .pill-row{ display:flex; gap: 12px; flex-wrap: wrap; align-items:center; }
    .pill-row small{ color: rgba(10,12,18,0.70); font-size: 12px; }
    .pill-row b{ color: rgba(10,12,18,0.86); }
    .muted{ color: rgba(10,12,18,0.62); }

    /* =============== AVATAR ORB + MENU (RESTORED) =============== */
    .node-backdrop{ position: fixed; inset: 0; z-index: 13000; background: transparent; }

    .user-node{
      position: fixed;
      top: 16px;
      right: 16px;
      z-index: 13010;
      user-select: none;
      pointer-events: auto;
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .node-orb{
      width: 44px;
      height: 44px;
      border-radius: 999px;
      border: 1px solid rgba(0,255,209,0.28);
      background: rgba(10,12,20,0.55);
      backdrop-filter: blur(12px);
      box-shadow: 0 18px 60px rgba(0,0,0,0.45),
                  0 0 0 1px rgba(0,255,209,0.18) inset,
                  0 0 38px rgba(0,255,209,0.12);
      position: relative;
      overflow: hidden;
      cursor: pointer;
      padding: 0;
      display:grid;
      place-items:center;
      pointer-events:auto;
    }
    .orb-img{ width: 120%; height: 120%; object-fit: cover; border-radius: 999px; will-change: transform; transform: translate3d(0,0,0); transition: transform 90ms linear; }
    .orb-initials{ font-weight: 900; letter-spacing: 0.12em; font-size: 11px; color: rgba(255,255,255,0.92); text-transform: uppercase; }
    .orb-pulse{ position:absolute; inset:-8px; border-radius:999px; background: radial-gradient(circle at 50% 50%, rgba(0,255,209,0.16), transparent 60%); animation: pulse 2.8s ease-in-out infinite; pointer-events:none; }
    @keyframes pulse{ 0%,100% { transform: scale(0.98); opacity: .55; } 50% { transform: scale(1.06); opacity: .95; } }
    .orb-ring{ position:absolute; inset:-2px; border-radius:999px; background: conic-gradient(from 180deg, rgba(0,255,209,0.0), rgba(0,255,209,0.65), rgba(140,0,255,0.55), rgba(0,255,209,0.0)); filter: blur(10px); opacity: 0.35; pointer-events:none; }

    .node-menu{
      position: absolute;
      top: 52px;
      right: 0;
      width: 260px;
      border-radius: 22px;
      padding: 14px;
      background: rgba(10,12,20,0.62);
      border: 1px solid rgba(0,255,209,0.20);
      backdrop-filter: blur(14px);
      box-shadow: 0 30px 90px rgba(0,0,0,0.50);
      overflow:hidden;
      z-index: 13020;
      pointer-events:auto;
    }
    .node-menu::before{
      content:"";
      position:absolute;
      inset:-2px;
      border-radius: 24px;
      background: conic-gradient(from 180deg, rgba(0,255,209,0), rgba(0,255,209,0.55), rgba(140,0,255,0.45), rgba(0,255,209,0));
      filter: blur(14px);
      opacity: 0.22;
      pointer-events:none;
    }
    .node-menu > *{ position:relative; z-index:1; }
    .node-head{ margin-bottom: 10px; }
    .node-title{ font-weight: 900; letter-spacing: 0.18em; font-size: 12px; color: rgba(255,255,255,0.90); }
    .node-sub{ margin-top: 6px; font-weight: 800; letter-spacing: 0.08em; color: rgba(0,255,209,0.92); font-size: 12px; }
    .node-sub2{ margin-top: 3px; opacity: .68; font-size: 12px; color: rgba(255,255,255,0.84); }

    .node-actions{ display:grid; gap: 8px; margin-top: 10px; }

    .node-btn{
      width: 100%;
      border: 0;
      border-radius: 16px;
      padding: 12px 12px;
      cursor: pointer;
      background: rgba(255,255,255,0.06);
      color: rgba(255,255,255,0.86);
      display:flex;
      align-items:center;
      gap: 10px;
      letter-spacing: 0.14em;
      font-weight: 900;
      font-size: 11px;
      pointer-events:auto;
    }
    .node-badge{
      margin-left: auto;
      padding: 2px 8px;
      border-radius: 999px;
      background: rgba(255,255,255,0.12);
      border: 1px solid rgba(255,255,255,0.24);
      font-size: 10px;
      letter-spacing: 0.12em;
      font-weight: 900;
      color: rgba(255,255,255,0.92);
    }
    .node-btn:hover{ background: rgba(0,255,209,0.12); box-shadow: 0 0 0 1px rgba(0,255,209,0.20) inset, 0 0 24px rgba(0,255,209,0.10); }
    .node-btn .dot{ width: 8px; height: 8px; border-radius: 999px; background: rgba(0,255,209,0.92); box-shadow: 0 0 16px rgba(0,255,209,0.55); flex:0 0 auto; }
    .node-btn.danger .dot{ background: rgba(255,120,120,0.95); box-shadow: 0 0 16px rgba(255,120,120,0.45); }

    .node-bell{
      position: relative;
      width: 38px;
      height: 38px;
      border-radius: 999px;
      border: 1px solid rgba(0,255,209,0.20);
      background: rgba(10,12,20,0.55);
      backdrop-filter: blur(12px);
      box-shadow: 0 12px 35px rgba(0,0,0,0.4),
                  0 0 0 1px rgba(0,255,209,0.18) inset;
      color: rgba(255,255,255,0.95);
      display: grid;
      place-items: center;
      font-size: 18px;
      cursor: pointer;
      padding: 0;
    }
    .node-bell.pulse{
      animation: bellPulse 0.9s ease;
    }
    @keyframes bellPulse{
      0%{ transform: scale(1); }
      30%{ transform: scale(1.08); }
      60%{ transform: scale(0.98); }
      100%{ transform: scale(1); }
    }
    .node-bell:hover{
      box-shadow: 0 0 0 1px rgba(0,255,209,0.25) inset, 0 12px 35px rgba(0,0,0,0.45);
    }
    .bell-badge{
      position: absolute;
      top: -6px;
      left: -6px;
      min-width: 18px;
      height: 18px;
      padding: 0 6px;
      border-radius: 999px;
      background: rgba(255,120,120,0.98);
      color: rgba(8,10,14,0.95);
      font-size: 11px;
      font-weight: 900;
      display:flex;
      align-items:center;
      justify-content:center;
      letter-spacing: 0.02em;
      box-shadow: 0 0 10px rgba(255,120,120,0.55);
    }
    .bell-badge.pulse{
      animation: badgePop 0.7s ease;
    }
    @keyframes badgePop{
      0%{ transform: scale(1); }
      40%{ transform: scale(1.25); }
      70%{ transform: scale(0.95); }
      100%{ transform: scale(1); }
    }

    .node-foot{ margin-top: 10px; display:flex; justify-content:flex-end; }
    .ghost{ border: 0; background: transparent; color: rgba(0,255,209,0.92); font-weight: 900; letter-spacing: 0.14em; cursor: pointer; font-size: 11px; text-decoration: underline; }

    .node-btn-row{ display:flex; align-items:center; gap: 10px; }
    .node-btn-row .node-btn{ flex: 1; }
    .node-edit{
      border: 0;
      background: transparent;
      cursor: pointer;
      font-weight: 900;
      letter-spacing: .06em;
      font-size: 11px;
      opacity: .75;
      color: rgba(255,255,255,0.90);
      text-decoration: underline;
      padding: 10px 6px;
      pointer-events:auto;
    }
    .node-edit:hover{ opacity: 1; }

    /* =============== PANEL OVERLAY (PROFILE EDITOR) =============== */
    .overlay{
      position: fixed;
      inset: 0;
      background: rgba(0,0,0,0.35);
      backdrop-filter: blur(6px);
      z-index: 14000;
      display:grid;
      place-items:center;
      padding: 18px;
      pointer-events:auto;
    }
    .panel{
      width: min(620px, 94vw);
      border-radius: 26px;
      padding: 16px;
      background: rgba(10,12,20,0.60);
      border: 1px solid rgba(0,255,209,0.20);
      box-shadow: 0 30px 90px rgba(0,0,0,0.55), 0 0 50px rgba(0,255,209,0.10);
      backdrop-filter: blur(14px);
      color: rgba(255,255,255,0.92);
      position: relative;
      overflow:hidden;
    }
    .panel::before{
      content:"";
      position:absolute;
      inset:-2px;
      border-radius: 28px;
      background: conic-gradient(from 180deg, rgba(0,255,209,0), rgba(0,255,209,0.55), rgba(140,0,255,0.45), rgba(0,255,209,0));
      filter: blur(16px);
      opacity: 0.18;
      pointer-events:none;
    }
    .panel > *{ position:relative; z-index:1; }

    .panel-head{ display:flex; align-items:center; justify-content:space-between; margin-bottom: 12px; }
    .panel-title{ font-weight: 900; letter-spacing: 0.18em; font-size: 12px; }
    .x{ width: 38px; height: 38px; border-radius: 14px; border: 1px solid rgba(255,255,255,0.10); background: rgba(255,255,255,0.06); color: rgba(255,255,255,0.90); cursor: pointer; font-size: 18px; }
    .x:hover{ background: rgba(0,255,209,0.10); border-color: rgba(0,255,209,0.20); }

    .panel-body{ display:grid; gap: 12px; }
    .notif-actions{
      display:flex;
      justify-content:space-between;
      align-items:center;
      gap: 12px;
    }
    .notif-count{
      font-size: 11px;
      letter-spacing: 0.16em;
      font-weight: 900;
      opacity: 0.8;
    }
    .notif-state{ font-size: 12px; opacity: 0.75; }
    .notif-state.error{ color: rgba(255,120,120,0.95); }
    .notif-list{ display:grid; gap: 10px; }
    .notif-empty{ font-size: 12px; opacity: 0.65; text-align:center; }
    .notif-item{
      border: 1px solid rgba(255,255,255,0.10);
      background: rgba(255,255,255,0.06);
      border-radius: 18px;
      padding: 10px;
      display:flex;
      gap: 12px;
      align-items:center;
      text-align:left;
      cursor:pointer;
      color: rgba(255,255,255,0.92);
      position: relative;
    }
    .notif-item:hover{
      background: rgba(255,255,255,0.10);
    }
    .notif-avatar{
      width: 36px;
      height: 36px;
      border-radius: 999px;
      overflow: hidden;
      border: 1px solid rgba(255,255,255,0.14);
      background: rgba(255,255,255,0.08);
      display:grid;
      place-items:center;
      flex:0 0 auto;
      font-weight: 900;
      letter-spacing: 0.1em;
      font-size: 11px;
    }
    .notif-avatar img{ width:100%; height:100%; object-fit:cover; }
    .notif-body{ flex:1; min-width:0; }
    .notif-line{ display:flex; flex-wrap:wrap; gap: 6px; font-size: 12px; }
    .notif-name{ font-weight: 900; letter-spacing: 0.06em; }
    .notif-text{ opacity: 0.82; }
    .notif-time{ font-size: 11px; opacity: 0.6; margin-left: auto; }
    .notif-unread{
      width: 8px;
      height: 8px;
      border-radius: 999px;
      background: rgba(255,255,255,0.9);
      flex:0 0 auto;
      margin-left: 6px;
    }


    .field{ display:grid; gap: 8px; }
    .field label{ font-size: 11px; opacity: .72; letter-spacing: 0.14em; font-weight: 900; }
    .field input, .field textarea{ padding: 12px; border-radius: 16px; border: 1px solid rgba(255,255,255,0.12); background: rgba(0,0,0,0.28); color: rgba(255,255,255,0.92); outline:none; resize: none; }
    .field input:focus, .field textarea:focus{ border-color: rgba(0,255,209,0.35); box-shadow: 0 0 0 3px rgba(0,255,209,0.10); }
    .field input:disabled{ opacity: .65; cursor: not-allowed; }

    .row{ display:flex; align-items:center; gap: 12px; flex-wrap: wrap; margin-top: 2px; }
    .cta{ border:0; border-radius: 16px; padding: 12px 14px; cursor: pointer; background: linear-gradient(90deg, rgba(0,255,209,0.85), rgba(140,0,255,0.75)); color: rgba(6,8,14,0.96); font-weight: 900; letter-spacing: 0.16em; font-size: 12px; box-shadow: 0 18px 50px rgba(0,255,209,0.16); }
    .cta:disabled{ opacity:.6; cursor:not-allowed; }
    .msg{ font-size: 12px; opacity: .85; }

    .presence-box{ border-radius: 18px; border: 1px solid rgba(255,255,255,0.10); background: rgba(255,255,255,0.05); padding: 12px; display:grid; gap: 10px; }
    .presence-line{ display:flex; justify-content:space-between; gap: 12px; align-items:center; }
    .presence-line .k{ opacity:.65; letter-spacing:.16em; font-weight: 900; font-size: 11px; }
    .presence-line .v{ color: rgba(0,255,209,0.92); font-weight: 900; letter-spacing: .08em; font-size: 12px; }

  `],
})
export class GlobePageComponent implements OnInit, AfterViewInit, OnDestroy {
  menuOpen = false;
  panel: Panel = null;

  userEmail = '';
  profile: Profile | null = null;
  meId: string | null = null;

  loadingProfile = false;
  profileError = '';

  private locationRefreshTimer: number | null = null;
  private locationRefreshInFlight = false;
  private readonly LOCATION_REFRESH_MS = 10 * 60_000;

  selectedCountry: CountryModel | null = null;

  totalUsers: number | null = null;
  onlineUsers: number | null = null;
  heartbeatText = '';

  localTotal: number | null = null;
  localOnline: number | null = null;

  userSearchTerm = '';
  userSearchError = '';
  userSuggestions: Profile[] = [];
  userSuggestionsLoading = false;
  private userSuggestionTimer: number | null = null;

  countrySearchTerm = '';
  countrySuggestions: CountryModel[] = [];

  activeTab: SearchTab = 'travel';
  searchTabs: { id: SearchTab; label: string }[] = [
    { id: 'travel', label: 'Travel' },
    { id: 'people', label: 'People' },
  ];

  posts: CountryPost[] = [];
  postsLoading = false;
  postsError = '';
  newPostTitle = '';
  newPostBody = '';
  postBusy = false;
  postFeedback = '';
  postComposerError = '';
  editingPostId: string | null = null;
  editPostTitle = '';
  editPostBody = '';
  editPostVisibility: 'public' | 'followers' | 'private' = 'public';
  postEditBusy = false;
  postEditError = '';
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
  reportingPostId: string | null = null;
  reportReason = '';
  reportBusy = false;
  reportError = '';
  reportFeedback = '';
  private followingIds = new Set<string>();
  private followBusyMap = new Map<string, boolean>();
  private pendingPostId: string | null = null;
  highlightedPostId: string | null = null;

  notifications: NotificationItem[] = [];
  notificationsLoading = false;
  notificationsActionBusy = false;
  notificationsError = '';
  notificationsUnreadCount = 0;
  notificationNow = Date.now();
  bellPulse = false;
  private bellPulseTimer: number | null = null;
  private notificationCountInitialized = false;

  private notificationInsertSub?: Subscription;
  private notificationUpdateSub?: Subscription;
  private notificationPollTimer: number | null = null;
  private notificationClockTimer: number | null = null;

  private lastPresenceSnap: PresenceSnapshot | null = null;

  countryTab: CountryTab = 'posts';
  composerOpen = false;

  private queryParamSub?: Subscription;
  private postEventsCreatedSub?: Subscription;
  private postEventsInsertSub?: Subscription;
  private postEventsUpdatedSub?: Subscription;
  private postEventsUpdateSub?: Subscription;
  private postEventsDeleteSub?: Subscription;
  private resettingGlobe = false;
  private pendingRouteState: RouteState | null = null;
  private applyingRouteState = false;
  countriesReady = false;
  private globeReady = false;
  private lastSyncedRouteState: RouteState = { country: null, tab: null, panel: null };

  // --- Avatar orb state ---
  nodeAvatarUrl = '';
  private nodeNormX = 0;
  private nodeNormY = 0;

  // --- Profile editor state (restored) ---
  editDisplayName = '';
  editBio = '';

  draftAvatarUrl = '';
  private draftNormX = 0;
  private draftNormY = 0;

  saveState: 'idle' | 'saving' | 'saved' = 'idle';
  uploadingAvatar = false;
  msg = '';

  adjustingAvatar = false;
  avatarPreviewOpen = false;

  dragging = false;
  private startX = 0;
  private startY = 0;
  private basePxX = 0;
  private basePxY = 0;

  private raf = 0;
  private pendingPxX = 0;
  private pendingPxY = 0;

  private readonly NODE_SIZE = 44;
  private readonly NODE_SCALE = 1.20;

  private readonly EDIT_SIZE = 168;
  private readonly EDIT_SCALE = 1.30;

  private readonly AVATAR_OUT_SIZE = 512;

  constructor(
    private countriesService: CountriesService,
    private globeService: GlobeService,
    private ui: UiStateService,
    private search: SearchService,
    private auth: AuthService,
    private gql: GraphqlService,
    private router: Router,
    private route: ActivatedRoute,
    private media: MediaService,
    private profiles: ProfileService,
    private location: LocationService,
    private presence: PresenceService,
    private postsService: PostsService,
    private postEvents: PostEventsService,
    private followService: FollowService,
    private notificationsService: NotificationsService,
    private notificationEvents: NotificationEventsService,
    private zone: NgZone,
    private cdr: ChangeDetectorRef
  ) {}

  /** Γ£à Angular templates canΓÇÖt do `(profile as any)`; do it here. */
  get cityName(): string {
    const p: any = this.profile as any;
    return (p?.city_name ?? p?.cityName ?? 'ΓÇö') as string;
  }

  private maxOffset(size: number, scale: number): number {
    const scaled = size * scale;
    return Math.max(0, (scaled - size) / 2);
  }

  private clampNorm(v: number): number {
    if (!Number.isFinite(v)) return 0;
    return Math.max(-1, Math.min(1, v));
  }

  get initials(): string {
    const name = (this.profile?.display_name || this.userEmail || 'U').trim();
    const parts = name.split(/\s+/).filter(Boolean);
    const a = parts[0]?.[0] ?? 'U';
    const b = parts.length > 1 ? (parts[parts.length - 1]?.[0] ?? '') : '';
    return (a + b).toUpperCase();
  }

  get nodeAvatarTransform(): string {
    const mo = this.maxOffset(this.NODE_SIZE, this.NODE_SCALE);
    const x = this.nodeNormX * mo;
    const y = this.nodeNormY * mo;
    return `translate3d(${x}px, ${y}px, 0)`;
  }

  get canPostHere(): boolean {
    if (!this.profile || !this.selectedCountry) return false;
    const profileCode = ((this.profile as any)?.country_code || '').toUpperCase();
    const selectedCode = (this.selectedCountry.code || '').toUpperCase();
    return !!profileCode && !!selectedCode && profileCode === selectedCode;
  }

  get draftAvatarTransform(): string {
    const mo = this.maxOffset(this.EDIT_SIZE, this.EDIT_SCALE);
    const x = this.draftNormX * mo;
    const y = this.draftNormY * mo;
    return `translate3d(${x}px, ${y}px, 0)`;
  }

  get profileAvatar(): string {
    return (this.profile as any)?.avatar_url ?? '';
  }

  get composerInitial(): string {
    const source = (this.profile?.display_name || this.profile?.username || this.userEmail || 'you').trim();
    return source ? source.slice(0, 1).toUpperCase() : 'Y';
  }

  get searchInputValue(): string {
    return this.activeTab === 'people' ? this.userSearchTerm : this.countrySearchTerm;
  }

  set searchInputValue(value: string) {
    if (this.activeTab === 'people') {
      this.userSearchTerm = value;
    } else {
      this.countrySearchTerm = value;
    }
  }

  async ngOnInit(): Promise<void> {
    this.postEventsCreatedSub = this.postEvents.createdPost$.subscribe((post) => {
      this.zone.run(() => this.handleCountryPostEvent(post));
    });
    this.postEventsInsertSub = this.postEvents.insert$.subscribe((event) => {
      this.zone.run(() => this.handleCountryPostInsert(event));
    });
    this.postEventsUpdatedSub = this.postEvents.updatedPost$.subscribe((post) => {
      this.zone.run(() => this.handleCountryPostUpdated(post));
    });
    this.postEventsUpdateSub = this.postEvents.update$.subscribe((event) => {
      this.zone.run(() => this.handleCountryPostUpdateEvent(event));
    });
    this.postEventsDeleteSub = this.postEvents.delete$.subscribe((event) => {
      this.zone.run(() => this.handleCountryPostDeleteEvent(event));
    });
    const navState = this.router.getCurrentNavigation()?.extras.state as { resetGlobe?: boolean } | null;
    if (navState?.resetGlobe) {
      this.clearSelectedCountry({ skipRouteUpdate: true });
    }
    this.loadingProfile = true;
    this.profileError = '';
    this.forceUi();

    try {
      const user = await this.auth.getUser();
      this.meId = user?.id ?? null;
      this.userEmail = user?.email ?? '';
      if (this.meId) {
        void this.refreshFollowingSnapshot();
        void this.refreshNotificationCount();
        this.startNotificationPolling();
        this.notificationEvents.stop();
        this.notificationEvents.start(this.meId);
        this.notificationInsertSub?.unsubscribe();
        this.notificationUpdateSub?.unsubscribe();
        this.notificationInsertSub = this.notificationEvents.insert$.subscribe(() => {
          this.zone.run(() => {
            void this.refreshNotificationCount();
            if (this.panel === 'notifications') {
              void this.refreshNotifications();
            }
          });
        });
        this.notificationUpdateSub = this.notificationEvents.update$.subscribe((event) => {
          this.zone.run(() => {
            const existingIndex = this.notifications.findIndex((notif) => notif.id === event.id);
            if (existingIndex >= 0) {
              const next = [...this.notifications];
              next[existingIndex] = {
                ...next[existingIndex],
                read_at: event.read_at ?? next[existingIndex].read_at,
              };
              this.notifications = next;
            }
            void this.refreshNotificationCount();
          });
        });
      } else {
        this.followingIds.clear();
        this.notificationInsertSub?.unsubscribe();
        this.notificationUpdateSub?.unsubscribe();
        this.notificationEvents.stop();
        this.stopNotificationPolling();
        this.notifications = [];
        this.notificationsUnreadCount = 0;
      }

      const { meProfile } = await this.profiles.meProfile();
      this.profile = meProfile;

      this.editDisplayName =
        meProfile?.display_name ?? (this.userEmail?.split('@')[0] ?? '');
      this.editBio = (meProfile as any)?.bio ?? '';

      this.nodeAvatarUrl = (meProfile as any)?.avatar_url ?? '';
      this.draftAvatarUrl = this.nodeAvatarUrl;

      this.nodeNormX = 0;
      this.nodeNormY = 0;
      this.draftNormX = 0;
      this.draftNormY = 0;

      if (this.nodeAvatarUrl) this.preloadImage(this.nodeAvatarUrl);

      this.cdr.detectChanges();
      this.startLocationRefresh();
    } catch (e: any) {
      this.profileError = e?.message ?? String(e);
    } finally {
      this.loadingProfile = false;
      this.forceUi();
    }

    this.queryParamSub = this.route.queryParamMap.subscribe((params) => {
      const resetFlag = params.get('resetGlobe');
      if (resetFlag === '1') {
        if (!this.resettingGlobe) {
          this.resettingGlobe = true;
          this.clearSelectedCountry({ skipRouteUpdate: true });
          void this.router
            .navigate([], {
              relativeTo: this.route,
              queryParams: { resetGlobe: null },
              replaceUrl: true,
            })
            .finally(() => {
              this.resettingGlobe = false;
            });
        }
        return;
      }
      const normalized = this.normalizeRouteState({
        country: params.get('country'),
        tab: params.get('tab'),
        panel: params.get('panel'),
      });
      if (this.routeStatesEqual(normalized, this.lastSyncedRouteState)) return;
      this.pendingRouteState = normalized;
      this.tryApplyPendingRouteState();
    });
  }

  async ngAfterViewInit(): Promise<void> {
    this.zone.runOutsideAngular(async () => {
      const globeEl = document.getElementById('globe');
      if (!globeEl) return;

      this.globeService.init(globeEl);
      this.globeService.whenReady().then(() => {
        this.zone.run(() => {
          this.globeReady = true;
          this.tryApplyPendingRouteState();
        });
      });

      const data = await this.countriesService.loadCountries();
      this.ui.setCountries(data.countries);
      this.globeService.setData(data);
      this.zone.run(() => {
        this.countriesReady = true;
        this.tryApplyPendingRouteState();
      });

      try {
        await this.presence.start({
          countries: data.countries,
          meCountryCode: ((this.profile as any)?.country_code ?? null),
          meCountryName: ((this.profile as any)?.country_name ?? null),
          meCityName: ((this.profile as any)?.city_name ?? null),
          onHeartbeat: (txt) => {
            this.zone.run(() => {
              this.heartbeatText = txt;
              this.forceUi();
            });
          },
          onUpdate: (snap) => {
            this.zone.run(() => {
              this.lastPresenceSnap = snap;
              this.totalUsers = snap.totalUsers;
              this.onlineUsers = snap.onlineUsers;

              this.globeService.setConnections((snap as any).points as any);
              this.globeService.setConnectionsOnline((snap as any).onlineIds as any);

              this.globeService.setConnectionsCountryFilter(this.selectedCountry?.code ?? null);

              this.recomputeLocal();
              this.forceUi();
            });
          },
        });
      } catch (e: any) {
        this.zone.run(() => {
          this.heartbeatText = `presence Γ£ù (${e?.message ?? e})`;
          this.forceUi();
        });
      }

      this.globeService.onCountryClick((country: CountryModel) => {
        this.zone.run(() => {
          this.focusCountry(country);
        });
      });

      try {
        await this.auth.getAccessToken();
        await this.gql.query<any>(`query { __typename }`);
      } catch {}

      this.zone.run(() => console.log('Γ£à Globe page ready'));
    });
  }

  ngOnDestroy(): void {
    try { this.presence.stop(); } catch {}
    this.queryParamSub?.unsubscribe();
    this.postEventsCreatedSub?.unsubscribe();
    this.postEventsInsertSub?.unsubscribe();
    this.postEventsUpdatedSub?.unsubscribe();
    this.postEventsUpdateSub?.unsubscribe();
    this.postEventsDeleteSub?.unsubscribe();
    this.notificationInsertSub?.unsubscribe();
    this.notificationUpdateSub?.unsubscribe();
    this.notificationEvents.stop();
    this.stopNotificationPolling();
    this.stopNotificationClock();
    if (this.bellPulseTimer) {
      window.clearTimeout(this.bellPulseTimer);
      this.bellPulseTimer = null;
    }
    if (this.locationRefreshTimer) window.clearInterval(this.locationRefreshTimer);
    if (this.userSuggestionTimer) {
      window.clearTimeout(this.userSuggestionTimer);
    }
  }

  private recomputeLocal(): void {
    if (!this.selectedCountry?.code) {
      this.localTotal = null;
      this.localOnline = null;
      return;
    }
    const snap: any = this.lastPresenceSnap as any;
    if (!snap) {
      this.localTotal = null;
      this.localOnline = null;
      return;
    }
    const cc = String(this.selectedCountry.code).toUpperCase();
    const entry = snap.byCountry?.[cc];
    this.localTotal = entry?.total ?? 0;
    this.localOnline = entry?.online ?? 0;
  }

  private computeFocusPadding(): { top: number; bottom: number; left: number; right: number } {
    const top = 90;
    const bottom = 20;
    const left = 20;
    let right = 20;

    const pane = document.querySelector('.main-pane') as HTMLElement | null;
    if (pane) {
      const rect = pane.getBoundingClientRect();
      right = Math.max(24, Math.round(rect.width + 32));
    } else {
      right = Math.max(24, Math.round(window.innerWidth * 0.45));
    }

    return { top, bottom, left, right };
  }

  private applyFocusView(country: CountryModel): void {
    this.globeService.setViewPadding(this.computeFocusPadding());
    this.globeService.flyTo(country.center.lat, country.center.lng, country.flyAltitude ?? 1.0, 900);
  }

  setCountryTab(tab: CountryTab, opts?: { skipRouteUpdate?: boolean }): void {
    if (this.countryTab === tab) return;
    this.countryTab = tab;
    if (tab === 'posts' && this.selectedCountry && !this.postsLoading && !this.posts.length) {
      void this.loadPostsForCountry(this.selectedCountry);
    }
    if (!opts?.skipRouteUpdate && this.selectedCountry) this.updateRouteState();
    this.forceUi();
  }

  focusCountry(country: CountryModel, opts?: { tab?: CountryTab; skipRouteUpdate?: boolean }): void {
    const tab = opts?.tab ?? 'posts';

    this.selectedCountry = country;
    this.countryTab = tab;
    if (!this.canPostHere) this.composerOpen = false;

    this.ui.setMode('focus');
    this.ui.setSelected(country.id);
    this.countrySearchTerm = country.name;
    this.countrySuggestions = [];

    this.globeService.setSoloCountry(country.id);
    this.globeService.setConnectionsCountryFilter(country.code ?? null);
    this.globeService.selectCountry(country.id);
    this.globeService.showFocusLabel(country.id);

    this.recomputeLocal();
    this.postComposerError = '';
    this.postsError = '';
    this.forceUi();

    setTimeout(() => {
      this.applyFocusView(country);
      this.globeService.resize();
    }, 0);
    setTimeout(() => this.globeService.resize(), 60);
    void this.loadPostsForCountry(country);

    if (!opts?.skipRouteUpdate) this.updateRouteState();
  }

  clearSelectedCountry(opts?: { skipRouteUpdate?: boolean }): void {
    const hadState = !!this.selectedCountry || !!this.panel;
    this.selectedCountry = null;
    this.countryTab = 'posts';
    this.composerOpen = false;

    this.ui.setMode('all');
    this.ui.setSelected(null);
    this.countrySearchTerm = '';
    this.countrySuggestions = [];

    this.globeService.setSoloCountry(null);
    this.globeService.setConnectionsCountryFilter(null);
    this.globeService.resetView();

    this.localTotal = null;
    this.localOnline = null;
    this.panel = null;
    this.posts = [];
    this.postsError = '';
    this.postComposerError = '';
    this.postFeedback = '';
    this.newPostBody = '';
    this.newPostTitle = '';

    this.forceUi();

    setTimeout(() => this.globeService.resize(), 0);
    setTimeout(() => this.globeService.resize(), 60);

    if (!opts?.skipRouteUpdate && hadState) this.updateRouteState();
  }

  private async loadPostsForCountry(country: CountryModel | null): Promise<void> {
    if (!country?.code) {
      this.posts = [];
      this.postsError = '';
      this.forceUi();
      return;
    }

    this.postsLoading = true;
    this.postsError = '';
    this.forceUi();

    try {
      this.posts = this.sortPostsAsc(await this.postsService.listByCountry(country.code));
    } catch (e: any) {
      this.postsError = e?.message ?? String(e);
    } finally {
      this.postsLoading = false;
      this.forceUi();
      this.tryScrollToPendingPost();
    }
  }

  private tryScrollToPendingPost(): void {
    const pendingId = this.pendingPostId;
    if (!pendingId) return;
    if (!this.posts.some((post) => post.id === pendingId)) return;
    this.pendingPostId = null;
    window.setTimeout(() => this.scrollToPost(pendingId), 0);
  }

  private scrollToPost(postId: string): void {
    if (!postId) return;
    const target = document.getElementById(`post-${postId}`);
    if (!target) return;
    this.highlightedPostId = postId;
    this.forceUi();
    target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    window.setTimeout(() => {
      if (this.highlightedPostId === postId) {
        this.highlightedPostId = null;
        this.forceUi();
      }
    }, 1500);
  }

  private handleCountryPostEvent(post: CountryPost): void {
    const currentCode = this.selectedCountry?.code?.toUpperCase() ?? null;
    const postCode = post.country_code?.toUpperCase() ?? null;
    if (!currentCode || !postCode || currentCode !== postCode) {
      return;
    }
    const isPublic = post.visibility === 'public' || post.visibility === 'country';
    if (!isPublic && !this.isAuthorSelf(post.author_id) && !this.isFollowingAuthor(post.author_id)) {
      return;
    }
    if (this.posts.some((existing) => existing.id === post.id)) {
      return;
    }
    this.posts = this.sortPostsAsc([...this.posts, post]);
    this.forceUi();
  }

  private handleCountryPostInsert(event: PostInsertEvent): void {
    const currentCode = this.selectedCountry?.code?.toUpperCase();
    const eventCode = event.country_code?.toUpperCase();
    if (!currentCode || !eventCode) return;
    if (currentCode !== eventCode) return;
    if (!this.selectedCountry) return;
    void this.loadPostsForCountry(this.selectedCountry);
  }

  private handleCountryPostUpdated(post: CountryPost): void {
    this.applyPostUpdate(post);
  }

  private handleCountryPostUpdateEvent(event: PostUpdateEvent): void {
    const currentCode = this.selectedCountry?.code?.toUpperCase();
    const eventCode = event.country_code?.toUpperCase();
    if (!currentCode || !eventCode) return;
    if (currentCode !== eventCode) return;
    if (!this.selectedCountry) return;
    void this.loadPostsForCountry(this.selectedCountry);
  }

  private handleCountryPostDeleteEvent(event: PostDeleteEvent): void {
    if (!event?.id) return;
    const currentCode = this.selectedCountry?.code?.toUpperCase() ?? null;
    const eventCode = event.country_code?.toUpperCase() ?? null;
    if (eventCode && currentCode && eventCode !== currentCode) return;
    const next = this.posts.filter((post) => post.id !== event.id);
    if (next.length !== this.posts.length) {
      this.posts = next;
      if (this.editingPostId === event.id) this.cancelPostEdit();
      if (this.openPostMenuId === event.id) this.openPostMenuId = null;
      if (this.confirmDeletePostId === event.id) this.confirmDeletePostId = null;
      this.forceUi();
    }
  }

  private applyPostUpdate(post: CountryPost): void {
    const currentCode = this.selectedCountry?.code?.toUpperCase() ?? null;
    const postCode = post.country_code?.toUpperCase() ?? null;
    if (!currentCode || !postCode || currentCode !== postCode) return;

    const isPublic = post.visibility === 'public' || post.visibility === 'country';
    const isSelf = this.isAuthorSelf(post.author_id);
    const isFollower = this.isFollowingAuthor(post.author_id);
    if (!isPublic && !isSelf && !isFollower) {
      const next = this.posts.filter((existing) => existing.id !== post.id);
      if (next.length !== this.posts.length) {
        this.posts = next;
        this.forceUi();
      }
      return;
    }

    const index = this.posts.findIndex((existing) => existing.id === post.id);
    if (index >= 0) {
      const next = [...this.posts];
      next[index] = post;
      this.posts = this.sortPostsAsc(next);
      this.forceUi();
      return;
    }

    this.posts = this.sortPostsAsc([...this.posts, post]);
    this.forceUi();
  }

  private async refreshNotifications(): Promise<void> {
    if (!this.meId) {
      this.notifications = [];
      this.notificationsError = '';
      this.notificationsLoading = false;
      this.forceUi();
      return;
    }

    this.notificationsLoading = true;
    this.notificationsError = '';
    this.forceUi();

    try {
      const { notifications } = await this.notificationsService.list(40);
      this.notifications = notifications ?? [];
    } catch (e: any) {
      this.notificationsError = e?.message ?? String(e);
    } finally {
      this.notificationsLoading = false;
      this.forceUi();
    }
  }

  private async refreshNotificationCount(): Promise<void> {
    if (!this.meId) {
      this.notificationsUnreadCount = 0;
      this.forceUi();
      return;
    }

    try {
      const prevCount = this.notificationsUnreadCount;
      const { notificationsUnreadCount } = await this.notificationsService.unreadCount();
      this.notificationsUnreadCount = notificationsUnreadCount ?? 0;
      if (this.notificationCountInitialized && this.notificationsUnreadCount > prevCount) {
        this.triggerBellPulse();
      }
      this.notificationCountInitialized = true;
    } catch {}

    this.forceUi();
  }

  private triggerBellPulse(): void {
    this.bellPulse = true;
    if (this.bellPulseTimer) {
      window.clearTimeout(this.bellPulseTimer);
    }
    this.bellPulseTimer = window.setTimeout(() => {
      this.bellPulse = false;
      this.bellPulseTimer = null;
      this.forceUi();
    }, 900);
    this.forceUi();
  }

  private startNotificationPolling(): void {
    if (this.notificationPollTimer) return;
    this.notificationPollTimer = window.setInterval(() => {
      void this.refreshNotificationCount();
    }, 5000);
  }

  private stopNotificationPolling(): void {
    if (!this.notificationPollTimer) return;
    window.clearInterval(this.notificationPollTimer);
    this.notificationPollTimer = null;
  }

  private startNotificationClock(): void {
    if (this.notificationClockTimer) return;
    this.notificationNow = Date.now();
    this.notificationClockTimer = window.setInterval(() => {
      this.notificationNow = Date.now();
      this.forceUi();
    }, 60000);
  }

  private stopNotificationClock(): void {
    if (!this.notificationClockTimer) return;
    window.clearInterval(this.notificationClockTimer);
    this.notificationClockTimer = null;
  }

  async markAllNotificationsRead(): Promise<void> {
    if (!this.meId || this.notificationsActionBusy) return;

    this.notificationsActionBusy = true;
    this.notificationsError = '';
    this.forceUi();

    try {
      await this.notificationsService.markAllRead();
      const now = new Date().toISOString();
      this.notifications = this.notifications.map((notif) =>
        notif.read_at ? notif : { ...notif, read_at: now }
      );
      this.notificationsUnreadCount = 0;
    } catch (e: any) {
      this.notificationsError = e?.message ?? String(e);
    } finally {
      this.notificationsActionBusy = false;
      this.forceUi();
    }
  }

  private async markNotificationRead(notif: NotificationItem): Promise<void> {
    if (!this.meId || !notif || notif.read_at) return;

    try {
      const { markNotificationRead } = await this.notificationsService.markRead(notif.id);
      if (markNotificationRead) {
        const now = new Date().toISOString();
        this.notifications = this.notifications.map((item) =>
          item.id === notif.id ? { ...item, read_at: now } : item
        );
        this.notificationsUnreadCount = Math.max(0, this.notificationsUnreadCount - 1);
        this.forceUi();
      }
    } catch {}
  }

  private looksLikeId(value: string): boolean {
    const trimmed = value.trim();
    if (!trimmed) return false;
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(trimmed);
  }

  private parseNotificationDate(value: string): number | null {
    const raw = String(value ?? '').trim();
    if (!raw || this.looksLikeId(raw)) return null;

    let parsed = Date.parse(raw);
    if (!Number.isFinite(parsed)) {
      const normalized = raw.includes('T') ? raw : raw.replace(' ', 'T');
      parsed = Date.parse(normalized);
    }

    if (!Number.isFinite(parsed)) {
      const numeric = Number(raw);
      if (Number.isFinite(numeric)) {
        parsed = numeric > 1e12 ? numeric : numeric * 1000;
      }
    }

    return Number.isFinite(parsed) ? parsed : null;
  }

  notificationActorName(notif: NotificationItem): string {
    const candidate = (notif.actor?.display_name || notif.actor?.username || '').trim();
    if (!candidate || this.looksLikeId(candidate)) return 'Someone';
    return candidate;
  }

  notificationMessage(notif: NotificationItem): string {
    const type = (notif.type || '').toLowerCase();
    if (type === 'follow') return 'started following you.';
    if (type === 'like') return 'liked your post.';
    if (type === 'comment') return 'commented on your post.';
    if (type === 'post') return 'shared a post.';
    return 'sent you a notification.';
  }

  openNotification(notif: NotificationItem): void {
    if (!notif) return;
    void this.markNotificationRead(notif);

    const type = (notif.type || '').toLowerCase();
    if (type === 'follow') {
      const slug = notif.actor?.username?.trim() || notif.actor_id;
      if (slug) {
        void this.router.navigate(['/user', slug]);
      }
      return;
    }
    if ((type === 'like' || type === 'comment') && notif.entity_id) {
      void this.navigateToNotificationPost(notif.entity_id);
    }
  }

  private async navigateToNotificationPost(postId: string): Promise<void> {
    if (!postId) return;
    try {
      const post = await this.postsService.getPostById(postId);
      if (!post) return;

      const targetCode = (post.country_code ?? '').toUpperCase();
      const currentCode = (this.selectedCountry?.code ?? '').toUpperCase();
      if (this.panel === 'notifications') {
        this.closePanel();
      }
      if (currentCode && targetCode && currentCode === targetCode) {
        this.pendingPostId = post.id;
        this.tryScrollToPendingPost();
        return;
      }

      const target = targetCode ? this.findCountryByRouteToken(targetCode) : null;
      if (!target) return;

      this.pendingPostId = post.id;
      this.closePanel({ skipRouteUpdate: true });
      this.focusCountry(target, { tab: 'posts' });
    } catch {}
  }

  formatDate(value: string): string {
    const createdAt = this.parseNotificationDate(value);
    if (!createdAt) return 'Just now';
    const diffMs = Math.max(0, this.notificationNow - createdAt);
    const diffMinutes = Math.floor(diffMs / 60000);
    if (diffMinutes < 1) return 'Just now';
    if (diffMinutes < 60) return `${diffMinutes}m`;
    const diffHours = Math.floor(diffMinutes / 60);
    if (diffHours < 24) return `${diffHours}h`;
    const diffDays = Math.floor(diffHours / 24);
    if (diffDays < 7) return `${diffDays}d`;
    return new Date(createdAt).toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
    });
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
    if (normalized === 'followers') return '\u{1F465}';
    return '\u{1F441}';
  }

  private sortPostsAsc(posts: CountryPost[]): CountryPost[] {
    return [...posts].sort((a, b) => {
      const aTime = new Date(a.created_at).getTime();
      const bTime = new Date(b.created_at).getTime();
      if (aTime !== bTime) return aTime - bTime;
      return a.id.localeCompare(b.id);
    });
  }

  async submitPost(): Promise<void> {
    if (!this.profile || !this.meId) {
      this.postComposerError = 'Sign in to share with your country.';
      return;
    }
    if (!this.canPostHere) {
    this.postComposerError = 'Switch to the country where you post from to post.';
      return;
    }
    const body = this.newPostBody.trim();
    if (!body) {
      this.postComposerError = 'Write something before posting.';
      return;
    }

    const countryCode = ((this.profile as any)?.country_code || '').toUpperCase();
    const countryName = this.profile.country_name;
    if (!countryCode || !countryName) {
      this.postComposerError = 'Profile country is missing.';
      return;
    }

    this.postBusy = true;
    this.postComposerError = '';
    this.postFeedback = '';
    this.forceUi();

    try {
      const post = await this.postsService.createPost({
        authorId: this.meId,
        title: this.newPostTitle.trim() || null,
        body,
        countryCode,
        countryName,
        cityName: (this.profile as any)?.city_name ?? null,
      });
      this.newPostBody = '';
      this.newPostTitle = '';
    if (!this.posts.some((existing) => existing.id === post.id)) {
      this.posts = this.sortPostsAsc([...this.posts, post]);
    }
      this.composerOpen = false;
      this.postFeedback = 'Shared with your country.';
      setTimeout(() => {
        this.postFeedback = '';
        this.cdr.detectChanges();
      }, 2000);
    } catch (e: any) {
      this.postComposerError = e?.message ?? String(e);
    } finally {
      this.postBusy = false;
      this.forceUi();
    }
  }

  startPostEdit(post: CountryPost): void {
    if (!this.isAuthorSelf(post.author_id)) return;
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
    if (!this.isAuthorSelf(post.author_id) || this.postEditBusy) return;
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
      const updated = await this.postsService.updatePost(post.id, {
        title: this.editPostTitle.trim() || null,
        body,
        visibility: this.editPostVisibility,
      });
      this.applyPostUpdate(updated);
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
    if (!this.isAuthorSelf(post.author_id)) return;
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
    if (!this.isAuthorSelf(post.author_id) || this.postEditBusy) return;
    this.openPostMenuId = null;
    this.confirmDeletePostId = null;
    this.postEditBusy = true;
    this.postEditError = '';
    this.forceUi();

    try {
      const deleted = await this.postsService.deletePost(post.id, {
        country_code: post.country_code ?? null,
        author_id: post.author_id ?? null,
      });
      if (deleted) {
        this.posts = this.posts.filter((existing) => existing.id !== post.id);
        if (this.editingPostId === post.id) this.cancelPostEdit();
      }
    } catch (e: any) {
      this.postEditError = e?.message ?? String(e);
    } finally {
      this.postEditBusy = false;
      this.forceUi();
    }
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
      const likes = await this.postsService.listLikes(postId, 40);
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
    this.forceUi();
  }

  private async loadComments(postId: string): Promise<void> {
    if (!postId) return;
    this.commentLoading[postId] = true;
    this.commentErrors[postId] = '';
    this.forceUi();

    try {
      const comments = await this.postsService.listComments(postId, 40);
      this.commentItems[postId] = comments;
    } catch (e: any) {
      this.commentErrors[postId] = e?.message ?? String(e);
    } finally {
      this.commentLoading[postId] = false;
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
      const comment = await this.postsService.addComment(post.id, draft);
      const existing = this.commentItems[post.id] ?? [];
      this.commentItems[post.id] = [...existing, comment];
      this.commentDrafts[post.id] = '';
      const updated = { ...post, comment_count: post.comment_count + 1 };
      this.applyPostUpdate(updated);
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
      await this.postsService.reportPost(post.id, reason);
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

  isFollowingAuthor(authorId?: string | null): boolean {
    return !!authorId && this.followingIds.has(authorId);
  }

  isAuthorSelf(authorId?: string | null): boolean {
    return !!authorId && this.meId === authorId;
  }

  openAuthorProfile(author: CountryPost['author'] | null | undefined): void {
    if (!author) return;
    const slug = author.username?.trim() || author.user_id;
    if (!slug) return;
    void this.router.navigate(['/user', slug]);
  }

  followBusyFor(authorId: string): boolean {
    return this.followBusyMap.get(authorId) === true;
  }

  async toggleFollowAuthor(authorId: string): Promise<void> {
    if (!this.meId || !authorId || this.meId === authorId) return;
    if (this.followBusyFor(authorId)) return;

    this.followBusyMap.set(authorId, true);
    this.forceUi();

    try {
      if (this.followingIds.has(authorId)) {
        await this.followService.unfollow(this.meId, authorId);
        this.followingIds.delete(authorId);
        this.postFeedback = 'Unfollowed';
      } else {
        await this.followService.follow(this.meId, authorId);
        this.followingIds.add(authorId);
        this.postFeedback = 'Following';
      }
      setTimeout(() => {
        this.postFeedback = '';
        this.cdr.detectChanges();
      }, 2000);
    } catch (e: any) {
      this.postComposerError = e?.message ?? String(e);
    } finally {
      this.followBusyMap.delete(authorId);
      this.forceUi();
    }
  }

  private async refreshFollowingSnapshot(): Promise<void> {
    if (!this.meId) {
      this.followingIds.clear();
      return;
    }
    try {
      const ids = await this.followService.listFollowingIds(this.meId);
      this.followingIds = new Set(ids);
      this.cdr.detectChanges();
    } catch (e) {
      console.warn('following snapshot failed', e);
    }
  }

  private startLocationRefresh(): void {
    if (this.locationRefreshTimer || !this.meId || !this.profile) return;
    void this.refreshLocationIfMoved();
    this.locationRefreshTimer = window.setInterval(() => {
      void this.refreshLocationIfMoved();
    }, this.LOCATION_REFRESH_MS);
  }

  private async refreshLocationIfMoved(): Promise<void> {
    if (this.locationRefreshInFlight || !this.meId || !this.profile) return;
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
      if (!this.canPostHere) this.composerOpen = false;
      await this.presence.setMyLocation(
        (this.profile as any)?.country_code ?? null,
        this.profile.country_name ?? null,
        (this.profile as any)?.city_name ?? null
      );
      this.forceUi();
    } catch (e) {
      console.warn('location refresh failed', e);
    } finally {
      this.locationRefreshInFlight = false;
    }
  }

  onUserSearchInput(value: string): void {
    this.userSearchTerm = value;
    this.userSearchError = '';
    this.scheduleUserSuggestionRefresh();
  }

  onUnifiedSearchInput(value: string): void {
    if (this.activeTab === 'people') {
      this.onUserSearchInput(value);
      return;
    }
    this.onCountrySearchInput(value);
  }

  private scheduleUserSuggestionRefresh(): void {
    if (this.userSuggestionTimer) {
      window.clearTimeout(this.userSuggestionTimer);
      this.userSuggestionTimer = null;
    }
    const trimmed = this.userSearchTerm.trim();
    if (!trimmed) {
      this.userSuggestions = [];
      this.forceUi();
      return;
    }
    this.userSuggestionTimer = window.setTimeout(() => {
      this.userSuggestionTimer = null;
      void this.refreshUserSuggestions(trimmed);
    }, 260);
  }

  private async refreshUserSuggestions(term: string): Promise<void> {
    if (!term) {
      this.userSuggestions = [];
      this.forceUi();
      return;
    }
    this.userSuggestionsLoading = true;
    this.forceUi();
    try {
      const { searchProfiles } = await this.profiles.searchProfiles(term, 7);
      this.userSuggestions = searchProfiles ?? [];
      if (!this.userSuggestions.length) {
        this.userSearchError = 'No matches yet.';
      }
    } catch (e: any) {
      this.userSearchError = e?.message ?? 'Unable to load suggestions.';
    } finally {
      this.userSuggestionsLoading = false;
      this.forceUi();
    }
  }

  onUserSearchKeydown(event: KeyboardEvent): void {
    if (event.key !== 'Enter') return;
    event.preventDefault();
    if (!this.userSuggestions.length) {
      if (this.userSearchTerm.trim()) {
        this.userSearchError = 'No matches yet.';
        this.forceUi();
      }
      return;
    }
    this.selectUserSuggestion(this.userSuggestions[0]);
  }

  handleSearchKeydown(event: KeyboardEvent): void {
    if (this.activeTab === 'people') {
      this.onUserSearchKeydown(event);
      return;
    }
    if (event.key === 'Enter') {
      event.preventDefault();
      this.visitCountry();
    }
  }

  selectUserSuggestion(profile: Profile): void {
    if (!profile) return;
    if (this.userSuggestionTimer) {
      window.clearTimeout(this.userSuggestionTimer);
      this.userSuggestionTimer = null;
    }
    const slug = profile.username?.trim() || profile.user_id;
    if (!slug) {
      this.userSearchError = 'Profile is missing routing info.';
      this.forceUi();
      return;
    }
    this.userSearchTerm = '';
    this.userSuggestions = [];
    this.userSearchError = '';
    this.forceUi();
    void this.router.navigate(['/user', slug]);
  }

  setActiveTab(tab: SearchTab): void {
    if (this.activeTab === tab) return;
    this.activeTab = tab;
    this.userSuggestions = [];
    this.countrySuggestions = [];
    this.userSearchError = '';
  }

  onCountrySearchInput(value: string): void {
    this.countrySearchTerm = value;
    this.updateCountrySuggestions(value);
  }

  private updateCountrySuggestions(raw: string): void {
    const trimmed = (raw || '').trim();
    if (!trimmed || !this.countriesReady) {
      this.countrySuggestions = [];
      this.forceUi();
      return;
    }
    this.countrySuggestions = this.search.prefixSuggest(this.ui.countries, trimmed, 6);
    this.forceUi();
  }

  visitCountry(): void {
    if (!this.canVisitCountry()) return;
    const candidate = this.search.bestCandidateForSearch(
      this.ui.countries,
      this.countrySearchTerm,
      this.countrySuggestions,
      -1
    );
    if (!candidate) {
      this.countrySuggestions = [];
      this.forceUi();
      return;
    }
    this.focusCountry(candidate);
  }

  canVisitCountry(): boolean {
    return this.countriesReady && !!this.countrySearchTerm.trim();
  }

  private tryApplyPendingRouteState(): void {
    if (!this.pendingRouteState) return;
    if (this.pendingRouteState.country && (!this.countriesReady || !this.globeReady)) return;

    const state = this.pendingRouteState;
    this.pendingRouteState = null;
    this.applyRouteState(state);
  }

  private applyRouteState(state: RouteState): void {
    this.applyingRouteState = true;
    try {
      const token = state.country;

      if (token) {
        const target = this.findCountryByRouteToken(token);
        if (target) {
          const desiredTab = state.tab ?? 'posts';
          if (!this.selectedCountry || this.selectedCountry.id !== target.id) {
            this.focusCountry(target, { tab: desiredTab, skipRouteUpdate: true });
          } else if (state.tab && state.tab !== this.countryTab) {
            this.setCountryTab(state.tab, { skipRouteUpdate: true });
          }
        } else if (this.selectedCountry) {
          this.clearSelectedCountry({ skipRouteUpdate: true });
        }
      } else if (this.selectedCountry) {
        this.clearSelectedCountry({ skipRouteUpdate: true });
      }

      if (state.panel) {
        if (this.panel !== state.panel) {
          this.openPanel(state.panel, { skipRouteUpdate: true });
        }
      } else if (this.panel) {
        this.closePanel({ skipRouteUpdate: true });
      }
    } finally {
      this.applyingRouteState = false;
      this.lastSyncedRouteState = state;
    }
  }

  private updateRouteState(): void {
    if (this.applyingRouteState) return;
    const next = this.buildCurrentRouteState();
    if (this.routeStatesEqual(next, this.lastSyncedRouteState)) return;

    this.lastSyncedRouteState = next;

    const queryParams = {
      country: next.country ?? null,
      tab: next.tab ?? null,
      panel: next.panel ?? null,
    };

    void this.router.navigate([], {
      relativeTo: this.route,
      queryParams,
      replaceUrl: true,
    });
  }

  private buildCurrentRouteState(): RouteState {
    const iso = this.selectedCountry?.code
      ? String(this.selectedCountry.code).toUpperCase()
      : null;
    const fallbackId = !iso && this.selectedCountry ? String(this.selectedCountry.id) : null;

    return {
      country: iso ?? fallbackId,
      tab: this.selectedCountry ? this.countryTab : null,
      panel: this.panel ?? null,
    };
  }

  private routeStatesEqual(a: RouteState, b: RouteState): boolean {
    return (
      (a.country ?? null) === (b.country ?? null) &&
      (a.tab ?? null) === (b.tab ?? null) &&
      (a.panel ?? null) === (b.panel ?? null)
    );
  }

  private normalizeRouteState(state: { country: string | null; tab: string | null; panel: string | null }): RouteState {
    const rawCountry = state.country?.trim() ?? null;
    const country = rawCountry ? rawCountry.toUpperCase() : null;

    const rawTab = state.tab?.trim().toLowerCase() ?? null;
    const tab = this.isValidTab(rawTab) ? rawTab : null;

    const rawPanel = state.panel?.trim().toLowerCase() ?? null;
    const panel = this.isValidPanel(rawPanel) ? (rawPanel as Exclude<Panel, null>) : null;

    return { country, tab, panel };
  }

  private isValidTab(value: string | null): value is CountryTab {
    return value === 'posts' || value === 'stats' || value === 'media';
  }

  private isValidPanel(value: string | null): value is Exclude<Panel, null> {
    return value === 'presence' || value === 'posts' || value === 'notifications';
  }

  private findCountryByRouteToken(token: string): CountryModel | null {
    const trimmed = token.trim();
    if (!trimmed) return null;

    const upper = trimmed.toUpperCase();
    const byIso = this.ui.countries.find(
      (c) => (c.code ?? '').toUpperCase() === upper
    );
    if (byIso) return byIso;

    const id = Number(trimmed);
    if (Number.isFinite(id)) {
      return this.ui.countries.find((c) => c.id === id) ?? null;
    }

    return null;
  }

  // -----------------------------
  // Menu / panels
  // -----------------------------
  toggleMenu(): void { this.menuOpen = !this.menuOpen; }
  closeMenu(): void { this.menuOpen = false; }

  goToMe(): void {
    this.closeMenu();
    void this.router.navigate(['/me']);
  }

  openPanel(p: Exclude<Panel, null>, opts?: { skipRouteUpdate?: boolean }): void {
    this.panel = p;
    this.menuOpen = false;

    this.msg = '';
    this.saveState = 'idle';

    if (p === 'notifications') {
      void this.refreshNotifications();
      void this.refreshNotificationCount();
      this.startNotificationClock();
    }

    this.forceUi();
    if (!opts?.skipRouteUpdate) this.updateRouteState();
  }

  closePanel(opts?: { skipRouteUpdate?: boolean }): void {
    if (!this.panel) return;
    const wasNotifications = this.panel === 'notifications';
    this.panel = null;
    this.adjustingAvatar = false;
    this.dragging = false;
    this.msg = '';
    this.saveState = 'idle';
    this.avatarPreviewOpen = false;
    this.forceUi();
    if (wasNotifications) this.stopNotificationClock();
    if (!opts?.skipRouteUpdate) this.updateRouteState();
  }

  // -----------------------------
  // Avatar preview / adjust
  // -----------------------------
  openAvatarPreview(): void {
    if (!this.draftAvatarUrl) return;
    this.avatarPreviewOpen = true;
    this.forceUi();
  }

  closeAvatarPreview(): void {
    this.avatarPreviewOpen = false;
    this.forceUi();
  }

  toggleAdjustAvatar(): void {
    if (!this.draftAvatarUrl) return;
    this.adjustingAvatar = !this.adjustingAvatar;
    this.forceUi();
  }

  resetAvatarPosition(): void {
    this.draftNormX = 0;
    this.draftNormY = 0;
    this.forceUi();
  }

  onAvatarDragStart(ev: PointerEvent): void {
    if (!this.adjustingAvatar) return;
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

    this.forceUi();
  }

  private onAvatarDragMove(ev: PointerEvent): void {
    if (!this.dragging) return;

    const dx = ev.clientX - this.startX;
    const dy = ev.clientY - this.startY;

    const mo = this.maxOffset(this.EDIT_SIZE, this.EDIT_SCALE);
    const clampPx = (v: number) => Math.max(-mo, Math.min(mo, v));

    this.pendingPxX = clampPx(this.basePxX + dx);
    this.pendingPxY = clampPx(this.basePxY + dy);

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
    this.forceUi();
  }

  // -----------------------------
  // Avatar upload + crop (restored)
  // -----------------------------
  private async cropAvatarToSquare(file: File): Promise<File> {
    const type = (file.type || '').toLowerCase();

    if (type === 'image/gif') throw new Error('GIF avatars are disabled for now.');
    if (!type.startsWith('image/')) throw new Error('Please choose an image file.');

    const outType =
      type === 'image/png' || type === 'image/webp' ? 'image/png' : 'image/jpeg';
    const outExt = outType === 'image/png' ? 'png' : 'jpg';

    const bitmap = await createImageBitmap(file);

    const side = Math.min(bitmap.width, bitmap.height);
    const sx = Math.floor((bitmap.width - side) / 2);
    const sy = Math.floor((bitmap.height - side) / 2);

    const canvas = document.createElement('canvas');
    canvas.width = this.AVATAR_OUT_SIZE;
    canvas.height = this.AVATAR_OUT_SIZE;

    const ctx = canvas.getContext('2d', { alpha: true });
    if (!ctx) throw new Error('Canvas not supported.');

    (ctx as any).imageSmoothingEnabled = true;
    (ctx as any).imageSmoothingQuality = 'high';

    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(bitmap, sx, sy, side, side, 0, 0, canvas.width, canvas.height);

    bitmap.close?.();

    const blob: Blob = await new Promise((resolve, reject) => {
      canvas.toBlob(
        (b) => (b ? resolve(b) : reject(new Error('Failed to crop image.'))),
        outType,
        outType === 'image/jpeg' ? 0.92 : undefined
      );
    });

    return new File([blob], `avatar.${outExt}`, { type: outType });
  }

  async onAvatar(e: Event): Promise<void> {
    const input = e.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;

    this.msg = '';
    this.uploadingAvatar = true;
    this.forceUi();

    try {
      const cropped = await this.cropAvatarToSquare(file);

      const r = await this.media.uploadAvatar(cropped);
      const url = (r as any)?.url;
      if (!url) throw new Error('Upload succeeded but returned no URL.');

      this.draftAvatarUrl = url;
      this.preloadImage(url);

      this.draftNormX = 0;
      this.draftNormY = 0;

      this.msg = 'Uploaded. Press SAVE to apply.';
    } catch (err: any) {
      this.msg = err?.message ?? String(err);
    } finally {
      this.uploadingAvatar = false;
      input.value = '';
      this.forceUi();
    }
  }

  async saveProfileAndClose(): Promise<void> {
    this.msg = '';
    this.saveState = 'saving';
    this.forceUi();

    try {
      const dn = this.editDisplayName.trim();
      const bio = this.editBio.trim();

      if (!dn) throw new Error('Display name is required.');

      const res = await this.profiles.updateProfile({
        display_name: dn,
        bio: bio ? bio.slice(0, 160) : null,
        avatar_url: this.draftAvatarUrl || null,
      });

      this.profile = (res as any).updateProfile;

      this.nodeAvatarUrl = (this.profile as any)?.avatar_url ?? '';
      this.nodeNormX = this.draftNormX;
      this.nodeNormY = this.draftNormY;

      if (this.nodeAvatarUrl) this.preloadImage(this.nodeAvatarUrl);

      try {
        await this.presence.setMyLocation(
          (this.profile as any)?.country_code ?? null,
          (this.profile as any)?.country_name ?? null,
          (this.profile as any)?.city_name ?? null
        );
      } catch {}

      this.saveState = 'saved';
      this.forceUi();

      window.setTimeout(() => {
        this.zone.run(() => this.closePanel());
      }, 220);
    } catch (e: any) {
      this.msg = e?.message ?? String(e);
      this.saveState = 'idle';
      this.forceUi();
    }
  }

  async logout(): Promise<void> {
    this.presence.stop();
    await this.auth.logout();
    await this.router.navigateByUrl('/auth');
  }

  private preloadImage(url: string): void {
    const img = new Image();
    img.decoding = 'async';
    img.loading = 'eager';
    img.src = url;
  }

  private forceUi(): void {
    this.zone.run(() => this.cdr.detectChanges());
  }
}
