import { Injectable } from '@angular/core';
import { environment } from '../../../envirnoments/envirnoment';
import { AuthService } from './auth.service';

export type AnonymousProfile = {
  id: string;
  username: string;
  avatar_seed: string;
  state: string;
  age_attested_at: string | null;
  created_at: string;
};

export type AnonymousSession = {
  ok: boolean;
  eligible: boolean;
  reason?: string;
  code?: string;
  profile: AnonymousProfile | null;
  age_attested: boolean;
  paid_enabled: boolean;
};

export type AnonymousSpace = {
  id: string;
  slug: string;
  title: string;
  description: string;
  category: string;
  tags: string[];
  visibility: string;
  admission: string;
  billing_mode: string;
  status: string;
  language: string;
  member_count: number;
  post_count: number;
  owner_username: string | null;
  joined: boolean;
  rules?: Array<{ position: number; text: string }>;
  created_at: string;
};

export type AnonymousAuthor = {
  id: string;
  username: string;
  avatar_seed: string;
};

export type AnonymousPost = {
  id: string;
  space_id: string;
  space_slug?: string;
  author: AnonymousAuthor;
  title: string | null;
  body: string;
  state: string;
  score: number;
  comment_count: number;
  created_at: string;
  edited_at: string | null;
  my_vote?: number;
};

export type AnonymousComment = {
  id: string;
  post_id: string;
  parent_id: string | null;
  author: AnonymousAuthor;
  body: string;
  depth: number;
  state: string;
  score: number;
  created_at: string;
  my_vote?: number;
};

export type AnonymousSpaceFilter =
  | 'for_you'
  | 'popular'
  | 'newest'
  | 'joined'
  | 'free'
  | 'paid';

export type AnonymousApiError = {
  ok: false;
  error?: string;
  code?: string;
  reason?: string;
  paid_enabled?: boolean;
  status: number;
};

export type AnonymousNotification = {
  id: string;
  kind: string;
  title?: string | null;
  body?: string | null;
  post_id?: string | null;
  space_id?: string | null;
  actor_username?: string | null;
  created_at: string;
  read_at?: string | null;
};

export type AnonymousSearchResults = {
  people: AnonymousProfile[];
  spaces: AnonymousSpace[];
  posts: AnonymousPost[];
};

export type AnonymousPublicProfilePayload = {
  profile: AnonymousProfile;
  post_count?: number | null;
  space_count?: number | null;
};

@Injectable({ providedIn: 'root' })
export class AnonymousService {
  private readonly timeoutMs = 12000;

  constructor(private auth: AuthService) {}

  async session(): Promise<AnonymousSession | AnonymousApiError> {
    return this.request<AnonymousSession>('GET', '/v1/anonymous/session');
  }

  async attest(): Promise<
    | { ok: true; profile: AnonymousProfile | null; age_attested: boolean }
    | AnonymousApiError
  > {
    return this.request('POST', '/v1/anonymous/attest', { attest: true });
  }

  /** Claim (or fetch) the generated Anonymous username. */
  async claimProfile(opts?: { regenerate?: boolean }): Promise<
    | { ok: true; profile: AnonymousProfile; created: boolean }
    | AnonymousApiError
  > {
    const body =
      opts?.regenerate === true ? { regenerate: true } : {};
    return this.request('POST', '/v1/anonymous/profile', body);
  }

  async me(): Promise<
    | { ok: true; profile: AnonymousProfile; age_attested: boolean }
    | AnonymousApiError
  > {
    return this.request('GET', '/v1/anonymous/profile/me');
  }

  async listSpaces(
    filter: AnonymousSpaceFilter = 'for_you',
    cursor?: string | null,
    limit = 24
  ): Promise<
    | { ok: true; spaces: AnonymousSpace[]; next_cursor: string | null }
    | AnonymousApiError
  > {
    const q: Record<string, string> = {
      filter,
      limit: String(Math.min(Math.max(limit, 1), 48)),
    };
    if (cursor) q['cursor'] = cursor;
    return this.request('GET', '/v1/anonymous/spaces', undefined, q);
  }

