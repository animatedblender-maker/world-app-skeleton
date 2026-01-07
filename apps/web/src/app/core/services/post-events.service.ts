import { Injectable, OnDestroy } from '@angular/core';
import { Subject, Observable } from 'rxjs';
import { CountryPost } from '../models/post.model';
import { supabase } from '../../supabase/supabase.client';

export type PostInsertEvent = {
  id: string;
  country_code: string | null;
  author_id: string | null;
};

@Injectable({ providedIn: 'root' })
export class PostEventsService implements OnDestroy {
  private createdPostSubject = new Subject<CountryPost>();
  readonly createdPost$: Observable<CountryPost> = this.createdPostSubject.asObservable();

  private insertSubject = new Subject<PostInsertEvent>();
  readonly insert$: Observable<PostInsertEvent> = this.insertSubject.asObservable();

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
      .subscribe();
  }

  emit(post: CountryPost): void {
    this.createdPostSubject.next(post);
  }

  ngOnDestroy(): void {
    this.channel?.unsubscribe();
  }
}
