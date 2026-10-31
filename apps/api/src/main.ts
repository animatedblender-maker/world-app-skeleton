import express, { type Request, type Response } from 'express';
import cors from 'cors';
import { GraphQLError } from 'graphql';
import { createYoga, createSchema, maskError as yogaMaskError } from 'graphql-yoga';
import type { YogaInitialContext, YogaSchemaDefinition } from 'graphql-yoga';
import { SignJWT } from 'jose';
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
import {
  getUserFromRequest,
  getUserFromToken,
  type AuthedUser,
} from './auth/request-user.js';
import { anonymousRouter } from './anonymous/index.js';
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
import { rebuildNeighborsForEntity } from './recommendation/knn.service.js';
import { backfillEmbeddings } from './recommendation/mind-embeddings.js';
import { backfillMultimodal } from './recommendation/mind-multimodal.js';
import {
  fetchForYouPage,
  fetchHomeFeedPage,
  fetchShelfPage,
  fetchSparksPage,
  HUB_PARENT_SLUGS,
  neighborSlug,
} from './recommendation/shelf.service.js';
import { getRemoteConfig } from './recommendation/remote-config.js';
import {
  ingestMetricBatch,
  metricsPrometheusText,
  metricsSummary,
  resetMetrics,
} from './recommendation/metrics-ingest.js';
import {
  handleReportsDataGet,
  handleReportsGet,
  handleReportsLogin,
  handleReportsLogout,
  hasReportsAccess,
} from './reports/reports-page.js';
import {
  handleMasqueradeModAction,
  handleMasqueradeModGet,
} from './reports/masquerade-mod-page.js';
import {
  handleModerationClaim,
  handleModerationQueueGet,
  handleModerationTicketAction,
} from './reports/moderation-queue-page.js';
import {
  handleAccountQueueGet,
  handleAccountQueueAction,
} from './reports/account-queue-page.js';
import { handleManagementGet } from './reports/management-page.js';
import {
  handlePolicyHandbookGet,
  handlePolicyHandbookPdfGet,
} from './reports/policy-handbook-page.js';
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
  handlePipelineLogStream,
  handlePipelineLogout,
  handlePipelineRun,
  handlePipelineRunStream,
  handleFrame0Get,
  handleFrame0Login,
  handleFrame0Logout,
  handleFrame0Status,
  handleFrame0Run,
} from './ops/ops-page.js';
import {
  handleMindDoc,
  handleMindGet,
  handleMindLogin,
  handleMindLogout,
  handleMindStatus,
  handleMindStream,
  handleMindPeopleSearch,
  handleMindPersonDossier,
} from './ops/mind-page.js';
import { MIND_POLICY_VERSION } from './recommendation/mind-contracts.js';
import {
  getInterestSnapshot,
  patchInterestControls,
  resetInterestControls,
  explainDecision,
} from './recommendation/mind-interest-controls.js';
import { hybridSearch } from './recommendation/mind-search.js';
import { suggestPeople } from './recommendation/mind-people-discovery.js';
import { getCreatorInsights } from './recommendation/mind-creator-insights.js';
import { worldCountryFeed } from './recommendation/mind-world.js';
import { bustSessionCache } from './recommendation/mind-session.js';
import { handlePosterBatch, handlePosterGet } from './media/poster-route.js';
import { kafkaEnabled } from './kafka/config.js';

type Context = YogaInitialContext & {
  user: AuthedUser | null;
};

const ORIGIN = process.env.WEB_ORIGIN ?? 'http://localhost:4200';
const DEFAULT_ORIGINS = [
  ORIGIN,
  'http://localhost',
  'https://localhost',
  'http://localhost:4200',
  'http://localhost:3000',
  'http://127.0.0.1:3000',
  'http://127.0.0.1:4200',
  'capacitor://localhost',
  'ionic://localhost',
];
const ALLOWED_ORIGINS = Array.from(
  new Set([...(process.env.WEB_ORIGINS ?? '').split(','), ...DEFAULT_ORIGINS])
)
  .map((value) => value.trim().replace(/\/$/, ''))
  .filter(Boolean);
const PORT = Number(process.env.PORT ?? 3000);

/** Local API / ops pages (e.g. /mind on :3000) send Origin matching the API itself. */
function isDevLoopbackOrigin(origin: string): boolean {
  try {
    const u = new URL(origin);
    if (u.hostname !== 'localhost' && u.hostname !== '127.0.0.1') return false;
    const port = u.port || (u.protocol === 'https:' ? '443' : '80');
    return port === String(PORT) || ['3000', '4200', '4091', '5173'].includes(port);
  } catch {
    return false;
  }
}

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

