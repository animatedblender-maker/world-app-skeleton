import { Injectable } from '@angular/core';
import { GqlService } from './gql.service';

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
  constructor(private gql: GqlService) {}

  async list(limit = 40, before?: string | null) {
    return this.gql.request<{ notifications: NotificationItem[] }>(LIST_NOTIFICATIONS, {
      limit,
      before: before ?? null,
    });
  }

  async unreadCount() {
    return this.gql.request<{ notificationsUnreadCount: number }>(UNREAD_COUNT);
  }

  async markRead(id: string) {
    return this.gql.request<{ markNotificationRead: boolean }>(MARK_READ, { id });
  }

  async markAllRead() {
    return this.gql.request<{ markAllNotificationsRead: number }>(MARK_ALL_READ);
  }
}
