import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import { createYoga, createSchema } from 'graphql-yoga';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { jwtVerify, createRemoteJWKSet } from 'jose';

type AuthedUser = {
  id: string;
  email?: string;
  role?: string;
  aud?: string | string[];
};

type Context = {
  user: AuthedUser | null;
  token: string | null;
  req: express.Request;
};

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const ORIGIN = process.env.WEB_ORIGIN ?? 'http://localhost:4200';
const PORT = Number(process.env.PORT ?? 3000);

// apps/api/.env should contain:
// SUPABASE_URL=https://xxxxx.supabase.co
// SUPABASE_ANON_KEY=xxxxx
// WEB_ORIGIN=http://localhost:4200
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY;

if (!SUPABASE_URL) {
  console.warn('⚠️ SUPABASE_URL not set. JWT verification will fail until you set it.');
}
if (!SUPABASE_ANON_KEY) {
  console.warn('⚠️ SUPABASE_ANON_KEY not set. PostgREST calls will fail until you set it.');
}

const JWKS =
  SUPABASE_URL
    ? createRemoteJWKSet(new URL(`${SUPABASE_URL}/auth/v1/.well-known/jwks.json`))
    : null;

function getBearerToken(req: express.Request): string | null {
  const authHeader = req.headers.authorization ?? '';
  return authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
}

async function getUserFromRequest(req: express.Request): Promise<AuthedUser | null> {
  try {
    const token = getBearerToken(req);
    console.log('AUTH HEADER:', req.headers.authorization ? 'present' : 'missing');

    if (!token || !JWKS) return null;

    const { payload } = await jwtVerify(token, JWKS, {
      // audience: 'authenticated', // enable if you hit audience errors later
    });

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

function requireAuth(ctx: Context): AuthedUser {
  if (!ctx.user) throw new Error('UNAUTHENTICATED');
  return ctx.user;
}

/**
 * ✅ Minimal helper so your resolvers can enforce auth consistently.
 * We keep it simple: auth check only.
 * DB-level security is handled by RLS via user's JWT in PostgREST calls.
 */
async function withRls<T>(ctx: Context, fn: (u: AuthedUser) => Promise<T> | T): Promise<T> {
  const u = requireAuth(ctx);
  return await fn(u);
}

/**
 * PostgREST helper that:
 * - uses anon key as apikey
 * - uses user's JWT as Authorization (so RLS applies)
 */
async function pgrest<T>(ctx: Context, path: string, init?: RequestInit): Promise<T> {
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) throw new Error('SUPABASE_NOT_CONFIGURED');
  if (!ctx.token) throw new Error('UNAUTHENTICATED');

  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SUPABASE_ANON_KEY,
      authorization: `Bearer ${ctx.token}`,
      'content-type': 'application/json',
      ...(init?.headers ?? {}),
    },
  });

  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`DB_ERROR ${res.status}: ${text || res.statusText}`);
  }

  const txt = await res.text();
  return (txt ? JSON.parse(txt) : null) as T;
}

/* -------------------------
   Countries loader
   ------------------------- */
type Country = {
  id: string;
  name: string;
  iso: string;
  continent?: string;
  center?: { lat: number; lng: number };
};

type CountriesPayload = {
  countries: Country[];
};

function loadCountriesFromGeoJSON(): CountriesPayload {
  // Adjust if your file lives elsewhere
  const geoPath = join(process.cwd(), 'src', 'data', 'countries50m.geojson');

  if (!existsSync(geoPath)) {
    throw new Error(
      `GeoJSON not found at: ${geoPath}\nCopy: apps/web/public/countries50m.geojson -> apps/api/src/data/countries50m.geojson`
    );
  }

  const raw = readFileSync(geoPath, 'utf-8');
  const json = JSON.parse(raw);

  const countries: Country[] = (json.features ?? []).map((f: any, idx: number) => {
    const props = f.properties ?? {};
    const name = props.ADMIN ?? props.NAME ?? `Country ${idx}`;
    const iso = props.ISO_A2 ?? props.ADM0_A3 ?? props.ISO3 ?? 'XX';

    return {
      id: String(idx),
      name,
      iso,
      continent: props.CONTINENT ?? props.REGION_UN ?? 'Unknown',
      center:
        props.LABEL_Y != null && props.LABEL_X != null
          ? { lat: Number(props.LABEL_Y), lng: Number(props.LABEL_X) }
          : undefined,
    };
  });

  return { countries };
}

/* -------------------------
   Schema + Resolvers
   ------------------------- */
const typeDefs = /* GraphQL */ `
  type LatLng {
    lat: Float!
    lng: Float!
  }

  type Country {
    id: ID!
    name: String!
    iso: String!
    continent: String
    center: LatLng
  }

  type CountriesPayload {
    countries: [Country!]!
  }

  type Me {
    id: ID!
    email: String
    role: String
  }

  type Profile {
    user_id: ID!
    email: String
    display_name: String
    username: String
    avatar_url: String
    country_name: String!
    country_code: String
    city_name: String
    bio: String
    created_at: String!
    updated_at: String!
  }

  input UpdateProfileInput {
    display_name: String
    username: String
    avatar_url: String
    country_name: String
    country_code: String
    city_name: String
    bio: String
  }

  type Query {
    countries: CountriesPayload!
    me: Me
    meProfile: Profile
    privatePing: String!
  }

  type Mutation {
    updateProfile(input: UpdateProfileInput!): Profile!
  }
`;

const resolvers = {
  Query: {
    countries: () => loadCountriesFromGeoJSON(),

    me: (_: any, __: any, ctx: Context) => {
      if (!ctx.user) return null;
      return { id: ctx.user.id, email: ctx.user.email, role: ctx.user.role };
    },

    privatePing: async (_: any, __: any, ctx: Context) => {
      return withRls(ctx, async (u) => `pong (authed as ${u.id})`);
    },

    meProfile: async (_: any, __: any, ctx: Context) => {
      return withRls(ctx, async (u) => {
        const rows = await pgrest<any[]>(
          ctx,
          `profiles?select=*&user_id=eq.${encodeURIComponent(u.id)}&limit=1`
        );
        return rows?.[0] ?? null;
      });
    },
  },

  Mutation: {
    updateProfile: async (_: any, args: any, ctx: Context) => {
      return withRls(ctx, async (u) => {
        const input = args?.input ?? {};

        // Patch (RLS enforces "only my row")
        const patched = await pgrest<any[]>(
          ctx,
          `profiles?user_id=eq.${encodeURIComponent(u.id)}`,
          {
            method: 'PATCH',
            headers: { Prefer: 'return=representation' },
            body: JSON.stringify({
              display_name: input.display_name ?? undefined,
              username: input.username ?? undefined,
              avatar_url: input.avatar_url ?? undefined,
              country_name: input.country_name ?? undefined,
              country_code: input.country_code ?? undefined,
              city_name: input.city_name ?? undefined,
              bio: input.bio ?? undefined,
            }),
          }
        );

        // PostgREST PATCH with Prefer usually returns the updated row(s)
        if (patched?.[0]) return patched[0];

        // Fallback fetch (in case response is empty)
        const rows = await pgrest<any[]>(
          ctx,
          `profiles?select=*&user_id=eq.${encodeURIComponent(u.id)}&limit=1`
        );
        if (!rows?.[0]) throw new Error('PROFILE_NOT_FOUND');
        return rows[0];
      });
    },
  },
};

const yoga = createYoga<Context>({
  schema: createSchema({ typeDefs, resolvers }),
  graphqlEndpoint: '/graphql',
  context: async ({ req }) => ({
    req: req as any,
    token: getBearerToken(req as any),
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