// JWT verify: ./auth/request-user.ts (shared with /v1/anonymous)

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
      if (
        !incomingOrigin ||
        ALLOWED_ORIGINS.includes(normalized) ||
        isDevLoopbackOrigin(normalized)
      ) {
        return callback(null, true);
      }
      return callback(new Error(`CORS origin ${incomingOrigin} not allowed`));
    },
    credentials: true,
  })
);

// Matterya Anonymous (adult-only pseudonymous Spaces) — JWT via getUserFromRequest
app.use('/v1/anonymous', anonymousRouter);

// ── Matterya management + moderation + Insights (password gate) ──────
// https://api.matterya.com/management        · Ops hub (all surfaces)
// https://api.matterya.com/reports           · Claim-next content moderation
// https://api.matterya.com/reports/accounts  · Account strike / review queue
// https://api.matterya.com/reports/analytics · Insights (activity/uploads)
app.get('/management', (req, res) => {
  void handleManagementGet(req, res).catch((err) => {
    console.error('[management]', err?.message ?? err);
    res.status(500).send('management failed');
  });
});
app.get('/management/policy', (req, res) => {
  void handlePolicyHandbookGet(req, res).catch((err) => {
    console.error('[management/policy]', err?.message ?? err);
    res.status(500).send('policy handbook failed');
  });
});
app.get('/management/policy.pdf', (req, res) => {
  void handlePolicyHandbookPdfGet(req, res).catch((err) => {
    console.error('[management/policy.pdf]', err?.message ?? err);
    res.status(500).send('policy handbook pdf failed');
  });
});
/** Alias without a trailing extension (some proxies mishandle .pdf paths). */
app.get('/management/policy/pdf', (req, res) => {
  void handlePolicyHandbookPdfGet(req, res).catch((err) => {
    console.error('[management/policy/pdf]', err?.message ?? err);
    res.status(500).send('policy handbook pdf failed');
  });
});
app.get('/reports', (req, res) => {
  void handleModerationQueueGet(req, res).catch((err) => {
    console.error('[reports]', err?.message ?? err);
    res.status(500).send('reports failed');
  });
});
app.get('/reports/analytics', (req, res) => {
  void handleReportsGet(req, res).catch((err: any) => {
    console.error('[reports/analytics]', err?.message ?? err);
    res.status(500).send('analytics failed');
  });
});
app.get('/insights', (_req, res) => res.redirect(302, '/reports/analytics'));
/** Snappy Insights JSON (cookie auth) — used by time-range filters without full reload */
app.get('/reports/data', (req, res) => {
  void handleReportsDataGet(req, res);
});
app.post('/reports/login', handleReportsLogin);
app.get('/reports/logout', handleReportsLogout);
app.post('/reports/claim', (req, res) => {
  void handleModerationClaim(req, res).catch((err) => {
    console.error('[reports/claim]', err?.message ?? err);
    res.status(500).send('claim failed');
  });
});
app.post('/reports/ticket/action', (req, res) => {
  void handleModerationTicketAction(req, res).catch((err) => {
    console.error('[reports/ticket/action]', err?.message ?? err);
    res.status(500).send('action failed');
  });
});
/** Account strike / review queue (severe or 3 mild strikes) */
app.get('/reports/accounts', (req, res) => {
  void handleAccountQueueGet(req, res).catch((err) => {
    console.error('[reports/accounts]', err?.message ?? err);
    res.status(500).send('accounts queue failed');
  });
});
app.post('/reports/accounts/action', (req, res) => {
  void handleAccountQueueAction(req, res).catch((err) => {
    console.error('[reports/accounts/action]', err?.message ?? err);
    res.status(500).send('accounts action failed');
  });
});
/** Masquerade review queue — legacy Remove / Flag / Skip (still available) */
app.get('/reports/masquerade', (req, res) => {
  void handleMasqueradeModGet(req, res);
});
app.post('/reports/masquerade/action', (req, res) => {
  void handleMasqueradeModAction(req, res).catch((err) => {
    console.error('[reports/masquerade/action]', err?.message ?? err);
    res.status(500).send('action failed');
  });
});
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
/** Re-attach to live log without starting a new run (browser network blip). */
app.get('/pipeline/log-stream', (req, res) => {
  void handlePipelineLogStream(req, res);
});
app.post('/pipeline/clear-log', handlePipelineClearLog);
app.get('/pipeline/status', (req, res) => {
  // Public enough for health widgets; no secrets.
  res.json({ ok: true, ...getPipelineStatus() });
});

