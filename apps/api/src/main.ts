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
import {
  getEngagementReport,
  ingestEngagementBatch,
  renderEngagementReportHtml,
} from './engagement/engagement.service.js';
import {
  rankCandidates,
  refreshItemStats,
  refreshUserFeatures,
} from './recommendation/rank.service.js';
import {
  handleReportsDataGet,
  handleReportsGet,
  handleReportsLogin,
  handleReportsLogout,
  hasReportsAccess,
} from './reports/reports-page.js';
import {
  authMailStatus,
  confirmEmailWithToken,
  resendConfirmation,
  signupWithMatteryaEmail,
} from './auth/signup-confirm.service.js';
import { getPipelineStatus, requestPipelineRun, runPipelineNow } from './content-pipeline/jobs.js';
import {
  handlePipelineClearLog,
  handlePipelineGet,
  handlePipelineLogin,
  handlePipelineLogout,
  handlePipelineRun,
  handlePipelineRunStream,
} from './content-pipeline/pipeline-page.js';
import { kafkaEnabled } from './kafka/config.js';

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

// Confirmation emails from noreply@matterya.com (Resend)
const _resendKey = (
  process.env.RESEND_API_KEY ?? process.env.RESEND_KEY ?? process.env.RESEND_API ?? ''
).trim();
if (!_resendKey) {
  console.warn(
    '⚠️ RESEND_API_KEY missing — signup confirmation mail will fail. ' +
      'Render → matterya-api → Environment → RESEND_API_KEY=re_… → Manual Deploy'
  );
} else {
  console.log(
    `✅ RESEND_API_KEY loaded: YES (len=${_resendKey.length}, prefix=${_resendKey.slice(0, 3)}…)`
  );
}
console.log(
  `📧 MAIL_FROM: ${(process.env.MAIL_FROM ?? '').trim() || 'Matterya <noreply@matterya.com> (default)'}`
);

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
app.use(express.urlencoded({ extended: false, limit: '32kb' }));
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

// ── Matterya reports page (password gate) ─────────────────────────────
// https://api.matterya.com/reports  ·  password via REPORTS_PAGE_PASSWORD
app.get('/reports', (req, res) => {
  void handleReportsGet(req, res);
});
/** Snappy Insights JSON (cookie auth) — used by time-range filters without full reload */
app.get('/reports/data', (req, res) => {
  void handleReportsDataGet(req, res);
});
app.post('/reports/login', handleReportsLogin);
app.get('/reports/logout', handleReportsLogout);
// Friendly alias
app.get('/report', (_req, res) => res.redirect(302, '/reports'));

// ── Content pipeline ops page (R2 → owned posts + feed shares) ─────────
// https://api.matterya.com/pipeline  ·  same password as reports by default
app.get('/pipeline', (req, res) => {
  void handlePipelineGet(req, res);
});
app.post('/pipeline/login', handlePipelineLogin);
app.get('/pipeline/logout', handlePipelineLogout);
app.post('/pipeline/run', (req, res) => {
  void handlePipelineRun(req, res);
});
/** Live SSE log stream for the ops page */
app.post('/pipeline/run-stream', (req, res) => {
  void handlePipelineRunStream(req, res);
});
app.post('/pipeline/clear-log', handlePipelineClearLog);
app.get('/pipeline/status', (req, res) => {
  // Public enough for health widgets; no secrets.
  res.json({ ok: true, ...getPipelineStatus() });
});

// ✅ health endpoint (typed _req to avoid implicit any)
app.get('/health', (_req: Request, res: Response) =>
  res.json({
    ok: true,
    features: {
      iosPushRoutes: true,
      iosPushStatus: true,
      matteryaEmailConfirm: true,
      contentPipeline: true,
      contentPipelinePage: true,
      r2PlaybackResolve: true,
      recsysRank: true,
      recsysWarehouse: true,
    },
    apnsConfigured: apns.isConfigured(),
    authMail: authMailStatus(),
    contentPipeline: getPipelineStatus(),
  })
);

