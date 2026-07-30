import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnDestroy, OnInit } from '@angular/core';
import { NavigationEnd, Router } from '@angular/router';
import { Subscription } from 'rxjs';

import { AuthService } from '../core/services/auth.service';
import { LocationService } from '../core/services/location.service';
import { NotificationsService } from '../core/services/notifications.service';
import { ProfileService } from '../core/services/profile.service';
import { resolveAvatarUrl } from '../core/utils/media-url.util';

type TabKey = 'feed' | 'globe' | 'hubs' | 'messages' | 'profile';

@Component({
  selector: 'app-bottom-tabs',
  standalone: true,
  imports: [CommonModule],
  host: {
    '[class.hidden]': 'tabsHidden',
  },
  template: `
    <nav class="bottom-tabs" [class.globe-mode]="globeMode" role="navigation" aria-label="Primary">
      <button type="button" class="tab-btn" aria-label="Feed" [class.active]="active === 'feed'" (click)="goFeed()">
        <svg class="tab-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7">
          <path d="M4 10.5L12 4l8 6.5V20a1 1 0 0 1-1 1h-5v-6H10v6H5a1 1 0 0 1-1-1v-9.5z" stroke-linejoin="round" />
        </svg>
      </button>

      <button type="button" class="tab-btn" aria-label="Globe" [class.active]="active === 'globe'" (click)="goGlobe()">
        <svg class="tab-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7">
          <circle cx="12" cy="12" r="8.5" />
          <path d="M3.5 12h17M12 3.5c2.4 2.6 3.6 5.4 3.6 8.5S14.4 17.9 12 20.5C9.6 17.9 8.4 15.1 8.4 12S9.6 6.1 12 3.5z" />
        </svg>
      </button>

      <button type="button" class="create-btn" aria-label="Create" (click)="toggleCreateMenu($event)">
        <span class="create-plus">+</span>
      </button>

      <button type="button" class="tab-btn" aria-label="Hubs" [class.active]="active === 'hubs'" (click)="goHubs()">
        <svg class="tab-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7">
          <rect x="3.5" y="3.5" width="7" height="7" rx="1.2" />
          <rect x="13.5" y="3.5" width="7" height="7" rx="1.2" />
          <rect x="3.5" y="13.5" width="7" height="7" rx="1.2" />
          <rect x="13.5" y="13.5" width="7" height="7" rx="1.2" />
        </svg>
      </button>

      <button
        type="button"
        class="tab-btn"
        aria-label="Messages"
        [class.active]="active === 'messages'"
        (click)="goMessages()"
      >
        <svg class="tab-svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7">
          <path
            d="M5 16.5V7.8A2.3 2.3 0 0 1 7.3 5.5h9.4A2.3 2.3 0 0 1 19 7.8v5.4a2.3 2.3 0 0 1-2.3 2.3H9.2L5 18.5v-2z"
            stroke-linejoin="round"
          />
        </svg>
        <span class="tab-dot" *ngIf="messagesUnreadCount > 0"></span>
      </button>

      <button
        type="button"
        class="tab-btn profile-tab"
        aria-label="Profile"
        [class.active]="active === 'profile'"
        (click)="goProfile()"
      >
        <span class="profile-avatar" [class.selected]="active === 'profile'">
          <img
            *ngIf="avatarUrl"
            [src]="avatarUrl"
            alt=""
            (error)="onAvatarError()"
          />
          <span *ngIf="!avatarUrl">{{ avatarInitials }}</span>
        </span>
      </button>
    </nav>

    <button
      *ngIf="createMenuOpen"
      type="button"
      class="create-backdrop"
      aria-label="Close create menu"
      (click)="closeCreateMenu()"
    ></button>

    <div class="create-sheet" *ngIf="createMenuOpen">
      <div class="create-handle"></div>
      <div class="create-head">
        <div>
          <div class="create-title">Create</div>
          <div class="create-sub">Share with your country</div>
        </div>
        <button type="button" class="create-close" (click)="closeCreateMenu()" aria-label="Close">×</button>
      </div>
      <button type="button" class="create-row" (click)="create('post')">
        <span class="create-row-title">Post</span>
        <span class="create-row-sub">Share an update</span>
      </button>
      <button type="button" class="create-row" (click)="create('video')">
        <span class="create-row-title">Video</span>
        <span class="create-row-sub">Long-form on Matterya Hubs</span>
      </button>
      <button type="button" class="create-row" (click)="create('spark')">
        <span class="create-row-title">Spark</span>
        <span class="create-row-sub">Short vertical video</span>
      </button>
      <button type="button" class="create-row" (click)="create('moment')">
        <span class="create-row-title">Moment</span>
        <span class="create-row-sub">Disappears in 24 hours</span>
      </button>
    </div>
  `,
  styles: [
    `
      :host {
        position: fixed;
        left: 0;
        right: 0;
        bottom: 0;
        z-index: 90;
        pointer-events: none;
        transition: transform 180ms ease, opacity 180ms ease;
      }
      :host.hidden {
        transform: translateY(calc(var(--tabs-height, 56px) + env(safe-area-inset-bottom) + 6px));
        opacity: 0;
      }
      .bottom-tabs {
        pointer-events: auto;
        display: grid;
        grid-template-columns: repeat(6, minmax(0, 1fr));
        align-items: center;
        width: 100%;
        margin: 0;
        padding: 4px 6px calc(4px + env(safe-area-inset-bottom));
        min-height: calc(var(--tabs-height, 56px) + env(safe-area-inset-bottom));
        background: rgba(253, 252, 250, 0.96);
        border-top: 0.5px solid var(--m-divider, #e2ded8);
        box-shadow: 0 -8px 24px rgba(44, 40, 37, 0.04);
      }
      .bottom-tabs.globe-mode {
        background: rgba(253, 252, 250, 0.94);
      }
      .tab-btn {
        border: 0;
        border-radius: 14px;
        background: transparent;
        color: var(--m-ink, #2c2825);
        cursor: pointer;
        padding: 8px 2px;
        position: relative;
        display: grid;
        place-items: center;
        min-height: 44px;
      }
      .tab-btn.active {
        color: var(--m-ink, #2c2825);
      }
      .tab-svg {
        width: 24px;
        height: 24px;
      }
      .tab-btn.active .tab-svg {
        stroke-width: 2;
      }
      .tab-dot {
        position: absolute;
        top: 8px;
        right: calc(50% - 14px);
        width: 8px;
        height: 8px;
        border-radius: 999px;
        background: var(--m-danger, #ea000b);
      }
      .create-btn {
        pointer-events: auto;
        border: 0;
        background: transparent;
        width: 100%;
        height: 48px;
        display: grid;
        place-items: center;
        cursor: pointer;
        transform: translateY(-8px);
      }
      .create-plus {
        width: 36px;
        height: 36px;
        border-radius: 12px;
        display: grid;
        place-items: center;
        font-size: 28px;
        font-weight: 300;
        line-height: 1;
        color: var(--m-ink, #2c2825);
        background: transparent;
      }
      .profile-avatar {
        width: 28px;
        height: 28px;
        border-radius: 999px;
        overflow: hidden;
        display: grid;
        place-items: center;
        background: var(--m-canvas-muted, #f2f0ec);
        font-size: 10px;
        font-weight: 700;
        color: var(--m-ink-secondary, #6b645d);
        border: 1.5px solid transparent;
      }
      .profile-avatar.selected {
        border-color: var(--m-accent, #6b5841);
        width: 26px;
        height: 26px;
      }
      .profile-avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .create-backdrop {
        position: fixed;
        inset: 0;
        border: 0;
        background: rgba(44, 40, 37, 0.16);
        pointer-events: auto;
        z-index: 91;
      }
      .create-sheet {
        position: fixed;
        left: 0;
        right: 0;
        bottom: 0;
        z-index: 92;
        pointer-events: auto;
        background: var(--m-surface, #fefdfb);
        border-radius: 18px 18px 0 0;
        padding: 8px 0 calc(12px + env(safe-area-inset-bottom));
        box-shadow: 0 -16px 40px rgba(44, 40, 37, 0.12);
        border-top: 0.5px solid var(--m-divider, #e2ded8);
      }
      .create-handle {
        width: 36px;
        height: 4px;
        border-radius: 999px;
        background: var(--m-border, #ddd8d1);
        margin: 6px auto 10px;
      }
      .create-head {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        padding: 0 20px 10px;
      }
      .create-title {
        font-family: 'Iowan Old Style', Palatino, Georgia, serif;
        font-size: 24px;
        color: var(--m-ink, #2c2825);
      }
      .create-sub {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
        margin-top: 2px;
      }
      .create-close {
        border: 0;
        background: transparent;
        font-size: 24px;
        color: var(--m-ink-muted, #948b82);
        cursor: pointer;
        line-height: 1;
        width: 36px;
        height: 36px;
      }
      .create-row {
        width: 100%;
        border: 0;
        background: transparent;
        text-align: left;
        padding: 14px 20px;
        cursor: pointer;
        display: grid;
        gap: 2px;
        border-top: 0.5px solid var(--m-divider, #e2ded8);
      }
      .create-row:hover {
        background: rgba(44, 40, 37, 0.04);
      }
      .create-row-title {
        font-size: 16px;
        font-weight: 650;
        color: var(--m-ink, #2c2825);
      }
      .create-row-sub {
        font-size: 12px;
        color: var(--m-ink-muted, #948b82);
      }
      @media (min-width: 900px) {
        .bottom-tabs {
          max-width: 720px;
          margin: 0 auto 10px;
          border-radius: 18px;
          border: 0.5px solid var(--m-divider, #e2ded8);
          width: min(720px, calc(100vw - 24px));
        }
        .create-sheet {
          left: 50%;
          transform: translateX(-50%);
          width: min(480px, 100vw);
          border-radius: 18px;
          bottom: calc(var(--tabs-height, 56px) + env(safe-area-inset-bottom) + 16px);
        }
      }
    `,
  ],
})
export class BottomTabsComponent implements OnInit, OnDestroy {
  active: TabKey = 'feed';
  messagesUnreadCount = 0;
  tabsHidden = false;
  createMenuOpen = false;
  globeMode = false;
  avatarUrl: string | null = null;
  avatarInitials = 'ME';

