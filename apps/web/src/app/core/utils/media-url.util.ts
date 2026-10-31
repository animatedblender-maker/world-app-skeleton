import { SUPABASE_URL } from '../../config/supabase.config';

const DICEBEAR_BASE = 'https://api.dicebear.com/7.x/identicon/svg?seed=';
const AVATARS_PUBLIC = `${SUPABASE_URL}/storage/v1/object/public/avatars/`;
const AVATARS_SIGN = `${SUPABASE_URL}/storage/v1/object/sign/avatars/`;
const OBJECT_PREFIX = `${SUPABASE_URL}/storage/v1/object/`;

/** Resolve profile avatar paths/URLs for <img src> (matches iOS MediaService.normalizedAvatarURL). */
export function resolveAvatarUrl(
  url: string | null | undefined,
  seed?: string | null
): string {
  const raw = String(url || '').trim();
  if (raw) {
    if (raw.startsWith('data:') || raw.startsWith('blob:')) return raw;

    // Signed storage URLs expire — always prefer public avatar object path.
    if (raw.includes('/storage/v1/object/sign/avatars/')) {
      const marker = '/storage/v1/object/sign/avatars/';
      const idx = raw.indexOf(marker);
      const pathPart = raw
        .slice(idx + marker.length)
        .split('?')[0]
        .split('#')[0];
      const decoded = decodeURIComponent(pathPart).replace(/^\/+/, '');
      if (decoded) return `${AVATARS_PUBLIC}${decoded}`;
    }

    const storageMatch = raw.match(
      /\/storage\/v1\/object\/(?:sign|public)\/avatars\/([^?#]+)/i
    );
    if (storageMatch?.[1]) {
      const normalizedPath = decodeURIComponent(storageMatch[1]).replace(/^\/+/, '');
      return `${AVATARS_PUBLIC}${normalizedPath}`;
    }

    if (/^https?:\/\//i.test(raw) || raw.startsWith('//')) {
      const absolute = raw.startsWith('//') ? `https:${raw}` : raw;
      return absolute.split('?')[0].split('#')[0];
    }

    if (raw.startsWith('/storage/')) {
      const path = raw.split('?')[0];
      if (path.includes('/sign/avatars/') || path.includes('/public/avatars/')) {
        const key = path.replace(/^.*\/(?:sign|public)\/avatars\//, '');
        return `${AVATARS_PUBLIC}${decodeURIComponent(key).replace(/^\/+/, '')}`;
      }
      return `${SUPABASE_URL}${path}`;
    }

    if (raw.startsWith('/')) {
      if (raw.includes('/storage/v1/object/')) {
        return resolveAvatarUrl(`${SUPABASE_URL}${raw.split('?')[0]}`, seed);
      }
      const key = raw.replace(/^\/+/, '').replace(/^avatars\//, '');
      return `${AVATARS_PUBLIC}${key}`;
    }

    // Bare storage key: userId/file.ext or file.ext
    let key = raw.replace(/^\/+/, '');
    if (key.startsWith('avatars/')) key = key.slice('avatars/'.length);
    if (key.startsWith(OBJECT_PREFIX) || key.startsWith(AVATARS_PUBLIC) || key.startsWith(AVATARS_SIGN)) {
      return resolveAvatarUrl(key, seed);
    }
    return `${AVATARS_PUBLIC}${key}`;
  }

  const fallback = String(seed || '').trim();
  return fallback ? `${DICEBEAR_BASE}${encodeURIComponent(fallback)}` : '';
}

/** Resolve post/media URLs that may be bare storage keys or JSON payloads. */
export function resolveMediaUrl(url: string | null | undefined): string {
  let raw = String(url || '').trim();
  if (!raw) return '';

  if (raw.startsWith('{') || raw.startsWith('[')) {
    try {
      const parsed = JSON.parse(raw) as any;
      if (Array.isArray(parsed?.urls)) raw = String(parsed.urls[0] || '');
      else if (parsed?.url) raw = String(parsed.url);
    } catch {
      // keep raw
    }
  }

  if (!raw) return '';
  if (raw.startsWith('data:') || raw.startsWith('blob:')) return raw;
  if (/^https?:\/\//i.test(raw) || raw.startsWith('//')) {
    return raw.startsWith('//') ? `https:${raw}` : raw;
  }
  if (raw.startsWith('/storage/')) return `${SUPABASE_URL}${raw.split('?')[0]}`;
  if (raw.startsWith('/')) return `${SUPABASE_URL}${raw}`;

  const key = raw.replace(/^\/+/, '').replace(/^posts\//, '');
  return `${SUPABASE_URL}/storage/v1/object/public/posts/${key}`;
}
