import express, { type Request, type Response } from 'express';
import cors from 'cors';
import { GraphQLError } from 'graphql';
import { createYoga, createSchema, maskError as yogaMaskError } from 'graphql-yoga';
import type { YogaInitialContext, YogaSchemaDefinition } from 'graphql-yoga';
import { jwtVerify, createRemoteJWKSet } from 'jose';

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

app.use('/graphql', (req: Request, res: Response) => {
  return yoga.handle(req, res);
});

app.listen(PORT, () => {
  console.log(`✅ GraphQL running at http://localhost:${PORT}/graphql`);
  console.log(`✅ Health at        http://localhost:${PORT}/health`);
  console.log(`✅ CORS origins allowed: ${ALLOWED_ORIGINS.join(', ')}`);
});
