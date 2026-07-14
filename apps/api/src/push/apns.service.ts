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
  console.warn(
    '⚠️ APNs disabled: missing APNS_TEAM_ID, APNS_KEY_ID, or APNS_PRIVATE_KEY. iOS push will not work (browser Web Push uses separate VAPID keys).'
  );
} else {
  console.log(
    `✅ APNs enabled for ${APNS_BUNDLE_ID} (${APNS_PRODUCTION ? 'production' : 'sandbox'} default host)`
  );
}

export type ApnsTokenStats = {
  alert: number;
  voip: number;
  total: number;
  environments: string[];
};

export type ApnsSendFailure = {
  deviceToken: string;
  kind: 'alert' | 'voip';
  error: string;
};

export type ApnsSendResult = {
  attempted: number;
  delivered: number;
  failures: ApnsSendFailure[];
  skippedReason?: 'apns_disabled' | 'no_tokens';
};

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

function alternateApnsEnvironments(environment: string | null | undefined): string[] {
  const normalized = String(environment ?? '').trim().toLowerCase();
  if (normalized === 'production') return ['production', 'sandbox'];
  if (normalized === 'sandbox' || normalized === 'development') return ['sandbox', 'production'];
  return APNS_PRODUCTION ? ['production', 'sandbox'] : ['sandbox', 'production'];
}

async function sendApnsWithEnvironmentFallback(
  deviceToken: string,
  topic: string,
  body: Record<string, unknown>,
  priority: number,
  pushType: 'alert' | 'voip' | 'background',
  environment: string | null
): Promise<string> {
  let lastError: unknown = null;
  for (const env of alternateApnsEnvironments(environment)) {
    try {
      await sendApns(deviceToken, topic, body, priority, pushType, env);
      return env;
    } catch (err) {
      lastError = err;
    }
  }
  throw lastError instanceof Error ? lastError : new Error(String(lastError ?? 'send_failed'));
}

async function sendApns(
  deviceToken: string,
  topic: string,
  body: Record<string, unknown>,
  priority: number,
  pushType: 'alert' | 'voip' | 'background' = 'alert',
  environment: string | null = null
): Promise<void> {
  if (!APNS_ENABLED) {
    throw new Error('apns_not_configured');
  }

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
  });
}

export class ApnsService {
  isConfigured(): boolean {
    return APNS_ENABLED;
  }

  getServerConfig(): { bundleId: string; production: boolean } {
    return { bundleId: APNS_BUNDLE_ID, production: APNS_PRODUCTION };
  }

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

