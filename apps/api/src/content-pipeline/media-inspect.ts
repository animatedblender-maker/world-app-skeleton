import {
  GetObjectCommand,
  HeadObjectCommand,
  ListObjectsV2Command,
  type S3Client,
} from '@aws-sdk/client-s3';
import { getBucket } from './r2.js';
import type { PackKind, R2Pack } from './types.js';

/** Where an R2 pack should land in the product. */
export type IngestSurface = 'spark' | 'feed_image' | 'longform' | 'skip';

export type PackMediaPlan = {
  surface: IngestSurface;
  /** Object key to serve (video.mp4 or media/01.jpg). */
  mediaKey: string;
  /**
   * All image object keys for gallery posts (media/01.jpg, media/02.jpg, …).
   * Empty for video/spark/longform. Primary is always `mediaKey` when image.
   */
  imageKeys?: string[];
  mediaType: 'video' | 'image';
  /** True only for real playable short video → Sparks. */
  isSpark: boolean;
  reason: string;
};

const IMAGE_NAME_RE = /^media\/\d+\.(jpe?g|png|gif|webp)$/i;

function packPrefix(pack: R2Pack): string {
  const i = pack.videoKey.lastIndexOf('/');
  return i >= 0 ? pack.videoKey.slice(0, i + 1) : `${pack.countryFolder}/${pack.videoId}/`;
}

function sniffKind(buf: Buffer): 'video' | 'image' | 'unknown' {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image'; // JPEG
  if (
    buf.length >= 8 &&
    buf[0] === 0x89 &&
    buf[1] === 0x50 &&
    buf[2] === 0x4e &&
    buf[3] === 0x47
  ) {
    return 'image'; // PNG
  }
  if (buf.length >= 6 && buf.slice(0, 6).toString('ascii') === 'GIF87a') return 'image';
  if (buf.length >= 6 && buf.slice(0, 6).toString('ascii') === 'GIF89a') return 'image';
  if (buf.length >= 12 && buf.slice(4, 8).toString('ascii') === 'ftyp') return 'video'; // MP4/MOV
  if (buf.length >= 4 && buf.slice(0, 4).toString('ascii') === 'RIFF') return 'video'; // WEBM/AVI-ish
  return 'unknown';
}

async function readMagic(client: S3Client, key: string): Promise<Buffer | null> {
  try {
    const out = await client.send(
      new GetObjectCommand({
        Bucket: getBucket(),
        Key: key,
        Range: 'bytes=0-31',
      })
    );
    if (!out.Body) return null;
    return Buffer.from(await out.Body.transformToByteArray());
  } catch {
    return null;
  }
}

async function listPackKeys(client: S3Client, prefix: string): Promise<string[]> {
  const keys: string[] = [];
  let token: string | undefined;
  do {
    const page = await client.send(
      new ListObjectsV2Command({
        Bucket: getBucket(),
        Prefix: prefix,
        ContinuationToken: token,
        MaxKeys: 100,
      })
    );
    for (const obj of page.Contents ?? []) {
      const key = obj.Key || '';
      if (key.startsWith(prefix)) keys.push(key.slice(prefix.length));
    }
    token = page.IsTruncated ? page.NextContinuationToken : undefined;
  } while (token);
  return keys;
}

function metaLooksLikeImagePost(meta: Record<string, unknown>): boolean {
  const source = String(meta.source ?? meta.platform ?? meta.origin ?? '').toLowerCase();
  const mt = String(meta.media_type ?? meta.type ?? '').toLowerCase();
  if (source.includes('reddit') && (mt === 'image' || mt === 'photo' || mt === 'both')) {
    return true;
  }
  if (mt === 'image' || mt === 'photo') return true;
  if (meta.image_post_info || meta.images || meta.image_urls || meta.photos) return true;
  const aweme = Number(meta.aweme_type ?? meta.awemeType ?? NaN);
  // Common TikTok photo-mode types.
  if (aweme === 150 || aweme === 68 || aweme === 2) return true;
  return false;
}

function durationSeconds(meta: Record<string, unknown>): number | null {
  const raw =
    meta.duration ??
    (meta.video as { duration?: unknown } | undefined)?.duration ??
    meta.video_duration;
  if (raw == null || raw === '') return null;
  const n = Number(raw);
  if (!Number.isFinite(n)) return null;
  // Some TikTok metas store ms.
  if (n > 1000) return n / 1000;
  return n;
}

