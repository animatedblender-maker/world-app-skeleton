import type { TextProviderResult } from './types.js';
import { stubTextProvider } from './providers/stub.js';
import { httpDetoxifyProvider } from './providers/http-detoxify.js';

export interface TextModerationProvider {
  readonly name: string;
  score(text: string): Promise<TextProviderResult>;
}

export function resolveTextProvider(): TextModerationProvider {
  const mode = (process.env.MODERATION_TEXT_PROVIDER || 'stub').trim().toLowerCase();
  if (mode === 'http' || mode === 'detoxify') {
    return httpDetoxifyProvider;
  }
  return stubTextProvider;
}
