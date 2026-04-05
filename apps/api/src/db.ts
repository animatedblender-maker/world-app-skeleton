import pg from 'pg';
import 'dotenv/config';

const { Pool } = pg;

// ✅ IMPORTANT (ESM):
// PoolClient is a TypeScript type, NOT a runtime export in ESM.
// So we import it as type-only (no runtime import).
export type PoolClient = pg.PoolClient;

const DATABASE_URL = process.env.DATABASE_URL;

if (!DATABASE_URL) {
  console.warn('⚠️ DATABASE_URL is not set. Postgres queries will fail until you set it.');
}

export const pool = new Pool({
  connectionString: DATABASE_URL,
  // optional: for Supabase you usually need SSL in production, but local dev varies
  ssl: process.env.PGSSLMODE === 'require' ? { rejectUnauthorized: false } : undefined,
  max: Number(process.env.DB_POOL_MAX ?? 4),
  idleTimeoutMillis: Number(process.env.DB_IDLE_TIMEOUT_MS ?? 10000),
  connectionTimeoutMillis: Number(process.env.DB_CONNECT_TIMEOUT_MS ?? 5000),
});
