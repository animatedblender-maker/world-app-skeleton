import { createClient } from '@supabase/supabase-js';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from '../config/supabase.config';

console.log('[Supabase] URL present?', !!SUPABASE_URL, 'len=', (SUPABASE_URL ?? '').length);
console.log('[Supabase] ANON present?', !!SUPABASE_ANON_KEY, 'len=', (SUPABASE_ANON_KEY ?? '').length);

function fetchWithTimeout(timeoutMs = 12000): typeof fetch {
  return async (input: RequestInfo | URL, init?: RequestInit) => {
    const controller = new AbortController();
    const t = setTimeout(() => controller.abort(), timeoutMs);

    try {
      return await fetch(input, { ...init, signal: controller.signal });
    } finally {
      clearTimeout(t);
    }
  };
}

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
     
  },
  global: {
    fetch: fetchWithTimeout(12000),
  },
});