// ── Frame 0 backfill progress ───────────────────────────────────────────
// https://api.matterya.com/frame0  ·  same password as pipeline/reports
app.get('/frame0', (req, res) => {
  void handleFrame0Get(req, res);
});
app.post('/frame0/login', handleFrame0Login);
app.get('/frame0/logout', handleFrame0Logout);
app.get('/frame0/status', (req, res) => {
  void handleFrame0Status(req, res);
});
app.post('/frame0/run', (req, res) => {
  void handleFrame0Run(req, res);
});

// ── MIND admin console (handbook + live recommendation ops) ───────────
// https://api.matterya.com/mind  ·  same password as pipeline/reports
app.get('/mind', (req, res) => {
  void handleMindGet(req, res);
});
app.post('/mind/login', handleMindLogin);
app.get('/mind/logout', handleMindLogout);
app.get('/mind/api/status', (req, res) => {
  void handleMindStatus(req, res);
});
app.get('/mind/api/stream', (req, res) => {
  void handleMindStream(req, res);
});
app.get('/mind/api/docs/:slug', (req, res) => {
  void handleMindDoc(req, res);
});
app.get('/mind/api/handbook', (req, res) => {
  (req.params as Record<string, string>).slug = 'handbook';
  void handleMindDoc(req, res);
});
app.get('/mind/api/people', (req, res) => {
  void handleMindPeopleSearch(req, res);
});
app.get('/mind/api/people/:userId', (req, res) => {
  void handleMindPersonDossier(req, res);
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
      r2PosterResolve: true,
      recsysRank: true,
      recsysWarehouse: true,
      hubsSlugShelves: true,
      performanceMetrics: true,
      remoteConfig: true,
      anonymous: true,
      anonymousPaid: process.env.ANONYMOUS_PAID_ENABLED === 'true',
      videoTranscripts: !!process.env.GROQ_API_KEY?.trim(),
      mindAdminPage: true,
      mindPolicyVersion: MIND_POLICY_VERSION,
    },
    apnsConfigured: apns.isConfigured(),
    authMail: authMailStatus(),
    contentPipeline: getPipelineStatus(),
  })
);

// ─── Video transcripts (Groq Whisper, server-side — keeps the iOS app light) ──
// GET  /v1/transcript/:postId  → { status, text, segments, language, … }
// POST /v1/transcript/:postId/enqueue → queue / re-queue one post
app.get('/v1/transcript/:postId', async (req: Request, res: Response) => {
  try {
    const postId = String(req.params.postId || '').trim();
    const uuidRe =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!uuidRe.test(postId)) return res.status(400).json({ error: 'post_id_required' });
    const { getTranscript } = await import('./media/transcribe.js');
    const row = await getTranscript(postId);
    if (!row) {
      return res.json({
        ok: true,
        post_id: postId,
        status: 'missing',
        text: null,
        segments: null,
      });
    }
    return res.json({
      ok: true,
      post_id: row.post_id,
      status: row.status,
      language: row.language,
      model: row.model,
      text: row.text,
      segments: row.segments,
      error: row.error,
      duration_seconds: row.duration_seconds,
      completed_at: row.completed_at,
    });
  } catch (err: any) {
    console.error('[transcript]', err?.message ?? err);
    return res.status(500).json({ error: 'transcript_failed', message: err?.message ?? 'error' });
  }
});