  private sub?: Subscription;
  private unreadPollTimer: number | null = null;
  private unreadRefreshInFlight = false;
  private lastScrollTop = 0;
  private scrollHandler = (event: Event) => this.handleScroll(event);

  constructor(
    private router: Router,
    private location: LocationService,
    private auth: AuthService,
    private notifications: NotificationsService,
    private profiles: ProfileService,
    private cdr: ChangeDetectorRef
  ) {}

  private paint(): void {
    try {
      this.cdr.detectChanges();
    } catch {
      // destroyed
    }
  }

  ngOnInit(): void {
    this.syncActive(this.router.url);
    void this.loadProfileAvatar();
    this.sub = this.router.events.subscribe((event) => {
      if (event instanceof NavigationEnd) {
        this.syncActive(event.urlAfterRedirects || event.url);
        this.createMenuOpen = false;
        // Re-fetch when returning to app chrome (avatar may have changed on /me).
        if (this.active === 'feed' || this.active === 'profile') {
          void this.loadProfileAvatar();
        }
        this.paint();
      }
    });
    void this.refreshUnreadMessages();
    this.unreadPollTimer = window.setInterval(() => this.refreshUnreadMessages(), 20000);
    window.addEventListener('scroll', this.scrollHandler, true);
  }

  ngOnDestroy(): void {
    this.sub?.unsubscribe();
    if (this.unreadPollTimer) {
      window.clearInterval(this.unreadPollTimer);
      this.unreadPollTimer = null;
    }
    window.removeEventListener('scroll', this.scrollHandler, true);
  }

