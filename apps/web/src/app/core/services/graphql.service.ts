import { Injectable } from '@angular/core';
import { AuthService } from './auth.service';
import { environment } from '../../../envirnoments/envirnoment';

type GraphqlResponse<T> = {
  data?: T;
  errors?: Array<{ message: string }>;
};

@Injectable({ providedIn: 'root' })
export class GraphqlService {
  private readonly endpoint = environment.graphqlEndpoint || 'http://localhost:3000/graphql';

  constructor(private auth: AuthService) {}

  async query<T>(query: string, variables?: Record<string, any>): Promise<T> {
    return this.request<T>(query, variables);
  }

  async mutate<T>(mutation: string, variables?: Record<string, any>): Promise<T> {
    return this.request<T>(mutation, variables);
  }

  private async request<T>(queryOrMutation: string, variables?: Record<string, any>): Promise<T> {
    const token = await this.auth.getAccessToken();
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 10000);

    try {
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
        signal: controller.signal,
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
    } catch (e: any) {
      if (e?.name === 'AbortError' || controller.signal.aborted) {
        throw new Error(`GraphQL timeout after 10000ms`);
      }
      throw e;
    } finally {
      clearTimeout(timer);
    }
  }
}
