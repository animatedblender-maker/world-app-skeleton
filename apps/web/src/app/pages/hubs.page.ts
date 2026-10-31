import { CommonModule } from '@angular/common';
import {
  AfterViewChecked,
  ChangeDetectorRef,
  Component,
  ElementRef,
  OnInit,
} from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { BottomTabsComponent } from '../components/bottom-tabs.component';
import { HubsVideoRowComponent } from '../components/hubs-video-row.component';
import { MatteryaTopbarComponent } from '../components/matterya-topbar.component';
import { MatteryaCopy } from '../core/copy/matterya-copy';
import type { CountryPost } from '../core/models/post.model';
import { AuthService } from '../core/services/auth.service';
import { NotificationsUiService } from '../core/services/notifications-ui.service';
import { FollowService } from '../core/services/follow.service';
import { LocationService } from '../core/services/location.service';
import { ProfileService } from '../core/services/profile.service';
import { resolveAvatarUrl, resolveMediaUrl } from '../core/utils/media-url.util';
import {
  HUBS_HOME_FILTERS,
  HubsCatalogService,
  type HubsChannel,
  type HubsLibrarySection,
} from '../hubs/hubs-catalog.service';
import { HubsPlaybackService } from '../hubs/hubs-playback.service';
import { HubsSeedService } from '../hubs/hubs-seed.service';

type HubsMode = 'home' | 'library';

type HubsRail = {
  id: string;
  title: string;
  posts: CountryPost[];
};