  async getTokenStatsForUser(userId: string): Promise<ApnsTokenStats> {
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
        return { alert: 0, voip: 0, total: 0, environments: [] };
      }
      try {
        const fallback = await pool.query<ApnsRow>(
          `select id, device_token, bundle_id, null::text as kind, null::text as apns_environment from public.ios_device_tokens where user_id = $1`,
          [userId]
        );
        rows = fallback.rows;
      } catch (fallbackErr) {
        console.warn('iOS device token query failed', fallbackErr);
        return { alert: 0, voip: 0, total: 0, environments: [] };
      }
    }

    const alert = rows.filter((row) => row.kind !== 'voip').length;
    const voip = rows.filter((row) => row.kind === 'voip').length;
    const environments = Array.from(
      new Set(
        rows
          .map((row) => String(row.apns_environment ?? '').trim().toLowerCase())
          .filter((value) => value === 'sandbox' || value === 'production')
      )
    );

    return { alert, voip, total: rows.length, environments };
  }

  private async queryTokensForUser(userId: string): Promise<ApnsRow[]> {
    try {
      const result = await pool.query<ApnsRow>(
        `select id, device_token, bundle_id, kind, apns_environment from public.ios_device_tokens where user_id = $1`,
        [userId]
      );
      return result.rows;
    } catch (err: any) {
      const message = String(err?.message ?? '');
      if (!message.includes('kind')) {
        console.warn('iOS device token query failed', err);
        return [];
      }
      try {
        const fallback = await pool.query<ApnsRow>(
          `select id, device_token, bundle_id, null::text as kind, null::text as apns_environment from public.ios_device_tokens where user_id = $1`,
          [userId]
        );
        return fallback.rows;
      } catch (fallbackErr) {
        console.warn('iOS device token query failed', fallbackErr);
        return [];
      }
    }
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
  ): Promise<ApnsSendResult> {
    if (!APNS_ENABLED) {
      return { attempted: 0, delivered: 0, failures: [], skippedReason: 'apns_disabled' };
    }

    const rows = await this.queryTokensForUser(userId);
    if (!rows.length) {
      return { attempted: 0, delivered: 0, failures: [], skippedReason: 'no_tokens' };
    }

    const isCall = payload.category === 'call' || payload.data?.type === 'call';
    const data = sanitizeApnsData(payload.data ?? {});
    const failures: ApnsSendFailure[] = [];
    let attempted = 0;
    let delivered = 0;

    if (isCall) {
      const callData = sanitizeApnsData({
        ...data,
        type: 'call',
        category: 'call',
        title: payload.title,
      });

      let voipDelivered = 0;
      const voipRows = rows.filter((row) => row.kind === 'voip');
      if (!voipRows.length) {
        console.warn(
          `Call push for user ${userId} has no VoIP device token registered. User must open Matterya on iPhone so Settings → Calling shows VoIP ready.`
        );
      } else {
        for (const row of voipRows) {
          const bundle = row.bundle_id ?? APNS_BUNDLE_ID;
          attempted += 1;
          try {
            const usedEnv = await sendApnsWithEnvironmentFallback(
              row.device_token,
              `${bundle}.voip`,
              callData,
              10,
              'voip',
              row.apns_environment
            );
            delivered += 1;
            voipDelivered += 1;
            if (usedEnv !== (row.apns_environment ?? '').toLowerCase()) {
              console.warn(
                `APNs voip delivered via ${usedEnv} for token registered as ${row.apns_environment ?? 'unknown'}`
              );
            }
          } catch (err: any) {
            const error = String(err?.message ?? err ?? 'send_failed');
            console.warn(`APNs voip send failed (${bundle}.voip, ${row.apns_environment ?? 'default'}):`, error);
            failures.push({ deviceToken: row.device_token, kind: 'voip', error });
          }
        }
      }

      const alertRows = rows.filter((row) => row.kind !== 'voip');
      for (const row of alertRows) {
        const topic = row.bundle_id ?? APNS_BUNDLE_ID;

        // Always try a silent wake so CallKit can present without the user tapping a banner.
        const silentBody = {
          aps: { 'content-available': 1 },
          ...callData,
        };
        attempted += 1;
        try {
          await sendApnsWithEnvironmentFallback(row.device_token, topic, silentBody, 5, 'background', row.apns_environment);
          delivered += 1;
        } catch (err: any) {
          const error = String(err?.message ?? err ?? 'send_failed');
          console.warn(`APNs call wake send failed (${topic}, ${row.apns_environment ?? 'default'}):`, error);
          failures.push({ deviceToken: row.device_token, kind: 'alert', error });
        }

        // If VoIP did not reach the device, also send a visible call alert (tap-to-answer fallback).
        if (voipDelivered < 1) {
          const visibleBody = {
            aps: {
              alert: {
                title: payload.title,
                body: payload.body ?? 'Incoming call',
              },
              sound: 'default',
              category: 'call',
              'interruption-level': 'time-sensitive',
            },
            ...callData,
          };
          attempted += 1;
          try {
            await sendApnsWithEnvironmentFallback(row.device_token, topic, visibleBody, 10, 'alert', row.apns_environment);
            delivered += 1;
          } catch (err: any) {
            const error = String(err?.message ?? err ?? 'send_failed');
            console.warn(`APNs call alert fallback failed (${topic}, ${row.apns_environment ?? 'default'}):`, error);
            failures.push({ deviceToken: row.device_token, kind: 'alert', error });
          }
        }
      }

      return { attempted, delivered, failures };
    }

    const alertRows = rows.filter((row) => row.kind !== 'voip');
    if (!alertRows.length) {
      return { attempted, delivered, failures };
    }

    const apnsBody = {
      aps: {
        alert: {
          title: payload.title,
          body: payload.body ?? '',
        },
        sound: 'default',
      },
      ...sanitizeApnsData({
        ...data,
        type: data.type ?? payload.category ?? 'message',
      }),
    };

    for (const row of alertRows) {
      const topic = row.bundle_id ?? APNS_BUNDLE_ID;
      attempted += 1;
      try {
        await sendApns(row.device_token, topic, apnsBody, payload.priority ?? 10, 'alert', row.apns_environment);
        delivered += 1;
      } catch (err: any) {
        const error = String(err?.message ?? err ?? 'send_failed');
        console.warn(`APNs alert send failed (${topic}, ${row.apns_environment ?? 'default'}):`, error);
        failures.push({ deviceToken: row.device_token, kind: 'alert', error });
      }
    }

    return { attempted, delivered, failures };
  }
}