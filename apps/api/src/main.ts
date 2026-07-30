import express, { type Request, type Response } from 'express';
import cors from 'cors';
import { GraphQLError } from 'graphql';
import { createYoga, createSchema, maskError as yogaMaskError } from 'graphql-yoga';
import type { YogaInitialContext, YogaSchemaDefinition } from 'graphql-yoga';
import { SignJWT, jwtVerify, createRemoteJWKSet } from 'jose';
import http from 'node:http';
import { WebSocketServer } from 'ws';

import dotenv from 'dotenv';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// ----------------------------------------------------
// ✅ Force-load apps/api/.env (even if run from repo root)
// ----------------------------------------------------
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// src/main.ts  -> apps/api/src
// we want       -> apps/api/.env
dotenv.config({ path: path.join(__dirname, '..', '.env'), override: true });

// ✅ ts-node --esm on Windows needs explicit ".ts"
import { typeDefs } from './graphql/typeDefs.js';
import { resolvers } from './graphql/resolvers.js';
import { PushService } from './push/push.service.js';
import { ApnsService } from './push/apns.service.js';
import { pool } from './db.js';
import { runDailyInsights } from './insights/daily-insights.js';
import {
  getAdminOverview,
  getAdminSettings,
  updateAdminSettings,
  listReportedPosts,
  getAdsAdminSummary,
  moderateReportedPost,
} from './admin/admin.service.js';
import { clearCountryMoodCache } from './graphql/modules/insights/insights.service.js';
import { startKafkaPipeline, stopKafkaPipeline } from './kafka/index.js';

type AuthedUser = {
  id: string;
  email?: string;
  role?: string;
  aud?: string | string[];
};

type Context = YogaInitialContext & {
  user: AuthedUser | null;
};

const ORIGIN = process.env.WEB_ORIGIN ?? 'http://localhost:4200';
const DEFAULT_ORIGINS = [
  ORIGIN,
  'http://localhost',
  'https://localhost',
  'http://localhost:4200',
  'capacitor://localhost',
  'ionic://localhost',
];
const ALLOWED_ORIGINS = Array.from(
  new Set([...(process.env.WEB_ORIGINS ?? '').split(','), ...DEFAULT_ORIGINS])
)
  .map((value) => value.trim().replace(/\/$/, ''))
  .filter(Boolean);
const PORT = Number(process.env.PORT ?? 3000);

const SUPABASE_URL = process.env.SUPABASE_URL;
const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY;
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET;
const LIVEKIT_URL = process.env.LIVEKIT_URL;
const INSIGHTS_CRON_SECRET = process.env.INSIGHTS_CRON_SECRET || '';
const ADMIN_PORTAL_KEY = process.env.ADMIN_PORTAL_KEY || 'worldapp-admin-2026';

if (!SUPABASE_URL) {
  console.warn('⚠️ SUPABASE_URL not set. JWT verification will fail until you set it.');
} else {
  console.log('✅ SUPABASE_URL loaded: YES');
}

if (!process.env.SUPABASE_SERVICE_ROLE_KEY) {
  console.warn('⚠️ SUPABASE_SERVICE_ROLE_KEY missing (apps/api/.env not loaded or key missing)');
} else {
  console.log('✅ SUPABASE_SERVICE_ROLE_KEY loaded: YES');
}

const JWKS =
  SUPABASE_URL
    ? createRemoteJWKSet(new URL(`${SUPABASE_URL}/auth/v1/.well-known/jwks.json`))
    : null;

async function getUserFromRequest(req: Request): Promise<AuthedUser | null> {
  try {
    const authHeader = req.headers.authorization ?? '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;

    if (!token || !JWKS) return null;

    const { payload } = await jwtVerify(token, JWKS, {});
    return {
      id: String(payload.sub),
      email: typeof payload['email'] === 'string' ? payload['email'] : undefined,
      role: typeof payload['role'] === 'string' ? payload['role'] : undefined,
      aud:
        typeof payload['aud'] === 'string' || Array.isArray(payload['aud'])
          ? payload['aud']
          : undefined,
    };
  } catch {
    return null;
  }
}

async function getUserFromToken(token: string | null): Promise<AuthedUser | null> {
  try {
    if (!token || !JWKS) return null;
    const { payload } = await jwtVerify(token, JWKS, {});
    return {
      id: String(payload.sub),
      email: typeof payload['email'] === 'string' ? payload['email'] : undefined,
      role: typeof payload['role'] === 'string' ? payload['role'] : undefined,
      aud:
        typeof payload['aud'] === 'string' || Array.isArray(payload['aud'])
          ? payload['aud']
          : undefined,
    };
  } catch {
    return null;
  }
}