// ─── Live R2 playback (never serve a dead signed URL) ─────────────────────────
// GET /v1/playback/:postId → { url, media_url, r2_key }
// Prefer GraphQL playbackMedia; this REST path is for simple clients / debugging.
app.get('/v1/playback/:postId', async (req: Request, res: Response) => {
  try {
    const postId = String(req.params.postId || '').trim();
    if (!postId) return res.status(400).json({ error: 'post_id_required' });
    const user = await getUserFromRequest(req);
    const { PostsService } = await import('./graphql/modules/posts/posts.service.js');
    const media = await new PostsService().playbackMedia(postId, user?.id ?? null);
    if (!media) return res.status(404).json({ error: 'not_found' });
    return res.json({ ok: true, ...media });
  } catch (err: any) {
    console.error('[playback]', err?.message ?? err);
    return res.status(500).json({ error: 'playback_failed', message: err?.message ?? 'error' });
  }
});

// ─── Matterya signup + branded email confirmation ───────────────────────────
// Clients must use these instead of Supabase Auth signup so confirmation goes
// through a real Matterya route: https://matterya.com/confirm-email?token=…

app.post('/auth/signup', async (req: Request, res: Response) => {
  try {
    // Pass raw body values so empty/null password is rejected with EMPTY_PASSWORD (not coerced to "").
    const email = req.body?.email;
    const password = req.body?.password;
    const result = await signupWithMatteryaEmail(
      email === undefined || email === null ? '' : String(email),
      password
    );
    return res.status(201).json(result);
  } catch (err: any) {
    const status = Number(err?.status) || 500;
    return res.status(status).json({
      error: err?.code ?? 'signup_failed',
      message: err?.message ?? 'Signup failed.',
      isExistingEmail: !!err?.isExistingEmail,
    });
  }
});

app.post('/auth/confirm-email', async (req: Request, res: Response) => {
  try {
    const token = String(req.body?.token ?? req.query.token ?? '');
    const result = await confirmEmailWithToken(token);
    return res.json(result);
  } catch (err: any) {
    const status = Number(err?.status) || 500;
    return res.status(status).json({
      error: err?.code ?? 'confirm_failed',
      message: err?.message ?? 'Confirmation failed.',
    });
  }
});

/** Browser-friendly GET: JSON for apps, or redirect to web success page when Accept is html. */
app.get('/auth/confirm-email', async (req: Request, res: Response) => {
  const token = String(req.query.token ?? '');
  const accept = String(req.headers.accept ?? '');
  try {
    const result = await confirmEmailWithToken(token);
    if (accept.includes('text/html')) {
      const web = (process.env.PUBLIC_WEB_ORIGIN ?? process.env.WEB_ORIGIN ?? 'https://matterya.com')
        .toString()
        .replace(/\/$/, '');
      return res.redirect(302, `${web}/confirm-email?ok=1&email=${encodeURIComponent(result.email)}`);
    }
    return res.json(result);
  } catch (err: any) {
    const status = Number(err?.status) || 500;
    if (accept.includes('text/html')) {
      const web = (process.env.PUBLIC_WEB_ORIGIN ?? process.env.WEB_ORIGIN ?? 'https://matterya.com')
        .toString()
        .replace(/\/$/, '');
      return res.redirect(
        302,
        `${web}/confirm-email?error=${encodeURIComponent(err?.message ?? 'Confirmation failed.')}`
      );
    }
    return res.status(status).json({
      error: err?.code ?? 'confirm_failed',
      message: err?.message ?? 'Confirmation failed.',
    });
  }
});

app.post('/auth/resend-confirmation', async (req: Request, res: Response) => {
  try {
    const email = String(req.body?.email ?? '');
    const result = await resendConfirmation(email);
    return res.json({
      ...result,
      message: 'If that email needs confirmation, we sent a new Matterya link.',
    });
  } catch (err: any) {
    const status = Number(err?.status) || 500;
    return res.status(status).json({
      error: err?.code ?? 'resend_failed',
      message: err?.message ?? 'Could not resend confirmation.',
    });
  }
});

