import { Injectable } from '@angular/core';
import { AuthService } from './auth.service';

@Injectable({ providedIn: 'root' })
export class GqlService {
  private endpoint = 'http://localhost:3000/graphql';

  constructor(private auth: AuthService) {}

  async request<T>(query: string, variables?: any): Promise<T> {
    const token = await this.auth.getAccessToken();

    const res = await fetch(this.endpoint, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify({ query, variables }),
    });

    const json = await res.json();
    if (json.errors?.length) throw new Error(json.errors[0].message);
    return json.data as T;
  }
}
