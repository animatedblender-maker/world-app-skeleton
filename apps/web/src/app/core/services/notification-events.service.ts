import { Injectable, OnDestroy } from '@angular/core';
import { Subject, Observable } from 'rxjs';
import { supabase } from '../../supabase/supabase.client';

export type NotificationEvent = {
  id: string;
  user_id: string;
  read_at?: string | null;
  type?: string | null;
};

@Injectable({ providedIn: 'root' })
export class NotificationEventsService implements OnDestroy {
  private channel: any = null;

  private insertSubject = new Subject<NotificationEvent>();
  readonly insert$: Observable<NotificationEvent> = this.insertSubject.asObservable();

  private updateSubject = new Subject<NotificationEvent>();
  readonly update$: Observable<NotificationEvent> = this.updateSubject.asObservable();

  start(userId: string): void {
    if (!userId) return;
    this.stop();

    this.channel = supabase.channel(`public:notifications:${userId}`);

    this.channel
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'notifications', filter: `user_id=eq.${userId}` },
        ({ new: row }: { new: Record<string, unknown> | null }) => {
          const id = row?.['id'];
          const userId = row?.['user_id'];
          if (typeof id !== 'string' || typeof userId !== 'string') return;
          this.insertSubject.next({
            id,
            user_id: userId,
            read_at: typeof row?.['read_at'] === 'string' ? row['read_at'] : null,
            type: typeof row?.['type'] === 'string' ? row['type'] : null,
          });
        }
      )
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'notifications', filter: `user_id=eq.${userId}` },
        ({ new: row }: { new: Record<string, unknown> | null }) => {
          const id = row?.['id'];
          const userId = row?.['user_id'];
          if (typeof id !== 'string' || typeof userId !== 'string') return;
          this.updateSubject.next({
            id,
            user_id: userId,
            read_at: typeof row?.['read_at'] === 'string' ? row['read_at'] : null,
            type: typeof row?.['type'] === 'string' ? row['type'] : null,
          });
        }
      )
      .subscribe();
  }

  stop(): void {
    if (!this.channel) return;
    try {
      supabase.removeChannel(this.channel);
    } catch {}
    this.channel = null;
  }

  ngOnDestroy(): void {
    this.stop();
  }
}
