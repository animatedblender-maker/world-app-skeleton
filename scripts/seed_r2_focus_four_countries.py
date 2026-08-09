#!/usr/bin/env python3
"""Seed Matterya feed from R2 Sparks + LongForm for four launch countries.

Sources (R2 bucket matterya-sparks):
  Sparks:    <Country>/<tiktok_id>/{video.mp4,meta.json,comments.json}
  LongForm:  LongForm/<Country>/<youtube_id>/{video.mp4,meta.json,comments.json}

Countries: United_States, Germany, Egypt, Albania
Authors/commenters: existing profiles in Supabase with matching country_code.

Idempotency: posts.media_path = r2:matterya-sparks/<object_key>
Playback: long-lived presigned GET URLs (R2 max ~7d) stored in media_url JSON;
          also embeds r2_key for a future re-sign job.

Credentials (local only, never committed):
  R2:        TikTokDashboard/.env.r2  (or env vars)
  Supabase:  SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
             (or /tmp/matterya_sr.key for the service role JWT)

Usage:
  python3 scripts/seed_r2_focus_four_countries.py --dry-run
  python3 scripts/seed_r2_focus_four_countries.py --sparks-per-country 50 --longform-per-country 20
  python3 scripts/seed_r2_focus_four_countries.py --all
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Set, Tuple

try:
    import boto3
    from botocore.config import Config
except ImportError:
    print("boto3 required: pip install boto3", file=sys.stderr)
    sys.exit(1)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_R2_ENV = Path(
    "/Volumes/MatteryaSSD/Development/TikTok-Api/TikTokDashboard/.env.r2"
)
DEFAULT_SR_KEY_FILE = Path("/tmp/matterya_sr.key")
DEFAULT_SUPABASE_URL = "https://bpdkltgikgbnfjswdbaj.supabase.co"

FOCUS = [
    ("United_States", "US", "United States"),
    ("Germany", "DE", "Germany"),
    ("Egypt", "EG", "Egypt"),
    ("Albania", "AL", "Albania"),
]

REQUIRED_FILES = frozenset({"video.mp4", "meta.json", "comments.json"})
PRESIGN_SECONDS = 7 * 24 * 3600  # R2 practical max
# No artificial cap — insert every comment from comments.json for the video.
# (Older seeds used MAX_COMMENTS_PER_POST=25 which made every Spark show 25.)
MAX_BODY = 4000
MAX_COMMENT_BODY = 5000
MAX_TITLE = 200

# Genre / free-text → category slug (must exist in public.categories)
GENRE_CATEGORY = {
    "music": "music",
    "dance": "music",
    "asmr": "spiritual",
    "food": "food",
    "cooking": "food",
    "travel": "food",
    "tech": "tech",
    "gaming": "tech",
    "comedy": "music",
    "sports": "tech",
    "fitness": "tech",
    "nature": "spiritual",
    "culture": "spiritual",
    "film": "music",
    "news": "tech",
}

DEFAULT_CATEGORY_SLUG = "tech"


# ---------------------------------------------------------------------------
# Env / clients
# ---------------------------------------------------------------------------


def load_dotenv(path: Path) -> Dict[str, str]:
    env: Dict[str, str] = {}
    if not path.exists():
        return env
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def resolve_supabase() -> Tuple[str, str]:
    url = (
        os.environ.get("SUPABASE_URL")
        or os.environ.get("NEXT_PUBLIC_SUPABASE_URL")
        or DEFAULT_SUPABASE_URL
    ).rstrip("/")
    key = (
        os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
        or os.environ.get("SERVICE_ROLE_KEY")
        or ""
    ).strip()
    if not key and DEFAULT_SR_KEY_FILE.exists():
        key = DEFAULT_SR_KEY_FILE.read_text(encoding="utf-8").strip()
    if not key:
        raise SystemExit(
            "Missing SUPABASE_SERVICE_ROLE_KEY (or /tmp/matterya_sr.key)"
        )
    return url, key


def resolve_r2(env_path: Path):
    file_env = load_dotenv(env_path)
    account = os.environ.get("R2_ACCOUNT_ID") or file_env.get("R2_ACCOUNT_ID", "")
    access = os.environ.get("R2_ACCESS_KEY_ID") or file_env.get("R2_ACCESS_KEY_ID", "")
    secret = (
        os.environ.get("R2_SECRET_ACCESS_KEY") or file_env.get("R2_SECRET_ACCESS_KEY", "")
    )
    bucket = os.environ.get("R2_BUCKET") or file_env.get("R2_BUCKET", "matterya-sparks")
    endpoint = os.environ.get("R2_ENDPOINT") or file_env.get("R2_ENDPOINT", "")
    if not endpoint and account:
        endpoint = f"https://{account}.r2.cloudflarestorage.com"
    if not (access and secret and endpoint and bucket):
        raise SystemExit(f"Incomplete R2 credentials in {env_path} / env")
    client = boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=access,
        aws_secret_access_key=secret,
        region_name="auto",
        config=Config(signature_version="s3v4", retries={"max_attempts": 5}),
    )
    return client, bucket


class SupabaseREST:
    def __init__(self, base_url: str, service_key: str):
        self.base = base_url.rstrip("/")
        self.key = service_key

    def _headers(self, prefer: Optional[str] = None) -> Dict[str, str]:
        h = {
            "apikey": self.key,
            "Authorization": f"Bearer {self.key}",
            "Content-Type": "application/json",
        }
        if prefer:
            h["Prefer"] = prefer
        return h

    def request(
        self,
        method: str,
        path: str,
        *,
        body: Any = None,
        prefer: Optional[str] = None,
        query: Optional[Dict[str, str]] = None,
        timeout: int = 120,
    ) -> Tuple[Dict[str, str], Any]:
        url = self.base + path
        if query:
            url += "?" + urllib.parse.urlencode(query, doseq=True)
        data = None if body is None else json.dumps(body).encode("utf-8")
        req = urllib.request.Request(
            url, data=data, headers=self._headers(prefer), method=method
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read().decode("utf-8")
                headers = {k.lower(): v for k, v in resp.headers.items()}
                if not raw:
                    return headers, None
                try:
                    return headers, json.loads(raw)
                except json.JSONDecodeError:
                    return headers, raw
        except urllib.error.HTTPError as e:
            err_body = e.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"HTTP {e.code} {method} {path}: {err_body[:800]}") from e

    def get_all(self, path: str, query: Dict[str, str], page_size: int = 1000) -> List[dict]:
        out: List[dict] = []
        start = 0
        while True:
            end = start + page_size - 1
            headers = self._headers("count=exact")
            headers["Range"] = f"{start}-{end}"
            url = self.base + path + "?" + urllib.parse.urlencode(query, doseq=True)
            req = urllib.request.Request(url, headers=headers, method="GET")
            with urllib.request.urlopen(req, timeout=120) as resp:
                raw = resp.read().decode("utf-8")
                batch = json.loads(raw) if raw else []
                if not batch:
                    break
                out.extend(batch)
                cr = resp.headers.get("Content-Range") or resp.headers.get("content-range") or ""
                # e.g. 0-999/1834
                total = None
                if "/" in cr:
                    try:
                        total = int(cr.split("/")[-1])
                    except ValueError:
                        total = None
                start += len(batch)
                if total is not None and start >= total:
                    break
                if len(batch) < page_size:
                    break
        return out


# ---------------------------------------------------------------------------
# R2 pack listing
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Pack:
    kind: str  # spark | longform
    country_folder: str
    country_code: str
    country_name: str
    video_id: str
    prefix: str  # object prefix ending with /

    @property
    def video_key(self) -> str:
        return f"{self.prefix}video.mp4"

    @property
    def meta_key(self) -> str:
        return f"{self.prefix}meta.json"

    @property
    def comments_key(self) -> str:
        return f"{self.prefix}comments.json"

    @property
    def media_path(self) -> str:
        return f"r2:matterya-sparks/{self.video_key}"


def list_complete_packs(
    client, bucket: str, prefix: str
) -> List[str]:
    """Return video_ids that have all three pack files under prefix."""
    packs: Dict[str, Set[str]] = {}
    token = None
    while True:
        kw: Dict[str, Any] = {
            "Bucket": bucket,
            "Prefix": prefix,
            "MaxKeys": 1000,
        }
        if token:
            kw["ContinuationToken"] = token
        resp = client.list_objects_v2(**kw)
        for obj in resp.get("Contents") or []:
            key = obj["Key"]
            if not key.startswith(prefix):
                continue
            rest = key[len(prefix) :]
            parts = rest.split("/")
            if len(parts) < 2:
                continue
            vid, fname = parts[0], parts[1]
            if not vid or not fname:
                continue
            # Skip nested/non-pack noise
            if len(parts) != 2:
                continue
            packs.setdefault(vid, set()).add(fname)
        if not resp.get("IsTruncated"):
            break
        token = resp.get("NextContinuationToken")
    return sorted(vid for vid, files in packs.items() if REQUIRED_FILES <= files)


def discover_packs(
    client, bucket: str, *, sparks: bool, longform: bool
) -> List[Pack]:
    out: List[Pack] = []
    for folder, code, name in FOCUS:
        if sparks:
            prefix = f"{folder}/"
            for vid in list_complete_packs(client, bucket, prefix):
                out.append(
                    Pack(
                        kind="spark",
                        country_folder=folder,
                        country_code=code,
                        country_name=name,
                        video_id=vid,
                        prefix=f"{folder}/{vid}/",
                    )
                )
        if longform:
            prefix = f"LongForm/{folder}/"
            for vid in list_complete_packs(client, bucket, prefix):
                out.append(
                    Pack(
                        kind="longform",
                        country_folder=folder,
                        country_code=code,
                        country_name=name,
                        video_id=vid,
                        prefix=f"LongForm/{folder}/{vid}/",
                    )
                )
    return out


# ---------------------------------------------------------------------------
# Content helpers
# ---------------------------------------------------------------------------


def s3_json(client, bucket: str, key: str) -> Any:
    obj = client.get_object(Bucket=bucket, Key=key)
    raw = obj["Body"].read()
    return json.loads(raw)


def clean_text(value: Any, max_len: int) -> str:
    if value is None:
        return ""
    text = str(value)
    text = text.replace("\x00", " ").strip()
    text = re.sub(r"\s+", " ", text)
    # Never surface the source platform name in captions / hashtags / comments.
    text = re.sub(r"tiktok", "matterya", text, flags=re.IGNORECASE)
    if len(text) > max_len:
        text = text[: max_len - 1].rstrip() + "…"
    return text


def pick_title(meta: dict, kind: str, video_id: str) -> str:
    for key in ("title", "desc", "description", "music_title"):
        t = clean_text(meta.get(key), MAX_TITLE)
        if t:
            return t
    if kind == "spark":
        return f"Spark {video_id[-6:]}"
    return f"Video {video_id}"


def pick_body(kind: str, title: str, meta: dict) -> str:
    title = clean_text(title, MAX_BODY - 20) or "Clip"
    if kind == "spark":
        return f"__spark__|{title}"
    # Long-form feed post — not a spark, not a share.
    channel = clean_text(meta.get("channel") or meta.get("author_name"), 80)
    if channel:
        return clean_text(f"{title}\n\n— {channel}", MAX_BODY)
    return title


def encode_media_url(
    *,
    signed_url: str,
    reel: bool,
    r2_key: str,
    source_id: str,
    kind: str,
) -> str:
    payload = {
        "urls": [signed_url],
        "types": ["video"],
        "r2_key": r2_key,
        "source": "r2_focus_seed",
        "source_id": source_id,
        "kind": kind,
    }
    if reel:
        payload["reel"] = True
    return json.dumps(payload, separators=(",", ":"))


def extract_comments(raw: Any) -> List[dict]:
    if raw is None:
        return []
    if isinstance(raw, list):
        items = raw
    elif isinstance(raw, dict):
        for k in ("comments", "data", "items", "results"):
            if isinstance(raw.get(k), list):
                items = raw[k]
                break
        else:
            items = []
    else:
        items = []
    out: List[dict] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        text = (
            item.get("text")
            or item.get("body")
            or item.get("content")
            or item.get("comment")
            or ""
        )
        text = clean_text(text, MAX_COMMENT_BODY)
        if not text or len(text) < 1:
            continue
        likes = item.get("digg_count") or item.get("like_count") or item.get("likes") or 0
        try:
            likes = int(likes)
        except (TypeError, ValueError):
            likes = 0
        out.append(
            {
                "text": text,
                "likes": max(0, likes),
                "user": item.get("user_nickname")
                or item.get("author")
                or item.get("user_id")
                or "",
            }
        )
    # Prefer higher-engagement comments first (full comments.json, no cap).
    out.sort(key=lambda c: c["likes"], reverse=True)
    return out


def map_category(meta: dict, categories_by_slug: Dict[str, str]) -> str:
    genre = str(meta.get("genre") or meta.get("category") or "").strip().lower()
    slug = GENRE_CATEGORY.get(genre)
    if not slug:
        blob = " ".join(
            str(meta.get(k) or "")
            for k in ("title", "description", "source", "genre", "channel")
        ).lower()
        for key, s in GENRE_CATEGORY.items():
            if key in blob:
                slug = s
                break
    slug = slug or DEFAULT_CATEGORY_SLUG
    return categories_by_slug.get(slug) or categories_by_slug[DEFAULT_CATEGORY_SLUG]


def random_created_at(rng: random.Random, days: int = 45) -> str:
    # Spread over recent window so feed feels alive.
    offset = rng.uniform(0, days * 24 * 3600)
    dt = datetime.now(timezone.utc) - timedelta(seconds=offset)
    return dt.isoformat().replace("+00:00", "Z")


def like_count_from_meta(meta: dict, kind: str) -> int:
    for key in ("play_count", "view_count", "digg_count", "like_count", "likes"):
        if key in meta and meta[key] is not None:
            try:
                n = int(meta[key])
            except (TypeError, ValueError):
                continue
            if n <= 0:
                continue
            # Compress large counts into a social-scale like count.
            if kind == "spark":
                return max(1, min(50_000, int(n ** 0.45)))
            return max(1, min(100_000, int(n ** 0.4)))
    return random.randint(3, 120)


# ---------------------------------------------------------------------------
# Seed core
# ---------------------------------------------------------------------------


@dataclass
class Profile:
    user_id: str
    country_code: str
    country_name: str
    city_name: Optional[str]


def load_profiles(db: SupabaseREST) -> Dict[str, List[Profile]]:
    by_cc: Dict[str, List[Profile]] = {code: [] for _, code, _ in FOCUS}
    for _, code, _ in FOCUS:
        rows = db.get_all(
            "/rest/v1/profiles",
            {
                "select": "user_id,country_code,country_name,city_name",
                "country_code": f"eq.{code}",
                "order": "user_id",
            },
        )
        for r in rows:
            uid = r.get("user_id")
            if not uid:
                continue
            by_cc[code].append(
                Profile(
                    user_id=uid,
                    country_code=code,
                    country_name=r.get("country_name") or code,
                    city_name=r.get("city_name"),
                )
            )
    return by_cc


def load_categories(db: SupabaseREST) -> Dict[str, str]:
    rows = db.get_all(
        "/rest/v1/categories",
        {"select": "id,slug", "order": "slug"},
    )
    out = {r["slug"]: r["id"] for r in rows if r.get("slug") and r.get("id")}
    if DEFAULT_CATEGORY_SLUG not in out and out:
        # fall back to any
        out[DEFAULT_CATEGORY_SLUG] = next(iter(out.values()))
    if not out:
        raise SystemExit("No categories in public.categories")
    return out


def load_existing_media_paths(db: SupabaseREST) -> Set[str]:
    """All media_path values already seeded from r2."""
    rows = db.get_all(
        "/rest/v1/posts",
        {
            "select": "media_path",
            "media_path": "like.r2:matterya-sparks/*",
        },
    )
    return {r["media_path"] for r in rows if r.get("media_path")}


def apply_caps(
    packs: List[Pack],
    *,
    sparks_per_country: Optional[int],
    longform_per_country: Optional[int],
    rng: random.Random,
) -> List[Pack]:
    by_key: Dict[Tuple[str, str], List[Pack]] = {}
    for p in packs:
        by_key.setdefault((p.kind, p.country_code), []).append(p)
    out: List[Pack] = []
    for (kind, cc), group in by_key.items():
        rng.shuffle(group)
        if kind == "spark" and sparks_per_country is not None:
            group = group[:sparks_per_country]
        if kind == "longform" and longform_per_country is not None:
            group = group[:longform_per_country]
        out.extend(group)
    # Interleave countries for a balanced feed over time
    rng.shuffle(out)
    return out


def seed_one(
    *,
    pack: Pack,
    client,
    bucket: str,
    db: SupabaseREST,
    profiles: List[Profile],
    categories: Dict[str, str],
    dry_run: bool,
    rng: random.Random,
) -> Dict[str, Any]:
    if not profiles:
        return {"status": "skip", "reason": "no_profiles", "pack": pack.media_path}

    meta = s3_json(client, bucket, pack.meta_key)
    if not isinstance(meta, dict):
        meta = {}
    try:
        comments_raw = s3_json(client, bucket, pack.comments_key)
    except Exception:
        comments_raw = []

    title = pick_title(meta, pack.kind, pack.video_id)
    body = pick_body(pack.kind, title, meta)
    signed = client.generate_presigned_url(
        "get_object",
        Params={"Bucket": bucket, "Key": pack.video_key},
        ExpiresIn=PRESIGN_SECONDS,
    )
    media_url = encode_media_url(
        signed_url=signed,
        reel=(pack.kind == "spark"),
        r2_key=pack.video_key,
        source_id=f"{pack.country_folder}/{pack.video_id}",
        kind=pack.kind,
    )
    author = rng.choice(profiles)
    category_id = map_category(meta, categories)
    created_at = random_created_at(rng)
    likes = like_count_from_meta(meta, pack.kind)
    comments = extract_comments(comments_raw)

    post_row = {
        "author_id": author.user_id,
        "category_id": category_id,
        "country_name": author.country_name or pack.country_name,
        "country_code": pack.country_code,
        "city_name": author.city_name,
        "title": title if pack.kind == "longform" else None,
        "body": body,
        "media_type": "video",
        "media_url": media_url,
        "media_path": pack.media_path,
        "visibility": "public",
        "like_count": likes,
        "comment_count": 0,  # trigger will bump on comment insert
        "created_at": created_at,
        "updated_at": created_at,
        "moderation_status": "active",
    }

    if dry_run:
        return {
            "status": "dry_run",
            "pack": pack.media_path,
            "kind": pack.kind,
            "country": pack.country_code,
            "title": title[:80],
            "comments": len(comments),
            "author": author.user_id[:8],
        }

    # Insert post
    _, created = db.request(
        "POST",
        "/rest/v1/posts",
        body=post_row,
        prefer="return=representation",
    )
    if not created:
        return {"status": "error", "reason": "empty_create", "pack": pack.media_path}
    post = created[0] if isinstance(created, list) else created
    post_id = post["id"]

    # Comments from other same-country users (round-robin-ish)
    comment_authors = [p for p in profiles if p.user_id != author.user_id] or profiles
    rng.shuffle(comment_authors)
    inserted_comments = 0
    comment_rows: List[dict] = []
    for i, c in enumerate(comments):
        c_author = comment_authors[i % len(comment_authors)]
        # Stagger comment times after post
        try:
            base = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
        except ValueError:
            base = datetime.now(timezone.utc)
        c_at = (base + timedelta(minutes=rng.randint(2, 60 * 24 * 7))).isoformat().replace(
            "+00:00", "Z"
        )
        comment_rows.append(
            {
                "post_id": post_id,
                "author_id": c_author.user_id,
                "body": c["text"],
                "created_at": c_at,
                "updated_at": c_at,
            }
        )
    # Batch comments in chunks of 50
    for i in range(0, len(comment_rows), 50):
        chunk = comment_rows[i : i + 50]
        if not chunk:
            continue
        try:
            db.request(
                "POST",
                "/rest/v1/post_comments",
                body=chunk,
                prefer="return=minimal",
            )
            inserted_comments += len(chunk)
        except Exception as e:
            # Fall back to one-by-one
            for row in chunk:
                try:
                    db.request(
                        "POST",
                        "/rest/v1/post_comments",
                        body=row,
                        prefer="return=minimal",
                    )
                    inserted_comments += 1
                except Exception as e2:
                    # skip bad comment
                    _ = e2

    return {
        "status": "ok",
        "pack": pack.media_path,
        "post_id": post_id,
        "kind": pack.kind,
        "country": pack.country_code,
        "comments": inserted_comments,
    }


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--r2-env", default=str(DEFAULT_R2_ENV))
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--all", action="store_true", help="No per-country caps")
    p.add_argument("--sparks-per-country", type=int, default=None)
    p.add_argument("--longform-per-country", type=int, default=None)
    p.add_argument("--skip-sparks", action="store_true")
    p.add_argument("--skip-longform", action="store_true")
    p.add_argument("--workers", type=int, default=8)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Hard cap on total packs processed after caps/shuffle",
    )
    p.add_argument(
        "--log",
        default=str(ROOT / "scripts" / "seed_r2_focus_log.jsonl"),
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    rng = random.Random(args.seed)

    if not args.all and args.sparks_per_country is None and args.longform_per_country is None:
        # Safe default for first runs — full dump needs --all
        args.sparks_per_country = 100
        args.longform_per_country = 40
        print(
            f"[seed] default caps sparks={args.sparks_per_country}/country "
            f"longform={args.longform_per_country}/country (pass --all for everything)"
        )

    sb_url, sb_key = resolve_supabase()
    client, bucket = resolve_r2(Path(args.r2_env))
    db = SupabaseREST(sb_url, sb_key)

    print("[seed] loading profiles + categories…")
    profiles_by_cc = load_profiles(db)
    for code, lst in profiles_by_cc.items():
        print(f"  profiles {code}: {len(lst)}")
    categories = load_categories(db)
    print(f"  categories: {list(categories.keys())}")

    print("[seed] listing R2 packs…")
    packs = discover_packs(
        client,
        bucket,
        sparks=not args.skip_sparks,
        longform=not args.skip_longform,
    )
    print(f"  complete packs on R2: {len(packs)}")
    counts: Dict[str, int] = {}
    for p in packs:
        counts[f"{p.kind}:{p.country_code}"] = counts.get(f"{p.kind}:{p.country_code}", 0) + 1
    for k in sorted(counts):
        print(f"    {k}: {counts[k]}")

    print("[seed] loading existing r2 media_path set…")
    existing = load_existing_media_paths(db)
    print(f"  already seeded: {len(existing)}")

    packs = [p for p in packs if p.media_path not in existing]
    packs = apply_caps(
        packs,
        sparks_per_country=None if args.all else args.sparks_per_country,
        longform_per_country=None if args.all else args.longform_per_country,
        rng=rng,
    )
    if args.limit is not None:
        packs = packs[: args.limit]
    print(f"[seed] to process: {len(packs)} dry_run={args.dry_run}")

    log_path = Path(args.log)
    log_path.parent.mkdir(parents=True, exist_ok=True)

    stats = {"ok": 0, "dry_run": 0, "skip": 0, "error": 0}
    t0 = time.time()

    def work(pack: Pack) -> Dict[str, Any]:
        local_rng = random.Random(rng.random() + hash(pack.media_path) % 10_000)
        try:
            return seed_one(
                pack=pack,
                client=client,
                bucket=bucket,
                db=db,
                profiles=profiles_by_cc.get(pack.country_code, []),
                categories=categories,
                dry_run=args.dry_run,
                rng=local_rng,
            )
        except Exception as e:
            return {
                "status": "error",
                "pack": pack.media_path,
                "error": str(e)[:500],
            }

    workers = max(1, min(args.workers, 16))
    done = 0
    with log_path.open("a", encoding="utf-8") as logf:
        with ThreadPoolExecutor(max_workers=workers) as ex:
            futures = {ex.submit(work, p): p for p in packs}
            for fut in as_completed(futures):
                result = fut.result()
                status = result.get("status", "error")
                stats[status] = stats.get(status, 0) + 1
                logf.write(json.dumps(result, ensure_ascii=False) + "\n")
                logf.flush()
                done += 1
                if done % 25 == 0 or done == len(packs):
                    elapsed = time.time() - t0
                    rate = done / elapsed if elapsed else 0
                    print(
                        f"  [{done}/{len(packs)}] ok={stats.get('ok',0)} "
                        f"err={stats.get('error',0)} dry={stats.get('dry_run',0)} "
                        f"{rate:.1f}/s"
                    )
                    if status == "error":
                        print(f"    last error: {result.get('error') or result}")

    elapsed = time.time() - t0
    print(f"[seed] done in {elapsed:.1f}s  stats={stats}  log={log_path}")
    return 0 if stats.get("error", 0) == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