  goFeed(): void {
    this.createMenuOpen = false;
    void this.router.navigate(['/feed']);
  }

  goGlobe(): void {
    this.createMenuOpen = false;
    const cached = this.location.getCachedLocation();
    const code = cached?.countryCode?.trim().toUpperCase();
    void this.router.navigate(['/globe'], {
      queryParams: code ? { country: null } : null,
    });
  }

  goHubs(): void {
    this.createMenuOpen = false;
    void this.router.navigate(['/hubs']);
  }

  goMessages(): void {
    this.createMenuOpen = false;
    void this.router.navigate(['/messages']);
  }

  goProfile(): void {
    this.createMenuOpen = false;
    void this.router.navigate(['/me']);
  }

  toggleCreateMenu(event?: Event): void {
    event?.stopPropagation();
    this.createMenuOpen = !this.createMenuOpen;
  }

  closeCreateMenu(): void {
    this.createMenuOpen = false;
  }

  create(kind: 'post' | 'video' | 'spark' | 'moment'): void {
    this.createMenuOpen = false;
    const cached = this.location.getCachedLocation();
    const code = cached?.countryCode?.trim().toUpperCase();
    if (kind === 'video' && code) {
      void this.router.navigate(['/globe'], {
        queryParams: { country: code, tab: 'posts', compose: 'video' },
      });
      return;
    }
    if (kind === 'spark' && code) {
      void this.router.navigate(['/globe'], {
        queryParams: { country: code, tab: 'posts', compose: 'spark' },
      });
      return;
    }
    void this.router.navigate(['/globe'], {
      queryParams: {
        country: code || null,
        tab: 'posts',
        compose: kind === 'moment' ? 'moment' : kind === 'video' ? 'video' : 'post',
      },
    });
  }

