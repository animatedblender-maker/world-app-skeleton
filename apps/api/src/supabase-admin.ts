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

export type AdminAuthUser = {
  id: string;
  email?: string;
  email_confirmed_at?: string | null;
};

/** Create auth user (optionally unconfirmed for Matterya email confirmation). */
export async function createAuthUser(opts: {
  email: string;
  password: string;
  emailConfirm?: boolean;
}): Promise<AdminAuthUser> {
  const res = await adminFetch('admin/users', {
    method: 'POST',
    body: JSON.stringify({
      email: opts.email,
      password: opts.password,
      email_confirm: opts.emailConfirm === true,
    }),
  });
  const text = await res.text().catch(() => '');
  let json: any = {};
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    json = { raw: text };
  }
  if (!res.ok) {
    const msg =
      json?.msg ||
      json?.message ||
      json?.error_description ||
      json?.error ||
      text.slice(0, 200) ||
      `HTTP ${res.status}`;
    throw new Error(String(msg));
  }
  const user = json?.user ?? json;
  if (!user?.id) throw new Error('SUPABASE_CREATE_USER_NO_ID');
  return {
    id: String(user.id),
    email: user.email,
    email_confirmed_at: user.email_confirmed_at ?? null,
  };
}

/** Look up auth user by email (admin list with filter). */
export async function findAuthUserByEmail(email: string): Promise<AdminAuthUser | null> {
  const q = new URLSearchParams({ email: email.trim().toLowerCase() });
  const res = await adminFetch(`admin/users?${q.toString()}`, { method: 'GET' });
  if (!res.ok) {
    // Fallback: page users (small projects) — avoid failing signup hard.
    const text = await res.text().catch(() => '');
    console.warn('[admin] findAuthUserByEmail failed:', res.status, text.slice(0, 120));
    return null;
  }
  const json = (await res.json().catch(() => ({}))) as {
    users?: AdminAuthUser[];
    id?: string;
    email?: string;
    email_confirmed_at?: string | null;
  };
  // Some GoTrue versions return { users: [...] }, others a single user for filter.
  if (Array.isArray(json.users)) {
    const hit = json.users.find(
      (u) => (u.email ?? '').toLowerCase() === email.trim().toLowerCase()
    );
    return hit
      ? {
          id: String(hit.id),
          email: hit.email,
          email_confirmed_at: hit.email_confirmed_at ?? null,
        }
      : null;
  }
  if (json.id) {
    return {
      id: String(json.id),
      email: json.email,
      email_confirmed_at: json.email_confirmed_at ?? null,
    };
  }
  return null;
}

/** Mark email confirmed (or unconfirmed) via admin API. */
export async function setAuthUserEmailConfirmed(
  userId: string,
  confirmed: boolean
): Promise<void> {
  const res = await adminFetch(`admin/users/${userId}`, {
    method: 'PUT',
    body: JSON.stringify({ email_confirm: confirmed }),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`SUPABASE_CONFIRM_EMAIL_FAILED: ${res.status} ${text.slice(0, 200)}`);
  }
}
