import { CommonModule } from '@angular/common';
import { ChangeDetectorRef, Component, OnDestroy, OnInit } from '@angular/core';
import { Subscription } from 'rxjs';

import {
  NotificationsUiService,
} from '../core/services/notifications-ui.service';
import type { NotificationItem } from '../core/services/notifications.service';

/** Global notifications panel — opens on top of any route (iOS-style overlay). */
@Component({
  selector: 'app-notifications-overlay',
  standalone: true,
  imports: [CommonModule],
  template: `
    <ng-container *ngIf="open">
      <button type="button" class="backdrop" aria-label="Close notifications" (click)="close()"></button>
      <div class="panel" role="dialog" aria-modal="true" aria-label="Notifications" (click)="$event.stopPropagation()">
        <div class="head">
          <div>
            <div class="title">Notifications</div>
            <div class="sub">Unread: {{ ui.unreadCount }}</div>
          </div>
          <button type="button" class="close" (click)="close()" aria-label="Close">✕</button>
        </div>

        <div class="actions">
          <button
            type="button"
            class="link"
            (click)="markAll()"
            [disabled]="ui.loading || ui.busy || !items.length"
          >
            Mark all read
          </button>
        </div>

        <div class="state" *ngIf="ui.loading">Loading…</div>
        <div class="state error" *ngIf="!ui.loading && ui.error">{{ ui.error }}</div>

        <div class="list" *ngIf="!ui.loading && !ui.error">
          <div class="empty" *ngIf="!items.length">No notifications yet.</div>
          <button
            type="button"
            class="item"
            *ngFor="let n of items; trackBy: track"
            [class.unread]="!n.read_at"
            (click)="openItem(n)"
          >
            <div class="avatar">
              <img *ngIf="ui.avatarUrl(n)" [src]="ui.avatarUrl(n)" alt="" />
              <span *ngIf="!ui.avatarUrl(n)">{{ ui.actorName(n).slice(0, 2).toUpperCase() }}</span>
            </div>
            <div class="body">
              <div class="line">
                <strong>{{ ui.actorName(n) }}</strong>
                {{ ui.message(n) }}
              </div>
              <div class="time">{{ ui.relativeTime(n.created_at) }}</div>
            </div>
            <span class="dot" *ngIf="!n.read_at"></span>
          </button>
        </div>
      </div>
    </ng-container>
  `,
  styles: [
    `
      .backdrop {
        position: fixed;
        inset: 0;
        z-index: 200;
        border: 0;
        background: rgba(44, 40, 37, 0.28);
        backdrop-filter: blur(4px);
        -webkit-backdrop-filter: blur(4px);
        cursor: pointer;
      }
      .panel {
        position: fixed;
        top: calc(env(safe-area-inset-top) + 56px);
        right: 12px;
        left: 12px;
        z-index: 201;
        max-width: 380px;
        margin-left: auto;
        max-height: min(70vh, 520px);
        display: flex;
        flex-direction: column;
        background: var(--m-surface, #fefdfb);
        color: var(--m-ink, #2c2825);
        border: 0.5px solid var(--m-border, #ddd8d1);
        border-radius: 18px;
        box-shadow: 0 18px 48px rgba(44, 40, 37, 0.18);
        overflow: hidden;
      }
      @media (min-width: 480px) {
        .panel {
          left: auto;
          width: min(380px, calc(100vw - 24px));
        }
      }
      .head {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 12px;
        padding: 14px 14px 8px;
      }
      .title {
        font-size: 12px;
        font-weight: 700;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: var(--m-ink-muted, #948b82);
      }
      .sub {
        margin-top: 4px;
        font-size: 13px;
        color: var(--m-ink, #2c2825);
      }
      .close {
        border: 0;
        background: var(--m-canvas-muted, #f2f0ec);
        width: 32px;
        height: 32px;
        border-radius: 999px;
        cursor: pointer;
        color: var(--m-ink-muted, #948b82);
        font-size: 14px;
      }
      .actions {
        padding: 0 14px 8px;
      }
      .link {
        border: 0;
        background: transparent;
        color: var(--m-accent-bright, #7b6347);
        font-size: 12px;
        font-weight: 700;
        cursor: pointer;
        padding: 0;
      }
      .link:disabled {
        opacity: 0.45;
        cursor: default;
      }
      .list {
        overflow-y: auto;
        padding: 0 10px 12px;
        -webkit-overflow-scrolling: touch;
      }
      .empty,
      .state {
        padding: 28px 12px;
        text-align: center;
        font-size: 13px;
        color: var(--m-ink-muted, #948b82);
      }
      .state.error {
        color: var(--m-danger, #ea000b);
      }
      .item {
        display: flex;
        align-items: flex-start;
        gap: 10px;
        width: 100%;
        border: 0.5px solid var(--m-border, #ddd8d1);
        background: var(--m-canvas-muted, #f2f0ec);
        border-radius: 14px;
        padding: 12px;
        margin-bottom: 8px;
        text-align: left;
        color: inherit;
        cursor: pointer;
        position: relative;
      }
      .item.unread {
        background: rgba(234, 0, 11, 0.08);
        border-color: rgba(234, 0, 11, 0.28);
      }
      .avatar {
        width: 36px;
        height: 36px;
        border-radius: 999px;
        overflow: hidden;
        background: var(--m-canvas-deep, #edeae5);
        display: grid;
        place-items: center;
        font-size: 11px;
        font-weight: 700;
        flex-shrink: 0;
      }
      .avatar img {
        width: 100%;
        height: 100%;
        object-fit: cover;
      }
      .body {
        flex: 1;
        min-width: 0;
      }
      .line {
        font-size: 13px;
        line-height: 1.35;
      }
      .line strong {
        font-weight: 700;
      }
      .time {
        margin-top: 4px;
        font-size: 11px;
        color: var(--m-ink-muted, #948b82);
      }
      .dot {
        width: 8px;
        height: 8px;
        border-radius: 999px;
        background: var(--m-danger, #ea000b);
        flex-shrink: 0;
        margin-top: 6px;
      }
    `,
  ],
})
export class NotificationsOverlayComponent implements OnInit, OnDestroy {
  open = false;
  items: NotificationItem[] = [];
  private subs: Subscription[] = [];

  constructor(
    public ui: NotificationsUiService,
    private cdr: ChangeDetectorRef
  ) {}

  ngOnInit(): void {
    this.subs.push(
      this.ui.isOpen$.subscribe((v) => {
        this.open = v;
        this.items = this.ui.items;
        this.paint();
      })
    );
    // Poll paint while open for loading/error/list updates
    const timer = window.setInterval(() => {
      if (!this.open) return;
      this.items = this.ui.items;
      this.paint();
    }, 200);
    this.subs.push({ unsubscribe: () => window.clearInterval(timer) } as Subscription);
  }

  ngOnDestroy(): void {
    this.subs.forEach((s) => s.unsubscribe());
  }

  track(_: number, n: NotificationItem): string {
    return n.id;
  }

  close(): void {
    this.ui.close();
  }

  markAll(): void {
    void this.ui.markAllRead().then(() => {
      this.items = this.ui.items;
      this.paint();
    });
  }

  openItem(n: NotificationItem): void {
    void this.ui.openItem(n);
  }

  private paint(): void {
    try {
      this.cdr.detectChanges();
    } catch {
      // destroyed
    }
  }
}