@Component({
  selector: 'app-hubs-page',
  standalone: true,
  imports: [
    CommonModule,
    FormsModule,
    BottomTabsComponent,
    HubsVideoRowComponent,
    MatteryaTopbarComponent,
  ],
  template: `
    <div class="hubs-shell">
      <app-matterya-topbar
        [title]="copy.matteryaHubs"
        (search)="showSearch = true"
        (notifications)="openNotifications()"
      ></app-matterya-topbar>

      <div class="home-bar" *ngIf="mode === 'home'">
        <button type="button" class="library-chip" (click)="openLibrary()">Library</button>
      </div>

      <main class="hubs-body" *ngIf="mode === 'home'">
        <div class="state" *ngIf="loading">{{ copy.loadingHubs }}</div>
        <div class="state error" *ngIf="!loading && error">{{ error }}</div>
        <div class="state" *ngIf="!loading && !error && homeEmpty">
          No videos here yet. {{ copy.hubsPublishHint }}
        </div>

        <ng-container *ngIf="!loading && !error && !homeEmpty">
          <!-- Netflix hero -->
          <section class="hero" *ngIf="heroPost as hero" (click)="openVideo(hero)">
            <div class="hero-media">
              <img *ngIf="thumb(hero)" [src]="thumb(hero)" alt="" />
              <div class="hero-scrim"></div>
              <div class="hero-copy">
                <div class="hero-kicker">People's cinema</div>
                <div class="hero-title">{{ catalog.displayHeadline(hero) }}</div>
                <div class="hero-actions">
                  <span class="hero-play">Play</span>
                  <span class="hero-author" *ngIf="catalog.displayAuthor(hero)">{{
                    catalog.displayAuthor(hero)
                  }}</span>
                </div>
              </div>
            </div>
          </section>

          <!-- Continue watching -->
          <section class="shelf" *ngIf="continueRail.length">
            <div class="section-title">{{ copy.continueWatching }}</div>
            <div
              class="rail"
              [attr.data-loop-n]="continueRail.length"
              (scroll)="onContinueRailScroll($event)"
            >
              <button
                type="button"
                class="rail-card"
                *ngFor="let p of loopedPosts(continueRail); trackBy: trackLooped"
                (click)="openVideo(p)"
              >
                <div class="rail-thumb">
                  <img *ngIf="thumb(p)" [src]="thumb(p)" alt="" />
                </div>
                <div class="rail-title">{{ catalog.displayHeadline(p) }}</div>
                <div class="progress"><span [style.width.%]="progressPercent(p)"></span></div>
              </button>
            </div>
          </section>

          <!-- Because you watched -->
          <section class="shelf" *ngIf="becauseRail?.posts?.length">
            <div class="section-title">{{ becauseRail!.title }}</div>
            <div
              class="rail"
              [attr.data-loop-n]="becauseRail!.posts.length"
              (scroll)="onLoopingRailScroll($event, becauseRail!.posts.length)"
            >
              <button
                type="button"
                class="rail-card"
                *ngFor="let p of loopedPosts(becauseRail!.posts); trackBy: trackLooped"
                (click)="openVideo(p)"
              >
                <div class="rail-thumb">
                  <img *ngIf="thumb(p)" [src]="thumb(p)" alt="" />
                </div>
                <div class="rail-title">{{ catalog.displayHeadline(p) }}</div>
              </button>
            </div>
          </section>

          <!-- From people like you -->
          <section class="shelf" *ngIf="peopleRail.length">
            <div class="section-title">From people like you</div>
            <div
              class="rail"
              [attr.data-loop-n]="peopleRail.length"
              (scroll)="onLoopingRailScroll($event, peopleRail.length)"
            >
              <button
                type="button"
                class="rail-card wide"
                *ngFor="let p of loopedPosts(peopleRail); trackBy: trackLooped"
                (click)="openVideo(p)"
              >
                <div class="rail-thumb">
                  <img *ngIf="thumb(p)" [src]="thumb(p)" alt="" />
                </div>
                <div class="rail-title">{{ catalog.displayHeadline(p) }}</div>
              </button>
            </div>
          </section>

          <!-- Following -->
          <section class="shelf" *ngIf="subscriptionChannels.length || followingRail.length">
            <div class="section-title">Following</div>
            <div class="channel-rail" *ngIf="subscriptionChannels.length">
              <button
                type="button"
                class="channel"
                *ngFor="let c of subscriptionChannels; trackBy: trackChannel"
                (click)="openChannel(c)"
              >
                <div class="channel-avatar">
                  <img *ngIf="avatar(c)" [src]="avatar(c)" alt="" />
                  <span *ngIf="!avatar(c)">{{ c.title.slice(0, 2).toUpperCase() }}</span>
                </div>
                <div class="channel-name">{{ c.title }}</div>
              </button>
            </div>
            <div
              class="rail"
              *ngIf="followingRail.length"
              [attr.data-loop-n]="followingRail.length"
              (scroll)="onLoopingRailScroll($event, followingRail.length)"
            >
              <button
                type="button"
                class="rail-card"
                *ngFor="let p of loopedPosts(followingRail); trackBy: trackLooped"
                (click)="openVideo(p)"
              >
                <div class="rail-thumb">
                  <img *ngIf="thumb(p)" [src]="thumb(p)" alt="" />
                </div>
                <div class="rail-title">{{ catalog.displayHeadline(p) }}</div>
              </button>
            </div>
          </section>

          <!-- Vibe / category rails -->
          <section class="shelf" *ngFor="let rail of vibeRails; trackBy: trackRail">
            <div class="section-title">{{ rail.title }}</div>
            <div
              class="rail"
              [attr.data-loop-n]="rail.posts.length"
              (scroll)="onLoopingRailScroll($event, rail.posts.length)"
            >
              <button
                type="button"
                class="rail-card"
                *ngFor="let p of loopedPosts(rail.posts); trackBy: trackLooped"
                (click)="openVideo(p)"
              >
                <div class="rail-thumb">
                  <img *ngIf="thumb(p)" [src]="thumb(p)" alt="" />
                </div>
                <div class="rail-title">{{ catalog.displayHeadline(p) }}</div>
              </button>
            </div>
          </section>

          <!-- More to watch -->
          <section class="shelf" *ngFor="let rail of moreRails; trackBy: trackRail">
            <div class="section-title">{{ rail.title }}</div>
            <div
              class="rail"
              [attr.data-loop-n]="rail.posts.length"
              (scroll)="onLoopingRailScroll($event, rail.posts.length)"
            >
              <button
                type="button"
                class="rail-card"
                *ngFor="let p of loopedPosts(rail.posts); trackBy: trackLooped"
                (click)="openVideo(p)"
              >
                <div class="rail-thumb">
                  <img *ngIf="thumb(p)" [src]="thumb(p)" alt="" />
                </div>
                <div class="rail-title">{{ catalog.displayHeadline(p) }}</div>
              </button>
            </div>
          </section>
        </ng-container>
      </main>

      <main class="library-screen" *ngIf="mode === 'library'">
        <header class="library-top">
          <button type="button" class="back" (click)="mode = 'home'" aria-label="Back">‹</button>
          <div class="library-title">Library</div>
        </header>
        <div class="library-tabs">
          <button
            type="button"
            class="chip"
            *ngFor="let s of librarySections"
            [class.active]="librarySection === s.id"
            (click)="librarySection = s.id"
          >
            {{ s.title }}
          </button>
        </div>
        <div class="state" *ngIf="!libraryVideos.length">{{ libraryEmptyText }}</div>
        <div class="sparks-grid" *ngIf="librarySection === 'reels' && libraryVideos.length">
          <button
            type="button"
            class="spark-cell"
            *ngFor="let p of libraryVideos; trackBy: trackById"
            (click)="openSpark(p)"
          >
            <img *ngIf="thumb(p)" [src]="thumb(p)" alt="" />
          </button>
        </div>
        <div class="hubs-video-grid" *ngIf="librarySection !== 'reels'">
          <app-hubs-video-row
            *ngFor="let p of libraryVideos; trackBy: trackById"
            [post]="p"
            (open)="openVideo($event)"
          ></app-hubs-video-row>
        </div>
      </main>

      <button type="button" class="search-backdrop" *ngIf="showSearch" (click)="closeSearch()" aria-label="Close search"></button>
      <section class="search-panel" *ngIf="showSearch">
        <div class="search-head">
          <input
            name="hubsSearch"
            [(ngModel)]="searchQuery"
            [placeholder]="copy.searchHubs"
            autocomplete="off"
            autofocus
          />
          <button type="button" (click)="closeSearch()" aria-label="Close">×</button>
        </div>
        <div class="search-state" *ngIf="!searchQuery.trim()">{{ copy.searchHubsHint }}</div>
        <button
          type="button"
          class="search-channel"
          *ngFor="let c of searchResults.channels; trackBy: trackChannel"
          (click)="openChannel(c)"
        >
          <div class="channel-avatar small">
            <img *ngIf="avatar(c)" [src]="avatar(c)" alt="" />
            <span *ngIf="!avatar(c)">{{ c.title.slice(0, 2).toUpperCase() }}</span>
          </div>
          <div>
            <div class="s-title">{{ c.title }}</div>
            <div class="s-sub">{{ c.videoCount }} videos</div>
          </div>
        </button>
        <app-hubs-video-row
          *ngFor="let p of searchResults.videos; trackBy: trackById"
          [post]="p"
          (open)="openVideo($event)"
        ></app-hubs-video-row>
      </section>

      <app-bottom-tabs></app-bottom-tabs>
    </div>
  `,
  styles: [
    `
      :host {
        display: block;
        min-height: 100%;
        background: var(--m-paper, #f8f6f2);
        color: var(--m-ink, #2c2825);
      }
      .hubs-shell {
        min-height: 100vh;
        padding-bottom: calc(var(--tabs-safe, 72px) + 16px);
        background: var(--m-paper, #f8f6f2);
      }
      .home-bar {
        display: flex;
        justify-content: flex-end;
        padding: 6px var(--m-page-padding, 16px) 2px;
      }
      .library-chip {
        border: 0.5px solid var(--m-border, #ddd8d1);
        background: var(--m-surface, #fefdfb);
        color: var(--m-ink, #2c2825);
        font-size: 12px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        padding: 8px 14px;
        border-radius: 999px;
        cursor: pointer;
      }
      .library-tabs {
        display: flex;
        gap: 4px;
        min-height: 48px;
        overflow-x: auto;
        padding: 4px var(--m-page-padding, 16px);
        background: var(--m-paper, #f8f6f2);
        border-bottom: 0.5px solid var(--m-divider, #e2ded8);
        scrollbar-width: none;
      }
      .library-tabs::-webkit-scrollbar {
        display: none;
      }
      .chip {
        flex: 0 0 auto;
        border: 0;
        background: transparent;
        color: var(--m-ink-muted, #948b82);
        font-size: 12px;
        font-weight: 700;
        text-transform: uppercase;
        padding: 8px 12px;
        position: relative;
        cursor: pointer;
      }
      .chip.active {
        color: var(--m-ink, #2c2825);
      }
      .chip.active::after {
        content: '';
        position: absolute;
        left: 12px;
        right: 12px;
        bottom: 2px;
        height: 1px;
        background: var(--m-ink, #2c2825);
      }
      .hubs-body,
      .library-screen {
        max-width: none;
        margin: 0;
        padding: 4px 0 24px;
        width: 100%;
      }
      .hubs-video-grid {
        display: grid;
        grid-template-columns: 1fr;
        gap: 0;
      }
      .state,
      .search-state {
        padding: 44px 16px;
        text-align: center;
        color: var(--m-ink-muted, #948b82);
        font-size: 14px;
      }
      .state.error {
        color: var(--m-danger, #ea000b);
      }

      /* Hero — ink/matte cinema billboard */
      .hero {
        padding: 0 var(--m-page-padding, 16px) 18px;
        cursor: pointer;
      }
      .hero-media {
        position: relative;
        width: 100%;
        height: min(320px, max(220px, 56vw));
        border-radius: 22px;
        overflow: hidden;
        background: var(--m-ink, #2c2825);
      }
      .hero-media img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .hero-scrim {
        position: absolute;
        inset: 0;
        background: linear-gradient(
          to bottom,
          transparent 20%,
          color-mix(in srgb, var(--m-ink, #2c2825) 55%, transparent) 70%,
          color-mix(in srgb, var(--m-ink, #2c2825) 92%, transparent) 100%
        );
      }
      .hero-copy {
        position: absolute;
        left: 0;
        right: 0;
        bottom: 0;
        padding: 22px;
        color: var(--m-paper, #f8f6f2);
      }
      .hero-kicker {
        font-size: 11px;
        font-weight: 700;
        letter-spacing: 1.2px;
        text-transform: uppercase;
        opacity: 0.78;
        margin-bottom: 8px;
      }
      .hero-title {
        font-size: clamp(20px, 4.5vw, 28px);
        font-weight: 700;
        line-height: 1.2;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .hero-actions {
        display: flex;
        align-items: center;
        gap: 12px;
        margin-top: 14px;
      }
      .hero-play {
        display: inline-flex;
        align-items: center;
        padding: 10px 18px;
        border-radius: 999px;
        background: var(--m-paper, #f8f6f2);
        color: var(--m-ink, #2c2825);
        font-size: 13px;
        font-weight: 700;
      }
      .hero-author {
        font-size: 13px;
        font-weight: 500;
        opacity: 0.9;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .shelf {
        padding-bottom: 22px;
      }
      .section-title {
        padding: 0 var(--m-page-padding, 16px) 10px;
        color: var(--m-ink, #2c2825);
        font-size: 17px;
        font-weight: 700;
        line-height: 1.25;
      }
      .rail,
      .channel-rail {
        display: flex;
        gap: 12px;
        overflow-x: auto;
        padding: 0 var(--m-page-padding, 16px);
        scrollbar-width: thin;
        -webkit-overflow-scrolling: touch;
        scroll-snap-type: x proximity;
      }
      .rail {
        padding-bottom: 4px;
      }
      .rail::-webkit-scrollbar {
        height: 6px;
      }
      .rail::-webkit-scrollbar-thumb {
        background: var(--m-border, #ddd8d1);
        border-radius: 999px;
      }
      .channel-rail::-webkit-scrollbar {
        display: none;
      }
      .rail-card {
        flex: 0 0 62vw;
        max-width: 280px;
        min-width: 168px;
        width: min(280px, 62vw);
        border: 0;
        background: transparent;
        padding: 0;
        color: inherit;
        text-align: left;
        cursor: pointer;
        scroll-snap-align: start;
      }
      .rail-card.wide {
        flex-basis: 68vw;
        max-width: 300px;
        width: min(300px, 68vw);
      }
      .rail-thumb {
        width: 100%;
        aspect-ratio: 16 / 9;
        background: var(--m-ink, #2c2825);
        border-radius: 12px;
        overflow: hidden;
      }
      .rail-thumb img,
      .spark-cell img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .rail-title {
        margin-top: 7px;
        font-size: 13px;
        font-weight: 650;
        line-height: 1.25;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
        color: var(--m-ink, #2c2825);
      }
      .progress {
        margin-top: 7px;
        height: 2px;
        border-radius: 999px;
        background: var(--m-canvas-deep, #edeae5);
        overflow: hidden;
      }
      .progress span {
        display: block;
        height: 100%;
        background: var(--m-ink, #2c2825);
      }
      .channel {
        flex: 0 0 72px;
        border: 0;
        background: transparent;
        padding: 0 0 8px;
        color: inherit;
        cursor: pointer;
      }
      .channel-avatar {
        width: 52px;
        height: 52px;
        margin: 0 auto 6px;
        border-radius: 999px;
        overflow: hidden;
        background: var(--m-canvas-deep, #edeae5);
        display: grid;
        place-items: center;
        font-size: 12px;
        font-weight: 700;
      }
      .channel-avatar.small {
        width: 42px;
        height: 42px;
        margin: 0;
        flex: 0 0 auto;
      }
      .channel-avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .channel-name {
        font-size: 11px;
        font-weight: 650;
        line-height: 1.2;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        color: var(--m-ink, #2c2825);
      }
      .library-top {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 2px var(--m-page-padding, 16px) 10px;
        border-bottom: 0.5px solid var(--m-divider, #e2ded8);
      }
      .back {
        width: 36px;
        height: 36px;
        border-radius: 999px;
        border: 0.5px solid var(--m-border, #ddd8d1);
        background: var(--m-surface, #fefdfb);
        color: var(--m-ink, #2c2825);
        font-size: 24px;
        cursor: pointer;
      }
      .library-title {
        font-size: 16px;
        font-weight: 700;
      }
      .sparks-grid {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 8px;
        padding: 8px var(--m-page-padding, 16px) 24px;
      }
      .spark-cell {
        border: 0;
        padding: 0;
        aspect-ratio: 9 / 16;
        border-radius: 0;
        overflow: hidden;
        background: var(--m-ink, #2c2825);
        cursor: pointer;
      }
      .search-backdrop {
        position: fixed;
        inset: 0;
        z-index: 110;
        border: 0;
        background: color-mix(in srgb, var(--m-ink, #2c2825) 18%, transparent);
      }
      .search-panel {
        position: fixed;
        left: 0;
        right: 0;
        top: 0;
        bottom: 0;
        z-index: 111;
        overflow-y: auto;
        background: var(--m-paper, #f8f6f2);
        padding: calc(env(safe-area-inset-top) + 12px) 0 calc(var(--tabs-safe, 72px) + 24px);
      }
      .search-head {
        display: flex;
        gap: 8px;
        padding: 0 var(--m-page-padding, 16px) 12px;
        max-width: none;
        margin: 0 auto;
      }
      .search-head input {
        flex: 1;
        min-width: 0;
        border: 0.5px solid var(--m-border, #ddd8d1);
        background: var(--m-canvas-muted, #f2f0ec);
        border-radius: 8px;
        padding: 11px 12px;
        font-size: 16px;
        color: var(--m-ink, #2c2825);
      }
      .search-head button {
        width: 40px;
        height: 40px;
        border: 0;
        background: transparent;
        color: var(--m-ink, #2c2825);
        font-size: 24px;
        cursor: pointer;
      }
      .search-channel {
        display: flex;
        align-items: center;
        gap: 12px;
        width: 100%;
        max-width: none;
        margin: 0 auto;
        border: 0;
        background: transparent;
        color: inherit;
        text-align: left;
        padding: 10px var(--m-page-padding, 16px);
        cursor: pointer;
      }
      .s-title {
        font-size: 14px;
        font-weight: 700;
      }
      .s-sub {
        margin-top: 2px;
        color: var(--m-ink-muted, #948b82);
        font-size: 12px;
      }

      /* Desktop = wider layout only, same Netflix components */
      @media (min-width: 900px) {
        .hubs-shell {
          padding-bottom: 24px;
        }
        .home-bar,
        .library-tabs {
          padding-left: 16px;
          padding-right: 16px;
        }
        .hero {
          padding: 0 16px 22px;
        }
        .hero-media {
          height: min(360px, 42vw);
        }
        .section-title {
          padding: 0 16px 12px;
          font-size: 18px;
        }
        .rail,
        .channel-rail {
          padding: 0 16px 6px;
          gap: 14px;
        }
        .rail-card {
          flex: 0 0 240px;
          width: 240px;
          max-width: 240px;
          min-width: 240px;
        }
        .rail-card.wide {
          flex: 0 0 260px;
          width: 260px;
          max-width: 260px;
          min-width: 260px;
        }
        .rail-title {
          font-size: 13px;
        }
        .hubs-video-grid {
          grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
          gap: 16px 14px;
          padding: 0 16px;
        }
        .sparks-grid {
          grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
          gap: 10px;
          padding: 0 16px;
        }
        .search-panel {
          left: var(--m-sidebar-w, 200px);
          width: min(520px, calc(100vw - var(--m-sidebar-w, 200px)));
        }
        .search-backdrop {
          left: var(--m-sidebar-w, 200px);
        }
      }
      @media (min-width: 1400px) {
        .rail-card {
          flex: 0 0 260px;
          width: 260px;
          max-width: 260px;
          min-width: 260px;
        }
        .rail-card.wide {
          flex: 0 0 280px;
          width: 280px;
          max-width: 280px;
          min-width: 280px;
        }
        .hubs-video-grid {
          grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
          gap: 18px 16px;
          padding: 0 18px;
        }
      }
    `,
  ],
})
export class HubsPageComponent implements OnInit, AfterViewChecked {
  /** Product floor: unique media per dense Netflix row (iOS rails rebuild rule). */
  private static readonly railN = 15;
  private static readonly vibeRailCount = 3;
  private static readonly moreRailRows = 2;
  private static readonly softFloor = 6;
  private static readonly railGapPx = 12;