/**
 * Decide Sparks vs normal feed post.
 * Fake `video.mp4` files that are actually JPEG/PNG (reddit memes under ShortForm/fy_*)
 * must become normal image posts — never Sparks.
 */
export async function planPackMedia(
  client: S3Client,
  pack: R2Pack,
  meta: Record<string, unknown>
): Promise<PackMediaPlan> {
  if (pack.kind === 'longform') {
    return {
      surface: 'longform',
      mediaKey: pack.videoKey,
      mediaType: 'video',
      isSpark: false,
      reason: 'longform_hubs',
    };
  }

  const prefix = packPrefix(pack);
  const relKeys = await listPackKeys(client, prefix);
  const numberedImageRels = relKeys
    .filter((k) => IMAGE_NAME_RE.test(k))
    .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  const imageRel =
    numberedImageRels[0] ||
    relKeys.find((k) => /\.(jpe?g|png|gif|webp)$/i.test(k) && !k.startsWith('frame0_'));
  const imageKeys = (numberedImageRels.length
    ? numberedImageRels
    : imageRel
      ? [imageRel]
      : []
  ).map((rel) => `${prefix}${rel}`);

  let videoHead: { size: number; ctype: string } | null = null;
  try {
    const head = await client.send(
      new HeadObjectCommand({ Bucket: getBucket(), Key: pack.videoKey })
    );
    videoHead = {
      size: Number(head.ContentLength || 0),
      ctype: String(head.ContentType || ''),
    };
  } catch {
    videoHead = null;
  }

  const magic = videoHead ? await readMagic(client, pack.videoKey) : null;
  const sniffed = magic ? sniffKind(magic) : 'unknown';
  const dur = durationSeconds(meta);
  const imagePost = metaLooksLikeImagePost(meta);

  // No video object — image pack only.
  if (!videoHead) {
    if (imageRel) {
      return {
        surface: 'feed_image',
        mediaKey: `${prefix}${imageRel}`,
        imageKeys,
        mediaType: 'image',
        isSpark: false,
        reason: 'image_only_pack',
      };
    }
    return {
      surface: 'skip',
      mediaKey: pack.videoKey,
      mediaType: 'video',
      isSpark: false,
      reason: 'missing_video_and_image',
    };
  }

  // video.mp4 is literally a still image (reddit fy_* scam copies).
  if (sniffed === 'image') {
    const key = imageRel ? `${prefix}${imageRel}` : pack.videoKey;
    return {
      surface: 'feed_image',
      mediaKey: key,
      imageKeys,
        mediaType: 'image',
      isSpark: false,
      reason: 'video_mp4_is_image_bytes',
    };
  }

  // Meta says image / reddit photo even if bytes look odd.
  if (imagePost && imageRel) {
    return {
      surface: 'feed_image',
      mediaKey: `${prefix}${imageRel}`,
      imageKeys,
        mediaType: 'image',
      isSpark: false,
      reason: 'meta_image_post',
    };
  }

  // Tiny object without MP4 ftyp — treat as non-video.
  if (sniffed !== 'video' && videoHead.size > 0 && videoHead.size < 120_000 && imageRel) {
    return {
      surface: 'feed_image',
      mediaKey: `${prefix}${imageRel}`,
      imageKeys,
        mediaType: 'image',
      isSpark: false,
      reason: 'tiny_non_ftyp_with_image',
    };
  }

  if (sniffed !== 'video' && dur != null && dur <= 0 && imageRel) {
    return {
      surface: 'feed_image',
      mediaKey: `${prefix}${imageRel}`,
      imageKeys,
        mediaType: 'image',
      isSpark: false,
      reason: 'zero_duration_with_image',
    };
  }

  // Real video → Sparks (TikTok country root + YouTube ShortForm).
  if (pack.kind === 'spark') {
    return {
      surface: 'spark',
      mediaKey: pack.videoKey,
      mediaType: 'video',
      isSpark: true,
      reason: sniffed === 'video' ? 'real_mp4' : 'assumed_video',
    };
  }

  return {
    surface: 'skip',
    mediaKey: pack.videoKey,
    mediaType: 'video',
    isSpark: false,
    reason: `unhandled_kind_${pack.kind as PackKind}`,
  };
}
