import { Pool, PoolClient } from 'pg';

export type DbUserClaims = {
  sub: string;             // user id
  email?: string;
  role?: string;           // usually "authenticated"
  aud?: string | string[];
  [k: string]: unknown;
};

const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) {
  throw new Error('Missing DATABASE_URL in apps/api/.env');
}

// Pool = scalable, reuses connections
export const pool = new Pool({
  connectionString: DATABASE_URL,
  max: 10, // adjust later
  idleTimeoutMillis: 30_000,
});

async function setRlsContext(client: PoolClient, claims: DbUserClaims | null) {
  // Always reset to a safe baseline
  // "anon" means policies that require authenticated won't apply
  await client.query(`select set_config('role', 'anon', true);`);
  await client.query(`select set_config('request.jwt.claims', '{}', true);`);

  if (!claims) return;

  // In Supabase, auth.uid() reads request.jwt.claims->>'sub'
  const claimsJson = JSON.stringify(claims);

  await client.query(`select set_config('request.jwt.claims', $1, true);`, [claimsJson]);
  await client.query(`select set_config('role', 'authenticated', true);`);
}

export async function withRls<T>(
  claims: DbUserClaims | null,
  fn: (client: PoolClient) => Promise<T>
): Promise<T> {
  const client = await pool.connect();

  try {
    // One transaction per request is the cleanest way to guarantee "set local" behavior.
    await client.query('begin;');

    await setRlsContext(client, claims);

    const result = await fn(client);

    await client.query('commit;');
    return result;
  } catch (err) {
    try {
      await client.query('rollback;');
    } catch {
      // ignore rollback errors
    }
    throw err;
  } finally {
    client.release();
  }
}
