import type { TextModerationProvider } from '../provider.js';
import type { TextModerationScores, TextProviderResult } from '../types.js';

/**
 * Optional sidecar: POST { text } → { scores: { toxicity, ... } }
 * Env: MODERATION_TEXT_URL (full URL). Timeout via MODERATION_TEXT_TIMEOUT_MS (default 800).
 * License/hosting for Detoxify must be approved before enabling in production.
 */
export const httpDetoxifyProvider: TextModerationProvider = {
  name: 'http-detoxify',
  async score(text: string): Promise<TextProviderResult> {
    const base = (process.env.MODERATION_TEXT_URL || '').trim();
    if (!base) {
      return {
        scores: zeroScores(),
        provider: 'http-detoxify',
        modelVersion: 'unconfigured',
        ok: false,
        error: 'MODERATION_TEXT_URL unset',
      };
    }
    const timeoutMs = Math.min(
      Math.max(Number(process.env.MODERATION_TEXT_TIMEOUT_MS) || 800, 200),
      5_000
    );
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const res = await fetch(base, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text: String(text ?? '').slice(0, 8_000) }),
        signal: ctrl.signal,
      });
      if (!res.ok) {
        return {
          scores: zeroScores(),
          provider: 'http-detoxify',
          modelVersion: 'http',
          ok: false,
          error: `http_${res.status}`,
        };
      }
      const body = (await res.json()) as {
        scores?: Partial<TextModerationScores>;
        model_version?: string;
        modelVersion?: string;
      };
      const s = body.scores ?? {};
      return {
        scores: {
          toxicity: num(s.toxicity),
          severe_toxicity: num(s.severe_toxicity),
          obscene: num(s.obscene),
          threat: num(s.threat),
          insult: num(s.insult),
          identity_attack: num(s.identity_attack),
          spam: num(s.spam),
        },
        provider: 'http-detoxify',
        modelVersion: String(body.model_version || body.modelVersion || 'detoxify'),
        ok: true,
      };
    } catch (err: any) {
      return {
        scores: zeroScores(),
        provider: 'http-detoxify',
        modelVersion: 'http',
        ok: false,
        error: err?.name === 'AbortError' ? 'timeout' : String(err?.message ?? err),
      };
    } finally {
      clearTimeout(timer);
    }
  },
};

function num(v: unknown): number {
  const n = Number(v);
  if (!Number.isFinite(n)) return 0;
  return Math.min(1, Math.max(0, n));
}

function zeroScores(): TextModerationScores {
  return {
    toxicity: 0,
    severe_toxicity: 0,
    obscene: 0,
    threat: 0,
    insult: 0,
    identity_attack: 0,
    spam: 0,
  };
}