app.post('/v1/transcript/:postId/enqueue', async (req: Request, res: Response) => {
  try {
    const postId = String(req.params.postId || '').trim();
    const uuidRe =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!uuidRe.test(postId)) return res.status(400).json({ error: 'post_id_required' });
    const { enqueueTranscript, transcriptionConfigured, transcribePost } = await import(
      './media/transcribe.js'
    );
    if (!transcriptionConfigured()) {
      return res.status(503).json({ error: 'transcription_not_configured' });
    }
    // On-demand captions (CC tap). Source `cc` can revive skipped free-tier backlog rows.
    // `force=1` replaces a short/ready row so captions can cover the full film.
    const force =
      req.body?.force === true ||
      req.query.force === '1' ||
      req.query.force === 'true';
    await enqueueTranscript(postId, 'cc', { force });
    const runNow = req.body?.run === true || req.query.run === '1';
    if (runNow) {
      // Async Whisper — never block HTTP. CC extracts up to ~10 min of audio.
      void transcribePost(postId, { mode: 'cc', force }).catch((err) => {
        console.error('[transcript/runNow]', postId, err?.message ?? err);
      });
      return res.json({
        ok: true,
        post_id: postId,
        status: 'processing',
        ran: true,
        async: true,
        mode: 'cc',
        force: !!force,
      });
    }
    return res.json({ ok: true, post_id: postId, status: 'pending', ran: false });
  } catch (err: any) {
    console.error('[transcript/enqueue]', err?.message ?? err);
    return res.status(500).json({ error: 'enqueue_failed', message: err?.message ?? 'error' });
  }
});

// ─── Instant Frame 0 posters from R2 pack path ───────────────────────────────
// GET  /v1/poster/:postId  → { url, key }   (…/frame0_512.webp signed)
// POST /v1/poster/batch    → { posters: { [postId]: url } }
app.get('/v1/poster/:postId', (req, res) => {
  void handlePosterGet(req, res);
});
app.post('/v1/poster/batch', (req, res) => {
  void handlePosterBatch(req, res);
});

// ─── Live R2 playback (never serve a dead signed URL) ─────────────────────────
// GET /v1/playback/:postId → { url, media_url, r2_key }
// Light SQL + resolvePlaybackForPostRow (anonymous OK). Avoid heavy postByIdForViewer.
app.get('/v1/playback/:postId', async (req: Request, res: Response) => {
  try {
    const postId = String(req.params.postId || '').trim();
    const uuidRe =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    if (!uuidRe.test(postId)) return res.status(400).json({ error: 'post_id_required' });

    const { resolvePlaybackForPostRow } = await import('./media/r2-playback.js');
    const { rows } = await pool.query<{
      id: string;
      media_url: string | null;
      media_path: string | null;
      shared_media_url: string | null;
      shared_media_path: string | null;
    }>(
      `
      select
        p.id::text as id,
        p.media_url,
        p.media_path,
        sp.media_url as shared_media_url,
        sp.media_path as shared_media_path
      from public.posts p
      left join public.posts sp on sp.id = p.shared_post_id
      where p.id = $1::uuid
      limit 1
      `,
      [postId]
    );
    const row = rows[0];
    if (!row) return res.status(404).json({ error: 'not_found' });
    const media = await resolvePlaybackForPostRow({
      id: row.id,
      media_url: row.media_url,
      media_path: row.media_path,
      shared_post: row.shared_media_url
        ? { media_url: row.shared_media_url, media_path: row.shared_media_path }
        : null,
    });
    if (!media?.url) return res.status(404).json({ error: 'not_found' });
    return res.json({
      ok: true,
      post_id: postId,
      url: media.url,
      media_url: media.media_url,
      r2_key: media.key || null,
    });
  } catch (err: any) {
    console.error('[playback]', err?.message ?? err);
    return res.status(500).json({ error: 'playback_failed', message: err?.message ?? 'error' });
  }
});

/**
 * Batch freshen play URLs for feed head / Sparks window (CDN edge warm).
 * POST /v1/playback/batch  body: { postIds: string[] }  max 12
 *
 * Fast path (launch-critical):
 * - Anonymous OK (same as GET /v1/playback/:id)
 * - One SQL for media rows (no heavy postByIdForViewer per id)
 * - Cap concurrent R2 presigns; hard wall-clock so iOS 3.5s clients get partial OK
 */
