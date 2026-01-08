import { Injectable } from '@angular/core';
import { AuthService } from './auth.service';
import { environment } from '../../../envirnoments/envirnoment';

@Injectable({ providedIn: 'root' })
export class GqlService {
  private endpoint = environment.graphqlEndpoint || 'http://localhost:3000/graphql';

  constructor(private auth: AuthService) {}

  async request<T>(query: string, variables?: any): Promise<T> {
    const token = await this.safeGetToken();

    let res: Response;
    let text = '';

    try {
      res = await fetch(this.endpoint, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          accept: 'application/json',
          ...(token ? { authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify({ query, variables: variables ?? {} }),
      });

      // Read as text first so we can show useful errors even if JSON parsing fails
      text = await res.text();
    } catch (e: any) {
      const msg = `GraphQL NETWORK error (endpoint=${this.endpoint}): ${e?.message ?? e}`;
      console.error('[gql] NETWORK', msg);
      throw new Error(msg);
    }

    // Try parsing JSON, but if the server returned HTML/plain text, show it
    let json: any = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      const msg = `GraphQL NON-JSON response (HTTP ${res.status} ${res.statusText}) from ${this.endpoint}:\n${text.slice(0, 600)}`;
      console.error('[gql] NON-JSON', msg);
      throw new Error(msg);
    }

    // If HTTP status is not OK, show details
    if (!res.ok) {
      const msg = `GraphQL HTTP error ${res.status} ${res.statusText} from ${this.endpoint}:\n${JSON.stringify(json).slice(0, 800)}`;
      console.error('[gql] HTTP', msg);
      throw new Error(msg);
    }

    // GraphQL errors
    if (json?.errors?.length) {
      console.error('[gql] GQL ERRORS', json.errors);
      console.error('[gql] GQL ERRORS JSON', JSON.stringify(json.errors));

      const first = json.errors[0];
      const code = typeof first?.extensions?.code === 'string' ? first.extensions.code : null;
      const msg = code
        ? `${first?.message ?? 'GraphQL error.'} (code=${code})`
        : first?.message ?? `GraphQL error: ${JSON.stringify(json.errors).slice(0, 800)}`;

      throw new Error(msg);
    }

    return json.data as T;
  }

  private async safeGetToken(): Promise<string | null> {
    try {
      const token = await this.auth.getAccessToken();
      return token || null;
    } catch (e) {
      // token fetch failed (not logged in / supabase not ready / etc.)
      console.warn('[gql] token missing:', e);
      return null;
    }
  }
}
