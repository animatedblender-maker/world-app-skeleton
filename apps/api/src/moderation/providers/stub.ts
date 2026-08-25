import type { TextModerationProvider } from '../provider.js';
import type { TextProviderResult } from '../types.js';

/** Default: no external ML. Local rules still apply. Never pretends to be SAFE on empty. */
export const stubTextProvider: TextModerationProvider = {
  name: 'stub',
  async score(text: string): Promise<TextProviderResult> {
    const t = String(text ?? '').trim();
    if (!t) {
      return {
        scores: {
          toxicity: 0,
          severe_toxicity: 0,
          obscene: 0,
          threat: 0,
          insult: 0,
          identity_attack: 0,
          spam: 0,
        },
        provider: 'stub',
        modelVersion: 'stub-1',
        ok: true,
      };
    }
    // Tiny heuristic so stub mode still exercises LIMITED path on obvious junk.
    const lower = t.toLowerCase();
    const spammy =
      (lower.match(/buy now|click here|crypto|giveaway/g) ?? []).length >= 2 ? 0.55 : 0.05;
    return {
      scores: {
        toxicity: Math.min(0.4, spammy),
        severe_toxicity: 0,
        obscene: 0,
        threat: 0,
        insult: 0,
        identity_attack: 0,
        spam: spammy,
      },
      provider: 'stub',
      modelVersion: 'stub-1',
      ok: true,
    };
  },
};
