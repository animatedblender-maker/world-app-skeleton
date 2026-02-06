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
dotenv.config({ path: path.join(__dirname, '..', '.env') });

// ✅ ts-node --esm on Windows needs explicit ".ts"
import { typeDefs } from './graphql/typeDefs.js';
import { resolvers } from './graphql/resolvers.js';
import { PushService } from './push/push.service.js';
import { pool } from './db.js';

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
        ['HANDLE_TAKEN', 'UNAUTHENTICATED'].includes(code);
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
const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });
const socketsByUser = new Map<string, Set<any>>();

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
app.get('/health', (_req: Request, res: Response) => res.json({ ok: true }));

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

app.post('/livekit/token', async (req: Request, res: Response) => {
  const user = await getUserFromRequest(req);
  if (!user?.id) return res.status(401).json({ error: 'unauthenticated' });
  const room = String(req.body?.room ?? '').trim();
  if (!room) return res.status(400).json({ error: 'missing_room' });
  if (!LIVEKIT_API_KEY || !LIVEKIT_API_SECRET) {
    return res.status(500).json({ error: 'livekit_not_configured' });
  }
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
    .setSubject(user.id)
    .setIssuedAt()
    .setExpirationTime('1h')
    .sign(new TextEncoder().encode(LIVEKIT_API_SECRET));
  return res.json({ token: jwt, url: LIVEKIT_URL ?? '' });
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
        await Promise.all(
          notifyTargets.map((memberId) =>
            push.sendToUser(memberId, {
              title: callerName,
              body: `Incoming ${kind.toLowerCase()}.`,
              url: `/messages?c=${conversationId}&call=${callParam}&from=${user.id}`,
              tag: `call:${conversationId}`,
            })
          )
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
});
