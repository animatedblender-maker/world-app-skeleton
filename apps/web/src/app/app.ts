import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { NavigationEnd, Router, RouterOutlet } from '@angular/router';
import { filter } from 'rxjs';

import { CallService, IncomingCall } from './core/services/call.service';
import { AuthService } from './core/services/auth.service';
import { NotificationsService } from './core/services/notifications.service';
import { NotificationEventsService } from './core/services/notification-events.service';
import type { Subscription } from 'rxjs';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, RouterOutlet],
  template: `
    <router-outlet />
    <button
      type="button"
      class="global-alert"
      *ngIf="!isMessagesRoute && !isProfileRoute && !isReelsRoute"
      aria-label="Open alerts"
      (click)="openNotifications()"
    >
      <img class="global-alert-icon" src="/assets/notification.png" alt="" />
      <span class="global-alert-badge" *ngIf="notificationsUnreadCount > 0">
        {{ notificationsUnreadCount }}
      </span>
    </button>
    <button
      type="button"
      class="global-travel"
      *ngIf="showTravelButton"
      aria-label="Travel to a country"
      (click)="openTravelSearch()"
    >
      <span class="global-travel-icon">✈</span>
    </button>
    <div class="global-call" *ngIf="incomingCall && !isMessagesRoute">
      <div class="global-call-card">
        <div class="global-call-title">
          Incoming {{ incomingCall.callType === 'video' ? 'video' : 'voice' }} call
        </div>
        <div class="global-call-actions">
          <button type="button" class="global-call-btn accept" (click)="acceptCall()">Accept</button>
          <button type="button" class="global-call-btn decline" (click)="declineCall()">Decline</button>
        </div>
      </div>
    </div>
  `,
  styles: [
    `
    .global-call{
      position:fixed;
      inset:0;
      display:grid;
      place-items:center;
      background:rgba(5,10,18,0.55);
      backdrop-filter:blur(8px);
      z-index:140;
      padding:16px;
    }
    .global-call-card{
      width:min(92vw, 420px);
      background:rgba(8,16,28,0.96);
      color:#eef6ff;
      border-radius:22px;
      padding:18px;
      box-shadow:0 20px 50px rgba(0,0,0,0.35);
      display:flex;
      flex-direction:column;
      gap:14px;
      align-items:center;
      text-align:center;
    }
    .global-call-title{
      font-size:16px;
      font-weight:700;
    }
    .global-call-actions{
      display:flex;
      gap:12px;
      justify-content:center;
      flex-wrap:wrap;
    }
    .global-call-btn{
      border:0;
      border-radius:16px;
      padding:10px 16px;
      font-weight:600;
      cursor:pointer;
    }
    .global-call-btn.accept{
      background:#2f9d66;
      color:#fff;
    }
    .global-call-btn.decline{
      background:#d84c4c;
      color:#fff;
    }
    .global-alert{
      position: fixed;
      top: calc(env(safe-area-inset-top) + 14px);
      right: 16px;
      width: 34px;
      height: 34px;
      border-radius: 12px;
      border: 0;
      background: transparent;
      color: #f4f7ff;
      display: grid;
      place-items: center;
      cursor: pointer;
      z-index: 120;
      box-shadow: none;
      backdrop-filter: none;
      padding: 0;
      transition: opacity 0.2s ease, transform 0.2s ease;
    }
    .global-travel{
      position: fixed;
      top: calc(env(safe-area-inset-top) + 14px);
      right: 56px;
      width: 34px;
      height: 34px;
      border-radius: 12px;
      border: 0;
      background: transparent;
      color: #f4f7ff;
      display: grid;
      place-items: center;
      cursor: pointer;
      z-index: 120;
      padding: 0;
      transition: opacity 0.2s ease, transform 0.2s ease;
    }
    :host-context(.feed-header-hidden) .global-travel{
      opacity: 0;
      pointer-events: none;
      transform: translateY(-8px);
    }
    .global-travel-icon{
      font-size: 20px;
      line-height: 1;
    }
    :host-context(.feed-header-hidden) .global-alert{
      opacity: 0;
      pointer-events: none;
      transform: translateY(-8px);
    }
    .global-alert-icon{
      width: 26px;
      height: 26px;
      object-fit: contain;
      display: block;
    }
    .global-alert-badge{
      position: absolute;
      top: -4px;
      right: -4px;
      min-width: 12px;
      height: 12px;
      border-radius: 999px;
      background: rgba(56, 158, 255, 0.95);
      color: #041629;
      font-size: 7px;
      font-weight: 900;
      display: grid;
      place-items: center;
      padding: 0 4px;
      box-shadow: 0 0 0 2px rgba(6,10,16,0.8);
    }
    @media (max-width: 640px){
      .global-alert{
        top: calc(env(safe-area-inset-top) + 10px);
        right: 12px;
        width: 30px;
        height: 30px;
      }
      .global-travel{
        top: calc(env(safe-area-inset-top) + 10px);
        right: 48px;
        width: 30px;
        height: 30px;
      }
      .global-travel-icon{
        font-size: 18px;
      }
      .global-alert-badge{
        top: -3px;
        right: -3px;
        min-width: 11px;
        height: 11px;
        font-size: 7px;
      }
      .global-alert-icon{
        width: 24px;
        height: 24px;
      }
    }
    `
  ],
})
export class AppComponent {
  incomingCall: IncomingCall | null = null;
  isMessagesRoute = false;
  isProfileRoute = false;
  isReelsRoute = false;
  showTravelButton = false;
  notificationsUnreadCount = 0;
  private notificationInsertSub?: Subscription;
  private notificationUpdateSub?: Subscription;
  private notificationPollTimer: number | null = null;
  private notificationsRefreshInFlight = false;
  private meId: string | null = null;