  async space(slug: string): Promise<
    | { ok: true; space: AnonymousSpace }
    | AnonymousApiError
  > {
    return this.request(
      'GET',
      `/v1/anonymous/spaces/${encodeURIComponent(slug)}`
    );
  }

  async createSpace(input: {
    title: string;
    description?: string;
    category?: string;
    slug?: string;
    visibility?: string;
    rules?: string[];
  }): Promise<{ ok: true; space: AnonymousSpace } | AnonymousApiError> {
    return this.request('POST', '/v1/anonymous/spaces', input);
  }

  async join(spaceId: string): Promise<
    | { ok: true; membership: unknown }
    | AnonymousApiError
  > {
    return this.request(
      'POST',
      `/v1/anonymous/spaces/${encodeURIComponent(spaceId)}/join`,
      {}
    );
  }

  async leave(spaceId: string): Promise<{ ok: true } | AnonymousApiError> {
    return this.request(
      'POST',
      `/v1/anonymous/spaces/${encodeURIComponent(spaceId)}/leave`,
      {}
    );
  }

  async listPosts(
    spaceId: string,
    opts?: { sort?: string; cursor?: string | null; limit?: number }
  ): Promise<
    | { ok: true; posts: AnonymousPost[]; next_cursor: string | null }
    | AnonymousApiError
  > {
    const q: Record<string, string> = {
      sort: opts?.sort || 'new',
      limit: String(Math.min(Math.max(opts?.limit ?? 20, 1), 48)),
    };
    if (opts?.cursor) q['cursor'] = opts.cursor;
    return this.request(
      'GET',
      `/v1/anonymous/spaces/${encodeURIComponent(spaceId)}/posts`,
      undefined,
      q
    );
  }

  async createPost(
    spaceId: string,
    input: { title?: string; body: string }
  ): Promise<{ ok: true; post: AnonymousPost } | AnonymousApiError> {
    return this.request(
      'POST',
      `/v1/anonymous/spaces/${encodeURIComponent(spaceId)}/posts`,
      input
    );
  }

  async getPost(postId: string): Promise<
    | { ok: true; post: AnonymousPost }
    | AnonymousApiError
  > {
    return this.request(
      'GET',
      `/v1/anonymous/posts/${encodeURIComponent(postId)}`
    );
  }

  async listComments(postId: string): Promise<
    | { ok: true; comments: AnonymousComment[] }
    | AnonymousApiError
  > {
    return this.request(
      'GET',
      `/v1/anonymous/posts/${encodeURIComponent(postId)}/comments`
    );
  }

  async createComment(
    postId: string,
    input: { body: string; parent_id?: string | null }
  ): Promise<{ ok: true; comment: AnonymousComment } | AnonymousApiError> {
    return this.request(
      'POST',
      `/v1/anonymous/posts/${encodeURIComponent(postId)}/comments`,
      input
    );
  }

  async vote(
    targetType: 'post' | 'comment',
    targetId: string,
    value: -1 | 0 | 1
  ): Promise<
    | { ok: true; value: number; score: number }
    | AnonymousApiError
  > {
    return this.request('POST', '/v1/anonymous/votes', {
      target_type: targetType,
      target_id: targetId,
      value,
    });
  }

  async feed(opts?: {
    sort?: string;
    cursor?: string | null;
    limit?: number;
  }): Promise<
    | { ok: true; posts: AnonymousPost[]; next_cursor: string | null }
    | AnonymousApiError
  > {
    const q: Record<string, string> = {
      sort: opts?.sort || 'for_you',
      limit: String(Math.min(Math.max(opts?.limit ?? 20, 1), 48)),
    };
    if (opts?.cursor) q['cursor'] = opts.cursor;
    return this.request('GET', '/v1/anonymous/feed', undefined, q);
  }

