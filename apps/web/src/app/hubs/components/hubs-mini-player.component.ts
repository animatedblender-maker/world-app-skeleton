import { CommonModule } from '@angular/common';
import {
  Component,
  ElementRef,
  OnDestroy,
  OnInit,
  ViewChild,
} from '@angular/core';
import { NavigationEnd, Router } from '@angular/router';
import { Subscription, filter } from 'rxjs';

import { resolveMediaUrl } from '../../core/utils/media-url.util';
import { HubsCatalogService } from '../hubs-catalog.service';
import { HubsPlaybackService, type HubsPlaybackState } from '../hubs-playback.service';

/**
 * Hubs mini player — continuous film while docked (GlobalHubPlaybackLayer mini).
 * Same content + playhead as watch; expand remounts watch from saved position.
 */
@Component({
  selector: 'app-hubs-mini-player',
  standalone: true,
  imports: [CommonModule],
  template: `
    <!-- Keep film mounted while a hubs post is active (even on watch) to avoid remount flicker on collapse. -->
    <div
      class="mini-wrap"
      *ngIf="mounted"
      [class.mini-hidden]="!show"
      [attr.aria-hidden]="show ? null : 'true'"
      role="region"
      aria-label="Hubs mini player"
    >
      <div class="mini">
        <button type="button" class="thumb-btn" (click)="expand()" aria-label="Expand video">
          <video
            #film
            class="film"
            playsinline
            webkit-playsinline
            [attr.poster]="thumb || null"
            (timeupdate)="onTime()"
            (play)="onNativePlay()"
            (pause)="onNativePause()"
            (click)="$event.stopPropagation(); expand()"
          ></video>
          <img *ngIf="thumb && !filmReady" class="poster-floor" [src]="thumb" alt="" />
          <span class="expand-badge" aria-hidden="true">⤢</span>
        </button>
        <div class="side">
          <button type="button" class="meta" (click)="expand()">
            <div class="title">{{ title }}</div>
            <div class="sub">{{ author }}</div>
          </button>
          <div class="controls">
            <button
              type="button"
              class="circle play"
              (click)="togglePlay()"
              [attr.aria-label]="state.playing ? 'Pause' : 'Play'"
            >
              {{ state.playing ? '❚❚' : '▶' }}
            </button>
            <button
              type="button"
              class="circle mute"
              (click)="toggleMute()"
              [attr.aria-label]="state.muted ? 'Unmute' : 'Mute'"
            >
              {{ state.muted ? '🔇' : '🔊' }}
            </button>
            <span class="flex"></span>
            <button type="button" class="circle close" (click)="stop()" aria-label="Close mini player">
              ✕
            </button>
          </div>
        </div>
      </div>
    </div>
  `,
  styles: [
    `
      .mini-wrap {
        position: fixed;
        left: 0;
        right: 0;
        bottom: calc(var(--tabs-safe, 49px) + 8px);
        z-index: 130;
        width: 100%;
        padding: 0 var(--m-page-padding, 16px);
        pointer-events: none;
        box-sizing: border-box;
      }
      .mini-wrap.mini-hidden {
        visibility: hidden;
        opacity: 0;
        pointer-events: none;
        /* Keep off-screen so it never intercepts taps on watch. */
        transform: translateY(120%);
      }
      .mini {
        pointer-events: auto;
        display: flex;
        align-items: center;
        gap: 14px;
        padding: 12px;
        border-radius: 18px;
        background: var(--m-surface, #fefdfb);
        border: 0.5px solid var(--m-border, #ddd8d1);
        box-shadow: 0 12px 28px rgba(44, 40, 37, 0.16);
        width: 100%;
        max-width: min(100%, 520px);
        margin: 0 auto;
      }
      .thumb-btn {
        width: 200px;
        height: 112px;
        flex-shrink: 0;
        border: 0;
        padding: 0;
        border-radius: 12px;
        overflow: hidden;
        background: var(--m-ink, #2c2825);
        position: relative;
        cursor: pointer;
        box-shadow: 0 3px 8px rgba(44, 40, 37, 0.16);
      }
      .thumb-btn .film,
      .thumb-btn .poster-floor {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        object-fit: cover;
        object-position: center center;
        display: block;
        background: #171412;
      }
      .thumb-btn .poster-floor {
        z-index: 1;
        pointer-events: none;
      }
      .thumb-btn .film {
        z-index: 2;
      }
      .expand-badge {
        position: absolute;
        right: 8px;
        bottom: 8px;
        z-index: 3;
        width: 26px;
        height: 26px;
        border-radius: 999px;
        background: rgba(0, 0, 0, 0.5);
        color: rgba(255, 255, 255, 0.95);
        font-size: 12px;
        display: grid;
        place-items: center;
        pointer-events: none;
      }
      .side {
        flex: 1;
        min-width: 0;
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      .meta {
        border: 0;
        background: transparent;
        padding: 0;
        text-align: left;
        color: inherit;
        cursor: pointer;
        width: 100%;
      }
      .title {
        font-size: 15px;
        font-weight: 650;
        color: var(--m-ink, #2c2825);
        line-height: 1.3;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
      }
      .sub {
        margin-top: 4px;
        font-size: 13px;
        color: var(--m-ink-muted, #948b82);
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }
      .controls {
        display: flex;
        align-items: center;
        gap: 12px;
      }
      .flex {
        flex: 1;
      }
      .circle {
        width: 40px;
        height: 40px;
        border-radius: 999px;
        border: 0;
        cursor: pointer;
        display: grid;
        place-items: center;
        font-size: 13px;
        font-weight: 700;
        color: var(--m-ink, #2c2825);
        background: var(--m-canvas-muted, #f2f0ec);
      }
      .circle.play {
        background: var(--m-accent-bright, #7b6347);
        color: var(--m-paper, #f8f6f2);
        box-shadow: 0 2px 4px rgba(44, 40, 37, 0.18);
      }
      .circle.close {
        width: 36px;
        height: 36px;
        color: var(--m-ink-muted, #948b82);
        font-size: 12px;
      }
      @media (max-width: 520px) {
        .thumb-btn {
          width: 148px;
          height: 84px;
        }
        .circle {
          width: 36px;
          height: 36px;
        }
      }
      @media (min-width: 700px) {
        .mini-wrap {
          bottom: calc(var(--tabs-safe, 0px) + 16px);
          padding: 0 20px;
        }
        .mini {
          max-width: min(720px, calc(100% - 0px));
          padding: 14px 16px;
          gap: 18px;
          border-radius: 20px;
        }
        .thumb-btn {
          width: 280px;
          height: 158px;
          border-radius: 14px;
        }
        .title {
          font-size: 17px;
        }
        .sub {
          font-size: 14px;
        }
        .circle {
          width: 46px;
          height: 46px;
          font-size: 14px;
        }
        .circle.close {
          width: 42px;
          height: 42px;
        }
      }
      @media (min-width: 900px) {
        .mini-wrap {
          left: var(--m-sidebar-w, 200px);
          right: 0;
          width: auto;
          bottom: 24px;
          padding: 0 28px;
        }
        .mini {
          max-width: min(820px, 52vw);
          margin-left: auto;
          margin-right: 0;
          padding: 16px 18px;
          gap: 20px;
        }
        .thumb-btn {
          width: 340px;
          height: 191px;
        }
        .title {
          font-size: 18px;
          -webkit-line-clamp: 2;
        }
        .sub {
          font-size: 14px;
        }
        .circle {
          width: 48px;
          height: 48px;
          font-size: 15px;
        }
        .expand-badge {
          width: 30px;
          height: 30px;
          font-size: 13px;
        }
      }
      @media (min-width: 1280px) {
        .mini {
          max-width: min(920px, 48vw);
        }
        .thumb-btn {
          width: 400px;
          height: 225px;
        }
        .title {
          font-size: 19px;
        }
      }
    `,
  ],
})
export class HubsMiniPlayerComponent implements OnInit, OnDestroy {
  state: HubsPlaybackState = { post: null, expanded: false, playing: false, muted: false };
  /** Full watch page already has the main player — never stack a mini on top of it. */
  private onWatchRoute = false;
  private sub?: Subscription;
  private routeSub?: Subscription;
  private boundPostId: string | null = null;
  private boundSrc = '';
  private startApplied = false;
  private syncing = false;
  filmReady = false;