  constructor(
    private callService: CallService,
    private router: Router,
    private auth: AuthService,
    private notifications: NotificationsService,
    private notificationEvents: NotificationEventsService
  ) {
    this.checkForAppUpdate();
    const redirect = new URLSearchParams(window.location.search).get('redirect');
    if (redirect) {
      try {
        window.history.replaceState(null, '', redirect);
        void this.router.navigateByUrl(redirect);
      } catch {}
    }
    this.callService.incoming$.subscribe((call) => {
      this.incomingCall = call;
    });
    this.updateRouteFlags(this.router.url);
    this.syncRootBackground(this.router.url);
    this.router.events.pipe(filter((event) => event instanceof NavigationEnd)).subscribe(() => {
      this.updateRouteFlags(this.router.url);
      this.syncRootBackground(this.router.url);
    });
    void this.initNotificationBadge();
  }

  private updateRouteFlags(url: string): void {
    this.isMessagesRoute = url.startsWith('/messages');
    this.isProfileRoute = url.startsWith('/me') || url.startsWith('/user');
    this.isReelsRoute = url.startsWith('/reels');
    let parsed: URL | null = null;
    try {
      parsed = new URL(url, window.location.origin);
    } catch {}
    const pathname = parsed?.pathname ?? url;
    const isGlobe =
      pathname === '/' || pathname.startsWith('/globe') || pathname.startsWith('/globe-cesium');
    const hasCountry = !!parsed?.searchParams?.get('country');
    this.showTravelButton = isGlobe && !hasCountry;
  }

  private syncRootBackground(url: string): void {
    if (typeof document === 'undefined') return;
    const root = document.documentElement;
    root.classList.remove('app-bg-globe', 'app-bg-feed', 'app-bg-light');
    const themeMeta = document.querySelector('meta[name="theme-color"]') as HTMLMetaElement | null;
    const setTheme = (color: string) => {
      if (themeMeta) themeMeta.setAttribute('content', color);
      document.body.style.backgroundColor = color;
      document.documentElement.style.backgroundColor = color;
    };
    let parsed: URL | null = null;
    try {
      parsed = new URL(url, window.location.origin);
    } catch {}
    const pathname = parsed?.pathname ?? url;
    const isGlobe =
      pathname.startsWith('/globe') || pathname === '/' || pathname.startsWith('/globe-cesium');
    const isReels = pathname.startsWith('/reels');
    const isFeed = isGlobe && !!parsed?.searchParams?.get('country');

    if (isFeed) {
      root.classList.add('app-bg-feed');
      const computed = getComputedStyle(root).getPropertyValue('--app-bg').trim();
      setTheme(computed || '#f5f6f8');
      return;
    }
    if (isGlobe || isReels) {
      root.classList.add('app-bg-globe');
      const computed = getComputedStyle(root).getPropertyValue('--app-bg').trim();
      setTheme(computed || '#05070b');
      return;
    }
    root.classList.add('app-bg-light');
    const computed = getComputedStyle(root).getPropertyValue('--app-bg').trim();
    setTheme(computed || '#f5f6f8');
  }