app.get('/auth/status', (_req: Request, res: Response) => {
  return res.json({ ok: true, ...authMailStatus() });
});

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

/**
 * Behavior / attention signals (scroll dwell, skip, watch, …).
 * Writes Postgres + kafka_outbox → topic matterya.engagement (live in Console / [kafka-live] logs).
 */
app.post('/v1/engagement/batch', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  if (!user?.id) return res.status(401).json({ error: 'unauthenticated' });
  try {
    const result = await ingestEngagementBatch({
      entityId: user.id,
      sessionId: req.body?.sessionId ?? null,
      events: Array.isArray(req.body?.events) ? req.body.events : [],
    });
    // Keep online features warm while users scroll (async — never block the client).
    if (result.accepted > 0) {
      void refreshUserFeatures(user.id).catch(() => {});
    }
    return res.json({ ok: true, ...result });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'engagement_ingest_failed' });
  }
});

/**
 * Server-side recsys ranker (scale path).
 * Client sends candidate post IDs; server returns ordered IDs + scores + decision log.
 * POST /v1/recommendation/rank
 * body: { surface, candidateIds[], sessionId?, followingIds?, limit? }
 */
app.post('/v1/recommendation/rank', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  if (!user?.id) return res.status(401).json({ error: 'unauthenticated' });
  try {
    const ranked = await rankCandidates({
      entityId: user.id,
      surface: String(req.body?.surface ?? 'home_for_you'),
      candidateIds: Array.isArray(req.body?.candidateIds) ? req.body.candidateIds : [],
      sessionId: req.body?.sessionId ?? null,
      followingIds: Array.isArray(req.body?.followingIds) ? req.body.followingIds : [],
      limit: req.body?.limit,
    });
    return res.json({ ok: true, ...ranked });
  } catch (err: any) {
    console.error('[recsys/rank]', err?.message ?? err);
    return res.status(500).json({ error: err?.message ?? 'rank_failed' });
  }
});

/**
 * Refresh online features for the caller (affinity / personality).
 * Also used by ops: POST /v1/recommendation/refresh-item-stats?hours=72 with cron secret.
 */
app.post('/v1/recommendation/refresh-features', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  if (!user?.id) return res.status(401).json({ error: 'unauthenticated' });
  try {
    const out = await refreshUserFeatures(user.id);
    return res.json({ ok: out.ok !== false, features: out });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'refresh_failed' });
  }
});

app.post('/v1/recommendation/refresh-item-stats', async (req: Request, res: Response) => {
  const secret = String(req.headers['x-cron-secret'] ?? req.query.secret ?? '').trim();
  const expected = String(process.env.CONTENT_CRON_SECRET ?? process.env.INSIGHTS_CRON_SECRET ?? '').trim();
  const user = await getUserFromRequest(req);
  const adminKey = String(req.headers['x-admin-key'] ?? '').trim();
  const isAdmin = !!ADMIN_PORTAL_KEY && adminKey === ADMIN_PORTAL_KEY;
  if ((!expected || secret !== expected) && !user?.id && !isAdmin) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  try {
    const hours = Number(req.body?.hours ?? req.query.hours ?? 72);
    const out = await refreshItemStats(hours);
    return res.json({ ok: true, updated: out.updated });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'item_stats_failed' });
  }
});

/**
 * People activity report (plain language + timestamp on every interaction).
 * JSON:  GET /v1/engagement/report?hours=24
 * HTML:  GET /v1/engagement/report?hours=24&format=html
 * Auth:  Bearer JWT  ·  admin key  ·  reports page cookie (password gate)
 * Prefer the Matterya UI: https://api.matterya.com/reports
 */