const schema: YogaSchemaDefinition<Context, {}> = createSchema({ typeDefs, resolvers }) as YogaSchemaDefinition<
  Context,
  {}
>;

const yoga = createYoga<Context>({
  schema,
  graphqlEndpoint: '/graphql',
  maskedErrors: {
    maskError(error, message, isDev) {
      const graphQLError = error instanceof GraphQLError ? error : null;
      const code =
        typeof graphQLError?.extensions?.code === 'string' ? graphQLError.extensions.code : '';
      const passthrough =
        graphQLError !== null &&
        ['HANDLE_TAKEN', 'UNAUTHENTICATED', 'BAD_USER_INPUT'].includes(code);
      if (passthrough && graphQLError) {
        return graphQLError;
      }
      return yogaMaskError(error as Error, message, isDev);
    },
  },
  context: async ({ req }: { req: Request }) => ({
    req,
    user: await getUserFromRequest(req),
  }),
});

const app = express();
const push = new PushService();
const apns = new ApnsService();
const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });
const socketsByUser = new Map<string, Set<any>>();

function hasAdminAccess(req: Request): boolean {
  const key = String(req.headers['x-admin-key'] ?? req.query.key ?? '').trim();
  return !!ADMIN_PORTAL_KEY && key === ADMIN_PORTAL_KEY;
}

app.use(express.json({ limit: '200kb' }));
app.use(
  cors({
    origin: (incomingOrigin, callback) => {
      const normalized = incomingOrigin ? incomingOrigin.replace(/\/$/, '') : '';
      if (!incomingOrigin || ALLOWED_ORIGINS.includes(normalized)) {
        return callback(null, true);
      }
      return callback(new Error(`CORS origin ${incomingOrigin} not allowed`));
    },
    credentials: true,
  })
);

// ✅ health endpoint (typed _req to avoid implicit any)
app.get('/health', (_req: Request, res: Response) =>
  res.json({
    ok: true,
    features: {
      iosPushRoutes: true,
      iosPushStatus: true,
    },
    apnsConfigured: apns.isConfigured(),
  })
);

app.get('/push/capabilities', (_req: Request, res: Response) => {
  const apnsConfig = apns.getServerConfig();
  return res.json({
    ok: true,
    webPushConfigured: Boolean(process.env.PUSH_VAPID_PUBLIC_KEY && process.env.PUSH_VAPID_PRIVATE_KEY),
    apnsConfigured: apns.isConfigured(),
    apnsProduction: apnsConfig.production,
    apnsBundleId: apnsConfig.bundleId,
    iosPushRoutes: true,
  });
});

app.get('/admin/bootstrap', async (req: Request, res: Response) => {
  if (!hasAdminAccess(req)) return res.status(401).json({ error: 'unauthorized' });
  try {
    const [overview, settings, reports, ads] = await Promise.all([
      getAdminOverview(),
      getAdminSettings(),
      listReportedPosts(20),
      getAdsAdminSummary(),
    ]);
    return res.json({ ok: true, overview, settings, reports, ads });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'failed' });
  }
});

app.get('/admin/settings', async (req: Request, res: Response) => {
  if (!hasAdminAccess(req)) return res.status(401).json({ error: 'unauthorized' });
  try {
    return res.json({ ok: true, settings: await getAdminSettings() });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'failed' });
  }
});

app.post('/admin/settings', async (req: Request, res: Response) => {
  if (!hasAdminAccess(req)) return res.status(401).json({ error: 'unauthorized' });
  try {
    const settings = await updateAdminSettings(req.body ?? {});
    clearCountryMoodCache();
    return res.json({ ok: true, settings });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'failed' });
  }
});

app.get('/admin/reports', async (req: Request, res: Response) => {
  if (!hasAdminAccess(req)) return res.status(401).json({ error: 'unauthorized' });
  try {
    const limit = Number(req.query.limit ?? 40);
    return res.json({ ok: true, reports: await listReportedPosts(limit) });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'failed' });
  }
});

app.post('/admin/reports/:postId/action', async (req: Request, res: Response) => {
  if (!hasAdminAccess(req)) return res.status(401).json({ error: 'unauthorized' });
  try {
    const postId = String(req.params.postId || '').trim();
    const action = String(req.body?.action || '').trim();
    const note = req.body?.note ?? null;
    const actor = req.body?.actor ?? req.headers['x-admin-actor'] ?? null;
    if (!postId) return res.status(400).json({ error: 'missing_post_id' });
    if (!action) return res.status(400).json({ error: 'missing_action' });
    const report = await moderateReportedPost(postId, action as any, note, String(actor ?? ''));
    return res.json({ ok: true, report });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'failed' });
  }
});

app.get('/admin/overview', async (req: Request, res: Response) => {
  if (!hasAdminAccess(req)) return res.status(401).json({ error: 'unauthorized' });
  try {
    return res.json({ ok: true, overview: await getAdminOverview() });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'failed' });
  }
});

