import { Injectable, OnDestroy } from '@angular/core';
import { Subject, Observable } from 'rxjs';
import { CountryPost } from '../models/post.model';
import { supabase } from '../../supabase/supabase.client';

export type PostInsertEvent = {
  id: string;
  country_code: string | null;
  author_id: string | null;
};

export type PostUpdateEvent = {
  id: string;
  country_code?: string | null;
  author_id?: string | null;
  visibility?: string | null;
};

export type PostDeleteEvent = {
  id: string;
  country_code?: string | null;
  author_id?: string | null;
};

@Injectable({ providedIn: 'root' })
export class PostEventsService implements OnDestroy {
  private createdPostSubject = new Subject<CountryPost>();
  readonly createdPost$: Observable<CountryPost> = this.createdPostSubject.asObservable();

  private updatedPostSubject = new Subject<CountryPost>();
  readonly updatedPost$: Observable<CountryPost> = this.updatedPostSubject.asObservable();

  private insertSubject = new Subject<PostInsertEvent>();
  readonly insert$: Observable<PostInsertEvent> = this.insertSubject.asObservable();

  private updateSubject = new Subject<PostUpdateEvent>();
  readonly update$: Observable<PostUpdateEvent> = this.updateSubject.asObservable();

  private deleteSubject = new Subject<PostDeleteEvent>();
  readonly delete$: Observable<PostDeleteEvent> = this.deleteSubject.asObservable();

  private channel = supabase.channel('public:posts');

  constructor() {
    this.channel
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'posts' },
        ({ new: row }) => {
          if (!row?.['id']) return;
          this.insertSubject.next({
            id: row['id'],
            country_code: row['country_code'] ?? null,
            author_id: row['author_id'] ?? null,
          });
        }
      )
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'posts' },
        ({ new: row }) => {
          if (!row?.['id']) return;
          this.updateSubject.next({
            id: row['id'],
            country_code: row['country_code'] ?? null,
            author_id: row['author_id'] ?? null,
            visibility: row['visibility'] ?? null,
          });
        }
      )
      .on(
        'postgres_changes',
        { event: 'DELETE', schema: 'public', table: 'posts' },
        ({ old: row }) => {
          if (!row?.['id']) return;
          this.deleteSubject.next({
            id: row['id'],
            country_code: row['country_code'] ?? null,
            author_id: row['author_id'] ?? null,
          });
        }
      )
      .subscribe();
  }

  emit(post: CountryPost): void {
    this.createdPostSubject.next(post);
  }

  emitUpdated(post: CountryPost): void {
    this.updatedPostSubject.next(post);
  }

  emitDeleted(event: PostDeleteEvent): void {
    if (!event?.id) return;
    this.deleteSubject.next({
      id: event.id,
      country_code: event.country_code ?? null,
      author_id: event.author_id ?? null,
    });
  }

  ngOnDestroy(): void {
    this.channel?.unsubscribe();
  }
}
