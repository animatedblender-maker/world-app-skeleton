import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import { createYoga, createSchema } from 'graphql-yoga';
import { jwtVerify, createRemoteJWKSet } from 'jose';

// ✅ ts-node --esm on Windows needs explicit ".ts"
import { typeDefs } from './graphql/typeDefs.ts';
import { resolvers } from './graphql/resolvers.ts';

type AuthedUser = {
  id: string;
  email?: string;
  role?: string;
  aud?: string | string[];
};

type Context = {
  user: AuthedUser | null;
  req: express.Request;
};

const ORIGIN = process.env.WEB_ORIGIN ?? 'http://localhost:4200';
const PORT = Number(process.env.PORT ?? 3000);

const SUPABASE_URL = process.env.SUPABASE_URL;

if (!SUPABASE_URL) {
  console.warn('⚠️ SUPABASE_URL not set. JWT verification will fail until you set it.');
}

const JWKS =
  SUPABASE_URL
    ? createRemoteJWKSet(new URL(`${SUPABASE_URL}/auth/v1/.well-known/jwks.json`))
    : null;

async function getUserFromRequest(req: express.Request): Promise<AuthedUser | null> {
  try {
    const authHeader = req.headers.authorization ?? '';
    const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;

    if (!token || !JWKS) return null;

    const { payload } = await jwtVerify(token, JWKS, {});
    return {
      id: String(payload.sub),
      email: typeof payload['email'] === 'string' ? payload['email'] : undefined,
      role: typeof payload['role'] === 'string' ? payload['role'] : undefined,
      aud: typeof payload['aud'] === 'string' || Array.isArray(payload['aud']) ? payload['aud'] : undefined,
    };
  } catch {
    return null;
  }
}

const yoga = createYoga<Context>({
  schema: createSchema({ typeDefs, resolvers }),
  graphqlEndpoint: '/graphql',
  context: async ({ req }) => ({
    req: req as any,
    user: await getUserFromRequest(req as any),
  }),
});

const app = express();

app.use(
  cors({
    origin: ORIGIN,
    credentials: true,
  })
);

app.use('/graphql', yoga);

app.listen(PORT, () => {
  console.log(`✅ GraphQL running at http://localhost:${PORT}/graphql`);
  console.log(`✅ CORS origin allowed: ${ORIGIN}`);
});