  onAvatarError(): void {
    // Broken storage URL → fall back to generated avatar or initials (never a ? icon).
    if (this.avatarUrl && !this.avatarUrl.includes('dicebear.com')) {
      const seed = this.avatarSeed || this.avatarInitials || 'user';
      this.avatarUrl = resolveAvatarUrl(null, seed) || null;
      this.paint();
      return;
    }
    this.avatarUrl = null;
    this.paint();
  }

  private avatarSeed = '';

  private async loadProfileAvatar(): Promise<void> {
    try {
      const user = await this.auth.getUser();
      if (!user) {
        this.avatarUrl = null;
        this.avatarInitials = 'ME';
        this.paint();
        return;
      }
      const { meProfile } = await this.profiles.meProfile();
      const name =
        meProfile?.display_name ||
        meProfile?.username ||
        user.email?.split('@')[0] ||
        'ME';
      this.avatarInitials = this.initialsFrom(name);
      this.avatarSeed =
        meProfile?.username || meProfile?.user_id || user.id || this.avatarInitials;
      // Always resolve to a usable <img> URL (public storage path or dicebear).
      const resolved = resolveAvatarUrl(
        meProfile?.avatar_url,
        this.avatarSeed
      );
      this.avatarUrl = resolved || null;
      this.paint();
    } catch {
      // keep last known
      this.paint();
    }
  }

  private initialsFrom(name: string): string {
    const cleaned = String(name || '')
      .trim()
      .replace(/[@._-]+/g, ' ')
      .replace(/\s+/g, ' ');
    if (!cleaned) return 'ME';
    const parts = cleaned.split(' ').filter(Boolean);
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return cleaned.slice(0, 2).toUpperCase();
  }

  private async refreshUnreadMessages(): Promise<void> {
    if (this.unreadRefreshInFlight) return;
    this.unreadRefreshInFlight = true;
    try {
      const user = await this.auth.getUser();
      if (!user) {
        this.messagesUnreadCount = 0;
        this.paint();
        return;
      }
      const { notifications } = await this.notifications.list(80);
      const unread = (notifications ?? []).filter(
        (notif) => !notif.read_at && String(notif?.type ?? '').toLowerCase() === 'message'
      );
      this.messagesUnreadCount = unread.length;
      this.paint();
    } catch {
      // keep last known
    } finally {
      this.unreadRefreshInFlight = false;
    }
  }

  private syncActive(url: string): void {
    let parsed: URL | null = null;
    try {
      parsed = new URL(url, window.location.origin);
    } catch {}
    const pathname = parsed?.pathname ?? url;
    this.globeMode =
      pathname === '/globe' || pathname.startsWith('/globe-cesium');

    if (pathname.startsWith('/messages')) {
      this.active = 'messages';
      return;
    }
    if (pathname.startsWith('/me') || pathname.startsWith('/user')) {
      this.active = 'profile';
      return;
    }
    if (pathname.startsWith('/hubs') || pathname.startsWith('/reels') || pathname.startsWith('/sparks')) {
      this.active = 'hubs';
      return;
    }
    if (pathname.startsWith('/globe') || pathname.startsWith('/globe-cesium')) {
      this.active = 'globe';
      return;
    }
    if (pathname.startsWith('/feed') || pathname === '/') {
      this.active = 'feed';
      return;
    }
    if (pathname.startsWith('/search')) {
      this.active = 'feed';
      return;
    }
    this.active = 'feed';
  }

  private handleScroll(event: Event): void {
    if (typeof window !== 'undefined' && window.innerWidth >= 900) {
      this.tabsHidden = false;
      return;
    }
    const target = event.target as HTMLElement | Document | Window | null;
    let current = 0;
    if (target && (target as HTMLElement).scrollTop != null) {
      current = (target as HTMLElement).scrollTop;
    } else {
      current = window.scrollY || document.documentElement.scrollTop || 0;
    }
    const delta = current - this.lastScrollTop;
    if (Math.abs(delta) < 6) return;
    if (delta > 0 && current > 20) {
      this.tabsHidden = true;
      this.createMenuOpen = false;
    } else if (delta < 0) {
      this.tabsHidden = false;
    }
    this.lastScrollTop = current;
  }
}
