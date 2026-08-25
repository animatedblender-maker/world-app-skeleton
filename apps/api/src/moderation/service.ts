import { pool } from '../db.js';
import { runLocalSpamRules } from './local-rules.js';
import { modInc } from './metrics.js';
import {
  decisionFromScores,
  mapDecisionToServing,
  POLICY_VERSION,
} from './policy.js';
import { resolveTextProvider } from './provider.js';
import type { ModerateTextInput, ModerateTextResult } from './types.js';

function envBool(key: string, fallback: boolean): boolean {
  const v = process.env[key];
  if (v == null || v === '') return fallback;
  return v === '1' || v.toLowerCase() === 'true' || v === 'yes';
}

/** Feature flag — default ON for rules+stub; set MODERATION_TEXT_ENABLED=0 to disable. */
export function isTextModerationEnabled(): boolean {
  return envBool('MODERATION_TEXT_ENABLED', true);
}

/**
 * Run local rules → provider → policy → persist → update serving status.
 * Safe to fire-and-forget after create. Provider failure → REVIEW (never silent SAFE).
 */
export async function moderateTextEntity(
  input: ModerateTextInput
): Promise<ModerateTextResult | null> {
  if (input.enabled === false || !isTextModerationEnabled()) return null;

  const entityId = String(input.entityId || '').trim();
  const text = String(input.text ?? '');
  if (!entityId || !text.trim()) return null;

  modInc('requests');

  const ruleHit = runLocalSpamRules(text);
  if (ruleHit) modInc('rule_blocks');

  const provider = resolveTextProvider();
  const scored = await provider.score(text);
  if (scored.ok) modInc('provider_ok');
  else modInc('provider_fail');

  const decision = decisionFromScores(scored.scores, scored, ruleHit);
  modInc(
    decision === 'safe'
      ? 'decision_safe'
      : decision === 'limited'
        ? 'decision_limited'
        : decision === 'held'
          ? 'decision_held'
          : 'decision_review'
  );

  const servingStatus = mapDecisionToServing(decision);
  const result: ModerateTextResult = {
    decision,
    servingStatus,
    provider: scored.provider,
    modelVersion: scored.modelVersion,
    policyVersion: POLICY_VERSION,
    rawScores: scored.scores,
    ruleHit: ruleHit ?? undefined,
  };

  try {
    await persistResult(input.entityType, entityId, result);
    await applyServingStatus(input.entityType, entityId, servingStatus, result);
  } catch (err: any) {
    modInc('persist_fail');
    console.warn('[moderation] persist failed', err?.message ?? err);
  }

  return result;
}

/** Fire-and-forget wrapper with timeout — create path must not hang. */
export function scheduleTextModeration(input: ModerateTextInput): void {
  if (!isTextModerationEnabled()) return;
  const timeoutMs = Math.min(
    Math.max(Number(process.env.MODERATION_SCHEDULE_TIMEOUT_MS) || 2_500, 500),
    10_000
  );
  void Promise.race([
    moderateTextEntity(input),
    new Promise<null>((resolve) => setTimeout(() => resolve(null), timeoutMs)),
  ]).catch((err) => {
    console.warn('[moderation] schedule error', err?.message ?? err);
  });
}

async function persistResult(
  entityType: ModerateTextInput['entityType'],
  entityId: string,
  result: ModerateTextResult
): Promise<void> {
  await pool.query(
    `
    insert into public.moderation_results
      (entity_type, entity_id, raw_scores, provider, model_version, policy_decision, policy_version)
    values ($1, $2, $3::jsonb, $4, $5, $6, $7)
    `,
    [
      entityType,
      entityId,
      JSON.stringify(result.rawScores),
      result.provider,
      result.modelVersion,
      result.decision,
      result.policyVersion,
    ]
  );
}

async function applyServingStatus(
  entityType: ModerateTextInput['entityType'],
  entityId: string,
  status: ModerateTextResult['servingStatus'],
  result: ModerateTextResult
): Promise<void> {
  const note =
    result.ruleHit?.reason ||
    (result.decision === 'safe' ? null : `auto:${result.decision}:${result.provider}`);
  const actor = `moderation:${result.provider}`;

  if (entityType === 'post') {
    try {
      await pool.query(
        `
        update public.posts
        set
          moderation_status = $2,
          moderation_note = coalesce($3, moderation_note),
          moderated_at = now(),
          moderation_actor = $4,
          moderation_policy_version = $5
        where id = $1::uuid
          and coalesce(moderation_actor, '') not like 'admin%'
        `,
        [entityId, status, note, actor, result.policyVersion]
      );
    } catch {
      // Pre-migration: column moderation_policy_version may be missing.
      await pool.query(
        `
        update public.posts
        set
          moderation_status = $2,
          moderation_note = coalesce($3, moderation_note),
          moderated_at = now(),
          moderation_actor = $4
        where id = $1::uuid
          and coalesce(moderation_actor, '') not like 'admin%'
        `,
        [entityId, status, note, actor]
      );
    }
    return;
  }

  try {
    await pool.query(
      `
      update public.post_comments
      set
        moderation_status = $2,
        moderation_note = coalesce($3, moderation_note),
        moderated_at = now(),
        moderation_actor = $4,
        moderation_policy_version = $5
      where id = $1::uuid
        and coalesce(moderation_actor, '') not like 'admin%'
      `,
      [entityId, status, note, actor, result.policyVersion]
    );
  } catch (err: any) {
    // Comment moderation columns require 20260825120000 migration.
    console.warn('[moderation] comment status skip', err?.message ?? err);
  }
}
