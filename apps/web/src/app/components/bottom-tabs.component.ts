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
        [class.active]="active === 'home'"
        (click)="goHome()"
      >
        Feed
      </button>
      <button
        type="button"
        class="tab-btn"
        [class.active]="active === 'search'"
        (click)="openSearch()"
      >
        Search
      </button>
      <button
        type="button"
        class="tab-btn"
        [class.active]="active === 'messages'"
        (click)="goMessages()"
      >
        Chats
        <span class="tab-badge" *ngIf="messagesUnreadCount > 0">{{ messagesUnreadCount }}</span>
      </button>
      <button
        type="button"
        class="tab-btn"
        [class.active]="active === 'profile'"
        (click)="goProfile()"
      >
        Profile
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
        background: rgba(6, 10, 16, 0.92);
        border-top: 1px solid rgba(255, 255, 255, 0.08);
        backdrop-filter: blur(12px);
        -webkit-backdrop-filter: blur(12px);
        box-shadow: 0 -12px 30px rgba(0, 0, 0, 0.35);
      }
      .tab-btn {
        border: 1px solid transparent;
        border-radius: 999px;
        background: transparent;
        color: rgba(255, 255, 255, 0.75);
        font-size: 12px;
        font-weight: 800;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        cursor: pointer;
        padding: 10px 6px;
        transition: background 160ms ease, color 160ms ease, border 160ms ease;
        position: relative;
      }
      .tab-btn:hover {
        color: #fff;
        border-color: rgba(255, 255, 255, 0.2);
      }
      .tab-btn.active {
        color: #fff;
        background: rgba(255, 255, 255, 0.12);
        border-color: rgba(255, 255, 255, 0.25);
      }
      .tab-badge{
        position: absolute;
        top: 4px;
        right: 8px;
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
        .tab-btn {
          font-size: 11px;
          letter-spacing: 0.06em;
          padding: 9px 4px;
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
    this.sub = this.router.events.subscribe((event) => {
      if (event instanceof NavigationEnd) {
        this.syncActive(event.urlAfterRedirects || event.url);
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
    const cached = this.location.getCachedLocation();
    const code = cached?.countryCode?.trim().toUpperCase();
    if (code) {
      void this.router.navigate(['/globe'], {
        queryParams: { country: code, tab: 'posts', panel: null, search: '0' },
      });
      return;
    }
    void this.router.navigate(['/globe']);
  }

  openSearch(): void {
    const onGlobe = this.router.url.startsWith('/globe') || this.router.url === '/';
    const isOpen = this.router.url.includes('search=1');
    if (onGlobe) {
      void this.router.navigate([], {
        relativeTo: this.route,
        queryParams: { search: isOpen ? '0' : '1', panel: null },
        queryParamsHandling: 'merge',
      });
      return;
    }
    void this.router.navigate(['/globe'], { queryParams: { search: '1' } });
  }

  goMessages(): void {
    void this.router.navigate(['/messages']);
  }

  goProfile(): void {
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
      if (url.includes('search=1')) {
        this.active = 'search';
        return;
      }
      this.active = 'home';
      return;
    }
    this.active = 'home';
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