app.post('/v1/playback/batch', async (req: Request, res: Response) => {
  const started = Date.now();
  try {
    const raw: unknown[] = Array.isArray(req.body?.postIds) ? req.body.postIds : [];
    const uuidRe =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    const postIds: string[] = [
      ...new Set(
        raw
          .map((x) => String(x ?? '').trim())
          .filter((s): s is string => uuidRe.test(s))
      ),
    ].slice(0, 12);
    if (postIds.length === 0) return res.json({ ok: true, items: [], count: 0 });

    const { resolvePlaybackForPostRow } = await import('./media/r2-playback.js');
    const { rows } = await pool.query<{
      id: string;
      media_url: string | null;
      media_path: string | null;
      shared_media_url: string | null;
      shared_media_path: string | null;
    }>(
      `
      select
        p.id::text as id,
        p.media_url,
        p.media_path,
        sp.media_url as shared_media_url,
        sp.media_path as shared_media_path
      from public.posts p
      left join public.posts sp on sp.id = p.shared_post_id
      where p.id = any($1::uuid[])
      `,
      [postIds]
    );

    const byId = new Map(rows.map((r) => [r.id, r]));
    const items: Array<{ id: string; url: string; r2_key: string | null }> = [];
    const WALL_MS = 2200;
    const CONCURRENCY = 4;
    let cursor = 0;

    async function worker(): Promise<void> {
      while (cursor < postIds.length) {
        if (Date.now() - started > WALL_MS) return;
        const i = cursor++;
        const id = postIds[i];
        const row = byId.get(id);
        if (!row) continue;
        try {
          const media = await resolvePlaybackForPostRow({
            id: row.id,
            media_url: row.media_url,
            media_path: row.media_path,
            shared_post: row.shared_media_url
              ? { media_url: row.shared_media_url, media_path: row.shared_media_path }
              : null,
          });
          if (!media?.url) continue;
          items.push({ id, url: media.url, r2_key: media.key || null });
        } catch {
          // skip bad row
        }
      }
    }

    await Promise.all(
      Array.from({ length: Math.min(CONCURRENCY, postIds.length) }, () => worker())
    );

    return res.json({
      ok: true,
      items,
      count: items.length,
      partial: items.length < postIds.length,
      ms: Date.now() - started,
    });
  } catch (err: any) {
    console.error('[playback/batch]', err?.message ?? err);
    return res.status(500).json({ error: 'playback_batch_failed', message: err?.message ?? 'error' });
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
    const birthdate = req.body?.birthdate;
    const result = await signupWithMatteryaEmail(
      email === undefined || email === null ? '' : String(email),
      password,
      birthdate
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

/** Text-moderation REVIEW/HELD/LIMITED queue (requires moderation_results migration). */
app.get('/admin/moderation/queue', async (req: Request, res: Response) => {
  if (!hasAdminAccess(req)) return res.status(401).json({ error: 'unauthorized' });
  try {
    const { listModerationQueue } = await import('./moderation/index.js');
    const limit = Number(req.query.limit ?? 40);
    return res.json({ ok: true, items: await listModerationQueue(limit) });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'failed' });
  }
});

app.get('/admin/moderation/metrics', async (req: Request, res: Response) => {
  if (!hasAdminAccess(req)) return res.status(401).json({ error: 'unauthorized' });
  try {
    const { moderationMetricsSnapshot } = await import('./moderation/index.js');
    return res.json(moderationMetricsSnapshot());
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
    const sessionId = req.body?.sessionId ?? null;
    const result = await ingestEngagementBatch({
      entityId: user.id,
      sessionId,
      events: Array.isArray(req.body?.events) ? req.body.events : [],
    });
    // Keep online features warm while users scroll (async — never block the client).
    if (result.accepted > 0) {
      void refreshUserFeatures(user.id).catch(() => {});
      bustSessionCache(user.id, sessionId);
    }
    return res.json({ ok: true, ...result });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'engagement_ingest_failed' });
  }
});

// ── MIND Phase 3b/4 user surfaces ───────────────────────────────────────────
// Interest controls (MIND-019)
app.get('/v1/me/interests', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  if (!user?.id) return res.status(401).json({ error: 'unauthenticated' });
  try {
    const snapshot = await getInterestSnapshot(user.id);
    return res.json({ ok: true, ...snapshot });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'interests_failed' });
  }
});

app.patch('/v1/me/interests', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  if (!user?.id) return res.status(401).json({ error: 'unauthenticated' });
  try {
    const controls = await patchInterestControls(user.id, {
      mutedHubs: req.body?.mutedHubs,
      mutedCreators: req.body?.mutedCreators,
      boostedTopics: req.body?.boostedTopics,
      chronoPreferred: req.body?.chronoPreferred,
      mode: req.body?.mode === 'replace' ? 'replace' : 'merge',
    });
    return res.json({ ok: true, controls });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'interests_patch_failed' });
  }
});

app.post('/v1/me/interests/reset', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  if (!user?.id) return res.status(401).json({ error: 'unauthenticated' });
  try {
    await resetInterestControls(user.id);
    return res.json({ ok: true, reset: true });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'interests_reset_failed' });
  }
});

