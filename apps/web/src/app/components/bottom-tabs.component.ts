import { CommonModule } from '@angular/common';
import { Component, OnDestroy, OnInit } from '@angular/core';
import { NavigationEnd, Router } from '@angular/router';
import { Subscription } from 'rxjs';

import { AuthService } from '../core/services/auth.service';
import { LocationService } from '../core/services/location.service';
import { NotificationsService } from '../core/services/notifications.service';

type TabKey = 'home' | 'search' | 'messages' | 'profile';

@Component({
  selector: 'app-bottom-tabs',
  standalone: true,
  imports: [CommonModule],
  host: {
    '[class.hidden]': 'tabsHidden',
  },
  template: `
    <nav class="bottom-tabs" [class.globe-mode]="globeMode" role="navigation" aria-label="Primary">
      <button
        type="button"
        class="tab-btn"
        aria-label="Feed"
        [class.active]="active === 'home'"
        (click)="goHome()"
      >
        <span class="tab-icon" aria-hidden="true">&#127968;</span>
      </button>
      <button
        type="button"
        class="tab-btn"
        aria-label="Search"
        [class.active]="active === 'search'"
        (click)="openSearch()"
      >
        <span class="tab-icon" aria-hidden="true">&#128269;</span>
      </button>
      <button
        type="button"
        class="tab-btn"
        aria-label="Chats"
        [class.active]="active === 'messages'"
        (click)="goMessages()"
      >
        <span class="tab-icon" aria-hidden="true">&#128172;</span>
        <span class="tab-badge" *ngIf="messagesUnreadCount > 0">{{ messagesUnreadCount }}</span>
      </button>
      <button
        type="button"
        class="tab-btn"
        aria-label="Profile"
        [class.active]="active === 'profile' || profileMenuOpen"
        (click)="toggleProfileMenu($event)"
      >
        <span class="tab-icon" aria-hidden="true">&#128100;</span>
      </button>
    </nav>

    <button
      *ngIf="profileMenuOpen"
      type="button"
      class="profile-menu-backdrop"
      aria-label="Close profile menu"
      (click)="closeProfileMenu()"
    ></button>

    <div class="profile-menu" *ngIf="profileMenuOpen">
      <button type="button" class="profile-menu-item" (click)="openProfileFromMenu()">Profile</button>
      <button type="button" class="profile-menu-item" (click)="openMessagesFromMenu()">Messages</button>
      <button type="button" class="profile-menu-item" (click)="openAdsFromMenu()">Ads</button>
      <button type="button" class="profile-menu-item muted" disabled>Settings</button>
      <button type="button" class="profile-menu-item danger" (click)="logout()">Logout</button>
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
        transform: translateY(calc(var(--tabs-height, 64px) + env(safe-area-inset-bottom) + 6px));
        opacity: 0;
      }
      .bottom-tabs {
        pointer-events: auto;
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        gap: 6px;
        padding: 6px 12px calc(8px + env(safe-area-inset-bottom));
        height: calc(var(--tabs-height, 64px) + env(safe-area-inset-bottom));
        background: #ffffff;
        border-top: 1px solid rgba(7, 20, 40, 0.08);
        box-shadow: 0 -6px 20px rgba(12, 18, 24, 0.08);
      }
      .bottom-tabs.globe-mode {
        background: transparent;
        border-top-color: transparent;
        box-shadow: none;
      }
      .bottom-tabs.globe-mode .tab-btn {
        color: rgba(236, 244, 255, 0.78);
      }
      .bottom-tabs.globe-mode .tab-btn:hover,
      .bottom-tabs.globe-mode .tab-btn.active {
        color: #ffffff;
      }
      .profile-menu-backdrop {
        position: fixed;
        inset: 0;
        border: 0;
        background: transparent;
        pointer-events: auto;
        z-index: 89;
      }
      .profile-menu {
        position: fixed;
        right: 12px;
        bottom: calc(var(--tabs-height, 64px) + env(safe-area-inset-bottom) + 10px);
        min-width: 176px;
        padding: 8px;
        border-radius: 18px;
        background: rgba(255, 255, 255, 0.98);
        border: 1px solid rgba(7, 20, 40, 0.08);
        box-shadow: 0 18px 44px rgba(12, 18, 24, 0.18);
        display: grid;
        gap: 4px;
        pointer-events: auto;
        z-index: 91;
      }
      .profile-menu-item {
        border: 0;
        background: transparent;
        text-align: left;
        border-radius: 12px;
        padding: 11px 12px;
        font-size: 14px;
        font-weight: 700;
        color: #0b1a2c;
        cursor: pointer;
      }
      .profile-menu-item:hover {
        background: rgba(11, 26, 44, 0.06);
      }
      .profile-menu-item.muted {
        color: rgba(11, 26, 44, 0.45);
        cursor: default;
      }
      .profile-menu-item.danger {
        color: #c53a3a;
      }
      .tab-btn {
        border: 0;
        border-radius: 14px;
        background: transparent;
        color: rgba(13, 22, 36, 0.7);
        cursor: pointer;
        padding: 6px 4px;
        transition: color 120ms ease;
        position: relative;
        display: grid;
        place-items: center;
        gap: 4px;
      }
      .tab-btn:hover {
        color: #101724;
      }
      .tab-btn.active {
        color: #0b1a2c;
      }
      .tab-icon {
        font-size: 20px;
        line-height: 1;
      }
      .tab-badge {
        position: absolute;
        top: 2px;
        right: 10px;
        min-width: 18px;
        height: 18px;
        border-radius: 999px;
        background: rgba(56, 158, 255, 0.95);
        color: #041629;
        font-size: 10px;
        font-weight: 900;
        display: grid;
        place-items: center;
        padding: 0 6px;
        box-shadow: 0 0 0 2px rgba(6, 10, 16, 0.8);
      }
      @media (max-width: 640px) {
        .profile-menu {
          right: 10px;
          min-width: 166px;
        }
        .tab-icon {
          font-size: 18px;
        }
        .tab-badge {
          top: 2px;
          right: 6px;
          min-width: 16px;
          height: 16px;
          font-size: 9px;
        }
      }
    `,
  ],
})
export class BottomTabsComponent implements OnInit, OnDestroy {
  active: TabKey = 'home';
  messagesUnreadCount = 0;
  tabsHidden = false;
  profileMenuOpen = false;
  globeMode = false;