  readonly copy = MatteryaCopy;

  allVideos: CountryPost[] = [];
  channels: HubsChannel[] = [];
  homeCountry: string | null = null;
  mode: HubsMode = 'home';
  librarySection: HubsLibrarySection = 'history';
  loading = true;
  error = '';
  showSearch = false;
  searchQuery = '';
  meId: string | null = null;
  followingIds = new Set<string>();

  heroPost: CountryPost | null = null;
  continueRail: CountryPost[] = [];
  becauseRail: HubsRail | null = null;
  peopleRail: CountryPost[] = [];
  followingRail: CountryPost[] = [];
  vibeRails: HubsRail[] = [];
  moreRails: HubsRail[] = [];

  librarySections: { id: HubsLibrarySection; title: string }[] = [
    { id: 'history', title: 'History' },
    { id: 'reels', title: MatteryaCopy.sparks },
    { id: 'saved', title: 'Saved' },
    { id: 'liked', title: 'Liked' },
    { id: 'uploads', title: 'Uploads' },
  ];

  continueVisibleCount = HubsPageComponent.railN;
  private readonly continuePageSize = HubsPageComponent.railN;
  private loopingJump = false;
  private continueNearEndArmed = true;
  private loopNeedsReset = false;

  constructor(
    public catalog: HubsCatalogService,
    private auth: AuthService,
    private cdr: ChangeDetectorRef,
    private follow: FollowService,
    private host: ElementRef<HTMLElement>,
    private location: LocationService,
    private playback: HubsPlaybackService,
    private profiles: ProfileService,
    private notificationsUi: NotificationsUiService,
    private router: Router
  ) {}