app.get('/v1/recommendation/why', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  if (!user?.id) return res.status(401).json({ error: 'unauthenticated' });
  const requestId = String(req.query.requestId ?? '').trim();
  if (!requestId) return res.status(400).json({ error: 'requestId_required' });
  const explained = await explainDecision({ requestId, entityId: user.id });
  const status = explained.ok ? 200 : explained.error === 'forbidden' ? 403 : 404;
  return res.status(status).json(explained);
});

// Hybrid search (MIND-020)
app.get('/v1/search', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  const q = String(req.query.q ?? req.query.query ?? '').trim();
  const limit = Math.min(Math.max(Number(req.query.limit) || 20, 1), 100);
  const offset = Math.min(Math.max(Number(req.query.offset) || 0, 0), 400);
  try {
    const result = await hybridSearch({
      query: q,
      limit,
      offset,
      viewerId: user?.id ?? null,
    });
    return res.json({ ok: true, ...result });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'search_failed' });
  }
});

// People discovery (MIND-021)
app.get('/v1/people/suggest', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  const limit = Number(req.query.limit) || 12;
  const countryCode = String(req.query.country ?? req.query.countryCode ?? '').trim() || null;
  try {
    const people = await suggestPeople({
      viewerId: user?.id ?? null,
      limit,
      countryCode,
    });
    return res.json({ ok: true, people });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'people_suggest_failed' });
  }
});

// World / country (MIND-022)
app.get('/v1/world/country/:code', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  const code = String(req.params.code ?? '').trim();
  const limit = Number(req.query.limit) || 24;
  const sessionId = String(req.query.session ?? '').trim() || null;
  try {
    const result = await worldCountryFeed({
      countryCode: code,
      limit,
      viewerId: user?.id ?? null,
      sessionId,
    });
    return res.json({ ok: true, ...result });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'world_country_failed' });
  }
});

// Creator insights (MIND-025) — owner only
app.get('/v1/creator/insights', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  if (!user?.id) return res.status(401).json({ error: 'unauthenticated' });
  try {
    const insights = await getCreatorInsights(user.id);
    return res.json({ ok: true, insights });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'creator_insights_failed' });
  }
});

// ─── Hubs slug shelves (thin cards — light client) ───────────────────────────
// GET /v1/hubs/for-you?limit=20&cursor=&session=
// GET /v1/hubs/shelves/:slug?limit=20&cursor=
// GET /v1/hubs/slugs

app.get('/v1/hubs/slugs', (_req: Request, res: Response) => {
  res.json({
    ok: true,
    slugs: [...HUB_PARENT_SLUGS],
    neighbors: Object.fromEntries(
      HUB_PARENT_SLUGS.map((s) => [s, neighborSlug(s)])
    ),
  });
});

app.get('/v1/hubs/for-you', async (req: Request, res: Response) => {
  try {
    const user = await getUserFromRequest(req).catch(() => null);
    // Raised so clients can page toward full LongForm inventory (~1.9k).
    const limit = Math.min(Math.max(Number(req.query.limit) || 20, 1), 80);
    const cursor = req.query.cursor ? String(req.query.cursor) : null;
    const session = req.query.session ? String(req.query.session) : null;
    const idempotencyKey = req.query.idempotencyKey
      ? String(req.query.idempotencyKey)
      : req.query.idempotency_key
        ? String(req.query.idempotency_key)
        : null;
    const page = await fetchForYouPage({
      limit,
      cursor,
      session,
      viewerUserId: user?.id ?? null,
      idempotencyKey,
    });
    return res.json({ ok: true, ...page });
  } catch (err: any) {
    console.error('[hubs/for-you]', err?.message ?? err);
    return res.status(500).json({
      error: 'hubs_for_you_failed',
      message: err?.message ?? 'error',
    });
  }
});

app.get('/v1/hubs/shelves/:slug', async (req: Request, res: Response) => {
  try {
    await getUserFromRequest(req).catch(() => null);
    const slug = String(req.params.slug || '').trim();
    if (!slug) return res.status(400).json({ error: 'slug_required' });
    const limit = Math.min(Math.max(Number(req.query.limit) || 20, 1), 80);
    const cursor = req.query.cursor ? String(req.query.cursor) : null;
    const page = await fetchShelfPage({ slug, limit, cursor });
    return res.json({ ok: true, ...page });
  } catch (err: any) {
    console.error('[hubs/shelves]', err?.message ?? err);
    return res.status(500).json({
      error: 'hubs_shelf_failed',
      message: err?.message ?? 'error',
    });
  }
});

