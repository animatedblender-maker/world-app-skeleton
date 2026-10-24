/**
 * Lightweight MIND eligibility checks — run with:
 *   npx tsx src/recommendation/eligibility.test.ts
 */
import { isEligibleForSurface, filterEligible } from './eligibility.js';

function assert(cond: unknown, msg: string) {
  if (!cond) throw new Error(msg);
}

assert(
  isEligibleForSurface({ id: 'a', state: 'active', namespace: 'public' }, 'home_for_you')
    .ok,
  'public active should pass home'
);

assert(
  !isEligibleForSurface(
    { id: 'a', state: 'active', namespace: 'masquerade' },
    'home_for_you'
  ).ok,
  'masquerade must not enter public home'
);

assert(
  !isEligibleForSurface(
    { id: 'a', state: 'active', namespace: 'public' },
    'masquerade_for_you'
  ).ok,
  'public must not enter masquerade surface'
);

assert(
  !isEligibleForSurface({ id: 'a', moderation_status: 'removed' }, 'home_for_you').ok,
  'removed moderation fails'
);

const kept = filterEligible(
  [
    { id: '1', state: 'active', namespace: 'public' },
    { id: '2', state: 'active', namespace: 'masquerade' },
    { id: '3', is_deleted: true, namespace: 'public' },
  ],
  'home_for_you'
);
assert(kept.length === 1 && kept[0]!.id === '1', 'filter keeps only public eligible');

console.log('eligibility.test.ts OK');
