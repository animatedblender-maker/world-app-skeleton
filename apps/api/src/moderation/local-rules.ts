import type { LocalRuleHit } from './types.js';

const URL_RE = /https?:\/\/[^\s]+/gi;
const REPEAT_CHAR_RE = /(.)\1{12,}/;

/** Deterministic first pass — free, sync, before any ML. */
export function runLocalSpamRules(text: string): LocalRuleHit | null {
  const raw = String(text ?? '');
  const trimmed = raw.trim();
  if (!trimmed) return null;

  const lower = trimmed.toLowerCase();

  // Obvious scam / phish bait (bounded list — expand via remote config later).
  const blocked = [
    'crypto giveaway',
    'send me your seed phrase',
    'free nitro',
    'onlyfans.com/',
    'bit.ly/free',
  ];
  for (const phrase of blocked) {
    if (lower.includes(phrase)) {
      return {
        code: 'blocklist_phrase',
        reason: `Matched blocklist: ${phrase}`,
        decision: 'held',
      };
    }
  }

  const urls = trimmed.match(URL_RE) ?? [];
  if (urls.length >= 5) {
    return {
      code: 'link_flood',
      reason: `Too many URLs (${urls.length})`,
      decision: 'review',
    };
  }

  if (REPEAT_CHAR_RE.test(trimmed) && trimmed.length > 40) {
    return {
      code: 'char_spam',
      reason: 'Excessive repeated characters',
      decision: 'review',
    };
  }

  // All-caps wall
  const letters = trimmed.replace(/[^a-zA-ZÄÖÜäöüß]/g, '');
  if (letters.length >= 40) {
    const upper = letters.replace(/[^A-ZÄÖÜ]/g, '').length;
    if (upper / letters.length > 0.85) {
      return {
        code: 'shouting',
        reason: 'Mostly uppercase shout',
        decision: 'limited',
      };
    }
  }

  return null;
}
