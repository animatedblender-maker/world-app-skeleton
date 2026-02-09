import { CommonModule } from '@angular/common';
import { Component, OnDestroy, OnInit } from '@angular/core';
import { ActivatedRoute, NavigationEnd, Router } from '@angular/router';
import { Subscription } from 'rxjs';
import { LocationService } from '../core/services/location.service';
import { AuthService } from '../core/services/auth.service';
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
    <nav class="bottom-tabs" role="navigation" aria-label="Primary">
      <button
        type="button"
        class="tab-btn"
        aria-label="Feed"
        [class.active]="active === 'home'"
        (click)="goHome()"
      >
        <span class="tab-icon" aria-hidden="true">🏠</span>
      </button>
      <button
        type="button"
        class="tab-btn"
        aria-label="Search"
        [class.active]="active === 'search'"
        (click)="openSearch()"
      >
        <span class="tab-icon" aria-hidden="true">🔍</span>
      </button>
      <button
        type="button"
        class="tab-btn"
        aria-label="Chats"
        [class.active]="active === 'messages'"
        (click)="goMessages()"
      >
        <span class="tab-icon" aria-hidden="true">💬</span>
        <span class="tab-badge" *ngIf="messagesUnreadCount > 0">{{ messagesUnreadCount }}</span>
      </button>
      <button
        type="button"
        class="tab-btn"
        aria-label="Profile"
        [class.active]="active === 'profile'"
        (click)="goProfile()"
      >
        <span class="tab-icon" aria-hidden="true">👤</span>
      </button>
    </nav>
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
      .tab-icon{
        font-size: 20px;
        line-height: 1;
      }
      .tab-label{
        display: none;
      }
      .tab-badge{
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
        box-shadow: 0 0 0 2px rgba(6,10,16,0.8);
      }
      @media (max-width: 640px) {
        .tab-icon{
          font-size: 18px;
        }
        .tab-badge{
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
  private sub?: Subscription;
  private lastGlobeUrl = '/globe';
  private unreadPollTimer: number | null = null;
  private unreadRefreshInFlight = false;
  private lastScrollTop = 0;
  private scrollHandler = (event: Event) => this.handleScroll(event);

  constructor(
    private router: Router,
    private route: ActivatedRoute,
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
    if (this.active === 'search') return;
    void this.router.navigate(['/search']);
  }

  goMessages(): void {
    if (this.active === 'messages') return;
    void this.router.navigate(['/messages']);
  }

  goProfile(): void {
    if (this.active === 'profile') return;
    void this.router.navigate(['/me']);
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
    } else if (delta < 0) {
      this.tabsHidden = false;
    }
    this.lastScrollTop = current;
  }
}