  ngOnInit(): void {
    void this.refresh();
  }

  ngAfterViewChecked(): void {
    if (this.loading || this.mode !== 'home') return;
    if (this.loopNeedsReset) {
      const root = this.host.nativeElement;
      root.querySelectorAll<HTMLElement>('.rail[data-loop-n]').forEach((el) => {
        delete el.dataset['loopInit'];
      });
      this.loopNeedsReset = false;
    }
    this.initLoopingRailOffsets();
  }

  get playReels(): CountryPost[] {
    return this.catalog.reels(this.allVideos);
  }

  get continueWatchingAll(): CountryPost[] {
    return this.catalog.continueWatchingFeed(this.allVideos);
  }

  get subscriptionVideos(): CountryPost[] {
    return this.catalog.subscriptionFeed(this.allVideos, this.followingIds);
  }

  get subscriptionChannels(): HubsChannel[] {
    return this.catalog.subscriptionChannels(this.channels, this.followingIds);
  }

  get homeEmpty(): boolean {
    return (
      !this.heroPost &&
      !this.continueRail.length &&
      !this.becauseRail?.posts?.length &&
      !this.peopleRail.length &&
      !this.followingRail.length &&
      !this.vibeRails.length &&
      !this.moreRails.length &&
      !this.subscriptionChannels.length
    );
  }