  private sub?: Subscription;
  private lastGlobeUrl = '/globe';
  private unreadPollTimer: number | null = null;
  private unreadRefreshInFlight = false;
  private lastScrollTop = 0;
  private scrollHandler = (event: Event) => this.handleScroll(event);

  constructor(
    private router: Router,
    private location: LocationService,
    private auth: AuthService,
    private notifications: NotificationsService
  ) {}

  ngOnInit(): void {
    this.syncActive(this.router.url);
    this.captureGlobeUrl(this.router.url);
    this.sub = this.router.events.subscribe((event) => {
      if (event instanceof NavigationEnd) {
        const url = event.urlAfterRedirects || event.url;
        this.syncActive(url);
        this.captureGlobeUrl(url);
        this.profileMenuOpen = false;
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

  goHome(): void {
    this.profileMenuOpen = false;
    if (this.lastGlobeUrl) {
      void this.router.navigateByUrl(this.lastGlobeUrl);
      return;
    }
    const cached = this.location.getCachedLocation();
    const code = cached?.countryCode?.trim().toUpperCase();
    void this.router.navigate(['/globe'], {
      queryParams: code ? { country: code, tab: 'posts', panel: null } : null,
    });
  }

  openSearch(): void {
    this.profileMenuOpen = false;
    if (this.active === 'search') return;
    void this.router.navigate(['/search']);
  }

  goMessages(): void {
    this.profileMenuOpen = false;
    if (this.active === 'messages') return;
    void this.router.navigate(['/messages']);
  }

  goProfile(): void {
    this.profileMenuOpen = false;
    if (this.active === 'profile') return;
    void this.router.navigate(['/me']);
  }

  toggleProfileMenu(event?: Event): void {
    event?.stopPropagation();
    this.profileMenuOpen = !this.profileMenuOpen;
  }

  closeProfileMenu(): void {
    this.profileMenuOpen = false;
  }

  openProfileFromMenu(): void {
    this.goProfile();
  }

  openMessagesFromMenu(): void {
    this.goMessages();
  }

  openAdsFromMenu(): void {
    this.profileMenuOpen = false;
    void this.router.navigate(['/ads']);
  }

  async logout(): Promise<void> {
    this.profileMenuOpen = false;
    try {
      await this.auth.logout();
    } catch {
      // ignore
    }
    void this.router.navigate(['/auth']);
  }

  private async refreshUnreadMessages(): Promise<void> {
    if (this.unreadRefreshInFlight) return;
    this.unreadRefreshInFlight = true;
    try {
      const user = await this.auth.getUser();
      if (!user) {
        this.messagesUnreadCount = 0;
        return;
      }
      const { notifications } = await this.notifications.list(80);
      const unread = (notifications ?? []).filter(
        (notif) => !notif.read_at && String(notif?.type ?? '').toLowerCase() === 'message'
      );
      this.messagesUnreadCount = unread.length;
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
    const hasCountry = !!parsed?.searchParams?.get('country');
    this.globeMode =
      (pathname === '/' || pathname.startsWith('/globe') || pathname.startsWith('/globe-cesium')) &&
      !hasCountry;
    if (url.startsWith('/messages')) {
      this.active = 'messages';
      return;
    }
    if (url.startsWith('/me')) {
      this.active = 'profile';
      return;
    }
    if (url.startsWith('/user')) {
      this.active = 'home';
      return;
    }
    if (url.startsWith('/globe') || url === '/' || url.startsWith('/globe-cesium')) {
      this.active = 'home';
      return;
    }
    if (url.startsWith('/search')) {
      this.active = 'search';
      return;
    }
    this.active = 'home';
  }

  private captureGlobeUrl(url: string): void {
    if (!(url.startsWith('/globe') || url === '/' || url.startsWith('/globe-cesium'))) return;
    this.lastGlobeUrl = this.stripSearchParam(url);
  }

  private stripSearchParam(url: string): string {
    try {
      const parsed = new URL(url, window.location.origin);
      parsed.searchParams.delete('search');
      return parsed.pathname + (parsed.search ? parsed.search : '');
    } catch {
      return url.replace(/([?&])search=[^&]+/, '').replace(/[?&]$/, '');
    }
  }

  private handleScroll(event: Event): void {
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
      this.profileMenuOpen = false;
    } else if (delta < 0) {
      this.tabsHidden = false;
    }
    this.lastScrollTop = current;
  }
}