// ─── Butter-smooth: metrics + remote config ─────────────────────────────────
// POST /v1/metrics/batch
// GET  /v1/metrics/summary  (ops; protect later with cron secret if public abuse)
// GET  /v1/config?v=

app.post('/v1/metrics/batch', async (req: Request, res: Response) => {
  try {
    // Auth optional — cold start may fire before token.
    await getUserFromRequest(req).catch(() => null);
    const result = ingestMetricBatch(req.body ?? {});
    return res.json({ ok: true, ...result });
  } catch (err: any) {
    console.error('[metrics/batch]', err?.message ?? err);
    return res.status(500).json({ error: 'metrics_ingest_failed' });
  }
});

function metricsReadAuthorized(req: Request): boolean {
  const secret =
    process.env.METRICS_SUMMARY_SECRET?.trim() ||
    process.env.CONTENT_CRON_SECRET?.trim() ||
    '';
  const header = String(req.headers['x-cron-secret'] ?? '').trim();
  const queryKey = String(req.query.key ?? '').trim();
  if (secret && (header === secret || queryKey === secret)) return true;
  return false;
}

app.get('/v1/metrics/summary', async (req: Request, res: Response) => {
  try {
    const user = await getUserFromRequest(req).catch(() => null);
    if (!user?.id && !metricsReadAuthorized(req)) {
      return res.status(401).json({ error: 'unauthorized' });
    }
    return res.json({ ok: true, ...metricsSummary() });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'summary_failed' });
  }
});

/** Clear in-memory milestone ring (stale p95 after telemetry fixes). Secret required. */
app.post('/v1/metrics/reset', async (req: Request, res: Response) => {
  try {
    if (!metricsReadAuthorized(req)) {
      return res.status(401).json({ error: 'unauthorized' });
    }
    const result = resetMetrics();
    return res.json({ ok: true, ...result });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'reset_failed' });
  }
});

/** Prometheus text — Grafana Cloud / Infinity / scrape. Same auth as summary. */
app.get('/v1/metrics/prometheus', async (req: Request, res: Response) => {
  try {
    const user = await getUserFromRequest(req).catch(() => null);
    if (!user?.id && !metricsReadAuthorized(req)) {
      return res.status(401).json({ error: 'unauthorized' });
    }
    res.setHeader('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
    return res.status(200).send(metricsPrometheusText());
  } catch (err: any) {
    return res.status(500).type('text').send(`# error ${err?.message ?? 'failed'}\n`);
  }
});

app.get('/v1/config', async (req: Request, res: Response) => {
  try {
    const clientV = req.query.v != null ? String(req.query.v) : null;
    const cfg = getRemoteConfig(clientV);
    if (cfg.unchanged) {
      return res.json({
        ok: true,
        unchanged: true,
        version: cfg.version,
        ttlSec: cfg.ttlSec,
      });
    }
    return res.json({
      ok: true,
      unchanged: false,
      version: cfg.version,
      ttlSec: cfg.ttlSec,
      flags: cfg.flags,
    });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'config_failed' });
  }
});

// ─── App-wide thin surfaces (same card shape as Hubs shelves) ────────────────
// GET /v1/feed?limit=24&cursor=
// GET /v1/sparks?limit=20&cursor=&slug=

app.get('/v1/feed', async (req: Request, res: Response) => {
  try {
    const user = await getUserFromRequest(req).catch(() => null);
    const limit = Math.min(Math.max(Number(req.query.limit) || 24, 1), 48);
    const cursor = req.query.cursor ? String(req.query.cursor) : null;
    const idempotencyKey = req.query.idempotencyKey
      ? String(req.query.idempotencyKey)
      : req.query.idempotency_key
        ? String(req.query.idempotency_key)
        : null;
    const session = req.query.session ? String(req.query.session) : null;
    const page = await fetchHomeFeedPage({
      limit,
      cursor,
      viewerUserId: user?.id ?? null,
      idempotencyKey,
      session,
    });
    return res.json({ ok: true, ...page });
  } catch (err: any) {
    console.error('[feed]', err?.message ?? err);
    return res.status(500).json({
      error: 'feed_page_failed',
      message: err?.message ?? 'error',
    });
  }
});

