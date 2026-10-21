import { pool } from '../db.js';

/** Append-only audit row. Never store account_id or vault link payloads. */
export async function writeAnonymousAudit(input: {
  actor?: string | null;
  action: string;
  target?: string | null;
  purpose?: string | null;
  meta?: Record<string, unknown>;
}): Promise<void> {
  try {
    await pool.query(
      `
      insert into security.audit_events (actor, action, target, purpose, meta)
      values ($1, $2, $3, $4, $5::jsonb)
      `,
      [
        input.actor ?? null,
        input.action,
        input.target ?? null,
        input.purpose ?? null,
        JSON.stringify(input.meta ?? {}),
      ]
    );
  } catch (err: any) {
    // Don't fail the product path if audit table isn't migrated yet.
    console.warn('[anonymous/audit]', err?.message ?? err);
  }
}

/** Best-effort outbox enqueue for async fanout (notifications/index). */
export async function enqueueAnonymousOutbox(
  type: string,
  payload: Record<string, unknown>
): Promise<void> {
  try {
    await pool.query(
      `
      insert into ops.outbox (type, payload, state)
      values ($1, $2::jsonb, 'pending')
      `,
      [type, JSON.stringify(payload)]
    );
  } catch (err: any) {
    console.warn('[anonymous/outbox]', err?.message ?? err);
  }
}
