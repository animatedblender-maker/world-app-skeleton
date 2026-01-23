import webPush from 'web-push';
import { pool } from '../db.js';

type SubscriptionInput = {
  endpoint: string;
  keys: {
    p256dh: string;
    auth: string;
  };
};

type SubscriptionRow = {
  id: string;
  user_id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
};

const VAPID_PUBLIC_KEY = process.env.PUSH_VAPID_PUBLIC_KEY ?? '';
const VAPID_PRIVATE_KEY = process.env.PUSH_VAPID_PRIVATE_KEY ?? '';
const VAPID_SUBJECT = process.env.PUSH_VAPID_SUBJECT ?? 'mailto:support@matterya.com';

const PUSH_ENABLED = Boolean(VAPID_PUBLIC_KEY && VAPID_PRIVATE_KEY);

if (PUSH_ENABLED) {
  webPush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);
} else {
  console.warn('⚠️ Push disabled: missing PUSH_VAPID_PUBLIC_KEY or PUSH_VAPID_PRIVATE_KEY');
}

export class PushService {
  async upsertSubscription(userId: string, subscription: SubscriptionInput, userAgent?: string | null): Promise<void> {
    if (!PUSH_ENABLED) return;
    if (!subscription?.endpoint || !subscription?.keys?.p256dh || !subscription?.keys?.auth) {
      throw new Error('Invalid subscription payload.');
    }
    await pool.query(
      `
      insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, user_agent)
      values ($1, $2, $3, $4, $5)
      on conflict (endpoint)
      do update set
        user_id = excluded.user_id,
        p256dh = excluded.p256dh,
        auth = excluded.auth,
        user_agent = excluded.user_agent,
        updated_at = now()
      `,
      [
        userId,
        subscription.endpoint,
        subscription.keys.p256dh,
        subscription.keys.auth,
        userAgent ?? null,
      ]
    );
  }

  async removeSubscription(userId: string, endpoint: string): Promise<void> {
    if (!endpoint) return;
    await pool.query(
      `
      delete from public.push_subscriptions
      where user_id = $1 and endpoint = $2
      `,
      [userId, endpoint]
    );
  }

  async sendToUser(
    userId: string,
    payload: {
      title: string;
      body?: string | null;
      url?: string | null;
      tag?: string | null;
    }
  ): Promise<void> {
    if (!PUSH_ENABLED) return;
    let rows: SubscriptionRow[] = [];
    try {
      const result = await pool.query<SubscriptionRow>(
        `
        select id, user_id, endpoint, p256dh, auth
        from public.push_subscriptions
        where user_id = $1
        `,
        [userId]
      );
      rows = result.rows;
    } catch (err) {
      console.warn('Push subscriptions query failed', err);
      return;
    }

    if (!rows.length) return;

    const message = JSON.stringify({
      title: payload.title,
      body: payload.body ?? '',
      url: payload.url ?? '/',
      tag: payload.tag ?? null,
      icon: '/logo.png',
      badge: '/logo.png',
    });

    const staleIds: string[] = [];

    for (const row of rows) {
      try {
        await webPush.sendNotification(
          {
            endpoint: row.endpoint,
            keys: {
              p256dh: row.p256dh,
              auth: row.auth,
            },
          },
          message
        );
      } catch (err: any) {
        const status = err?.statusCode;
        if (status === 404 || status === 410) {
          staleIds.push(row.id);
        } else {
          console.warn('Push send failed', status ?? err);
        }
      }
    }

    if (staleIds.length) {
      try {
        await pool.query(
          `
          delete from public.push_subscriptions
          where id = any($1::uuid[])
          `,
          [staleIds]
        );
      } catch (err) {
        console.warn('Failed to prune stale push subscriptions', err);
      }
    }
  }
}