  get libraryVideos(): CountryPost[] {
    switch (this.librarySection) {
      case 'history':
        return this.catalog.historyVideos(this.allVideos);
      case 'reels':
        return this.catalog.reels(this.allVideos).filter((p) => this.catalog.isSaved(p.id) || p.author_id === this.meId);
      case 'saved':
        return this.catalog.savedVideos(this.allVideos);
      case 'liked':
        return this.catalog.likedVideos(this.allVideos);
      case 'uploads':
        return this.catalog.myUploads(this.allVideos, this.meId);
    }
  }

  get libraryEmptyText(): string {
    switch (this.librarySection) {
      case 'history':
        return 'Nothing in history yet. Videos you watch will appear here.';
      case 'reels':
        return MatteryaCopy.saveSparksHint;
      case 'saved':
        return 'No saved videos. Tap Save on any video to watch later.';
      case 'liked':
        return 'No liked videos. Like videos while watching to collect them here.';
      case 'uploads':
        return `No uploads yet. Publish a video or ${MatteryaCopy.spark.toLowerCase()} from Create.`;
    }
  }

  get searchResults(): { videos: CountryPost[]; channels: HubsChannel[] } {
    return this.catalog.search(this.searchQuery, this.allVideos, this.channels);
  }

  private async refresh(): Promise<void> {
    this.loading = true;
    this.error = '';
    this.continueVisibleCount = this.continuePageSize;
    this.homeCountry = this.location.getCachedLocation()?.countryCode?.trim().toUpperCase() || null;
    this.paint();

    try {
      const user = await this.auth.getUser().catch(() => null);
      this.meId = user?.id || null;
      if (this.meId) {
        const [following, profileResult] = await Promise.all([
          this.follow.listFollowingIds(this.meId).catch(() => [] as string[]),
          this.profiles.meProfile().catch(() => ({ meProfile: null })),
        ]);
        this.followingIds = new Set(following);
        if (profileResult.meProfile?.country_code) {
          this.homeCountry = String(profileResult.meProfile.country_code).trim().toUpperCase();
        }
      }

      this.allVideos = await this.catalog.loadCatalog({
        forceRefresh: false,
        followingIDs: [...this.followingIds],
        viewerCountry: this.homeCountry,
      });
      this.channels = this.catalog.currentChannels;
      this.rebuildRails();
    } catch (e: any) {
      this.error = e?.message || MatteryaCopy.hubsLoadError;
      this.allVideos = [];
      this.channels = [];
      this.clearRails();
    } finally {
      this.loading = false;
      this.paint();
    }
  }

