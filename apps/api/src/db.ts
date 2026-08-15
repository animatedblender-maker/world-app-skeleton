import pg from 'pg';
import dotenv from 'dotenv';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Load apps/api/.env even when process.cwd() is the monorepo root.
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '..', '.env'), override: true });

const { Pool } = pg;

// ✅ IMPORTANT (ESM):
// PoolClient is a TypeScript type, NOT a runtime export in ESM.
// So we import it as type-only (no runtime import).
export type PoolClient = pg.PoolClient;

const DATABASE_URL = process.env.DATABASE_URL?.trim() || '';

if (!DATABASE_URL) {
  console.warn(
    '⚠️ DATABASE_URL is not set. Postgres queries will fail until you set it.\n' +
      '   → apps/api/.env  (uncomment and fill DATABASE_URL from Supabase → Settings → Database)\n' +
      '   Example:\n' +
      '   DATABASE_URL=postgresql://postgres.bpdkltgikgbnfjswdbaj:YOUR_PASSWORD@aws-1-eu-north-1.pooler.supabase.com:5432/postgres\n' +
      '   PGSSLMODE=require'
  );
}

// When DATABASE_URL is missing, pg would default to localhost:5432 and crash workers.
// Use a dummy URL that fails fast with a clear error only when queried.
export const pool = new Pool({
  connectionString:
    DATABASE_URL || 'postgresql://postgres:postgres@127.0.0.1:1/postgres',
  // optional: for Supabase you usually need SSL in production, but local dev varies
  ssl:
    process.env.PGSSLMODE === 'require' || DATABASE_URL.includes('supabase')
      ? { rejectUnauthorized: false }
      : undefined,
  // Supabase pooler: keep modest. Too low (4) + concurrent GraphQL → "timeout exceeded when trying to connect".
  max: Number(process.env.DB_POOL_MAX ?? 10),
  idleTimeoutMillis: Number(process.env.DB_IDLE_TIMEOUT_MS ?? 15000),
  connectionTimeoutMillis: Number(process.env.DB_CONNECT_TIMEOUT_MS ?? 12000),
  allowExitOnIdle: false,
});

pool.on('error', (err) => {
  console.warn('[pg] idle client error:', err.message);
});