app.get('/admin/ads/summary', async (req: Request, res: Response) => {
  if (!hasAdminAccess(req)) return res.status(401).json({ error: 'unauthorized' });
  try {
    return res.json({ ok: true, ads: await getAdsAdminSummary() });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'failed' });
  }
});

app.post('/admin/insights/run', async (req: Request, res: Response) => {
  if (!hasAdminAccess(req)) return res.status(401).json({ error: 'unauthorized' });
  try {
    clearCountryMoodCache();
    const result = await runDailyInsights();
    return res.json({ ok: true, ...result });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'failed' });
  }
});

app.post('/push/subscribe', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  if (!user?.id) return res.status(401).json({ error: 'unauthenticated' });

  const subscription = req.body?.subscription;
  try {
    const uaHeader = req.headers['user-agent'];
    const userAgent = Array.isArray(uaHeader) ? uaHeader.join(' ') : uaHeader;
    await push.upsertSubscription(user.id, subscription, userAgent);
    return res.json({ ok: true });
  } catch (err: any) {
    return res.status(400).json({ error: err?.message ?? 'invalid_subscription' });
  }
});

app.post('/push/unsubscribe', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  if (!user?.id) return res.status(401).json({ error: 'unauthenticated' });

  const endpoint = req.body?.endpoint;
  if (!endpoint) return res.status(400).json({ error: 'missing_endpoint' });
  await push.removeSubscription(user.id, endpoint);
  return res.json({ ok: true });
});

app.post('/push/ios/register', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  if (!user?.id) return res.status(401).json({ error: 'unauthenticated' });

  const deviceToken = String(req.body?.deviceToken ?? '').trim();
  const bundleId = req.body?.bundleId ? String(req.body.bundleId) : null;
  const kind = String(req.body?.kind ?? 'alert');
  const environment = req.body?.environment ? String(req.body.environment) : null;
  if (!deviceToken) return res.status(400).json({ error: 'missing_device_token' });

  try {
    await apns.upsertToken(user.id, deviceToken, bundleId, kind, environment);
    return res.json({ ok: true });
  } catch (err: any) {
    return res.status(400).json({ error: err?.message ?? 'register_failed' });
  }
});

app.post('/push/ios/unregister', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  if (!user?.id) return res.status(401).json({ error: 'unauthenticated' });

  const deviceToken = String(req.body?.deviceToken ?? '').trim();
  if (!deviceToken) return res.status(400).json({ error: 'missing_device_token' });
  await apns.removeToken(user.id, deviceToken);
  return res.json({ ok: true });
});

app.get('/push/ios/status', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  if (!user?.id) return res.status(401).json({ error: 'unauthenticated' });

  const tokens = await apns.getTokenStatsForUser(user.id);
  const config = apns.getServerConfig();
  return res.json({
    ok: true,
    apnsConfigured: apns.isConfigured(),
    apnsProduction: config.production,
    bundleId: config.bundleId,
    tokens,
  });
});

app.post('/push/ios/test', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  if (!user?.id) return res.status(401).json({ error: 'unauthenticated' });

  if (!apns.isConfigured()) {
    return res.status(503).json({
      ok: false,
      error: 'apns_not_configured',
      message: 'Matterya API server is missing APNs credentials (APNS_TEAM_ID, APNS_KEY_ID, APNS_PRIVATE_KEY).',
    });
  }

  const tokens = await apns.getTokenStatsForUser(user.id);
  if (tokens.alert < 1) {
    return res.status(404).json({
      ok: false,
      error: 'no_alert_tokens',
      message: 'No alert push token registered for this account on the server.',
      tokens,
    });
  }

  const result = await apns.sendToUser(user.id, {
    title: 'Matterya',
    body: 'Push notifications are working.',
    data: { type: 'test' },
  });

  if (result.delivered < 1) {
    return res.status(502).json({
      ok: false,
      error: 'apns_delivery_failed',
      message: 'Apple rejected the push or delivery failed.',
      result,
      tokens,
    });
  }

  return res.json({ ok: true, result, tokens });
});

app.post('/livekit/token', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  if (!user?.id) return res.status(401).json({ error: 'unauthenticated' });
  const room = String(req.body?.room ?? '').trim();
  if (!room) return res.status(400).json({ error: 'missing_room' });
  if (!LIVEKIT_API_KEY || !LIVEKIT_API_SECRET) {
    return res.status(500).json({ error: 'livekit_not_configured' });
  }
  const instance = String(req.body?.instance ?? '').trim();
  const identity = instance ? `${user.id}#${instance}` : user.id;
  const jwt = await new SignJWT({
    name: user.email ?? user.id,
    video: {
      room,
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
    },
  })
    .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
    .setIssuer(LIVEKIT_API_KEY)
    .setSubject(identity)
    .setIssuedAt()
    .setExpirationTime('1h')
    .sign(new TextEncoder().encode(LIVEKIT_API_SECRET));
  return res.json({ token: jwt, url: LIVEKIT_URL ?? '' });
});

