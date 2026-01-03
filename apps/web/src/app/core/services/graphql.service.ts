import { Injectable } from '@angular/core';
import { AuthService } from './auth.service';

type GraphqlResponse<T> = {
  data?: T;
  errors?: Array<{ message: string }>;
};

@Injectable({ providedIn: 'root' })
export class GraphqlService {
  // Your Yoga endpoint
  private readonly endpoint = 'http://localhost:3000/graphql';

  constructor(private auth: AuthService) {}

  async query<T>(query: string, variables?: Record<string, any>): Promise<T> {
    return this.request<T>(query, variables);
  }

  async mutate<T>(mutation: string, variables?: Record<string, any>): Promise<T> {
    return this.request<T>(mutation, variables);
  }

  private async request<T>(queryOrMutation: string, variables?: Record<string, any>): Promise<T> {
    const token = await this.auth.getAccessToken(); // ✅ key piece

    const res = await fetch(this.endpoint, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: JSON.stringify({
        query: queryOrMutation,
        variables: variables ?? undefined,
      }),
    });

    const json = (await res.json()) as GraphqlResponse<T>;

    if (!res.ok) {
      throw new Error(`GraphQL HTTP ${res.status}: ${JSON.stringify(json)}`);
    }

    if (json.errors?.length) {
      throw new Error(json.errors.map((e) => e.message).join(' | '));
    }

    if (!json.data) {
      throw new Error('GraphQL: missing data');
    }

    return json.data;
  }
}