  async search(
    query: string,
    limit = 12
  ): Promise<{ ok: true } & AnonymousSearchResults | AnonymousApiError> {
    const q = query.trim();
    if (!q) {
      return { ok: true, people: [], spaces: [], posts: [] };
    }
    const res = await this.request<any>('GET', '/v1/anonymous/search', undefined, {
      q,
      limit: String(Math.min(Math.max(limit, 1), 24)),
    });
    if ('ok' in res && res.ok === false) return res as AnonymousApiError;
    const data = res?.data ?? res;
    return {
      ok: true,
      people: Array.isArray(data?.people)
        ? data.people
        : Array.isArray(data?.profiles)
          ? data.profiles
          : [],
      spaces: Array.isArray(data?.spaces) ? data.spaces : [],
      posts: Array.isArray(data?.posts) ? data.posts : [],
    };
  }

  /** Public Masquerade profile by username (search → profile deep-link). */
  async publicProfile(
    username: string
  ): Promise<{ ok: true; payload: AnonymousPublicProfilePayload } | AnonymousApiError> {
    const handle = username.trim().replace(/^@+/, '');
    if (!handle) {
      return { ok: false, code: 'not_found', reason: 'Profile not found.', status: 404 };
    }
    const res = await this.request<any>(
      'GET',
      `/v1/anonymous/profiles/${encodeURIComponent(handle)}`
    );
    if ('ok' in res && res.ok === false) return res as AnonymousApiError;
    const data = res?.data ?? res;
    const profileRaw = data?.profile ?? data;
    const usernameOut = String(profileRaw?.username || '').trim();
    if (!usernameOut) {
      return { ok: false, code: 'not_found', reason: 'Profile not found.', status: 404 };
    }
    const profile: AnonymousProfile = {
      id: String(profileRaw?.id || ''),
      username: usernameOut,
      avatar_seed: String(profileRaw?.avatar_seed || profileRaw?.avatarSeed || usernameOut),
      state: String(profileRaw?.state || 'active'),
      age_attested_at: profileRaw?.age_attested_at ?? profileRaw?.ageAttestedAt ?? null,
      created_at: String(profileRaw?.created_at || profileRaw?.createdAt || ''),
    };
    return {
      ok: true,
      payload: {
        profile,
        post_count: data?.post_count ?? data?.postCount ?? null,
        space_count: data?.space_count ?? data?.spaceCount ?? null,
      },
    };
  }

  async authorPosts(
    username: string,
    opts?: { cursor?: string | null; limit?: number }
  ): Promise<
    | { ok: true; posts: AnonymousPost[]; next_cursor: string | null }
    | AnonymousApiError
  > {
    const handle = username.trim().replace(/^@+/, '');
    if (!handle) {
      return { ok: true, posts: [], next_cursor: null };
    }
    const q: Record<string, string> = {
      limit: String(Math.min(Math.max(opts?.limit ?? 24, 1), 48)),
    };
    if (opts?.cursor) q['cursor'] = opts.cursor;
    const res = await this.request<any>(
      'GET',
      `/v1/anonymous/profiles/${encodeURIComponent(handle)}/posts`,
      undefined,
      q
    );
    if ('ok' in res && res.ok === false) return res as AnonymousApiError;
    const data = res?.data ?? res;
    const posts: AnonymousPost[] = Array.isArray(data?.posts)
      ? data.posts
      : Array.isArray(data?.items)
        ? data.items
        : [];
    return {
      ok: true,
      posts,
      next_cursor: data?.next_cursor ?? data?.nextCursor ?? null,
    };
  }

  async notifications(opts?: {
    cursor?: string | null;
    limit?: number;
  }): Promise<
    | {
        ok: true;
        notifications: AnonymousNotification[];
        next_cursor: string | null;
        unread_count: number;
      }
    | AnonymousApiError
  > {
    const q: Record<string, string> = {
      limit: String(Math.min(Math.max(opts?.limit ?? 40, 1), 80)),
    };
    if (opts?.cursor) q['cursor'] = opts.cursor;
    const res = await this.request<any>('GET', '/v1/anonymous/notifications', undefined, q);
    if ('ok' in res && res.ok === false) return res as AnonymousApiError;
    const data = res?.data ?? res;
    const items: AnonymousNotification[] = Array.isArray(data?.notifications)
      ? data.notifications
      : Array.isArray(data?.items)
        ? data.items
        : [];
    return {
      ok: true,
      notifications: items,
      next_cursor: data?.next_cursor ?? data?.nextCursor ?? null,
      unread_count:
        typeof data?.unread_count === 'number'
          ? data.unread_count
          : typeof data?.unreadCount === 'number'
            ? data.unreadCount
            : items.filter((n) => !n.read_at).length,
    };
  }