app.get('/v1/engagement/report', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  const adminKey = String(
    req.headers['x-admin-key'] ?? req.query.key ?? ''
  ).trim();
  const isAdmin = !!ADMIN_PORTAL_KEY && adminKey === ADMIN_PORTAL_KEY;
  if (!user?.id && !isAdmin && !hasReportsAccess(req)) {
    return res.status(401).json({ error: 'unauthenticated' });
  }
  try {
    const hours = Math.max(1, Math.min(720, Number(req.query.hours ?? 24) || 24));
    const report = await getEngagementReport(hours);
    const format = String(req.query.format ?? 'json').toLowerCase();
    if (format === 'html') {
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      return res.send(renderEngagementReportHtml(report));
    }
    return res.json({ ok: true, report });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'report_failed' });
  }
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

/**
 * Automated R2 catalog → owned posts + feed spark shares + presign refresh.
 * Prefer Kafka enqueue when KAFKA_ENABLED (consumer runs work).
 * Auth: CONTENT_CRON_SECRET or INSIGHTS_CRON_SECRET.
 *
 * Ops UI: https://api.matterya.com/pipeline
 * Cron:  POST https://api.matterya.com/cron/content-pipeline
 *        Header: x-cron-secret: <you choose this secret>
 */
app.post('/cron/content-pipeline', async (req: Request, res: Response) => {
  const secret = req.headers['x-cron-secret'] || req.query.secret;
  const expected =
    process.env.CONTENT_CRON_SECRET?.trim() ||
    process.env.INSIGHTS_CRON_SECRET?.trim() ||
    INSIGHTS_CRON_SECRET;
  if (!expected || String(secret ?? '') !== expected) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  try {
    const dryRun =
      String(req.query.dryRun ?? req.body?.dryRun ?? '') === '1' ||
      String(req.query.dryRun ?? req.body?.dryRun ?? '') === 'true';
    const resignOnly =
      String(req.query.resignOnly ?? req.body?.resignOnly ?? '') === '1' ||
      String(req.query.resignOnly ?? req.body?.resignOnly ?? '') === 'true';
    const forceInline =
      String(req.query.inline ?? req.body?.inline ?? '') === '1' ||
      String(req.query.inline ?? req.body?.inline ?? '') === 'true';
    const rawOriginals = Number(req.query.maxOriginals ?? req.body?.maxOriginals);
    const rawShares = Number(req.query.maxShares ?? req.body?.maxShares);
    const rawResign = Number(req.query.maxResign ?? req.body?.maxResign);
    const rawMs = Number(req.query.maxMs ?? req.body?.maxMs);
    const opts = {
      dryRun,
      resignOnly,
      // Flood by default: omit caps so every new R2 video is ingested this run.
      // Optional ?maxOriginals=N & ?maxMs=ms still throttle when explicitly set.
      maxOriginals:
        Number.isFinite(rawOriginals) && rawOriginals > 0 ? rawOriginals : undefined,
      maxShares: Number.isFinite(rawShares) && rawShares > 0 ? rawShares : undefined,
      maxResign: Number.isFinite(rawResign) && rawResign > 0 ? rawResign : 2000,
      maxMs: Number.isFinite(rawMs) && rawMs > 0 ? rawMs : 0,
      requestedBy: 'cron',
      forceInline,
      source: 'cron',
    };
    // Default: Kafka queue when available; ?inline=1 forces in-process run.
    if (!forceInline && kafkaEnabled()) {
      const result = await requestPipelineRun(opts);
      if (result.mode === 'kafka') {
        return res.status(202).json({
          ok: true,
          mode: 'kafka',
          eventId: result.eventId,
          message: 'R2IngestRequested enqueued — consumer will run the pipeline',
        });
      }
    }
    const stats = await runPipelineNow(opts);
    return res.status(stats.ok ? 200 : 500).json({ mode: 'inline', ...stats });
  } catch (err: any) {
    return res.status(500).json({ ok: false, error: err?.message ?? 'failed' });
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
