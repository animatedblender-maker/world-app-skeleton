import crypto from 'node:crypto';
import http2 from 'node:http2';
import { pool } from '../db.js';

type ApnsRow = {
  id: string;
  device_token: string;
  bundle_id: string | null;
  kind: string | null;
  apns_environment: string | null;
};

const APNS_TEAM_ID = process.env.APNS_TEAM_ID ?? '';
const APNS_KEY_ID = process.env.APNS_KEY_ID ?? '';
const APNS_PRIVATE_KEY = (process.env.APNS_PRIVATE_KEY ?? '').replace(/\\n/g, '\n');
const APNS_BUNDLE_ID = process.env.APNS_BUNDLE_ID ?? 'com.matterya.worldapp';
const APNS_PRODUCTION = String(process.env.APNS_PRODUCTION ?? 'false').toLowerCase() === 'true';

const APNS_ENABLED = Boolean(APNS_TEAM_ID && APNS_KEY_ID && APNS_PRIVATE_KEY);

if (!APNS_ENABLED) {
  console.warn('⚠️ APNs disabled: missing APNS_TEAM_ID, APNS_KEY_ID, or APNS_PRIVATE_KEY');
}

let cachedJwt: { token: string; expiresAt: number } | null = null;

function sanitizeApnsData(
  data: Record<string, string | null | undefined>
): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(data)) {
    if (value == null) continue;
    out[key] = String(value);
  }
  return out;
}

function apnsJwt(): string {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && cachedJwt.expiresAt > now + 120) {
    return cachedJwt.token;
  }

  const header = Buffer.from(JSON.stringify({ alg: 'ES256', kid: APNS_KEY_ID })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({ iss: APNS_TEAM_ID, iat: now })).toString('base64url');
  const unsigned = `${header}.${payload}`;
  const sign = crypto.createSign('SHA256');
  sign.update(unsigned);
  sign.end();
  const signature = sign.sign(APNS_PRIVATE_KEY).toString('base64url');
  const token = `${unsigned}.${signature}`;
  cachedJwt = { token, expiresAt: now + 3000 };
  return token;
}

function apnsHostForEnvironment(environment: string | null | undefined): string {
  const normalized = String(environment ?? '').trim().toLowerCase();
  const useProduction =
    normalized === 'production' ||
    (normalized !== 'sandbox' && normalized !== 'development' && APNS_PRODUCTION);
  return useProduction ? 'api.push.apple.com' : 'api.sandbox.push.apple.com';
}