  async markNotificationRead(id: string): Promise<{ ok: true } | AnonymousApiError> {
    const trimmed = id.trim();
    if (!trimmed) return { ok: true };
    return this.request('POST', `/v1/anonymous/notifications/${encodeURIComponent(trimmed)}/read`, {});
  }

  async markAllNotificationsRead(): Promise<{ ok: true; updated?: number } | AnonymousApiError> {
    return this.request('POST', '/v1/anonymous/notifications/read-all', {});
  }

  async checkoutStart(body: Record<string, unknown> = {}): Promise<AnonymousApiError> {
    const res = await this.request<AnonymousApiError>(
      'POST',
      '/v1/anonymous/checkout/start',
      body
    );
    if ('ok' in res && res.ok === false) return res;
    return {
      ok: false,
      code: 'paid_disabled',
      reason: 'Paid Spaces are not enabled yet.',
      status: 503,
    };
  }

  errorMessage(err: AnonymousApiError | null | undefined, fallback = 'Something went wrong.'): string {
    if (!err) return fallback;
    if (err.reason) return err.reason;
    switch (err.code || err.error) {
      case 'under_18':
        return 'Anonymous is only available to adults 18 and older.';
      case 'missing_birthdate':
        return 'Add your birthday in Matterya profile settings before entering Anonymous.';
      case 'age_attestation_required':
        return 'Confirm you are 18+ to enter Anonymous.';
      case 'profile_required':
        return 'Claim an Anonymous username to continue.';
      case 'paid_disabled':
        return 'Paid Spaces are coming soon. Join free Spaces for now.';
      case 'username_immutable':
        return 'Anonymous username cannot be changed.';
      case 'unauthenticated':
        return 'Sign in to use Anonymous.';
      default:
        return err.error || fallback;
    }
  }

  private async request<T extends { ok?: boolean }>(
    method: 'GET' | 'POST',
    path: string,
    body?: unknown,
    query?: Record<string, string>
  ): Promise<T | AnonymousApiError> {
    const base = (environment.apiBaseUrl || 'https://api.matterya.com').replace(
      /\/$/,
      ''
    );
    const url = new URL(`${base}${path}`);
    if (query) {
      for (const [k, v] of Object.entries(query)) {
        if (v != null && v !== '') url.searchParams.set(k, v);
      }
    }

    const headers: Record<string, string> = { accept: 'application/json' };
    try {
      const token = await this.auth.getAccessToken();
      if (token) headers['authorization'] = `Bearer ${token}`;
    } catch {
      // fall through — API will 401
    }
    if (body !== undefined) {
      headers['content-type'] = 'application/json';
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const res = await fetch(url.toString(), {
        method,
        headers,
        body: body !== undefined ? JSON.stringify(body) : undefined,
        signal: controller.signal,
      });
      const json = (await res.json().catch(() => ({}))) as any;
      if (!res.ok || json?.ok === false) {
        return {
          ok: false,
          error: json?.error,
          code: json?.code || json?.error,
          reason: json?.reason || json?.message,
          paid_enabled: json?.paid_enabled,
          status: res.status,
        };
      }
      return json as T;
    } catch (e: any) {
      const aborted = e?.name === 'AbortError';
      return {
        ok: false,
        code: 'network',
        reason: aborted
          ? 'Anonymous timed out. Try again.'
          : e?.message || 'Couldn’t reach Anonymous right now.',
        status: 0,
      };
    } finally {
      clearTimeout(timer);
    }
  }
}
