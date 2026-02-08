import { CommonModule } from '@angular/common';
import {
  AfterViewInit,
  Component,
  ElementRef,
  EventEmitter,
  HostListener,
  Input,
  OnDestroy,
  Output,
  ViewChild,
} from '@angular/core';

@Component({
  selector: 'app-video-player',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div
      class="video-shell"
      [class.is-playing]="isPlaying"
      (mousemove)="revealControls()"
      (touchstart)="revealControls()"
    >
      <video
        #videoEl
        [src]="src"
        [attr.poster]="poster || null"
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
      <div class="video-overlay"></div>
      <button
        *ngIf="showMute"
        class="mute-toggle"
        type="button"
        [attr.aria-label]="isMuted ? 'Unmute video' : 'Mute video'"
        (click)="toggleMute(videoEl, $event)"
      >
        <svg
          *ngIf="!isMuted"
          class="icon-svg icon-stroke"
          viewBox="0 0 24 24"
          aria-hidden="true"
        >
          <path d="M4 10h4l5-4v12l-5-4H4z"></path>
          <path d="M16 9a3 3 0 0 1 0 6"></path>
          <path d="M18.5 6.5a6 6 0 0 1 0 11"></path>
        </svg>
        <svg
          *ngIf="isMuted"
          class="icon-svg icon-stroke"
          viewBox="0 0 24 24"
          aria-hidden="true"
        >
          <path d="M4 10h4l5-4v12l-5-4H4z"></path>
          <line x1="16" y1="8" x2="21" y2="13"></line>
          <line x1="21" y1="8" x2="16" y2="13"></line>
        </svg>
      </button>
      <button
        class="center-play"
        *ngIf="showCenterOverlay"
        type="button"
        aria-label="Play video"
        (click)="onVideoTap(videoEl, $event)"
      >
        <svg
          *ngIf="!isPlaying"
          class="center-icon"
          viewBox="0 0 24 24"
          aria-hidden="true"
        >
          <path d="M8 5v14l11-7z"></path>
        </svg>
        <svg
          *ngIf="isPlaying"
          class="center-icon"
          viewBox="0 0 24 24"
          aria-hidden="true"
        >
          <rect x="6" y="5" width="4" height="14" rx="1"></rect>
          <rect x="14" y="5" width="4" height="14" rx="1"></rect>
        </svg>
      </button>
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
        background: #050505;
        overflow: hidden;
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
        width: 100%;
        display: block;
        max-height: none;
        height: auto;
        object-fit: contain;
        background: #000;
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
        background: linear-gradient(180deg, rgba(0, 0, 0, 0.55), rgba(0, 0, 0, 0) 45%, rgba(0, 0, 0, 0.65));
        opacity: 0.7;
        transition: opacity 200ms ease;
        pointer-events: none;
      }
      .video-shell.is-playing .video-overlay {
        opacity: 0.3;
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
      }
      .center-play:hover {
        transform: scale(1.05);
        background: rgba(10, 10, 10, 0.9);
      }
      .play-icon {
        width: 0;
        height: 0;
        border-top: 16px solid transparent;
        border-bottom: 16px solid transparent;
        border-left: 26px solid #fff;
        margin-left: 6px;
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
        z-index: 3;
      }
      .buffering {
        position: absolute;
        inset: 0;
        display: grid;
        place-items: center;
        pointer-events: none;
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
export class VideoPlayerComponent implements AfterViewInit, OnDestroy {
  private static globalMuted = false;
  @Input({ required: true }) src!: string;
  @Input() poster: string | null = null;
  @Input() preload: 'none' | 'metadata' | 'auto' = 'metadata';
  @Input() showMute = true;
  @Input() centerOverlayMode: 'always' | 'on-click' = 'on-click';
  @Input() tapBehavior: 'toggle' | 'emit' | 'none' = 'toggle';
  @Output() videoTap = new EventEmitter<void>();
  @Output() viewed = new EventEmitter<void>();
  @ViewChild('videoEl', { static: true }) videoRef!: ElementRef<HTMLVideoElement>;

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
  private muteHandler: ((event: Event) => void) | null = null;
  private viewTracked = false;

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
    if (this.centerOverlayMode === 'on-click') {
      return this.centerOverlayVisible;
    }
    return !this.isPlaying;
  }

  onVideoTap(video: HTMLVideoElement, event: Event): void {
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
    this.triggerCenterOverlay();
    if (video.paused) {
      this.userPaused = false;
      this.autoPaused = false;
      void video.play();
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
    this.requestAutoplay(video);
  }

  onTimeUpdate(video: HTMLVideoElement): void {
    this.currentTime = video.currentTime || 0;
    this.duration = Number.isFinite(video.duration) ? video.duration : this.duration;
    this.progressPercent = this.duration ? (this.currentTime / this.duration) * 100 : 0;
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
    this.revealControls();
  }

  onPlay(): void {
    this.isPlaying = true;
    this.userPaused = false;
    this.autoPaused = false;
    this.revealControls();
  }

  onPause(): void {
    this.isPlaying = false;
    this.controlsVisible = true;
    this.clearHideTimer();
  }

  onError(): void {
    this.isPlaying = false;
    this.isBuffering = false;
    this.controlsVisible = true;
    this.clearHideTimer();
  }

  onEnded(): void {
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
    window.addEventListener('video-player-mute', this.muteHandler);
    this.observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            this.isInView = true;
            this.requestAutoplay(video);
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
      { threshold: 0.35 }
    );
    this.observer.observe(video);
  }

  ngOnDestroy(): void {
    this.observer?.disconnect();
    this.observer = null;
    if (this.centerTimer) {
      clearTimeout(this.centerTimer);
      this.centerTimer = null;
    }
    if (this.muteHandler) {
      window.removeEventListener('video-player-mute', this.muteHandler);
      this.muteHandler = null;
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
    if (video.currentTime < 0.5) return;
    this.viewTracked = true;
    this.viewed.emit();
  }

  private requestAutoplay(video: HTMLVideoElement): void {
    if (!this.isInView) return;
    if (this.userPaused) return;
    if (!video.paused && !video.ended) return;
    const playAttempt = video.play();
    if (playAttempt && typeof playAttempt.catch === 'function') {
      playAttempt.catch(() => {});
    }
  }
}
