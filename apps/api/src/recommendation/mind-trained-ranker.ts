/**
 * MIND-016 — Lightweight logistic ranker behind a flag.
 * Weights JSON (fixed feature schema). Default OFF — heuristic remains baseline.
 */
import fs from 'node:fs';
import path from 'node:path';

export function mindTrainedRankerEnabled(): boolean {
  const v = process.env.MIND_TRAINED_RANKER_ENABLED;
  if (v == null || v === '') return false;
  return v === '1' || v.toLowerCase() === 'true' || v === 'yes';
}

export type RankerFeatures = {
  following: number;
  affinity: number;
  itemStats: number;
  fresh: number;
  bubble: number;
  knn: number;
  mediaTopic: number;
  ann: number;
  coldStart: number;
  opportunity: number;
  session: number;
  muted: number;
};

export type RankerWeights = {
  version: string;
  bias: number;
  weights: Partial<Record<keyof RankerFeatures, number>>;
  trainedAt?: string;
};

/** Hand-tuned prior that mimics a weak logistic until offline fit replaces it. */
export const DEFAULT_RANKER_WEIGHTS: RankerWeights = {
  version: 'logistic.v0-prior',
  bias: -0.2,
  weights: {
    following: 1.4,
    affinity: 0.9,
    itemStats: 0.55,
    fresh: 0.45,
    bubble: 0.85,
    knn: 0.7,
    mediaTopic: 0.4,
    ann: 0.65,
    coldStart: 0.2,
    opportunity: 0.35,
    session: 0.5,
    muted: -3.0,
  },
  trainedAt: null as unknown as undefined,
};

let cached: { at: number; weights: RankerWeights } | null = null;

function weightsPath(): string | null {
  const p = process.env.MIND_RANKER_WEIGHTS_PATH?.trim();
  if (p) return p;
  // Default beside apps/api
  return path.join(process.cwd(), 'data', 'mind-ranker-weights.json');
}

export function loadRankerWeights(): RankerWeights {
  if (!mindTrainedRankerEnabled()) return DEFAULT_RANKER_WEIGHTS;
  if (cached && Date.now() - cached.at < 60_000) return cached.weights;
  const file = weightsPath();
  try {
    if (file && fs.existsSync(file)) {
      const raw = JSON.parse(fs.readFileSync(file, 'utf8')) as RankerWeights;
      if (raw?.weights && typeof raw.bias === 'number') {
        cached = { at: Date.now(), weights: raw };
        return raw;
      }
    }
  } catch {
    /* fall through */
  }
  cached = { at: Date.now(), weights: DEFAULT_RANKER_WEIGHTS };
  return DEFAULT_RANKER_WEIGHTS;
}

function sigmoid(x: number): number {
  if (x > 20) return 1;
  if (x < -20) return 0;
  return 1 / (1 + Math.exp(-x));
}

/** Map logistic probability to roughly heuristic score scale (~0–10). */
export function trainedScore(
  features: RankerFeatures,
  weights: RankerWeights = loadRankerWeights()
): number {
  let z = weights.bias;
  for (const [k, w] of Object.entries(weights.weights)) {
    const key = k as keyof RankerFeatures;
    z += (w ?? 0) * (features[key] ?? 0);
  }
  return sigmoid(z) * 10;
}

export function emptyFeatures(): RankerFeatures {
  return {
    following: 0,
    affinity: 0,
    itemStats: 0,
    fresh: 0,
    bubble: 0,
    knn: 0,
    mediaTopic: 0,
    ann: 0,
    coldStart: 0,
    opportunity: 0,
    session: 0,
    muted: 0,
  };
}