app.get('/v1/sparks', async (req: Request, res: Response) => {
  try {
    const user = await getUserFromRequest(req).catch(() => null);
    const limit = Math.min(Math.max(Number(req.query.limit) || 20, 1), 40);
    const cursor = req.query.cursor ? String(req.query.cursor) : null;
    const slug = req.query.slug ? String(req.query.slug) : null;
    // Client can pass exclude=id,id,… (watched / already in pager) for endless unwatched.
    const excludeRaw = req.query.exclude != null ? String(req.query.exclude) : '';
    const excludeIds = excludeRaw
      .split(/[, ]+/)
      .map((s) => s.trim())
      .filter(Boolean)
      .slice(0, 800);
    const page = await fetchSparksPage({
      limit,
      cursor,
      slug,
      viewerUserId: user?.id ?? null,
      excludeIds,
    });
    return res.json({ ok: true, ...page });
  } catch (err: any) {
    console.error('[sparks]', err?.message ?? err);
    return res.status(500).json({
      error: 'sparks_page_failed',
      message: err?.message ?? 'error',
    });
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

/** Rebuild cosine-KNN neighbors for the caller (ops / after heavy engagement). */
app.post('/v1/recommendation/rebuild-neighbors', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  if (!user?.id) return res.status(401).json({ error: 'unauthenticated' });
  try {
    const k = Number(req.body?.k ?? 40);
    const out = await rebuildNeighborsForEntity(user.id, k);
    return res.json({ ok: true, neighbors: out.neighbors });
  } catch (err: any) {
    return res.status(500).json({ error: err?.message ?? 'knn_failed' });
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
/**
 * Catch-up: embed Public posts missing voyage-4-lite vectors.
 * Auth: CONTENT_CRON_SECRET or INSIGHTS_CRON_SECRET (same as content-pipeline).
 * Cron: POST /cron/mind-embeddings?limit=400
 *        Header: x-cron-secret: …
 * New uploads/seeds also schedule embeds inline — this only fills gaps.
 */
app.post('/cron/mind-embeddings', async (req: Request, res: Response) => {
  const secret = req.headers['x-cron-secret'] || req.query.secret;
  const expected =
    process.env.CONTENT_CRON_SECRET?.trim() ||
    process.env.INSIGHTS_CRON_SECRET?.trim() ||
    INSIGHTS_CRON_SECRET;
  if (!expected || String(secret ?? '') !== expected) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  try {
    const rawLimit = Number(req.query.limit ?? req.body?.limit ?? 400);
    const rawBatch = Number(req.query.batchSize ?? req.body?.batchSize ?? 64);
    const limit =
      Number.isFinite(rawLimit) && rawLimit > 0 ? Math.min(rawLimit, 5000) : 400;
    const batchSize =
      Number.isFinite(rawBatch) && rawBatch > 0 ? Math.min(rawBatch, 128) : 64;
    const out = await backfillEmbeddings({ limit, batchSize });
    return res.json({ ok: true, ...out, limit, batchSize });
  } catch (err: any) {
    console.error('[cron/mind-embeddings]', err?.message ?? err);
    return res.status(500).json({ error: err?.message ?? 'embed_catchup_failed' });
  }
});

/**
 * Catch-up: Sparks multimodal thumb embeds (voyage-multimodal-3.5).
 * Auth: same cron secret as content-pipeline / mind-embeddings.
 * Cron: POST /cron/mind-multimodal?limit=200
 * New Sparks also schedule inline — this fills the historical library.
 */
app.post('/cron/mind-multimodal', async (req: Request, res: Response) => {
  const secret = req.headers['x-cron-secret'] || req.query.secret;
  const expected =
    process.env.CONTENT_CRON_SECRET?.trim() ||
    process.env.INSIGHTS_CRON_SECRET?.trim() ||
    INSIGHTS_CRON_SECRET;
  if (!expected || String(secret ?? '') !== expected) {
    return res.status(401).json({ error: 'unauthorized' });
  }
  try {
    const rawLimit = Number(req.query.limit ?? req.body?.limit ?? 200);
    const limit =
      Number.isFinite(rawLimit) && rawLimit > 0 ? Math.min(rawLimit, 2000) : 200;
    const out = await backfillMultimodal({ limit });
    return res.json({ ok: true, ...out, limit });
  } catch (err: any) {
    console.error('[cron/mind-multimodal]', err?.message ?? err);
    return res.status(500).json({ error: err?.message ?? 'multimodal_catchup_failed' });
  }
});

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
