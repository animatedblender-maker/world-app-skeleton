import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

type GraphqlResponse<T> = {
  data?: T;
  errors?: Array<{ message: string }>;
};

@Injectable({ providedIn: 'root' })
export class GraphqlService {
  private readonly endpoint = 'http://localhost:3000/graphql';

  private getToken(): string | null {
    return localStorage.getItem('world_token'); // Supabase access token stored here
  }

  query<TData, TVars extends Record<string, any> = Record<string, any>>(
    query: string,
    variables?: TVars
  ): Observable<TData> {
    return new Observable<TData>((subscriber) => {
      const token = this.getToken();

      fetch(this.endpoint, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify({ query, variables: variables ?? {} }),
      })
        .then(async (res) => {
          const json = (await res.json()) as GraphqlResponse<TData>;
          if (!res.ok) throw new Error(`HTTP ${res.status}`);
          if (json.errors?.length) throw new Error(json.errors.map((e) => e.message).join(' | '));
          if (!json.data) throw new Error('Missing data');
          subscriber.next(json.data);
          subscriber.complete();
        })
        .catch((err) => subscriber.error(err));
    });
  }
}
