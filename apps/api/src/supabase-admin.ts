/**
 * Minimal Supabase Auth Admin helpers (service role).
 * Used for permanent account deletion and optional ban on deactivate.
 */

const SUPABASE_URL = (process.env.SUPABASE_URL ?? '').replace(/\/$/, '');
const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';

export function supabaseAdminConfigured(): boolean {
  return Boolean(SUPABASE_URL && SERVICE_ROLE);
}

async function adminFetch(path: string, init: RequestInit = {}): Promise<Response> {
  if (!supabaseAdminConfigured()) {
    throw new Error('SUPABASE_ADMIN_NOT_CONFIGURED');
  }
  const url = `${SUPABASE_URL}/auth/v1/${path.replace(/^\//, '')}`;
  const headers = new Headers(init.headers);
  headers.set('apikey', SERVICE_ROLE);
  headers.set('Authorization', `Bearer ${SERVICE_ROLE}`);
  if (init.body && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }
  return fetch(url, { ...init, headers });
}

/** Ban a user so password login fails until unbanned (deactivate). */
export async function banAuthUser(userId: string, duration = '876000h'): Promise<void> {
  const res = await adminFetch(`admin/users/${userId}`, {
    method: 'PUT',
    body: JSON.stringify({ ban_duration: duration }),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`SUPABASE_BAN_FAILED: ${res.status} ${text.slice(0, 200)}`);
  }
}

/** Clear ban so a reactivated user can sign in again. */
export async function unbanAuthUser(userId: string): Promise<void> {
  const res = await adminFetch(`admin/users/${userId}`, {
    method: 'PUT',
    body: JSON.stringify({ ban_duration: 'none' }),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`SUPABASE_UNBAN_FAILED: ${res.status} ${text.slice(0, 200)}`);
  }
}

/** Permanently delete the Auth user (cascades FKs to profiles/posts/etc where defined). */
export async function deleteAuthUser(userId: string): Promise<void> {
  const res = await adminFetch(`admin/users/${userId}`, {
    method: 'DELETE',
  });
  if (!res.ok && res.status !== 404) {
    const text = await res.text().catch(() => '');
    throw new Error(`SUPABASE_DELETE_USER_FAILED: ${res.status} ${text.slice(0, 200)}`);
  }
}
