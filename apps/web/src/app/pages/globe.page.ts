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
import { PresenceService, type PresenceSnapshot } from '../core/services/presence.service';
import { PostsService } from '../core/services/posts.service';
import { FollowService } from '../core/services/follow.service';
import { PostEventsService, type PostInsertEvent } from '../core/services/post-events.service';
import { CountryPost } from '../core/models/post.model';

type Panel = 'presence' | 'posts' | null;
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
                  <div class="post-card" *ngFor="let post of posts">
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
                    </div>
                    <div class="post-body">
                      <div class="post-title" *ngIf="post.title">{{ post.title }}</div>
                      <p>{{ post.body }}</p>
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
            {{ panel === 'presence' ? 'MY PRESENCE' : 'MY POSTS' }}
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
      border-radius:20px;
      border:1px solid rgba(0,0,0,0.06);
      background:rgba(255,255,255,0.95);
      padding:16px;
      box-shadow:0 18px 60px rgba(0,0,0,0.10);
    }
    .post-author{
      display:flex;
      align-items:center;
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
      outline:2px solid rgba(0,255,209,0.6);
      outline-offset:2px;
    }
    .author-avatar{
      width:42px;
      height:42px;
      border-radius:999px;
      overflow:hidden;
      background:rgba(10,12,20,0.65);
      border:1px solid rgba(0,0,0,0.12);
      box-shadow:0 8px 28px rgba(0,0,0,0.18);
      display:grid;
      place-items:center;
      color:rgba(255,255,255,0.85);
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
      background:linear-gradient(90deg, rgba(0,255,209,0.25), rgba(140,0,255,0.25));
      color:rgba(0,0,0,0.85);
      border-color:rgba(0,0,0,0.12);
      box-shadow:0 0 0 1px rgba(0,255,209,0.18) inset;
    }
    .follow-chip:disabled{ opacity:0.6; cursor:not-allowed; }
    .post-body{ margin-top:12px; font-size:14px; line-height:1.5; color:rgba(10,12,18,0.85); }
    .post-title{ font-weight:900; margin-bottom:6px; letter-spacing:0.06em; text-transform:uppercase; font-size:12px; }

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
      width: 44px;
      height: 44px;
      user-select: none;
      pointer-events: auto;
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
    .node-btn:hover{ background: rgba(0,255,209,0.12); box-shadow: 0 0 0 1px rgba(0,255,209,0.20) inset, 0 0 24px rgba(0,255,209,0.10); }
    .node-btn .dot{ width: 8px; height: 8px; border-radius: 999px; background: rgba(0,255,209,0.92); box-shadow: 0 0 16px rgba(0,255,209,0.55); flex:0 0 auto; }
    .node-btn.danger .dot{ background: rgba(255,120,120,0.95); box-shadow: 0 0 16px rgba(255,120,120,0.45); }

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
  private followingIds = new Set<string>();
  private followBusyMap = new Map<string, boolean>();

  private lastPresenceSnap: PresenceSnapshot | null = null;

  countryTab: CountryTab = 'posts';
  composerOpen = false;

  private queryParamSub?: Subscription;
  private postEventsCreatedSub?: Subscription;
  private postEventsInsertSub?: Subscription;
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
    private presence: PresenceService,
    private postsService: PostsService,
    private postEvents: PostEventsService,
    private followService: FollowService,
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
      } else {
        this.followingIds.clear();
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
    this.globeService.flyTo(country.center.lat, country.center.lng, country.flyAltitude ?? 1.0, 900);

    this.recomputeLocal();
    this.postComposerError = '';
    this.postsError = '';
    this.forceUi();

    setTimeout(() => this.globeService.resize(), 0);
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
    }
  }

  private handleCountryPostEvent(post: CountryPost): void {
    const currentCode = this.selectedCountry?.code?.toUpperCase() ?? null;
    const postCode = post.country_code?.toUpperCase() ?? null;
    if (!currentCode || !postCode || currentCode !== postCode) {
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
    return value === 'presence' || value === 'posts';
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

    this.forceUi();
    if (!opts?.skipRouteUpdate) this.updateRouteState();
  }

  closePanel(opts?: { skipRouteUpdate?: boolean }): void {
    if (!this.panel) return;
    this.panel = null;
    this.adjustingAvatar = false;
    this.dragging = false;
    this.msg = '';
    this.saveState = 'idle';
    this.avatarPreviewOpen = false;
    this.forceUi();
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