async function sendApns(
  deviceToken: string,
  topic: string,
  body: Record<string, unknown>,
  priority: number,
  pushType: 'alert' | 'voip' = 'alert',
  environment: string | null = null
): Promise<void> {
  if (!APNS_ENABLED) return;

  const host = apnsHostForEnvironment(environment);
  const client = http2.connect(`https://${host}`);

  await new Promise<void>((resolve, reject) => {
    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${deviceToken}`,
      authorization: `bearer ${apnsJwt()}`,
      'apns-topic': topic,
      'apns-push-type': pushType,
      'apns-priority': String(priority),
      ...(pushType === 'voip' ? { 'apns-expiration': '0' } : {}),
    });

    req.setEncoding('utf8');
    let response = '';
    req.on('response', (headers) => {
      const status = Number(headers[':status'] ?? 0);
      req.on('data', (chunk) => {
        response += chunk;
      });
      req.on('end', () => {
        client.close();
        if (status >= 200 && status < 300) {
          resolve();
          return;
        }
        if (status === 410) {
          void pool.query(`delete from public.ios_device_tokens where device_token = $1`, [deviceToken]);
        }
        reject(new Error(`APNs ${status}: ${response}`));
      });
    });
    req.on('error', (err) => {
      client.close();
      reject(err);
    });
    req.write(JSON.stringify(body));
    req.end();
  }).catch((err) => {
    console.warn('APNs send failed', err);
  });
}

export class ApnsService {
  async upsertToken(
    userId: string,
    deviceToken: string,
    bundleId?: string | null,
    kind: string = 'alert',
    environment: string | null = null
  ): Promise<void> {
    if (!deviceToken) throw new Error('missing_device_token');
    const normalizedKind = kind === 'voip' ? 'voip' : 'alert';
    const normalizedEnvironment =
      String(environment ?? '').trim().toLowerCase() === 'production' ? 'production' : 'sandbox';
    const bundle = bundleId ?? APNS_BUNDLE_ID;
    try {
      await pool.query(
        `
        insert into public.ios_device_tokens (user_id, device_token, bundle_id, kind, apns_environment)
        values ($1, $2, $3, $4, $5)
        on conflict (device_token)
        do update set
          user_id = excluded.user_id,
          bundle_id = excluded.bundle_id,
          kind = excluded.kind,
          apns_environment = excluded.apns_environment,
          updated_at = now()
        `,
        [userId, deviceToken, bundle, normalizedKind, normalizedEnvironment]
      );
    } catch (err: any) {
      const message = String(err?.message ?? '');
      if (!message.includes('kind') && !message.includes('apns_environment')) throw err;
      await pool.query(
        `
        insert into public.ios_device_tokens (user_id, device_token, bundle_id)
        values ($1, $2, $3)
        on conflict (device_token)
        do update set
          user_id = excluded.user_id,
          bundle_id = excluded.bundle_id,
          updated_at = now()
        `,
        [userId, deviceToken, bundle]
      );
    }
  }

  async removeToken(userId: string, deviceToken: string): Promise<void> {
    if (!deviceToken) return;
    await pool.query(
      `delete from public.ios_device_tokens where user_id = $1 and device_token = $2`,
      [userId, deviceToken]
    );
  }

  async sendToUser(
    userId: string,
    payload: {
      title: string;
      body?: string | null;
      category?: string | null;
      data?: Record<string, string | null | undefined>;
      priority?: number;
    }
  ): Promise<void> {
    if (!APNS_ENABLED) return;

    let rows: ApnsRow[] = [];
    try {
      const result = await pool.query<ApnsRow>(
        `select id, device_token, bundle_id, kind, apns_environment from public.ios_device_tokens where user_id = $1`,
        [userId]
      );
      rows = result.rows;
    } catch (err: any) {
      const message = String(err?.message ?? '');
      if (!message.includes('kind')) {
        console.warn('iOS device token query failed', err);
        return;
      }
      try {
        const fallback = await pool.query<ApnsRow>(
          `select id, device_token, bundle_id, null::text as kind, null::text as apns_environment from public.ios_device_tokens where user_id = $1`,
          [userId]
        );
        rows = fallback.rows;
      } catch (fallbackErr) {
        console.warn('iOS device token query failed', fallbackErr);
        return;
      }
    }

    if (!rows.length) return;

    const isCall = payload.category === 'call' || payload.data?.type === 'call';
    const data = sanitizeApnsData(payload.data ?? {});

    if (isCall) {
      const voipRows = rows.filter((row) => row.kind === 'voip');
      const voipBody = sanitizeApnsData({
        ...data,
        type: 'call',
        title: payload.title,
      });
      for (const row of voipRows) {
        const bundle = row.bundle_id ?? APNS_BUNDLE_ID;
        await sendApns(row.device_token, `${bundle}.voip`, voipBody, 10, 'voip', row.apns_environment);
      }
      if (voipRows.length) return;
      console.warn(
        `Call push for user ${userId} has no VoIP device token; falling back to alert push (no full-screen CallKit takeover).`
      );
    }

    const alertRows = rows.filter((row) => row.kind !== 'voip');
    if (!alertRows.length) return;

    const aps: Record<string, unknown> = {
      alert: {
        title: payload.title,
        body: payload.body ?? '',
      },
      sound: isCall ? 'MatteryaCall.caf' : 'default',
      'content-available': isCall ? 1 : 0,
    };

    const apnsBody = {
      aps,
      ...sanitizeApnsData({
        ...data,
        type: data.type ?? payload.category ?? 'message',
      }),
    };

    for (const row of alertRows) {
      const topic = row.bundle_id ?? APNS_BUNDLE_ID;
      await sendApns(row.device_token, topic, apnsBody, payload.priority ?? 10, 'alert', row.apns_environment);
    }
  }
}