app.post('/insights/run-daily', async (req: Request, res: Response) => {
  const secret = req.headers['x-cron-secret'] || req.query.secret;
  if (!INSIGHTS_CRON_SECRET || String(secret ?? '') !== INSIGHTS_CRON_SECRET) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  try {
    const result = await runDailyInsights();
    return res.json({ ok: true, ...result });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'failed' });
  }
});

wss.on('connection', async (socket, req) => {
  const url = new URL(req.url ?? '', `http://${req.headers.host}`);
  const token = url.searchParams.get('token');
  const user = await getUserFromToken(token);
  if (!user?.id) {
    socket.close(1008, 'unauthorized');
    return;
  }

  if (!socketsByUser.has(user.id)) {
    socketsByUser.set(user.id, new Set());
  }
  socketsByUser.get(user.id)!.add(socket);

  socket.on('message', async (data: any) => {
    let msg: any = null;
    try {
      msg = JSON.parse(String(data ?? ''));
    } catch {
      return;
    }
    const type = String(msg?.type ?? '');
    const conversationId = String(msg?.conversationId ?? '');
    if (!type || !conversationId) return;

    try {
      const { rows } = await pool.query<{ user_id: string }>(
        `select user_id from public.conversation_members where conversation_id = $1`,
        [conversationId]
      );
      const memberIds = rows.map((row) => row.user_id);
      if (!memberIds.includes(user.id)) return;

      if (type === 'call-offer') {
        const callParam = msg?.callType === 'video' ? 'video' : 'audio';
        const kind = callParam === 'video' ? 'Video call' : 'Voice call';
        let callerName = 'Incoming call';
        try {
          const { rows: profileRows } = await pool.query<{ display_name: string | null; username: string | null }>(
            `
            select display_name, username
            from public.profiles
            where user_id = $1
            `,
            [user.id]
          );
          const profile = profileRows[0];
          const name = profile?.display_name?.trim() || profile?.username?.trim();
          if (name) callerName = name;
        } catch {}
        const notifyTargets = memberIds.filter((memberId) => memberId !== user.id);
        const callId = msg?.callId ? String(msg.callId) : null;
        const roomName = msg?.roomName ? String(msg.roomName) : null;
        await Promise.all(
          notifyTargets.map(async (memberId) => {
            await Promise.all([
              apns.sendToUser(memberId, {
                title: callerName,
                body: `Incoming ${kind.toLowerCase()}.`,
                category: 'call',
                priority: 10,
                data: {
                  type: 'call',
                  conversationId,
                  from: user.id,
                  callType: callParam,
                  callId,
                  roomName,
                },
              }),
              push.sendToUser(memberId, {
                title: callerName,
                body: `Incoming ${kind.toLowerCase()}.`,
                url: `/messages?c=${conversationId}&call=${callParam}&from=${user.id}`,
                tag: `call:${conversationId}`,
              }),
            ]);
          })
        );
      }

      const payload = JSON.stringify({
        ...msg,
        from: user.id,
      });
      for (const memberId of memberIds) {
        if (memberId === user.id) continue;
        const sockets = socketsByUser.get(memberId);
        if (!sockets) continue;
        for (const s of sockets) {
          if (s.readyState === 1) {
            s.send(payload);
          }
        }
      }
    } catch (err) {
      console.warn('ws signal failed', err);
    }
  });

  socket.on('close', () => {
    const set = socketsByUser.get(user.id);
    if (!set) return;
    set.delete(socket);
    if (!set.size) socketsByUser.delete(user.id);
  });
});

app.use('/graphql', (req: Request, res: Response) => {
  return yoga.handle(req, res);
});

server.listen(PORT, () => {
  console.log(`✅ GraphQL running at http://localhost:${PORT}/graphql`);
  console.log(`✅ WS signaling at  http://localhost:${PORT}/ws`);
  console.log(`✅ Health at        http://localhost:${PORT}/health`);
  console.log(`✅ CORS origins allowed: ${ALLOWED_ORIGINS.join(', ')}`);
  // Async event backbone (no-op unless KAFKA_ENABLED=true).
  void startKafkaPipeline();
});

async function shutdown(signal: string) {
  console.log(`\n${signal} received — shutting down…`);
  try {
    await stopKafkaPipeline();
  } catch {
    /* ignore */
  }
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 4000).unref();
}

process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('SIGTERM', () => void shutdown('SIGTERM'));
