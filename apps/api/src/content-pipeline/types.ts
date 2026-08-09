/** Content pipeline types — R2 catalog → owned posts (never orphan). */

export type PackKind = 'spark' | 'longform';

export type ProfileOwner = {
  userId: string;
  countryCode: string;
  countryName: string | null;
  cityName: string | null;
};

export type R2Pack = {
  kind: PackKind;
  countryFolder: string;
  countryCode: string;
  countryName: string;
  videoId: string;
  /** S3 key for video.mp4 */
  videoKey: string;
  metaKey: string;
  commentsKey: string;
  /** Idempotency key stored on posts.media_path */
  mediaPath: string;
};

export type PipelineOptions = {
  dryRun?: boolean;
  /** Max new original posts this tick */
  maxOriginals?: number;
  /** Max new feed spark shares this tick */
  maxShares?: number;
  /** Max media_url re-signs this tick */
  maxResign?: number;
  /** Soft deadline ms from start */
  maxMs?: number;
  /** Only resign (skip discover/ingest) */
  resignOnly?: boolean;
  /** Only discover/ingest (skip resign) */
  ingestOnly?: boolean;
};

export type PipelineStats = {
  ok: boolean;
  dryRun: boolean;
  discovered: number;
  insertedOriginals: number;
  insertedShares: number;
  skippedNoOwner: number;
  skippedExisting: number;
  skippedIncomplete: number;
  resigned: number;
  errors: string[];
  ms: number;
};
