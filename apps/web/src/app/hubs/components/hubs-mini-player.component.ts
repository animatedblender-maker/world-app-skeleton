import { CommonModule } from '@angular/common';
import { Component, OnDestroy, OnInit } from '@angular/core';
import { NavigationEnd, Router } from '@angular/router';
import { Subscription, filter } from 'rxjs';

import { resolveMediaUrl } from '../../core/utils/media-url.util';
import { HubsCatalogService } from '../hubs-catalog.service';
import { HubsPlaybackService, type HubsPlaybackState } from '../hubs-playback.service';

/**
 * Hubs mini player — iOS-inspired bar, scaled up on large screens so it stays
 * proportional to desktop viewports (not a phone-sized 196×110 strip).
 */
@Component({
  selector: 'app-hubs-mini-player',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="mini-wrap" *ngIf="show" role="region" aria-label="Hubs mini player">
      <div class="mini">
        <button type="button" class="thumb-btn" (click)="expand()" aria-label="Expand video">
          <img *ngIf="thumb" [src]="thumb" alt="" />
          <span class="expand-badge" aria-hidden="true">⤢</span>
        </button>
        <div class="side">
          <button type="button" class="meta" (click)="expand()">
            <div class="title">{{ title }}</div>
            <div class="sub">{{ author }}</div>
          </button>
          <div class="controls">
            <button type="button" class="circle play" (click)="togglePlay()" [attr.aria-label]="state.playing ? 'Pause' : 'Play'">
              {{ state.playing ? '❚❚' : '▶' }}
            </button>
            <button type="button" class="circle mute" (click)="toggleMute()" [attr.aria-label]="state.muted ? 'Unmute' : 'Mute'">
              {{ state.muted ? '🔇' : '🔊' }}
            </button>
            <span class="flex"></span>
            <button type="button" class="circle close" (click)="stop()" aria-label="Close mini player">✕</button>
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
      .thumb-btn img {
        width: 100%;
        height: 100%;
        object-fit: cover;
        display: block;
      }
      .expand-badge {
        position: absolute;
        right: 8px;
        bottom: 8px;
        width: 26px;
        height: 26px;
        border-radius: 999px;
        background: rgba(0, 0, 0, 0.5);
        color: rgba(255, 255, 255, 0.95);
        font-size: 12px;
        display: grid;
        place-items: center;
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
      /* Phone: slightly tighter */
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
      /* Tablet / desktop: much larger so it matches big screens */
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

  constructor(
    private playback: HubsPlaybackService,
    private catalog: HubsCatalogService,
    private router: Router
  ) {}

  ngOnInit(): void {
    this.onWatchRoute = this.isWatchUrl(this.router.url);
    this.sub = this.playback.changes$.subscribe((s) => {
      this.state = s;
    });
    this.routeSub = this.router.events
      .pipe(filter((e): e is NavigationEnd => e instanceof NavigationEnd))
      .subscribe((e) => {
        this.onWatchRoute = this.isWatchUrl(e.urlAfterRedirects || e.url);
      });
  }

  ngOnDestroy(): void {
    this.sub?.unsubscribe();
    this.routeSub?.unsubscribe();
  }

  private isWatchUrl(url: string): boolean {
    return /\/hubs\/watch(\/|$|\?)/.test(url || '');
  }

  get show(): boolean {
    // Stay hidden on the full watch page so Share / overlays never leave a dual player.
    if (this.onWatchRoute) return false;
    return !!this.state.post && !this.state.expanded;
  }

  get title(): string {
    return this.state.post ? this.catalog.displayHeadline(this.state.post) : '';
  }

  get author(): string {
    return this.state.post ? this.catalog.displayAuthor(this.state.post) : '';
  }

  get thumb(): string | null {
    if (!this.state.post) return null;
    const t = this.state.post.thumb_url || this.catalog.mediaUrl(this.state.post);
    return t ? resolveMediaUrl(t) || t : null;
  }

  expand(): void {
    if (!this.state.post) return;
    this.playback.expand();
    void this.router.navigate(['/hubs', 'watch', this.state.post.id]);
  }

  togglePlay(): void {
    this.playback.togglePlay();
  }

  toggleMute(): void {
    this.playback.toggleMute();
  }

  stop(): void {
    this.playback.stop();
  }
}
