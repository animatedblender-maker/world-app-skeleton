import { Injectable } from '@angular/core';
import { Router } from '@angular/router';
import { BehaviorSubject } from 'rxjs';

import { resolveAvatarUrl } from '../utils/media-url.util';
import {
  NotificationsService,
  type NotificationItem,
} from './notifications.service';

/**
 * App-wide notifications panel — open anywhere (iOS globePanel overlay pattern),
 * without navigating to /globe.
 */
@Injectable({ providedIn: 'root' })
export class NotificationsUiService {
  private readonly open$ = new BehaviorSubject(false);
  readonly isOpen$ = this.open$.asObservable();

  private readonly items$ = new BehaviorSubject<NotificationItem[]>([]);
  readonly itemsSnapshot = () => this.items$.value;

  private readonly loading$ = new BehaviorSubject(false);
  private readonly error$ = new BehaviorSubject('');
  private readonly busy$ = new BehaviorSubject(false);
  private readonly unread$ = new BehaviorSubject(0);

  get isOpen(): boolean {
    return this.open$.value;
  }
  get loading(): boolean {
    return this.loading$.value;
  }
  get error(): string {
    return this.error$.value;
  }
  get busy(): boolean {
    return this.busy$.value;
  }
  get unreadCount(): number {
    return this.unread$.value;
  }
  get items(): NotificationItem[] {
    return this.items$.value;
  }

  constructor(
    private notifications: NotificationsService,
    private router: Router
  ) {}

  open(): void {
    this.open$.next(true);
    void this.refresh();
  }

  close(): void {
    this.open$.next(false);
  }

  toggle(): void {
    if (this.isOpen) this.close();
    else this.open();
  }

  async refresh(): Promise<void> {
    this.loading$.next(true);
    this.error$.next('');
    try {
      const { notifications } = await this.notifications.list(80);
      const next = (notifications ?? []).filter(
        (n) => String(n?.type ?? '').toLowerCase() !== 'message'
      );
      this.items$.next(next);
      this.unread$.next(next.filter((n) => !n.read_at).length);
    } catch (e: any) {
      this.error$.next(e?.message || 'Could not load notifications');
    } finally {
      this.loading$.next(false);
    }
  }

  setUnreadFromBadge(count: number): void {
    this.unread$.next(Math.max(0, count));
  }

  async markAllRead(): Promise<void> {
    if (this.busy) return;
    this.busy$.next(true);
    this.error$.next('');
    try {
      await this.notifications.markAllRead();
      const now = new Date().toISOString();
      this.items$.next(this.items.map((n) => (n.read_at ? n : { ...n, read_at: now })));
      this.unread$.next(0);
    } catch (e: any) {
      this.error$.next(e?.message || 'Could not mark all read');
    } finally {
      this.busy$.next(false);
    }
  }

  async openItem(notif: NotificationItem): Promise<void> {
    if (!notif) return;
    await this.markOneRead(notif);

    const type = String(notif.type || '').toLowerCase();
    this.close();

    if (type === 'follow') {
      const slug = notif.actor?.username?.trim() || notif.actor_id;
      if (slug) void this.router.navigate(['/user', slug]);
      return;
    }
    if (type === 'message' && notif.entity_id) {
      void this.router.navigate(['/messages'], { queryParams: { c: notif.entity_id } });
      return;
    }
    if (
      (type === 'like' ||
        type === 'comment' ||
        type === 'comment_like' ||
        type === 'comment_reply' ||
        type === 'post') &&
      notif.entity_id
    ) {
      // Stay generic: post detail works from any screen (no globe detour).
      void this.router.navigate(['/post', notif.entity_id]);
    }
  }

  actorName(notif: NotificationItem): string {
    const candidate = (notif.actor?.display_name || notif.actor?.username || '').trim();
    if (!candidate || this.looksLikeId(candidate)) return 'Someone';
    return candidate;
  }

  message(notif: NotificationItem): string {
    const type = (notif.type || '').toLowerCase();
    if (type === 'follow') return 'started following you.';
    if (type === 'like') return 'liked your post.';
    if (type === 'comment') return 'commented on your post.';
    if (type === 'comment_like') return 'liked your comment.';
    if (type === 'comment_reply') return 'replied to your comment.';
    if (type === 'message') return 'sent you a message.';
    if (type === 'post') return 'shared a post.';
    return 'sent you a notification.';
  }

  avatarUrl(notif: NotificationItem): string | null {
    const seed = notif.actor?.username || notif.actor_id || notif.id;
    return resolveAvatarUrl(notif.actor?.avatar_url, seed) || null;
  }

  relativeTime(iso: string): string {
    const t = Date.parse(iso);
    if (!Number.isFinite(t)) return '';
    const sec = Math.max(0, Math.floor((Date.now() - t) / 1000));
    if (sec < 60) return 'just now';
    if (sec < 3600) return `${Math.floor(sec / 60)}m`;
    if (sec < 86400) return `${Math.floor(sec / 3600)}h`;
    if (sec < 86400 * 7) return `${Math.floor(sec / 86400)}d`;
    return new Date(t).toLocaleDateString();
  }

  private async markOneRead(notif: NotificationItem): Promise<void> {
    if (notif.read_at) return;
    try {
      await this.notifications.markRead(notif.id);
      const now = new Date().toISOString();
      this.items$.next(
        this.items.map((n) => (n.id === notif.id ? { ...n, read_at: now } : n))
      );
      this.unread$.next(Math.max(0, this.unreadCount - 1));
    } catch {
      // ignore
    }
  }

  private looksLikeId(value: string): boolean {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      value.trim()
    );
  }
}
