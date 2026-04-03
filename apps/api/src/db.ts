import pg from 'pg';
import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';

const { Pool } = pg;

// ✅ IMPORTANT (ESM):
// PoolClient is a TypeScript type, NOT a runtime export in ESM.
// So we import it as type-only (no runtime import).
export type PoolClient = pg.PoolClient;

const DATABASE_URL = process.env.DATABASE_URL;
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!DATABASE_URL) {
  console.warn('⚠️ DATABASE_URL is not set. Postgres queries will fail until you set it.');
}

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.warn('⚠️ Supabase admin client is not fully configured. Service-role reads may fail.');
}

export const pool = new Pool({
  connectionString: DATABASE_URL,
  // optional: for Supabase you usually need SSL in production, but local dev varies
  ssl: process.env.PGSSLMODE === 'require' ? { rejectUnauthorized: false } : undefined,
});

export const supabaseAdmin =
  SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY
    ? createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
        auth: { persistSession: false, autoRefreshToken: false },
      })
    : null;

type RequestRole = 'authenticated' | 'anon';

type RequestContext = {
  userId?: string | null;
  role?: RequestRole;
};

export async function withRequestContext<T>(
  context: RequestContext,
  fn: (client: PoolClient) => Promise<T>
): Promise<T> {
  const client = await pool.connect();
  const role = context.role ?? (context.userId ? 'authenticated' : 'anon');
  const claims = {
    role,
    sub: context.userId ?? null,
  };

  try {
    await client.query('begin');

    // Match the claim shape Supabase policies expect when they call auth.uid()/auth.role().
    await client.query(`select set_config('request.jwt.claims', $1, true)`, [JSON.stringify(claims)]);
    await client.query(`select set_config('request.jwt.claim.role', $1, true)`, [role]);
    await client.query(`select set_config('request.jwt.claim.sub', $1, true)`, [context.userId ?? '']);

    // Some Supabase RLS setups also key off the active DB role.
    try {
      await client.query(`set local role ${role}`);
    } catch {
      // Ignore if the connection user is not allowed to switch roles.
    }

    const result = await fn(client);
    await client.query('commit');
    return result;
  } catch (err) {
    await client.query('rollback');
    throw err;
  } finally {
    client.release();
  }
}
