import { CommonModule } from '@angular/common';
import { Component, EventEmitter, Input, Output } from '@angular/core';
import { Router } from '@angular/router';

@Component({
  selector: 'app-matterya-topbar',
  standalone: true,
  imports: [CommonModule],
  template: `
    <header class="matterya-topbar" [class.over-globe]="overGlobe">
      <button type="button" class="topbar-icon" aria-label="Menu" (click)="onMenu()">
        <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.7">
          <path d="M4 7h16M4 12h16M4 17h16" stroke-linecap="round" />
        </svg>
      </button>

      <div class="topbar-title">{{ title }}</div>

      <div class="topbar-actions">
        <button
          *ngIf="showSearch"
          type="button"
          class="topbar-icon"
          aria-label="Search"
          (click)="onSearch()"
        >
          <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.6">
            <circle cx="11" cy="11" r="6.5" />
            <path d="M16.2 16.2L20 20" stroke-linecap="round" />
          </svg>
        </button>
        <button
          *ngIf="showNotifications"
          type="button"
          class="topbar-icon"
          aria-label="Notifications"
          (click)="onNotifications()"
        >
          <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.5">
            <path d="M6 9a6 6 0 0 1 12 0c0 4 1.5 5.5 1.5 5.5H4.5S6 13 6 9z" stroke-linejoin="round" />
            <path d="M10 18.5a2 2 0 0 0 4 0" stroke-linecap="round" />
          </svg>
          <span class="topbar-badge" *ngIf="unreadCount > 0"></span>
        </button>
      </div>
    </header>
  `,
  styles: [
    `
      :host {
        display: block;
        position: sticky;
        top: 0;
        z-index: 50;
      }
      :host.fixed-host {
        position: fixed;
        left: 0;
        right: 0;
        top: 0;
      }
      .matterya-topbar {
        display: grid;
        grid-template-columns: 44px 1fr auto;
        align-items: center;
        gap: 0;
        min-height: 44px;
        padding: 0 12px;
        padding-top: env(safe-area-inset-top);
        background: rgba(254, 253, 251, 0.92);
        border-bottom: 0.5px solid var(--m-divider, #e2ded8);
        backdrop-filter: blur(14px);
        -webkit-backdrop-filter: blur(14px);
      }
      .matterya-topbar.over-globe {
        background: rgba(254, 253, 251, 0.9);
      }
      .topbar-title {
        text-align: center;
        font-family: 'Iowan Old Style', 'Palatino Linotype', Palatino, Georgia, serif;
        font-size: 22px;
        font-weight: 400;
        letter-spacing: 0.5px;
        color: var(--m-ink, #2c2825);
        line-height: 44px;
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        pointer-events: none;
      }
      .topbar-actions {
        display: flex;
        align-items: center;
        justify-content: flex-end;
        gap: 2px;
        min-width: 88px;
      }
      .topbar-icon {
        position: relative;
        border: 0;
        background: transparent;
        color: var(--m-ink, #2c2825);
        width: 44px;
        height: 44px;
        display: grid;
        place-items: center;
        cursor: pointer;
        border-radius: 12px;
        padding: 0;
        flex: 0 0 auto;
      }
      .topbar-icon:hover {
        background: rgba(44, 40, 37, 0.05);
      }
      .topbar-icon svg {
        display: block;
      }
      .topbar-badge {
        position: absolute;
        top: 10px;
        right: 10px;
        width: 7px;
        height: 7px;
        border-radius: 999px;
        background: var(--m-danger, #ea000b);
      }
      @media (min-width: 900px) {
        .matterya-topbar {
          min-height: 56px;
          padding: 0 var(--m-page-padding, 28px);
          padding-top: env(safe-area-inset-top);
          grid-template-columns: 48px 1fr auto;
          background: rgba(254, 253, 251, 0.94);
        }
        .topbar-title {
          text-align: left;
          font-size: 26px;
          line-height: 56px;
          pointer-events: auto;
        }
        .topbar-icon {
          width: 48px;
          height: 48px;
        }
        .topbar-actions {
          min-width: 96px;
          gap: 4px;
        }
      }
    `,
  ],
})
export class MatteryaTopbarComponent {
  @Input() title = 'Matterya';
  @Input() showSearch = true;
  @Input() showNotifications = true;
  @Input() unreadCount = 0;
  @Input() overGlobe = false;
  @Input() menuMode: 'profile' | 'emit' = 'profile';

  @Output() search = new EventEmitter<void>();
  @Output() notifications = new EventEmitter<void>();
  @Output() menu = new EventEmitter<void>();

  constructor(private router: Router) {}

  onMenu(): void {
    if (this.menuMode === 'emit') {
      this.menu.emit();
      return;
    }
    void this.router.navigate(['/me']);
  }

  onSearch(): void {
    if (this.search.observed) {
      this.search.emit();
      return;
    }
    void this.router.navigate(['/search']);
  }

  onNotifications(): void {
    if (this.notifications.observed) {
      this.notifications.emit();
      return;
    }
    void this.router.navigate(['/globe'], {
      queryParams: { panel: 'notifications', search: '0' },
    });
  }
}