  @ViewChild('film') filmRef?: ElementRef<HTMLVideoElement>;

  constructor(
    private playback: HubsPlaybackService,
    private catalog: HubsCatalogService,
    private router: Router
  ) {}

  ngOnInit(): void {
    this.onWatchRoute = this.isWatchUrl(this.router.url);
    this.sub = this.playback.changes$.subscribe((s) => {
      this.state = s;
      // Defer DOM sync until *ngIf has created the <video>.
      this.queueFilmSync();
    });
    this.routeSub = this.router.events
      .pipe(filter((e): e is NavigationEnd => e instanceof NavigationEnd))
      .subscribe((e) => {
        const nextWatch = this.isWatchUrl(e.urlAfterRedirects || e.url);
        // Leaving watch → mini: re-apply catalog playhead (watch advanced while film was paused).
        if (this.onWatchRoute && !nextWatch) {
          this.startApplied = false;
        }
        this.onWatchRoute = nextWatch;
        this.queueFilmSync();
      });
  }

  private filmSyncTimer: ReturnType<typeof setTimeout> | null = null;

  private queueFilmSync(): void {
    if (this.filmSyncTimer != null) {
      clearTimeout(this.filmSyncTimer);
    }
    this.filmSyncTimer = setTimeout(() => {
      this.filmSyncTimer = null;
      this.syncFilm();
    }, 0);
  }

