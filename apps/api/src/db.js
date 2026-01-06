import pg from 'pg';
import 'dotenv/config';
const { Pool } = pg;
const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) {
    console.warn('⚠️ DATABASE_URL is not set. Postgres queries will fail until you set it.');
}
export const pool = new Pool({
    connectionString: DATABASE_URL,
    // optional: for Supabase you usually need SSL in production, but local dev varies
    ssl: process.env.PGSSLMODE === 'require' ? { rejectUnauthorized: false } : undefined,
});
