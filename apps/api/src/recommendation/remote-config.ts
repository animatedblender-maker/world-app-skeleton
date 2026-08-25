/**
 * Versioned remote config / kill switches (butter-smooth ADR-002).
 * In-process only for now — no per-request DB. Env can override.
 */

export type RemoteFlags = {
  prefetch_depth_high: number;
  prefetch_depth_low: number;
  player_pool_size: number;
  thin_feed_enabled: boolean;
  thin_hubs_enabled: boolean;
  thin_sparks_enabled: boolean;
  metrics_sample_rate: number;
  kill_prefetch: boolean;
  kill_server_rank: boolean;
  feed_snapshot_max_age_hours: number;
  feed_soft_stale_minutes: number;
  /** Text moderation MVP — rules + stub/http provider. */
  moderation_text_enabled: boolean;
};

const DEFAULT_FLAGS: RemoteFlags = {
  prefetch_depth_high: 3,
  prefetch_depth_low: 1,
  player_pool_size: 3,
  thin_feed_enabled: true,
  thin_hubs_enabled: true,
  thin_sparks_enabled: true,
  metrics_sample_rate: 1,
  kill_prefetch: false,
  kill_server_rank: false,
  feed_snapshot_max_age_hours: 24,
  feed_soft_stale_minutes: 10,
  moderation_text_enabled: true,
};

/** Bump when flag defaults change so clients refresh. */
export const CONFIG_VERSION =
  process.env.MATTERYA_CONFIG_VERSION?.trim() || '2026-08-25.1';

const TTL_SEC = Math.min(
  Math.max(Number(process.env.MATTERYA_CONFIG_TTL_SEC) || 60, 15),
  600
);

function envBool(key: string, fallback: boolean): boolean {
  const v = process.env[key];
  if (v == null || v === '') return fallback;
  return v === '1' || v.toLowerCase() === 'true' || v === 'yes';
}

function envNum(key: string, fallback: number): number {
  const n = Number(process.env[key]);
  return Number.isFinite(n) ? n : fallback;
}

export function getRemoteConfig(clientVersion?: string | null): {
  unchanged: boolean;
  version: string;
  ttlSec: number;
  flags: RemoteFlags;
} {
  const flags: RemoteFlags = {
    ...DEFAULT_FLAGS,
    kill_prefetch: envBool('FLAG_KILL_PREFETCH', DEFAULT_FLAGS.kill_prefetch),
    kill_server_rank: envBool('FLAG_KILL_SERVER_RANK', DEFAULT_FLAGS.kill_server_rank),
    thin_feed_enabled: envBool('FLAG_THIN_FEED', DEFAULT_FLAGS.thin_feed_enabled),
    thin_hubs_enabled: envBool('FLAG_THIN_HUBS', DEFAULT_FLAGS.thin_hubs_enabled),
    thin_sparks_enabled: envBool('FLAG_THIN_SPARKS', DEFAULT_FLAGS.thin_sparks_enabled),
    prefetch_depth_high: envNum('FLAG_PREFETCH_DEPTH_HIGH', DEFAULT_FLAGS.prefetch_depth_high),
    prefetch_depth_low: envNum('FLAG_PREFETCH_DEPTH_LOW', DEFAULT_FLAGS.prefetch_depth_low),
    player_pool_size: envNum('FLAG_PLAYER_POOL', DEFAULT_FLAGS.player_pool_size),
    metrics_sample_rate: Math.min(
      1,
      Math.max(0, envNum('FLAG_METRICS_SAMPLE', DEFAULT_FLAGS.metrics_sample_rate))
    ),
    feed_snapshot_max_age_hours: envNum(
      'FLAG_FEED_SNAPSHOT_HOURS',
      DEFAULT_FLAGS.feed_snapshot_max_age_hours
    ),
    feed_soft_stale_minutes: envNum(
      'FLAG_FEED_SOFT_STALE_MIN',
      DEFAULT_FLAGS.feed_soft_stale_minutes
    ),
    moderation_text_enabled: envBool(
      'MODERATION_TEXT_ENABLED',
      DEFAULT_FLAGS.moderation_text_enabled
    ),
  };

  const v = String(clientVersion ?? '').trim();
  if (v && v === CONFIG_VERSION) {
    return { unchanged: true, version: CONFIG_VERSION, ttlSec: TTL_SEC, flags };
  }
  return { unchanged: false, version: CONFIG_VERSION, ttlSec: TTL_SEC, flags };
}