  private clearRails(): void {
    this.heroPost = null;
    this.continueRail = [];
    this.becauseRail = null;
    this.peopleRail = [];
    this.followingRail = [];
    this.vibeRails = [];
    this.moreRails = [];
    this.loopNeedsReset = true;
  }

  /**
   * Ports iOS rebuildCachedHubsRails lightly:
   * hero → Continue → Because → people → Following → vibe → more.
   * Global claim by id + media fingerprint; dense floor ~15 unique media.
   */
  private rebuildRails(): void {
    const railN = HubsPageComponent.railN;
    const minRail = HubsPageComponent.softFloor;
    const ranked = this.catalog.filterVideos(
      this.allVideos,
      'all',
      this.followingIds,
      this.homeCountry
    );
    const history = this.catalog.historyVideos(this.allVideos).filter((p) => this.catalog.isLongForm(p));

    const continueSeed = history.length
      ? history
      : this.catalog.continueWatchingFeed(this.allVideos, railN * 2);
    this.heroPost = continueSeed[0] ?? ranked[0] ?? this.allVideos.find((p) => this.catalog.isLongForm(p)) ?? null;

    const claimedIds = new Set<string>();
    const claimedMedia = new Set<string>();
    const mediaKey = (p: CountryPost) => this.catalog.railMediaKey(p);

    const claimOne = (post: CountryPost): boolean => {
      const key = mediaKey(post);
      if (claimedIds.has(post.id) || claimedMedia.has(key)) return false;
      claimedIds.add(post.id);
      claimedMedia.add(key);
      return true;
    };

    const claim = (posts: CountryPost[], limit: number): CountryPost[] => {
      const out: CountryPost[] = [];
      for (const post of posts) {
        if (!this.catalog.isLongForm(post)) continue;
        if (!claimOne(post)) continue;
        out.push(post);
        if (out.length >= limit) break;
      }
      return out;
    };

    const padToRailN = (seed: CountryPost[]): CountryPost[] => {
      if (seed.length >= railN) return seed.slice(0, railN);
      const out = [...seed];
      const filler = ranked.filter((p) => !claimedIds.has(p.id) && !claimedMedia.has(mediaKey(p)));
      out.push(...claim(filler, railN - out.length));
      return out;
    };

    if (this.heroPost) claimOne(this.heroPost);

    // Continue — pad toward product floor from ranked leftovers.
    const continueClaimed = claim(continueSeed, railN);
    this.continueRail = padToRailN(continueClaimed).slice(0, this.continueVisibleCount);

    // Because you watched — same-slug related from seed.
    const becauseSeed = continueSeed[0] ?? this.heroPost;
    if (becauseSeed) {
      claimOne(becauseSeed);
      const seedSlug = this.catalog.parentHubSlug(becauseSeed);
      const related = ranked.filter((p) => {
        if (p.id === becauseSeed.id) return false;
        const slug = this.catalog.parentHubSlug(p);
        if (seedSlug && slug) return slug === seedSlug;
        return p.author_id === becauseSeed.author_id;
      });
      const becausePosts = claim(related, railN);
      const padded = becausePosts.length >= minRail ? padToRailN(becausePosts) : becausePosts;
      this.becauseRail =
        padded.length >= minRail
          ? {
              id: `because-${becauseSeed.id}`,
              title: this.becauseYouWatchedTitle(becauseSeed),
              posts: padded.slice(0, railN),
            }
          : null;
    } else {
      this.becauseRail = null;
    }

    // People like you — unclaimed ranked.
    const peopleCandidates = ranked.filter(
      (p) => !claimedIds.has(p.id) && !claimedMedia.has(mediaKey(p))
    );
    this.peopleRail = padToRailN(claim(peopleCandidates, railN)).slice(0, railN);

    // Following rail (horizontal, not a vertical grid).
    this.followingRail = claim(this.subscriptionVideos, railN);

    // One-pass slug buckets (ranked order).
    const buckets = new Map<string, CountryPost[]>();
    const bucketSeen = new Map<string, Set<string>>();
    for (const post of ranked) {
      if (!this.catalog.isLongForm(post)) continue;
      const slug = this.catalog.parentHubSlug(post) || 'daily';
      const key = mediaKey(post);
      let seen = bucketSeen.get(slug);
      if (!seen) {
        seen = new Set();
        bucketSeen.set(slug, seen);
      }
      if (seen.has(key)) continue;
      seen.add(key);
      const list = buckets.get(slug) ?? [];
      if (list.length < railN * 2) {
        list.push(post);
        buckets.set(slug, list);
      }
    }

    const titleForSlug = (slug: string): string => {
      const known = HUBS_HOME_FILTERS.find((f) => f.id === slug);
      if (known) return known.title;
      return HubsSeedService.channelDisplayName(slug, false);
    };

    const vibe: HubsRail[] = [];
    for (const slug of HubsSeedService.hubOrder) {
      if (vibe.length >= HubsPageComponent.vibeRailCount) break;
      const seed = buckets.get(slug) ?? [];
      let posts = claim(seed, railN);
      if (posts.length < railN && posts.length >= Math.max(4, minRail - 2)) {
        posts = padToRailN(posts);
      }
      if (posts.length < minRail) {
        for (const post of posts) {
          claimedIds.delete(post.id);
          claimedMedia.delete(mediaKey(post));
        }
        continue;
      }
      vibe.push({ id: `vibe-${slug}`, title: titleForSlug(slug), posts: posts.slice(0, railN) });
    }
    // Extra slugs not in hubOrder if still short on vibe rows.
    if (vibe.length < HubsPageComponent.vibeRailCount) {
      for (const [slug, seed] of buckets) {
        if (vibe.length >= HubsPageComponent.vibeRailCount) break;
        if (HubsSeedService.hubOrder.includes(slug as (typeof HubsSeedService.hubOrder)[number])) continue;
        let posts = claim(seed, railN);
        if (posts.length < railN && posts.length >= minRail) posts = padToRailN(posts);
        if (posts.length < minRail) continue;
        vibe.push({ id: `vibe-${slug}`, title: titleForSlug(slug), posts: posts.slice(0, railN) });
      }
    }
    this.vibeRails = vibe;

    // More to watch leftovers.
    const fillerTitles = [
      'Fresh uploads',
      'Keep browsing',
      'More to watch',
      'Popular now',
      'Still more',
      'Worth another look',
      'Deep cuts',
      'Browse all',
    ];
    const rest = ranked.filter((p) => !claimedIds.has(p.id) && !claimedMedia.has(mediaKey(p)));
    const more: HubsRail[] = [];
    let offset = 0;
    let row = 0;
    while (offset < rest.length && row < HubsPageComponent.moreRailRows) {
      const window = rest.slice(offset, offset + railN * 2);
      let slice = claim(window, railN);
      if (slice.length < railN && slice.length >= minRail) slice = padToRailN(slice);
      offset += railN;
      if (slice.length < minRail) break;
      more.push({
        id: `more-${row}`,
        title: fillerTitles[Math.min(row, fillerTitles.length - 1)],
        posts: slice.slice(0, railN),
      });
      row += 1;
    }
    this.moreRails = more;
    this.loopNeedsReset = true;
  }