  openTravelSearch(): void {
    void this.router.navigate(['/globe'], {
      queryParams: { travel: '1' },
      queryParamsHandling: 'merge',
    });
  }

  private checkForAppUpdate(): void {
    if (typeof window === 'undefined') return;
    const versionUrl = new URL('/version.json', window.location.origin);
    versionUrl.searchParams.set('t', String(Date.now()));
    fetch(versionUrl.toString(), {
      cache: 'no-store',
      headers: { 'cache-control': 'no-cache' },
    })
      .then((res) => (res.ok ? res.json() : null))
      .then((data) => {
        if (!data?.version) return;
        const key = 'matterya_app_version';
        const reloadKey = 'matterya_update_reload';
        let current: string | null = null;
        let alreadyReloaded = false;
        try {
          current = window.localStorage.getItem(key);
          alreadyReloaded = window.sessionStorage.getItem(reloadKey) === data.version;
        } catch {}
        if (current && current !== data.version && !alreadyReloaded) {
          try {
            if ('serviceWorker' in navigator) {
              navigator.serviceWorker.getRegistrations().then((regs) => {
                regs.forEach((reg) => reg.unregister());
              });
            }
            if ('caches' in window) {
              caches.keys().then((keys) => keys.forEach((k) => caches.delete(k)));
            }
          } catch {}
          try {
            window.sessionStorage.setItem(reloadKey, data.version);
          } catch {}
          const url = new URL(window.location.href);
          url.searchParams.set('v', data.version);
          window.location.replace(url.toString());
          return;
        }
        try {
          window.localStorage.setItem(key, data.version);
          window.sessionStorage.removeItem(reloadKey);
        } catch {}
      })
      .catch(() => {});
  }

  acceptCall(): void {
    if (!this.incomingCall) return;
    const { conversationId, callType, from } = this.incomingCall;
    this.callService.clearIncomingCall();
    void this.router.navigate(['/messages'], {
      queryParams: { c: conversationId, call: callType, from },
    });
  }

  declineCall(): void {
    if (!this.incomingCall) return;
    const { conversationId, callId } = this.incomingCall;
    this.callService.sendSignal('call-decline', conversationId, { callId });
    this.callService.clearIncomingCall();
  }

  openNotifications(): void {
    const url = this.router.url;
    if (url.startsWith('/globe') || url === '/') {
      void this.router.navigate([], {
        queryParams: { panel: 'notifications', search: '0' },
        queryParamsHandling: 'merge',
      });
      return;
    }
    void this.router.navigate(['/globe'], {
      queryParams: { panel: 'notifications', search: '0' },
    });
  }

  private async initNotificationBadge(): Promise<void> {
    try {
      const user = await this.auth.getUser();
      this.meId = user?.id ?? null;
      if (!this.meId) {
        this.notificationsUnreadCount = 0;
        return;
      }
      this.notificationEvents.start(this.meId);
      this.notificationInsertSub?.unsubscribe();
      this.notificationUpdateSub?.unsubscribe();
      this.notificationInsertSub = this.notificationEvents.insert$.subscribe(() => {
        void this.refreshNotificationsUnread();
      });
      this.notificationUpdateSub = this.notificationEvents.update$.subscribe(() => {
        void this.refreshNotificationsUnread();
      });
      void this.refreshNotificationsUnread();
      this.startNotificationPolling();
    } catch {
      // ignore
    }
  }

  private startNotificationPolling(): void {
    if (this.notificationPollTimer) return;
    this.notificationPollTimer = window.setInterval(() => {
      void this.refreshNotificationsUnread();
    }, 20000);
  }

  private async refreshNotificationsUnread(): Promise<void> {
    if (this.notificationsRefreshInFlight) return;
    this.notificationsRefreshInFlight = true;
    try {
      if (!this.meId) {
        this.notificationsUnreadCount = 0;
        return;
      }
      const { notifications } = await this.notifications.list(80);
      const unread = (notifications ?? []).filter(
        (notif) => !notif.read_at && String(notif?.type ?? '').toLowerCase() !== 'message'
      );
      this.notificationsUnreadCount = unread.length;
    } catch {
      // keep last known count
    } finally {
      this.notificationsRefreshInFlight = false;
    }
  }
}
