import { CommonModule } from '@angular/common';
import {
  AfterViewInit,
  Component,
  ElementRef,
  EventEmitter,
  HostListener,
  Input,
  OnChanges,
  OnDestroy,
  Output,
  SimpleChanges,
  ViewChild,
} from '@angular/core';

import { AdsService, type AdSlotModel } from '../core/services/ads.service';

@Component({
  selector: 'app-video-player',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div
      class="video-shell"
      [class.is-playing]="isPlaying"
      [class.matterya-chrome]="showsControls"
      [class.chrome-visible]="shouldShowChrome"
      (mousemove)="revealControls()"
      (touchstart)="revealControls()"
    >
      <video
        #videoEl
        [src]="currentSrc"
        [attr.poster]="currentPoster"
        [attr.preload]="preload"
        playsinline
        (click)="onVideoTap(videoEl, $event)"
        (timeupdate)="onTimeUpdate(videoEl)"
        (loadedmetadata)="onLoaded(videoEl)"
        (canplay)="setBuffering(false)"
        (error)="onError()"
        (ended)="onEnded()"
        (play)="onPlay()"
        (pause)="onPause()"
        (waiting)="setBuffering(true)"
        (playing)="setBuffering(false)"
      ></video>
      <div class="video-overlay" [class.subtle]="showsControls"></div>
      <div class="ad-layer" *ngIf="isAdMode && activeAd">
        <div class="ad-pill">Sponsored</div>
        <button
          *ngIf="activeAd.creative.click_url"
          class="ad-learn-more"
          type="button"
          (click)="openAdLink($event)"
        >
          {{ activeAd.creative.cta_label || 'Learn more' }}
        </button>
        <button *ngIf="adSkipReady" class="ad-skip" type="button" (click)="skipAd($event)">Skip</button>
        <div class="ad-countdown" *ngIf="!adSkipReady && adSkipSecondsLeft > 0">
          Skip in {{ adSkipSecondsLeft }}s
        </div>
      </div>

      <!-- Simple feed mute (when full Matterya chrome is off) -->
      <button
        *ngIf="showMute && !isAdMode && !showsControls"
        class="mute-toggle"
        type="button"
        [attr.aria-label]="isMuted ? 'Unmute video' : 'Mute video'"
        (click)="toggleMute(videoEl, $event)"
      >
        <svg *ngIf="!isMuted" class="icon-svg icon-stroke" viewBox="0 0 24 24" aria-hidden="true">
          <path d="M4 10h4l5-4v12l-5-4H4z"></path>
          <path d="M16 9a3 3 0 0 1 0 6"></path>
          <path d="M18.5 6.5a6 6 0 0 1 0 11"></path>
        </svg>
        <svg *ngIf="isMuted" class="icon-svg icon-stroke" viewBox="0 0 24 24" aria-hidden="true">
          <path d="M4 10h4l5-4v12l-5-4H4z"></path>
          <line x1="16" y1="8" x2="21" y2="13"></line>
          <line x1="21" y1="8" x2="16" y2="13"></line>
        </svg>
      </button>
      <button
        class="center-play"
        *ngIf="!showsControls && showCenterOverlay"
        type="button"
        aria-label="Play video"
        (click)="onVideoTap(videoEl, $event)"
      >
        <svg *ngIf="!isPlaying" class="center-icon" viewBox="0 0 24 24" aria-hidden="true">
          <path d="M8 5v14l11-7z"></path>
        </svg>
        <svg *ngIf="isPlaying" class="center-icon" viewBox="0 0 24 24" aria-hidden="true">
          <rect x="6" y="5" width="4" height="14" rx="1"></rect>
          <rect x="14" y="5" width="4" height="14" rx="1"></rect>
        </svg>
      </button>

      <!-- iOS / Android MatteryaVideoControls -->
      <div class="matterya-controls" *ngIf="showsControls && !isAdMode && shouldShowChrome" (click)="$event.stopPropagation()">
        <div class="mc-top">
          <span class="mc-spacer"></span>
          <button
            type="button"
            class="mc-icon"
            *ngIf="showMute"
            [attr.aria-label]="isMuted ? 'Unmute' : 'Mute'"
            (click)="toggleMute(videoEl, $event)"
          >
            <svg *ngIf="!isMuted" class="icon-svg icon-stroke" viewBox="0 0 24 24" aria-hidden="true">
              <path d="M4 10h4l5-4v12l-5-4H4z"></path>
              <path d="M16 9a3 3 0 0 1 0 6"></path>
              <path d="M18.5 6.5a6 6 0 0 1 0 11"></path>
            </svg>
            <svg *ngIf="isMuted" class="icon-svg icon-stroke" viewBox="0 0 24 24" aria-hidden="true">
              <path d="M4 10h4l5-4v12l-5-4H4z"></path>
              <line x1="16" y1="8" x2="21" y2="13"></line>
              <line x1="21" y1="8" x2="16" y2="13"></line>
            </svg>
          </button>
          <div class="mc-quality-wrap" *ngIf="qualityOptions.length > 1">
            <button
              type="button"
              class="mc-icon mc-quality-btn"
              aria-label="Quality"
              [attr.aria-expanded]="qualityMenuOpen"
              (click)="toggleQualityMenu($event)"
            >
              <span class="mc-quality-label">{{ activeQualityLabel }}</span>
            </button>
            <div class="mc-quality-menu" *ngIf="qualityMenuOpen" role="menu">
              <button
                type="button"
                class="mc-quality-item"
                *ngFor="let q of qualityOptions"
                role="menuitemradio"
                [class.active]="q.id === activeQualityId"
                (click)="selectQuality(q, videoEl, $event)"
              >
                {{ q.label }}
              </button>
            </div>
          </div>
          <button
            type="button"
            class="mc-icon"
            *ngIf="allowsFullscreen"
            aria-label="Fullscreen"
            (click)="toggleFullscreen(videoEl, $event)"
          >
            <svg class="icon-svg icon-stroke" viewBox="0 0 24 24" aria-hidden="true">
              <path d="M8 3H5a2 2 0 0 0-2 2v3"></path>
              <path d="M16 3h3a2 2 0 0 1 2 2v3"></path>
              <path d="M8 21H5a2 2 0 0 1-2-2v-3"></path>
              <path d="M16 21h3a2 2 0 0 0 2-2v-3"></path>
            </svg>
          </button>
        </div>
        <div class="mc-bottom">
          <button
            type="button"
            class="mc-play"
            [attr.aria-label]="isPlaying ? 'Pause' : 'Play'"
            (click)="togglePlay(videoEl, $event)"
          >
            <svg *ngIf="!isPlaying" class="mc-play-icon" viewBox="0 0 24 24" aria-hidden="true">
              <path d="M8 5v14l11-7z"></path>
            </svg>
            <svg *ngIf="isPlaying" class="mc-play-icon" viewBox="0 0 24 24" aria-hidden="true">
              <rect x="6" y="5" width="4" height="14" rx="1"></rect>
              <rect x="14" y="5" width="4" height="14" rx="1"></rect>
            </svg>
          </button>
          <span class="mc-time">{{ formatTime(currentTime) }}</span>
          <input
            class="mc-scrub"
            type="range"
            min="0"
            max="100"
            step="0.1"
            [value]="progressPercent"
            (input)="onScrub($event, videoEl)"
            (click)="$event.stopPropagation()"
            aria-label="Seek"
          />
          <span class="mc-time dim">{{ formatTime(duration) }}</span>
        </div>
      </div>

      <div class="buffering" *ngIf="isBuffering">
        <span class="spinner"></span>
      </div>
    </div>
  `,
  styles: [
    `
      :host {
        display: block;
        width: 100%;
      }
      :host(.reel-player) {
        height: 100%;
      }
      :host(.reel-player) .video-shell {
        height: 100%;
      }
      :host(.reel-player) .ad-layer {
        z-index: 60;
      }
      :host(.reel-player) .ad-pill,
      :host(.reel-player) .ad-learn-more {
        top: 16px;
      }
      :host(.reel-player) .ad-pill {
        left: 16px;
      }
      :host(.reel-player) .ad-learn-more {
        right: 16px;
      }
      :host(.reel-player) .ad-skip,
      :host(.reel-player) .ad-countdown {
        bottom: 16px;
        right: 16px;
      }
      :host(.reel-player) video {
        height: 100%;
        max-height: none;
        object-fit: cover;
      }
      :host(.reel-player) .center-play {
        width: 96px;
        height: 96px;
        background: rgba(210, 210, 220, 0.35);
        border: 1px solid rgba(255, 255, 255, 0.4);
        box-shadow: 0 18px 40px rgba(0, 0, 0, 0.4);
        backdrop-filter: blur(4px);
      }
      :host(.reel-player) .center-icon {
        width: 34px;
        height: 34px;
      }
      :host(.reel-player) .mute-toggle {
        top: 16px;
        right: 16px;
        width: 52px;
        height: 52px;
        border-radius: 50%;
        border: 1px solid rgba(255, 255, 255, 0.2);
        background: rgba(8, 10, 14, 0.65);
        color: #fff;
        box-shadow: none;
      }
      :host(.reel-player) .icon-svg {
        width: 22px;
        height: 22px;
      }
      :host(.controls-hidden) .controls {
        display: none;
      }
      .video-shell {
        position: relative;
        width: 100%;
        height: 100%;
        min-height: 0;
        background: #050505;
        overflow: hidden;
        max-height: var(--player-max-height, none);
        isolation: isolate;
      }
      .video-shell:fullscreen,
      .video-shell:-webkit-full-screen,
      .video-shell.is-fullscreen {
        width: 100vw;
        height: 100vh;
        max-height: 100vh;
        border-radius: 0;
        background: #000;
      }
      .video-shell.is-fullscreen {
        position: fixed;
        inset: 0;
        z-index: 9999;
      }
      video {
        position: relative;
        z-index: 0;
        width: 100%;
        height: 100%;
        display: block;
        max-height: var(--player-max-height, none);
        object-fit: contain;
        object-position: center center;
        background: #000;
      }
      /* Matterya watch chrome: fill the stage box, never crop */
      .video-shell.matterya-chrome {
        height: 100%;
      }
      .video-shell.matterya-chrome {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
      }
      .video-shell.matterya-chrome video {
        position: absolute;
        inset: 0;
        width: 100%;
        height: 100%;
        max-height: none;
        /* contain + stage AR matched to video = fill without crop */
        object-fit: contain;
        object-position: center center;
      }
      .mc-quality-wrap {
        position: relative;
      }
      .mc-quality-btn {
        min-width: 44px;
        padding: 0 8px !important;
        font-size: 11px;
        font-weight: 750;
        letter-spacing: 0.02em;
      }
      .mc-quality-label {
        white-space: nowrap;
      }
      .mc-quality-menu {
        position: absolute;
        top: calc(100% + 6px);
        right: 0;
        min-width: 108px;
        padding: 6px;
        border-radius: 12px;
        background: rgba(20, 16, 14, 0.94);
        border: 0.5px solid rgba(255, 255, 255, 0.12);
        box-shadow: 0 10px 28px rgba(0, 0, 0, 0.35);
        z-index: 20;
      }
      .mc-quality-item {
        display: block;
        width: 100%;
        border: 0;
        background: transparent;
        color: #f5f0ea;
        text-align: left;
        padding: 8px 10px;
        border-radius: 8px;
        font-size: 12px;
        font-weight: 650;
        cursor: pointer;
      }
      .mc-quality-item:hover {
        background: rgba(255, 255, 255, 0.08);
      }
      .mc-quality-item.active {
        background: rgba(123, 99, 71, 0.45);
        color: #fff;
      }
      .video-shell:fullscreen video,
      .video-shell:-webkit-full-screen video,
      .video-shell.is-fullscreen video {
        max-height: 100vh;
        height: 100%;
        object-fit: contain;
      }
      .video-overlay {
        position: absolute;
        inset: 0;
        z-index: 1;
        background: linear-gradient(180deg, rgba(0, 0, 0, 0.55), rgba(0, 0, 0, 0) 45%, rgba(0, 0, 0, 0.65));
        opacity: 0.7;
        transition: opacity 200ms ease;
        pointer-events: none;
      }
      .video-shell.is-playing .video-overlay {
        opacity: 0.3;
      }
      .ad-layer {
        position: absolute;
        inset: 0;
        z-index: 50;
        pointer-events: none;
      }
      .ad-pill,
      .ad-countdown,
      .ad-skip {
        position: absolute;
        pointer-events: auto;
        z-index: 51;
        border-radius: 999px;
        padding: 8px 12px;
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }
      .ad-pill {
        top: 12px;
        left: 12px;
        background: rgba(0, 0, 0, 0.66);
        color: #fff;
      }
      .ad-countdown {
        bottom: 12px;
        right: 12px;
        background: rgba(0, 0, 0, 0.66);
        color: #fff;
      }
      .ad-skip {
        bottom: 12px;
        right: 12px;
        top: auto;
        border: 0;
        background: rgba(255, 255, 255, 0.9);
        color: #0c1520;
        cursor: pointer;
      }
      .ad-learn-more {
        position: absolute;
        top: 12px;
        right: 12px;
        border: 0;
        border-radius: 999px;
        background: rgba(255, 255, 255, 0.92);
        color: #0b1520;
        cursor: pointer;
        text-transform: none;
        letter-spacing: 0.01em;
        font-size: 12px;
        font-weight: 700;
        padding: 8px 12px;
        line-height: 1;
        box-shadow: 0 8px 18px rgba(0, 0, 0, 0.18);
        z-index: 51;
      }
      .center-play {
        position: absolute;
        inset: 0;
        margin: auto;
        width: 84px;
        height: 84px;
        border-radius: 50%;
        border: 0;
        background: rgba(10, 10, 10, 0.78);
        display: grid;
        place-items: center;
        box-shadow: 0 10px 30px rgba(0, 0, 0, 0.35);
        cursor: pointer;
        transition: transform 180ms ease, background 180ms ease;
        z-index: 15;
      }
      .center-play:hover {
        transform: scale(1.05);
        background: rgba(10, 10, 10, 0.9);
      }
      .center-icon {
        width: 26px;
        height: 26px;
        fill: #fff;
      }
      .mute-toggle {
        position: absolute;
        top: 12px;
        right: 12px;
        width: 34px;
        height: 34px;
        border-radius: 50%;
        border: 1px solid rgba(255, 255, 255, 0.2);
        background: rgba(0, 0, 0, 0.55);
        color: #fff;
        display: grid;
        place-items: center;
        cursor: pointer;
        z-index: 20;
      }
      .video-overlay.subtle {
        background: linear-gradient(180deg, rgba(44, 40, 37, 0.35), transparent 40%, transparent 55%, rgba(44, 40, 37, 0.55));
        opacity: 0.55;
      }
      .video-shell.matterya-chrome.is-playing:not(.chrome-visible) .video-overlay.subtle {
        opacity: 0.15;
      }
      /* —— MatteryaVideoControls (pixel-match iOS VideoPlayerView) —— */
      .matterya-controls {
        --m-accent-bright: #7b6347; /* Theme.accentBright 0.482,0.388,0.278 */
        --m-ink: #2c2825;
        --m-paper: #f8f6f2;
        position: absolute;
        inset: 0;
        z-index: 30;
        display: flex;
        flex-direction: column;
        justify-content: space-between;
        pointer-events: none;
      }
      .mc-top {
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 10px 12px 0;
        pointer-events: auto;
      }
      .mc-spacer {
        flex: 1;
      }
      .mc-icon {
        width: 34px;
        height: 34px;
        border: 0;
        border-radius: 999px;
        background: rgba(44, 40, 37, 0.45);
        color: #fff;
        display: grid;
        place-items: center;
        cursor: pointer;
        padding: 0;
      }
      .mc-icon:hover {
        background: rgba(44, 40, 37, 0.65);
      }
      .mc-icon .icon-svg {
        width: 16px;
        height: 16px;
      }
      .mc-bottom {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 14px 14px 14px;
        pointer-events: auto;
        background: linear-gradient(180deg, transparent, rgba(44, 40, 37, 0.72));
      }
      .mc-play {
        width: 42px;
        height: 42px;
        flex-shrink: 0;
        border: 0;
        border-radius: 999px;
        background: var(--m-accent-bright, #7b6347);
        color: var(--m-paper, #f8f6f2);
        display: grid;
        place-items: center;
        cursor: pointer;
        box-shadow: 0 3px 8px rgba(44, 40, 37, 0.25);
        padding: 0;
      }
      .mc-play:hover {
        filter: brightness(1.08);
      }
      .mc-play-icon {
        width: 18px;
        height: 18px;
        fill: currentColor;
        display: block;
      }
      .mc-time {
        font-size: 12px;
        font-variant-numeric: tabular-nums;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
        color: rgba(255, 255, 255, 0.9);
        min-width: 36px;
        flex-shrink: 0;
      }
      .mc-time.dim {
        color: rgba(255, 255, 255, 0.75);
      }
      .mc-scrub {
        flex: 1;
        min-width: 0;
        height: 20px;
        margin: 0;
        appearance: none;
        -webkit-appearance: none;
        cursor: pointer;
        --scrub-pct: 0%;
        /* iOS MatteryaScrubber: gold fill + white track */
        background: linear-gradient(
          to right,
          var(--m-accent-bright, #7b6347) 0%,
          var(--m-accent-bright, #7b6347) var(--scrub-pct, 0%),
          rgba(255, 255, 255, 0.22) var(--scrub-pct, 0%),
          rgba(255, 255, 255, 0.22) 100%
        );
        background-size: 100% 4px;
        background-repeat: no-repeat;
        background-position: center;
        border-radius: 999px;
      }
      .mc-scrub::-webkit-slider-runnable-track {
        height: 4px;
        border-radius: 999px;
        background: transparent;
      }
      .mc-scrub::-webkit-slider-thumb {
        -webkit-appearance: none;
        appearance: none;
        width: 14px;
        height: 14px;
        margin-top: -5px;
        border-radius: 999px;
        background: var(--m-paper, #f8f6f2);
        box-shadow: 0 1px 3px rgba(44, 40, 37, 0.25);
        border: 0;
      }
      .mc-scrub::-moz-range-track {
        height: 4px;
        border-radius: 999px;
        background: rgba(255, 255, 255, 0.22);
      }
      .mc-scrub::-moz-range-progress {
        height: 4px;
        border-radius: 999px;
        background: var(--m-accent-bright, #7b6347);
      }
      .mc-scrub::-moz-range-thumb {
        width: 14px;
        height: 14px;
        border-radius: 999px;
        background: var(--m-paper, #f8f6f2);
        border: 0;
        box-shadow: 0 1px 3px rgba(44, 40, 37, 0.25);
      }
      .video-shell.matterya-chrome:not(.chrome-visible) .matterya-controls {
        opacity: 0;
        pointer-events: none;
        transition: opacity 180ms ease;
      }
      .video-shell.matterya-chrome.chrome-visible .matterya-controls {
        opacity: 1;
        transition: opacity 180ms ease;
      }
      .buffering {
        position: absolute;
        inset: 0;
        display: grid;
        place-items: center;
        pointer-events: none;
        z-index: 25;
      }
      .spinner {
        width: 42px;
        height: 42px;
        border-radius: 50%;
        border: 3px solid rgba(255, 255, 255, 0.25);
        border-top-color: #fff;
        animation: spin 800ms linear infinite;
      }
      @keyframes spin {
        to {
          transform: rotate(360deg);
        }
      }
      .icon-svg {
        width: 18px;
        height: 18px;
        display: block;
      }
      .icon-stroke {
        fill: none;
        stroke: currentColor;
        stroke-width: 2;
        stroke-linecap: round;
        stroke-linejoin: round;
      }
    `,
  ],
})
export class VideoPlayerComponent implements AfterViewInit, OnChanges, OnDestroy {
  private static globalMuted = false;
  private static nextInstanceId = 1;
  private static activeAdPlayerId: string | null = null;
  private static activeContentPlayerId: string | null = null;
  private static adDebugEnabled: boolean | null = null;
  /** Posts that already finished a pre-roll this session — avoid re-ad on mini→expand remount. */
  private static adsCompletedForPost = new Set<string>();
  @Input({ required: true }) src!: string;
  /** Optional multi-bitrate ladder; auto-derived for Archive _512kb / full .mp4 pairs. */
  @Input() sources: Array<{ id: string; label: string; src: string }> | null = null;
  @Input() poster: string | null = null;
  @Input() preload: 'none' | 'metadata' | 'auto' = 'metadata';
  @Input() showMute = true;
  /** iOS/Android Matterya chrome: golden play, scrubber, mute, fullscreen. */
  @Input() showsControls = false;
  @Input() allowsFullscreen = false;
  @Input() centerOverlayMode: 'always' | 'on-click' = 'on-click';
  @Input() tapBehavior: 'toggle' | 'emit' | 'none' = 'toggle';
  @Input() adPlacement: 'video' | 'reel' | null = null;
  @Input() adCountryCode: string | null = null;
  @Input() adContentCountryCode: string | null = null;
  @Input() adPostId: string | null = null;
  /** Resume position (seconds) applied once after metadata loads. */
  @Input() startTime: number | null = null;
  @Output() videoTap = new EventEmitter<void>();
  @Output() viewed = new EventEmitter<void>();
  @Output() timeUpdate = new EventEmitter<{ currentTime: number; duration: number }>();
  @Output() playState = new EventEmitter<boolean>();
  @ViewChild('videoEl', { static: true }) videoRef!: ElementRef<HTMLVideoElement>;
  private startTimeApplied = false;

  isPlaying = false;
  isMuted = false;
  isBuffering = false;
  controlsVisible = true;
  currentTime = 0;
  duration = 0;
  progressPercent = 0;
  centerOverlayVisible = false;
  private hideTimer: ReturnType<typeof setTimeout> | null = null;
  private centerTimer: ReturnType<typeof setTimeout> | null = null;
  private observer: IntersectionObserver | null = null;
  private autoPaused = false;
  private userPaused = false;
  private isInView = false;
  private readonly playerInstanceId = `vp-${VideoPlayerComponent.nextInstanceId++}`;
  private muteHandler: ((event: Event) => void) | null = null;
  private adFocusHandler: ((event: Event) => void) | null = null;
  private contentFocusHandler: ((event: Event) => void) | null = null;
  private viewTracked = false;
  activeAd: AdSlotModel | null = null;
  isAdMode = false;
  adDecisionMade = false;
  adSecondsLeft = 0;
  adSkipSecondsLeft = 0;
  adSkipReady = false;
  private adSkipAfterSeconds = 0;
  private adCountdownTimer: ReturnType<typeof setInterval> | null = null;
  private adImpressionLogged = false;
  private adPreparedForSrc: string | null = null;
  private adPreparing = false;
  private adDebugLoggedForSrc = false;
  private adRetryCount = 0;
  private adStartedAt = 0;
  private adBlockedByAnother = false;

  constructor(private ads: AdsService) {}

  qualityOptions: Array<{ id: string; label: string; src: string }> = [];
  /** Always prefer the original working stream as Auto. */
  activeQualityId = 'auto';
  qualityMenuOpen = false;
  private qualityResumeAt: number | null = null;
  private qualityResumePlay = false;
  private qualitySwitchInFlight = false;
  private qualityFallbackUsed = false;

  @Output() aspectRatio = new EventEmitter<number>();

  get activeQualityLabel(): string {
    const hit = this.qualityOptions.find((q) => q.id === this.activeQualityId);
    return hit?.label || 'Auto';
  }

  get currentSrc(): string {
    if (this.adsEnabled && !this.adDecisionMade) return '';
    if (this.isAdMode && this.activeAd) return this.activeAd.creative.media_url;
    const hit = this.qualityOptions.find((q) => q.id === this.activeQualityId);
    // Never invent a URL — fall back to the input src that loaded the page.
    return hit?.src || this.src || '';
  }

  private rebuildQualityOptions(): void {
    if (this.sources?.length) {
      this.qualityOptions = this.sources.slice();
    } else {
      this.qualityOptions = this.deriveQualityOptions(this.src);
    }
    // Reset to Auto whenever the base src changes so we never stick on a dead High URL.
    this.activeQualityId = 'auto';
    this.qualityFallbackUsed = false;
    this.qualityMenuOpen = false;
    if (!this.qualityOptions.some((q) => q.id === 'auto')) {
      this.qualityOptions = [
        { id: 'auto', label: 'Auto', src: String(this.src || '').trim() },
        ...this.qualityOptions,
      ];
    }
    // Drop optional alternates that 404 so the menu only lists playable streams.
    void this.pruneUnreachableQualities();
  }

  /**
   * Build quality ladder from the **known-good** source first.
   * Archive seeds use *_512kb.mp4 — full .mp4 is optional and often missing,
   * so Auto must stay on the original URL.
   */
  private deriveQualityOptions(src: string): Array<{ id: string; label: string; src: string }> {
    const raw = String(src || '').trim();
    if (!raw) return [{ id: 'auto', label: 'Auto', src: '' }];

    const options: Array<{ id: string; label: string; src: string }> = [
      { id: 'auto', label: 'Auto', src: raw },
    ];

    if (/_512kb\.mp4(\?|$)/i.test(raw)) {
      const high = raw.replace(/_512kb\.mp4/i, '.mp4');
      if (high !== raw) {
        options.push({ id: 'high', label: 'High', src: high });
      }
      // 512kb is the same bytes as Auto — only expose when Auto is something else
      return options;
    }

    if (/\.mp4(\?|$)/i.test(raw) && /archive\.org/i.test(raw) && !/_512kb/i.test(raw)) {
      const low = raw.replace(/\.mp4/i, '_512kb.mp4');
      if (low !== raw) {
        options.push({ id: '512', label: '512kb', src: low });
      }
      return options;
    }

    return options;
  }

  private async pruneUnreachableQualities(): Promise<void> {
    const baseSrc = String(this.src || '').trim();
    const candidates = this.qualityOptions.filter((q) => q.id !== 'auto' && q.src && q.src !== baseSrc);
    if (!candidates.length) return;
    const kept = this.qualityOptions.filter((q) => q.id === 'auto' || q.src === baseSrc);
    for (const q of candidates) {
      const ok = await this.urlLooksPlayable(q.src);
      if (ok) kept.push(q);
    }
    // Dedupe by id
    const seen = new Set<string>();
    this.qualityOptions = kept.filter((q) => {
      if (seen.has(q.id)) return false;
      seen.add(q.id);
      return true;
    });
  }

  private async urlLooksPlayable(url: string): Promise<boolean> {
    try {
      const res = await fetch(url, { method: 'HEAD', mode: 'cors' });
      if (res.ok) return true;
      // Some CDNs reject HEAD — try a tiny range GET
      if (res.status === 405 || res.status === 403 || res.status === 0) {
        const get = await fetch(url, {
          method: 'GET',
          headers: { Range: 'bytes=0-1' },
          mode: 'cors',
        });
        return get.ok || get.status === 206;
      }
      return false;
    } catch {
      // CORS may block probe — keep the option; runtime error handler will fall back.
      return true;
    }
  }

  toggleQualityMenu(event: Event): void {
    event.stopPropagation();
    this.qualityMenuOpen = !this.qualityMenuOpen;
    this.revealControls();
  }

  selectQuality(
    q: { id: string; label: string; src: string },
    video: HTMLVideoElement,
    event: Event
  ): void {
    event.stopPropagation();
    this.qualityMenuOpen = false;
    if (q.id === this.activeQualityId || !q.src) return;
    this.qualityResumePlay = !video.paused && !video.ended;
    this.qualityResumeAt = Number.isFinite(video.currentTime) ? video.currentTime : 0;
    this.qualitySwitchInFlight = true;
    this.qualityFallbackUsed = false;
    this.activeQualityId = q.id;
    // Explicitly apply src + load so Angular property binding can't leave a dead element.
    try {
      video.pause();
    } catch {
      // ignore
    }
    video.src = q.src;
    video.load();
    this.setBuffering(true);
    this.revealControls();
  }

  /** If a quality pick 404s, snap back to Auto (original src) and keep watching. */
  private recoverFromQualityError(video: HTMLVideoElement): boolean {
    if (this.qualityFallbackUsed) return false;
    if (this.activeQualityId === 'auto' && !this.qualitySwitchInFlight) return false;
    const autoSrc = String(this.src || '').trim();
    if (!autoSrc) return false;
    // Drop the broken option from the menu so it can't be re-selected.
    const badId = this.activeQualityId;
    this.qualityOptions = this.qualityOptions.filter((q) => q.id === 'auto' || q.id !== badId);
    this.qualityFallbackUsed = true;
    this.activeQualityId = 'auto';
    this.qualitySwitchInFlight = true;
    this.qualityResumePlay = true;
    try {
      video.removeAttribute('src');
      video.load();
      video.src = autoSrc;
      video.load();
      this.setBuffering(true);
      this.controlsVisible = true;
      return true;
    } catch {
      return false;
    }
  }

  get currentPoster(): string | null {
    if (this.isAdMode) return null;
    return this.poster || null;
  }

  get adsEnabled(): boolean {
    // Temporarily disabled app-wide — re-enable by returning !!this.adPlacement.
    return false;
  }

  @HostListener('click', ['$event'])
  handleHostClick(event: Event): void {
    if (this.tapBehavior !== 'emit') return;
    const target = event.target as HTMLElement | null;
    if (!target) return;
    if (target.closest('.controls')) return;
    if (target.closest('button')) return;
    if (target.closest('input')) return;
    event.stopPropagation();
    this.videoTap.emit();
  }

  get showCenterOverlay(): boolean {
    if (this.isAdMode || this.showsControls) return false;
    if (this.centerOverlayMode === 'on-click') {
      return this.centerOverlayVisible;
    }
    return !this.isPlaying;
  }

  get shouldShowChrome(): boolean {
    if (!this.showsControls || this.isAdMode) return false;
    return this.controlsVisible || !this.isPlaying;
  }

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['src'] || changes['sources']) {
      this.rebuildQualityOptions();
      this.qualityResumeAt = null;
      this.qualityResumePlay = false;
      this.qualitySwitchInFlight = false;
      this.qualityFallbackUsed = false;
    }
    if (changes['src'] && !changes['src'].firstChange) {
      this.resetAdState();
      this.startTimeApplied = false;
      this.qualityMenuOpen = false;
      if (this.videoRef?.nativeElement) {
        const v = this.videoRef.nativeElement;
        // Always re-bind the known-good Auto source on src input change.
        v.src = this.currentSrc;
        v.load();
        this.requestAutoplay(v);
      }
    }
    if (changes['startTime'] && !changes['startTime'].firstChange) {
      this.startTimeApplied = false;
      this.applyStartTime(this.videoRef?.nativeElement);
    }
  }

  onVideoTap(video: HTMLVideoElement, event: Event): void {
    if (this.isAdMode) {
      event.stopPropagation();
      return;
    }
    // iOS: tap toggles chrome visibility; play/pause is the golden button.
    if (this.showsControls) {
      event.stopPropagation();
      if (this.controlsVisible && this.isPlaying) {
        this.controlsVisible = false;
        this.clearHideTimer();
      } else {
        this.revealControls();
      }
      return;
    }
    if (this.tapBehavior === 'emit') {
      event.stopPropagation();
      this.videoTap.emit();
      return;
    }
    if (this.tapBehavior === 'none') {
      event.stopPropagation();
      return;
    }
    this.togglePlay(video, event);
  }

  togglePlay(video: HTMLVideoElement, event: Event): void {
    event.stopPropagation();
    if (this.isAdMode) return;
    if (this.adsEnabled && !this.adDecisionMade) return;
    this.triggerCenterOverlay();
    if (video.paused) {
      if (this.isAdMode) {
        this.adBlockedByAnother = false;
      }
      this.userPaused = false;
      this.autoPaused = false;
      this.safePlay(video);
    } else {
      this.userPaused = true;
      this.autoPaused = false;
      video.pause();
    }
    this.revealControls();
  }

  toggleMute(video: HTMLVideoElement, event: Event): void {
    event.stopPropagation();
    VideoPlayerComponent.globalMuted = !video.muted;
    this.applyGlobalMute(video, VideoPlayerComponent.globalMuted);
    window.dispatchEvent(
      new CustomEvent('video-player-mute', { detail: VideoPlayerComponent.globalMuted })
    );
    this.revealControls();
  }

  toggleFullscreen(video: HTMLVideoElement, event: Event): void {
    event.stopPropagation();
    const shell = video.closest('.video-shell') as HTMLElement | null;
    if (!shell) return;
    const doc = document as Document & {
      webkitFullscreenElement?: Element | null;
      msFullscreenElement?: Element | null;
      webkitExitFullscreen?: () => Promise<void> | void;
      msExitFullscreen?: () => Promise<void> | void;
    };
    const anyVideo = video as HTMLVideoElement & { webkitEnterFullscreen?: () => void };
    if (!doc.fullscreenEnabled && anyVideo.webkitEnterFullscreen) {
      anyVideo.webkitEnterFullscreen();
      this.revealControls();
      return;
    }
    const fullscreenElement =
      doc.fullscreenElement || doc.webkitFullscreenElement || doc.msFullscreenElement;
    if (fullscreenElement) {
      if (doc.exitFullscreen) {
        doc.exitFullscreen();
      } else if (doc.webkitExitFullscreen) {
        doc.webkitExitFullscreen();
      } else if (doc.msExitFullscreen) {
        doc.msExitFullscreen();
      }
      this.revealControls();
      return;
    }
    if (shell.requestFullscreen) {
      shell.requestFullscreen();
    } else {
      if (anyVideo.webkitEnterFullscreen) {
        anyVideo.webkitEnterFullscreen();
      } else if (video.requestFullscreen) {
        video.requestFullscreen();
      } else {
        shell.classList.toggle('is-fullscreen');
      }
    }
    this.revealControls();
  }

  onLoaded(video: HTMLVideoElement): void {
    this.duration = Number.isFinite(video.duration) ? video.duration : 0;
    this.qualitySwitchInFlight = false;
    // Match player box to native aspect so contain fills without letterbox gaps.
    const w = video.videoWidth || 0;
    const h = video.videoHeight || 0;
    if (w > 0 && h > 0) {
      this.aspectRatio.emit(w / h);
    }
    if (this.qualityResumeAt != null) {
      const t = this.qualityResumeAt;
      const play = this.qualityResumePlay;
      this.qualityResumeAt = null;
      this.qualityResumePlay = false;
      const resume = () => {
        try {
          if (t > 0 && Number.isFinite(t)) video.currentTime = Math.min(t, video.duration || t);
        } catch {
          // ignore
        }
        if (play) {
          this.userPaused = false;
          this.autoPaused = false;
          void video.play().catch(() => undefined);
        }
      };
      // Seek after canplay is more reliable than on metadata alone.
      if (video.readyState >= 2) resume();
      else {
        const once = () => {
          video.removeEventListener('canplay', once);
          resume();
        };
        video.addEventListener('canplay', once);
      }
      return;
    }
    this.applyStartTime(video);
    this.requestAutoplay(video);
  }

  private applyStartTime(video?: HTMLVideoElement | null): void {
    if (!video || this.startTimeApplied) return;
    const t = Number(this.startTime);
    if (!Number.isFinite(t) || t < 1) return;
    if (Number.isFinite(video.duration) && video.duration > 0 && t >= video.duration - 1) return;
    try {
      video.currentTime = t;
      this.startTimeApplied = true;
    } catch {
      // seek may fail until more data is buffered
    }
  }

  onTimeUpdate(video: HTMLVideoElement): void {
    this.currentTime = video.currentTime || 0;
    this.duration = Number.isFinite(video.duration) ? video.duration : this.duration;
    this.progressPercent = this.duration ? (this.currentTime / this.duration) * 100 : 0;
    this.syncScrubCssVar();
    if (this.isAdMode) {
      this.adSecondsLeft = Math.max(0, Math.ceil((video.duration || 0) - (video.currentTime || 0)));
      this.adSkipSecondsLeft = Math.max(
        0,
        Math.ceil(this.adSkipAfterSeconds - (video.currentTime || 0))
      );
      this.adSkipReady = (video.currentTime || 0) >= this.adSkipAfterSeconds;
    } else {
      this.timeUpdate.emit({ currentTime: this.currentTime, duration: this.duration });
    }
    this.trackView(video);
  }

  onScrub(event: Event, video: HTMLVideoElement): void {
    event.stopPropagation();
    const target = event.target as HTMLInputElement;
    const value = Number(target.value);
    if (!this.duration) return;
    video.currentTime = (value / 100) * this.duration;
    this.currentTime = video.currentTime;
    this.progressPercent = value;
    this.syncScrubCssVar();
    this.revealControls();
  }

  private syncScrubCssVar(): void {
    const shell = this.videoRef?.nativeElement?.closest?.('.video-shell') as HTMLElement | null;
    const pct = `${this.progressPercent || 0}%`;
    if (shell) shell.style.setProperty('--scrub-pct', pct);
    // Also set on the range input (does not inherit custom props in all engines)
    const scrub = shell?.querySelector?.('.mc-scrub') as HTMLElement | null;
    if (scrub) scrub.style.setProperty('--scrub-pct', pct);
  }

  onPlay(): void {
    this.isPlaying = true;
    this.userPaused = false;
    this.autoPaused = false;
    if (this.isAdMode) {
      this.setGlobalActiveAd(true);
      if (!this.adStartedAt) this.adStartedAt = Date.now();
      this.markAdImpression();
      this.startAdCountdown();
    } else {
      this.setGlobalActiveContent(true);
      this.playState.emit(true);
    }
    this.revealControls();
  }

  onPause(): void {
    this.isPlaying = false;
    if (this.isAdMode) {
      this.releaseGlobalActiveAdIfOwner();
    } else {
      this.releaseGlobalActiveContentIfOwner();
      this.playState.emit(false);
    }
    this.controlsVisible = true;
    this.clearHideTimer();
  }

  onError(): void {
    const video = this.videoRef?.nativeElement;
    // Quality switch to a missing High URL must not kill the player permanently.
    if (video && this.recoverFromQualityError(video)) {
      return;
    }
    this.isPlaying = false;
    this.isBuffering = false;
    this.controlsVisible = true;
    this.clearHideTimer();
    if (this.isAdMode) {
      console.info('[ads-debug] ad media playback error', {
        adUrl: this.activeAd?.creative?.media_url ?? null,
        placement: this.adPlacement,
        country: this.adCountryCode,
        contentCountry: this.adContentCountryCode,
      });
      const video = this.videoRef?.nativeElement;
      if (video && this.adRetryCount < 1) {
        this.adRetryCount += 1;
        setTimeout(() => {
          video.load();
          this.safePlay(video);
        }, 40);
        return;
      }
      this.finishAd();
    }
  }

  onEnded(): void {
    if (this.isAdMode) {
      const elapsed = this.adStartedAt ? Date.now() - this.adStartedAt : 0;
      const video = this.videoRef?.nativeElement;
      if (video && elapsed > 0 && elapsed < 500 && this.adRetryCount < 1) {
        this.adRetryCount += 1;
        setTimeout(() => {
          video.currentTime = 0;
          video.load();
          this.safePlay(video);
        }, 40);
        return;
      }
      this.finishAd();
      return;
    }
    this.releaseGlobalActiveContentIfOwner();
    this.isPlaying = false;
    this.controlsVisible = true;
    this.currentTime = 0;
    this.progressPercent = 0;
  }

  setBuffering(state: boolean): void {
    this.isBuffering = state;
    if (!state) {
      this.requestAutoplay(this.videoRef.nativeElement);
    }
  }

  revealControls(): void {
    this.controlsVisible = true;
    this.clearHideTimer();
    if (this.isPlaying) {
      this.hideTimer = setTimeout(() => {
        this.controlsVisible = false;
      }, 2200);
    }
  }

  formatTime(value: number): string {
    if (!Number.isFinite(value)) return '0:00';
    const total = Math.floor(value);
    const minutes = Math.floor(total / 60);
    const seconds = total % 60;
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  }

  private clearHideTimer(): void {
    if (this.hideTimer) {
      clearTimeout(this.hideTimer);
      this.hideTimer = null;
    }
  }

  private triggerCenterOverlay(): void {
    if (this.centerOverlayMode !== 'on-click') return;
    this.centerOverlayVisible = true;
    if (this.centerTimer) {
      clearTimeout(this.centerTimer);
    }
    this.centerTimer = setTimeout(() => {
      this.centerOverlayVisible = false;
    }, 1100);
  }

  ngAfterViewInit(): void {
    this.rebuildQualityOptions();
    const video = this.videoRef.nativeElement;
    const windowMuted = typeof window !== 'undefined' ? (window as any).__videoMuted : undefined;
    const globalMuted = windowMuted === true ? true : VideoPlayerComponent.globalMuted;
    VideoPlayerComponent.globalMuted = globalMuted;
    this.applyGlobalMute(video, globalMuted);
    this.muteHandler = (event: Event) => {
      const detail = (event as CustomEvent<boolean>).detail;
      VideoPlayerComponent.globalMuted = detail;
      this.applyGlobalMute(video, detail);
    };
    this.adFocusHandler = (event: Event) => {
      const detail = (event as CustomEvent<{ ownerId: string | null; active: boolean }>).detail;
      if (!detail) return;
      if (detail.active) {
        if (!detail.ownerId || detail.ownerId === this.playerInstanceId) return;
        if (!video.paused && !video.ended) {
          this.autoPaused = true;
          video.pause();
        }
        return;
      }
      this.adBlockedByAnother = false;
      if (!this.isInView) return;
      if (!video.paused || video.ended) return;
      if (this.userPaused) return;
      this.requestAutoplay(video);
    };
    this.contentFocusHandler = (event: Event) => {
      const detail = (event as CustomEvent<{ ownerId: string | null; active: boolean }>).detail;
      if (!detail) return;
      if (detail.active) {
        if (!detail.ownerId || detail.ownerId === this.playerInstanceId) return;
        if (!video.paused && !video.ended) {
          this.autoPaused = true;
          video.pause();
        }
        return;
      }
      if (!this.isInView) return;
      if (!video.paused || video.ended) return;
      if (this.userPaused) return;
      if (this.isAnotherContentActive()) return;
      this.requestAutoplay(video);
    };
    window.addEventListener('video-player-mute', this.muteHandler);
    window.addEventListener('video-player-ad-focus', this.adFocusHandler);
    window.addEventListener('video-player-content-focus', this.contentFocusHandler);
    this.observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            this.isInView = true;
            if (this.adsEnabled && !this.adDecisionMade) {
              void this.prepareAdIfNeeded(video);
            } else {
              this.requestAutoplay(video);
            }
            this.autoPaused = false;
          } else {
            this.isInView = false;
            if (!video.paused && !video.ended) {
              this.autoPaused = true;
              video.pause();
            }
          }
        }
      },
      { threshold: 0.12 }
    );
    this.observer.observe(video);
  }

  ngOnDestroy(): void {
    this.observer?.disconnect();
    this.observer = null;
    this.clearAdCountdown();
    this.releaseGlobalActiveAdIfOwner();
    this.releaseGlobalActiveContentIfOwner();
    if (this.centerTimer) {
      clearTimeout(this.centerTimer);
      this.centerTimer = null;
    }
    if (this.muteHandler) {
      window.removeEventListener('video-player-mute', this.muteHandler);
      this.muteHandler = null;
    }
    if (this.adFocusHandler) {
      window.removeEventListener('video-player-ad-focus', this.adFocusHandler);
      this.adFocusHandler = null;
    }
    if (this.contentFocusHandler) {
      window.removeEventListener('video-player-content-focus', this.contentFocusHandler);
      this.contentFocusHandler = null;
    }
  }

  private applyGlobalMute(video: HTMLVideoElement, muted: boolean): void {
    video.muted = muted;
    this.isMuted = muted;
    try {
      (window as any).__videoMuted = muted;
    } catch {}
  }

  private trackView(video: HTMLVideoElement): void {
    if (this.viewTracked) return;
    if (!this.isInView) return;
    if (this.isAdMode) return;
    if (video.currentTime < 0.5) return;
    this.viewTracked = true;
    this.viewed.emit();
  }

  private requestAutoplay(video: HTMLVideoElement): void {
    if (this.adsEnabled && !this.adDecisionMade) {
      void this.prepareAdIfNeeded(video);
      return;
    }
    if (!this.isInView) return;
    if (this.userPaused) return;
    if (this.isAnotherVideoActive()) return;
    if (!video.paused && !video.ended) return;
    if (!this.tryClaimPlaybackSlot()) return;
    this.safePlay(video);
  }

  openAdLink(event: Event): void {
    event.stopPropagation();
    const url = this.activeAd?.creative?.click_url;
    if (!url) return;
    void this.ads.logClick(this.activeAd!.impression_token).catch(() => {});
    window.open(url, '_blank', 'noopener');
  }

  skipAd(event: Event): void {
    event.stopPropagation();
    if (!this.adSkipReady) return;
    this.finishAd();
  }

  private async prepareAdIfNeeded(video: HTMLVideoElement): Promise<void> {
    if (!this.adsEnabled) {
      this.adDecisionMade = true;
      return;
    }
    const src = String(this.src || '').trim();
    if (!src) {
      this.adDecisionMade = true;
      return;
    }
    // Same post re-opened after mini/expand — never re-roll the pre-roll.
    const postKey = String(this.adPostId || '').trim();
    if (postKey && VideoPlayerComponent.adsCompletedForPost.has(postKey)) {
      this.adDecisionMade = true;
      this.activeAd = null;
      this.isAdMode = false;
      this.adPreparedForSrc = src;
      this.applyGlobalMute(video, VideoPlayerComponent.globalMuted);
      this.requestAutoplay(video);
      return;
    }
    if (this.adPreparing) return;
    if (this.adPreparedForSrc === src) return;
    this.adPreparing = true;
    this.adPreparedForSrc = src;
    this.isBuffering = true;
    try {
      const countryCode = this.adCountryCode || this.adContentCountryCode || null;
      const contentCountryCode = this.adContentCountryCode || this.adCountryCode || null;
      const placement = this.adPlacement!;
      this.activeAd = await this.ads.serveVideoAd({
        placement,
        country_code: countryCode,
        content_country_code: contentCountryCode,
        post_id: this.adPostId,
      });
      if (!this.activeAd && placement === 'reel') {
        const fallbackAttempts = [
          { country_code: countryCode, content_country_code: contentCountryCode },
          { country_code: contentCountryCode, content_country_code: contentCountryCode },
          { country_code: countryCode, content_country_code: countryCode },
        ];

        for (const attempt of fallbackAttempts) {
          if (this.activeAd) break;
          this.activeAd = await this.ads.serveVideoAd({
            placement: 'video',
            country_code: attempt.country_code,
            content_country_code: attempt.content_country_code,
            post_id: this.adPostId,
          });
        }
      }
      this.isAdMode = !!this.activeAd;
      this.adSecondsLeft = Number(this.activeAd?.creative?.duration_seconds ?? 0);
      this.adSkipAfterSeconds = Math.max(5, Number(this.activeAd?.skip_after_seconds ?? 0));
      this.adSkipSecondsLeft = this.adSkipAfterSeconds;
      this.adSkipReady = false;
      this.adImpressionLogged = false;
      this.adRetryCount = 0;
      this.adStartedAt = 0;
      this.adBlockedByAnother = false;
    } catch {
      this.activeAd = null;
      this.isAdMode = false;
    } finally {
      this.adPreparing = false;
      this.adDecisionMade = true;
      this.isBuffering = false;
      if (!this.activeAd) {
        void this.logAdDebugIfEmpty();
      }
      this.applyGlobalMute(video, VideoPlayerComponent.globalMuted);
      video.load();
      this.requestAutoplay(video);
    }
  }

  private markAdImpression(): void {
    if (!this.activeAd || this.adImpressionLogged) return;
    this.adImpressionLogged = true;
    void this.ads.logImpression(this.activeAd.impression_token).catch(() => {});
  }

  private startAdCountdown(): void {
    if (!this.isAdMode || !this.activeAd) return;
    if (this.adCountdownTimer) return;
    this.adSkipReady = false;
    this.adCountdownTimer = setInterval(() => {
      const video = this.videoRef?.nativeElement;
      if (!video || video.paused) return;
      this.adSecondsLeft = Math.max(0, Math.ceil((video.duration || 0) - (video.currentTime || 0)));
      this.adSkipSecondsLeft = Math.max(
        0,
        Math.ceil(this.adSkipAfterSeconds - (video.currentTime || 0))
      );
      this.adSkipReady = (video.currentTime || 0) >= this.adSkipAfterSeconds;
      if (this.adSecondsLeft <= 0) {
        this.clearAdCountdown();
      }
    }, 250);
  }

  private clearAdCountdown(): void {
    if (this.adCountdownTimer) {
      clearInterval(this.adCountdownTimer);
      this.adCountdownTimer = null;
    }
  }

  private finishAd(): void {
    const video = this.videoRef?.nativeElement;
    if (video && !video.paused) {
      video.pause();
    }
    this.releaseGlobalActiveAdIfOwner();
    this.clearAdCountdown();
    this.isAdMode = false;
    this.adDecisionMade = true;
    this.adSecondsLeft = 0;
    this.adSkipSecondsLeft = 0;
    this.adSkipReady = false;
    this.adSkipAfterSeconds = 0;
    this.adRetryCount = 0;
    this.adStartedAt = 0;
    this.adBlockedByAnother = false;
    this.currentTime = 0;
    this.progressPercent = 0;
    this.duration = 0;
    const postKey = String(this.adPostId || '').trim();
    if (postKey) {
      VideoPlayerComponent.adsCompletedForPost.add(postKey);
    }
    if (!video) return;
    video.removeAttribute('src');
    video.load();
    this.applyGlobalMute(video, VideoPlayerComponent.globalMuted);
    this.requestAutoplay(video);
  }

  private resetAdState(): void {
    this.releaseGlobalActiveAdIfOwner();
    this.releaseGlobalActiveContentIfOwner();
    this.clearAdCountdown();
    this.activeAd = null;
    this.isAdMode = false;
    this.adDecisionMade = !this.adsEnabled;
    this.adSecondsLeft = 0;
    this.adSkipSecondsLeft = 0;
    this.adSkipReady = false;
    this.adSkipAfterSeconds = 0;
    this.adImpressionLogged = false;
    this.adPreparedForSrc = null;
    this.adPreparing = false;
    this.adDebugLoggedForSrc = false;
    this.adRetryCount = 0;
    this.adStartedAt = 0;
    this.adBlockedByAnother = false;
    this.viewTracked = false;
  }

  private safePlay(video: HTMLVideoElement, allowMutedRetry = true): void {
    const playAttempt = video.play();
    if (!playAttempt || typeof playAttempt.catch !== 'function') return;
    playAttempt.catch((error: any) => {
      const name = String(error?.name ?? '');
      if (name === 'AbortError') return;
      if (name === 'NotAllowedError' && this.isAdMode && allowMutedRetry) {
        video.muted = true;
        this.isMuted = true;
        this.safePlay(video, false);
        return;
      }
      if (name === 'NotAllowedError') {
        this.releasePlaybackSlotIfOwner();
        return;
      }
      this.releasePlaybackSlotIfOwner();
    });
  }

  private isAnotherAdActive(): boolean {
    const owner = VideoPlayerComponent.activeAdPlayerId;
    return !!owner && owner !== this.playerInstanceId;
  }

  private isAnotherContentActive(): boolean {
    const owner = VideoPlayerComponent.activeContentPlayerId;
    return !!owner && owner !== this.playerInstanceId;
  }

  private isAnotherVideoActive(): boolean {
    return this.isAnotherAdActive() || this.isAnotherContentActive();
  }

  private tryClaimPlaybackSlot(): boolean {
    if (this.isAdMode) {
      if (this.isAnotherVideoActive()) return false;
      this.setGlobalActiveAd(true);
      return true;
    }
    if (this.isAnotherVideoActive()) return false;
    this.setGlobalActiveContent(true);
    return true;
  }

  private releasePlaybackSlotIfOwner(): void {
    if (this.isAdMode) {
      this.releaseGlobalActiveAdIfOwner();
      return;
    }
    this.releaseGlobalActiveContentIfOwner();
  }

  private setGlobalActiveAd(active: boolean): void {
    if (!this.isAdMode || typeof window === 'undefined') return;
    if (active) {
      this.adBlockedByAnother = false;
    }
    VideoPlayerComponent.activeAdPlayerId = active ? this.playerInstanceId : null;
    window.dispatchEvent(
      new CustomEvent('video-player-ad-focus', {
        detail: { ownerId: VideoPlayerComponent.activeAdPlayerId, active },
      })
    );
  }

  private releaseGlobalActiveAdIfOwner(): void {
    if (typeof window === 'undefined') return;
    if (VideoPlayerComponent.activeAdPlayerId !== this.playerInstanceId) return;
    VideoPlayerComponent.activeAdPlayerId = null;
    window.dispatchEvent(
      new CustomEvent('video-player-ad-focus', {
        detail: { ownerId: null, active: false },
      })
    );
  }

  private setGlobalActiveContent(active: boolean): void {
    if (this.isAdMode || typeof window === 'undefined') return;
    VideoPlayerComponent.activeContentPlayerId = active ? this.playerInstanceId : null;
    window.dispatchEvent(
      new CustomEvent('video-player-content-focus', {
        detail: { ownerId: VideoPlayerComponent.activeContentPlayerId, active },
      })
    );
  }

  private releaseGlobalActiveContentIfOwner(): void {
    if (typeof window === 'undefined') return;
    if (VideoPlayerComponent.activeContentPlayerId !== this.playerInstanceId) return;
    VideoPlayerComponent.activeContentPlayerId = null;
    window.dispatchEvent(
      new CustomEvent('video-player-content-focus', {
        detail: { ownerId: null, active: false },
      })
    );
  }

  private async logAdDebugIfEmpty(): Promise<void> {
    if (!this.adsEnabled) return;
    if (this.adDebugLoggedForSrc) return;
    if (!this.isAdDebugEnabled()) return;
    this.adDebugLoggedForSrc = true;
    try {
      const debug = await this.ads.debugServeVideoAd({
        placement: this.adPlacement!,
        country_code: this.adCountryCode,
        content_country_code: this.adContentCountryCode,
        post_id: this.adPostId,
      });
      console.info('[ads-debug]', debug);
    } catch (error) {
      console.info('[ads-debug] debugServeVideoAd failed', error);
    }
  }

  private isAdDebugEnabled(): boolean {
    if (typeof window === 'undefined') return false;
    if (VideoPlayerComponent.adDebugEnabled !== null) {
      return VideoPlayerComponent.adDebugEnabled;
    }
    try {
      const qs = new URLSearchParams(window.location.search);
      const queryEnabled = qs.get('ads_debug') === '1';
      const localEnabled = window.localStorage.getItem('ads_debug') === '1';
      VideoPlayerComponent.adDebugEnabled = queryEnabled || localEnabled;
    } catch {
      VideoPlayerComponent.adDebugEnabled = false;
    }
    return VideoPlayerComponent.adDebugEnabled;
  }
}