  private becauseYouWatchedTitle(post: CountryPost): string {
    const raw = this.catalog
      .displayHeadline(post)
      .replace(/\n/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
    if (!raw) return 'Because you watched';
    const maxChars = 42;
    if (raw.length <= maxChars) return `Because you watched ${raw}`;
    return `Because you watched ${raw.slice(0, maxChars).trim()}…`;
  }

  /** 2-cycle DOM for endless rails; short shelves stay a plain row. */
  loopedPosts(posts: CountryPost[]): CountryPost[] {
    if (!posts?.length) return [];
    if (posts.length < 3) return posts;
    return posts.concat(posts);
  }

  trackLooped(index: number, p: CountryPost): string {
    return `${index}-${p.id}`;
  }

  onContinueRailScroll(ev: Event): void {
    const n = this.continueRail.length;
    this.onLoopingRailScroll(ev, n);
    if (n < 3) {
      this.growContinueIfNearEnd(ev);
      return;
    }
    if (!this.continueNearEndArmed) return;
    const el = ev.target as HTMLElement | null;
    if (!el) return;
    const first = el.children[0] as HTMLElement | undefined;
    if (!first?.offsetWidth) return;
    const stride = first.offsetWidth + HubsPageComponent.railGapPx;
    const cycleWidth = n * stride;
    if (cycleWidth <= 0) return;
    const logical = Math.floor((el.scrollLeft % cycleWidth) / stride);
    if (logical > n * 0.72) {
      this.continueNearEndArmed = false;
      this.growContinueRail();
      window.setTimeout(() => {
        this.continueNearEndArmed = true;
      }, 1200);
    }
  }

  onLoopingRailScroll(ev: Event, n: number): void {
    if (n < 3 || this.loopingJump) return;
    const el = ev.target as HTMLElement | null;
    if (!el) return;
    const first = el.children[0] as HTMLElement | undefined;
    if (!first?.offsetWidth) return;
    const stride = first.offsetWidth + HubsPageComponent.railGapPx;
    const cycleWidth = n * stride;
    if (cycleWidth <= 0) return;

    if (el.scrollLeft < cycleWidth * 0.35) {
      this.loopingJump = true;
      el.scrollLeft += cycleWidth;
      this.loopingJump = false;
    } else if (el.scrollLeft > cycleWidth * 1.35) {
      this.loopingJump = true;
      el.scrollLeft -= cycleWidth;
      this.loopingJump = false;
    }
  }

  private growContinueIfNearEnd(event: Event): void {
    const el = event.target as HTMLElement | null;
    if (!el) return;
    const remaining = el.scrollWidth - el.scrollLeft - el.clientWidth;
    if (remaining < 280) this.growContinueRail();
  }

  private growContinueRail(): void {
    const all = this.continueWatchingAll;
    if (this.continueVisibleCount >= Math.min(all.length, HubsPageComponent.railN * 3)) return;
    this.continueVisibleCount = Math.min(
      Math.min(all.length, HubsPageComponent.railN * 3),
      this.continueVisibleCount + this.continuePageSize
    );
    const ids = new Set(this.continueRail.map((p) => p.id));
    for (const p of all) {
      if (this.continueRail.length >= this.continueVisibleCount) break;
      if (ids.has(p.id) || !this.catalog.isLongForm(p)) continue;
      this.continueRail.push(p);
      ids.add(p.id);
    }
    this.paint();
  }

  /** Seed each looping rail to cycle-1 head so both edges can wrap. */
  private initLoopingRailOffsets(): void {
    const root = this.host.nativeElement;
    const rails = root.querySelectorAll<HTMLElement>('.rail[data-loop-n]');
    for (const el of Array.from(rails)) {
      if (el.dataset['loopInit'] === '1') continue;
      const n = Number(el.getAttribute('data-loop-n') || 0);
      if (n < 3) {
        el.dataset['loopInit'] = '1';
        continue;
      }
      const first = el.children[0] as HTMLElement | undefined;
      if (!first?.offsetWidth) continue;
      const stride = first.offsetWidth + HubsPageComponent.railGapPx;
      el.scrollLeft = n * stride;
      el.dataset['loopInit'] = '1';
    }
  }

  openLibrary(): void {
    this.mode = 'library';
  }

  closeSearch(): void {
    this.showSearch = false;
    this.searchQuery = '';
  }

  openNotifications(): void {
    this.notificationsUi.open();
  }

  openVideo(post: CountryPost): void {
    if (!post) return;
    if (this.catalog.isReel(post)) {
      this.openSpark(post);
      return;
    }
    this.playback.start(post, true);
    void this.router.navigate(['/hubs', 'watch', post.id]);
  }

  openSpark(post: CountryPost | null | undefined): void {
    if (!post) return;
    const country = post.country_code || this.homeCountry || 'US';
    void this.router.navigate(['/sparks', country], {
      queryParams: { post: post.id },
      state: { seedPosts: [post, ...this.playReels] },
    });
  }

  openChannel(channel: HubsChannel): void {
    this.closeSearch();
    void this.router.navigate(['/hubs', 'channel', channel.authorID]);
  }

  thumb(post: CountryPost): string | null {
    const t = this.catalog.posterUrl(post);
    return t ? resolveMediaUrl(t) || t : null;
  }

  avatar(channel: HubsChannel): string | null {
    const u = channel.author?.avatar_url;
    return u ? resolveAvatarUrl(u) || u : null;
  }

  progressPercent(post: CountryPost): number {
    const seconds = this.catalog.playbackPosition(post.id);
    return Math.max(8, Math.min(92, (seconds / 900) * 100));
  }

  trackById(_: number, post: CountryPost): string {
    return post.id;
  }

  trackChannel(_: number, channel: HubsChannel): string {
    return channel.authorID;
  }

  trackRail(_: number, rail: HubsRail): string {
    return rail.id;
  }

  private paint(): void {
    try {
      this.cdr.detectChanges();
    } catch {
      // destroyed
    }
  }
}
