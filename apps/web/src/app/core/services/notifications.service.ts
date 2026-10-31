import { Injectable } from '@angular/core';
import { environment } from '../../../envirnoments/envirnoment';
import { GqlService } from './gql.service';
import { AuthService } from './auth.service';

export type NotificationActor = {
  user_id: string;
  display_name?: string | null;
  username?: string | null;
  avatar_url?: string | null;
};

export type NotificationItem = {
  id: string;
  user_id: string;
  actor_id?: string | null;
  type: string;
  entity_type?: string | null;
  entity_id?: string | null;
  read_at?: string | null;
  created_at: string;
  actor?: NotificationActor | null;
};

const LIST_NOTIFICATIONS = `
query Notifications($limit: Int, $before: String) {
  notifications(limit: $limit, before: $before) {
    id
    user_id
    actor_id
    type
    entity_type
    entity_id
    read_at
    created_at
    actor {
      user_id
      display_name
      username
      avatar_url
    }
  }
}
`;

const UNREAD_COUNT = `
query NotificationsUnreadCount {
  notificationsUnreadCount
}
`;

const MARK_READ = `
mutation MarkNotificationRead($id: ID!) {
  markNotificationRead(id: $id)
}
`;

const MARK_ALL_READ = `
mutation MarkAllNotificationsRead {
  markAllNotificationsRead
}
`;

@Injectable({ providedIn: 'root' })
export class NotificationsService {
  private endpoint = environment.graphqlEndpoint || 'http://localhost:3000/graphql';

  constructor(
    private gql: GqlService,
    private auth: AuthService
  ) {}

  async list(limit = 40, before?: string | null) {
    try {
      return await this.gql.request<{ notifications: NotificationItem[] }>(LIST_NOTIFICATIONS, {
        limit,
        before: before ?? null,
      });
    } catch {
      return await this.quietRequest<{ notifications: NotificationItem[] }>(LIST_NOTIFICATIONS, {
        limit,
        before: before ?? null,
      }, { notifications: [] });
    }
  }

  async unreadCount() {
    try {
      return await this.gql.request<{ notificationsUnreadCount: number }>(UNREAD_COUNT);
    } catch {
      return await this.quietRequest<{ notificationsUnreadCount: number }>(
        UNREAD_COUNT,
        undefined,
        { notificationsUnreadCount: 0 }
      );
    }
  }

  async markRead(id: string) {
    return this.gql.request<{ markNotificationRead: boolean }>(MARK_READ, { id });
  }

  async markAllRead() {
    return this.gql.request<{ markAllNotificationsRead: number }>(MARK_ALL_READ);
  }

  private async quietRequest<T>(query: string, variables: any, fallback: T): Promise<T> {
    try {
      const token = await this.auth.getAccessToken();
      const res = await fetch(this.endpoint, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          accept: 'application/json',
          ...(token ? { authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify({ query, variables: variables ?? {} }),
      });
      const text = await res.text();
      const json = text ? JSON.parse(text) : null;
      if (!res.ok || json?.errors?.length || !json?.data) return fallback;
      return json.data as T;
    } catch {
      return fallback;
    }
  }
}