  ngOnDestroy(): void {
    if (this.filmSyncTimer != null) {
      clearTimeout(this.filmSyncTimer);
      this.filmSyncTimer = null;
    }
    this.persistPosition(true);
    this.sub?.unsubscribe();
    this.routeSub?.unsubscribe();
  }

  private isWatchUrl(url: string): boolean {
    return /\/hubs\/watch(\/|$|\?)/.test(url || '');
  }

  /** Visible docked chrome — never on the full watch page. */
  get show(): boolean {
    if (this.onWatchRoute) return false;
    return !!this.state.post && !this.state.expanded;
  }

  /** Keep <video> in DOM while hubs session is active (watch or mini) to reduce collapse remount flicker. */
  get mounted(): boolean {
    return !!this.state.post;
  }

  get title(): string {
    return this.state.post ? this.catalog.displayHeadline(this.state.post) : '';
  }

  get author(): string {
    return this.state.post ? this.catalog.displayAuthor(this.state.post) : '';
  }

  get thumb(): string | null {
    if (!this.state.post) return null;
    const t = this.catalog.posterUrl(this.state.post);
    return t ? resolveMediaUrl(t) || t : null;
  }

  get mediaSrc(): string {
    if (!this.state.post) return '';
    const raw = this.catalog.mediaUrl(this.state.post);
    return resolveMediaUrl(raw) || raw || '';
  }

  expand(): void {
    if (!this.state.post) return;
    this.persistPosition(true);
    this.playback.expand();
    void this.router.navigate(['/hubs', 'watch', this.state.post.id]);
  }

  togglePlay(): void {
    this.playback.togglePlay();
  }

  toggleMute(): void {
    this.playback.toggleMute();
    const muted = this.playback.muted;
    try {
      (window as any).__videoMuted = muted;
      window.dispatchEvent(new CustomEvent('video-player-mute', { detail: muted }));
    } catch {
      // SSR / non-browser
    }
  }

  stop(): void {
    this.persistPosition(true);
    this.teardownFilm();
    this.playback.stop();
  }

  onTime(): void {
    this.persistPosition(false);
  }

  onNativePlay(): void {
    if (this.syncing) return;
    if (!this.state.playing) this.playback.setPlaying(true);
  }

  onNativePause(): void {
    if (this.syncing) return;
    // Ignore pause while tearing down / navigating to watch.
    if (!this.show) return;
    if (this.state.playing) this.playback.setPlaying(false);
  }

  private syncFilm(): void {
    if (!this.state.post) {
      this.teardownFilm();
      return;
    }
    const video = this.filmRef?.nativeElement;
    if (!video) return;

    const postId = this.state.post.id;
    const src = this.mediaSrc;
    if (!src) return;

    // On full watch the main player owns audio — keep mini film warm but paused (no dual audio).
    const shouldPlay = this.show && !!this.state.playing;

    if (this.boundPostId !== postId || this.boundSrc !== src) {
      this.boundPostId = postId;
      this.boundSrc = src;
      this.startApplied = false;
      this.filmReady = false;
      video.poster = this.thumb || '';
      video.src = src;
      video.load();
    }

    video.muted = !!this.state.muted;
    this.applyStartTime(video);

    this.syncing = true;
    try {
      if (shouldPlay) {
        void video.play().then(
          () => {
            this.filmReady = true;
          },
          () => {
            // Autoplay may require muted — keep poster floor visible.
          }
        );
      } else if (!video.paused) {
        video.pause();
      }
    } finally {
      this.syncing = false;
    }
  }

  private applyStartTime(video: HTMLVideoElement): void {
    if (this.startApplied || !this.state.post) return;
    const t = this.catalog.playbackPosition(this.state.post.id);
    if (!Number.isFinite(t) || t < 1) {
      this.startApplied = true;
      return;
    }
    const apply = () => {
      try {
        if (Number.isFinite(video.duration) && video.duration > 0 && t >= video.duration - 1) {
          this.startApplied = true;
          return;
        }
        video.currentTime = t;
        this.startApplied = true;
      } catch {
        // seek may fail until buffered
      }
    };
    if (video.readyState >= 1) apply();
    else {
      const once = () => {
        video.removeEventListener('loadedmetadata', once);
        apply();
      };
      video.addEventListener('loadedmetadata', once);
    }
  }

  private persistPosition(force: boolean): void {
    const video = this.filmRef?.nativeElement;
    const post = this.state.post;
    if (!video || !post) return;
    const t = video.currentTime || 0;
    if (t < 0.5) return;
    if (force) {
      this.catalog.savePlaybackPosition(t, post.id, video.duration);
    } else {
      this.catalog.notePlaybackPosition(t, post.id, video.duration);
    }
  }

  private teardownFilm(): void {
    const video = this.filmRef?.nativeElement;
    if (video) {
      try {
        video.pause();
        video.removeAttribute('src');
        video.load();
      } catch {
        // ignore
      }
    }
    this.boundPostId = null;
    this.boundSrc = '';
    this.startApplied = false;
    this.filmReady = false;
  }
}
