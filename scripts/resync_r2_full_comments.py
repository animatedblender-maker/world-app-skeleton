#!/usr/bin/env python3
"""Re-sync full comments.json from R2 into Supabase for existing R2 posts.

Why: seed_r2_focus_four_countries.py used to cap at MAX_COMMENTS_PER_POST=25,
so every Spark showed exactly 25 comments even when comments.json had more.
Also posts.comment_count often drifted (e.g. 50) from the real row count.

This script:
  1. Loads every post with media_path like r2:matterya-sparks/*
  2. Fetches that pack's comments.json from R2 (all comments, no cap)
  3. Replaces post_comments for that post
  4. Sets posts.comment_count to the real inserted count
  5. Re-copies full origin threads onto __spark_share__ posts

Usage:
  python3 scripts/resync_r2_full_comments.py --dry-run
  python3 scripts/resync_r2_full_comments.py
  python3 scripts/resync_r2_full_comments.py --limit 20
  python3 scripts/resync_r2_full_comments.py --skip-shares
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    import boto3
    from botocore.config import Config
except ImportError:
    print("boto3 required: pip install boto3", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_R2_ENV = Path(
    "/Volumes/MatteryaSSD/Development/TikTok-Api/TikTokDashboard/.env.r2"
)
DEFAULT_SR_KEY_FILE = Path("/tmp/matterya_sr.key")
DEFAULT_SUPABASE_URL = "https://bpdkltgikgbnfjswdbaj.supabase.co"
MEDIA_PREFIX = "r2:matterya-sparks/"
MAX_COMMENT_BODY = 5000
BATCH = 80


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
        raise SystemExit("Missing SUPABASE_SERVICE_ROLE_KEY (or /tmp/matterya_sr.key)")
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


class SB:
    def __init__(self, base: str, key: str):
        self.base = base.rstrip("/")
        self.key = key

    def headers(self, prefer: Optional[str] = None) -> Dict[str, str]:
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
        query: Optional[dict] = None,
        timeout: int = 180,
    ):
        url = self.base + path
        if query:
            url += "?" + urllib.parse.urlencode(query, doseq=True)
        data = None if body is None else json.dumps(body).encode("utf-8")
        req = urllib.request.Request(
            url, data=data, headers=self.headers(prefer), method=method
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                raw = r.read().decode("utf-8")
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            raise RuntimeError(
                f"{e.code} {method} {path}: {e.read()[:500].decode(errors='ignore')}"
            ) from e

    def get_all(self, path: str, query: dict, page: int = 1000) -> List[dict]:
        out: List[dict] = []
        start = 0
        while True:
            headers = self.headers("count=exact")
            headers["Range"] = f"{start}-{start + page - 1}"
            url = self.base + path + "?" + urllib.parse.urlencode(query, doseq=True)
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=180) as r:
                batch = json.loads(r.read() or "[]")
                if not batch:
                    break
                out.extend(batch)
                cr = r.headers.get("Content-Range") or ""
                total = int(cr.split("/")[-1]) if "/" in cr and cr.split("/")[-1].isdigit() else len(out)
                start += len(batch)
                if start >= total or len(batch) < page:
                    break
        return out


def clean_text(text: Any, max_len: int) -> str:
    if text is None:
        return ""
    s = str(text).replace("\x00", "").strip()
    # Never surface the source platform name in comments / captions.
    s = re.sub(r"tiktok", "matterya", s, flags=re.IGNORECASE)
    if len(s) > max_len:
        s = s[:max_len]
    return s


def extract_comments(raw: Any) -> List[dict]:
    """Full comments.json — no artificial cap."""
    if raw is None:
        return []
    if isinstance(raw, list):
        items = raw
    elif isinstance(raw, dict):
        items = []
        for k in ("comments", "data", "items", "results"):
            if isinstance(raw.get(k), list):
                items = raw[k]
                break
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
        if not text:
            continue
        likes = item.get("digg_count") or item.get("like_count") or item.get("likes") or 0
        try:
            likes = int(likes)
        except (TypeError, ValueError):
            likes = 0
        out.append({"text": text, "likes": max(0, likes)})
    out.sort(key=lambda c: c["likes"], reverse=True)
    return out


def media_path_to_comments_key(media_path: str) -> Optional[str]:
    if not media_path or not media_path.startswith(MEDIA_PREFIX):
        return None
    key = media_path[len(MEDIA_PREFIX) :]
    if key.endswith("/video.mp4"):
        return key[: -len("video.mp4")] + "comments.json"
    if key.endswith("video.mp4"):
        return key[: -len("video.mp4")] + "comments.json"
    # fallback: sibling comments.json
    if "/" in key:
        return key.rsplit("/", 1)[0] + "/comments.json"
    return None


def s3_json(client, bucket: str, key: str) -> Any:
    obj = client.get_object(Bucket=bucket, Key=key)
    return json.loads(obj["Body"].read())


def replace_comments(
    db: SB,
    post_id: str,
    comments: List[dict],
    author_ids: List[str],
    rng: random.Random,
    dry_run: bool,
) -> int:
    if not author_ids:
        return 0
    if dry_run:
        return len(comments)

    # Wipe existing seed comments for this post (trigger will zero comment_count).
    db.request(
        "DELETE",
        "/rest/v1/post_comments",
        prefer="return=minimal",
        query={"post_id": f"eq.{post_id}"},
    )

    if not comments:
        db.request(
            "PATCH",
            "/rest/v1/posts",
            body={"comment_count": 0},
            prefer="return=minimal",
            query={"id": f"eq.{post_id}"},
        )
        return 0

    pool = list(author_ids)
    rng.shuffle(pool)
    now = datetime.now(timezone.utc)
    rows: List[dict] = []
    for i, c in enumerate(comments):
        c_at = (now - timedelta(minutes=rng.randint(1, 60 * 24 * 14))).isoformat().replace(
            "+00:00", "Z"
        )
        rows.append(
            {
                "post_id": post_id,
                "author_id": pool[i % len(pool)],
                "body": c["text"],
                "created_at": c_at,
                "updated_at": c_at,
            }
        )

    inserted = 0
    for i in range(0, len(rows), BATCH):
        chunk = rows[i : i + BATCH]
        try:
            db.request(
                "POST",
                "/rest/v1/post_comments",
                body=chunk,
                prefer="return=minimal",
            )
            inserted += len(chunk)
        except Exception:
            for row in chunk:
                try:
                    db.request(
                        "POST",
                        "/rest/v1/post_comments",
                        body=row,
                        prefer="return=minimal",
                    )
                    inserted += 1
                except Exception:
                    pass

    # Force exact count (trigger may drift under bulk delete/insert races).
    db.request(
        "PATCH",
        "/rest/v1/posts",
        body={"comment_count": inserted},
        prefer="return=minimal",
        query={"id": f"eq.{post_id}"},
    )
    return inserted


def parse_share_sid(body: str) -> Optional[str]:
    if not body:
        return None
    m = re.search(r"__spark_share__\|sid=([0-9a-fA-F-]{36})", body)
    return m.group(1) if m else None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--r2-env", default=str(DEFAULT_R2_ENV))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=0, help="Max origin posts to resync (0=all)")
    ap.add_argument("--workers", type=int, default=10)
    ap.add_argument("--skip-shares", action="store_true")
    ap.add_argument("--only-shares", action="store_true")
    args = ap.parse_args()

    url, key = resolve_supabase()
    db = SB(url, key)
    client, bucket = resolve_r2(Path(args.r2_env))
    rng = random.Random(42)

    print("[resync] loading profiles…")
    profiles = db.get_all(
        "/rest/v1/profiles",
        {"select": "user_id,country_code", "country_code": "in.(US,DE,EG,AL)"},
    )
    by_cc: Dict[str, List[str]] = {}
    for p in profiles:
        cc = (p.get("country_code") or "").upper()
        if cc and p.get("user_id"):
            by_cc.setdefault(cc, []).append(p["user_id"])
    fallback_authors = [p["user_id"] for p in profiles if p.get("user_id")]
    print(f"[resync] profiles: { {k: len(v) for k, v in sorted(by_cc.items())} }")

    if not args.only_shares:
        print("[resync] loading R2 origin posts…")
        posts = db.get_all(
            "/rest/v1/posts",
            {
                "select": "id,media_path,country_code,comment_count",
                "media_path": f"like.{MEDIA_PREFIX}*",
                "order": "created_at.desc",
            },
        )
        if args.limit and args.limit > 0:
            posts = posts[: args.limit]
        print(f"[resync] origin posts: {len(posts)} dry_run={args.dry_run}")

        # Cache comments.json per R2 key (shares reuse origins).
        comments_cache: Dict[str, List[dict]] = {}
        cache_lock = threading.Lock()
        stats = {"ok": 0, "err": 0, "empty": 0, "skipped": 0, "comments": 0}
        stats_lock = threading.Lock()
        t0 = time.time()

        def load_comments(ckey: str) -> List[dict]:
            with cache_lock:
                if ckey in comments_cache:
                    return comments_cache[ckey]
            try:
                raw = s3_json(client, bucket, ckey)
                extracted = extract_comments(raw)
            except Exception as e:
                if "NoSuchKey" in str(e) or "404" in str(e):
                    extracted = []
                else:
                    raise
            with cache_lock:
                comments_cache[ckey] = extracted
                return comments_cache[ckey]

        def work(post: dict) -> Tuple[str, int, str]:
            pid = post["id"]
            mp = post.get("media_path") or ""
            ckey = media_path_to_comments_key(mp)
            if not ckey:
                return "skip", 0, pid
            try:
                comments = load_comments(ckey)
                cc = (post.get("country_code") or "US").upper()
                authors = by_cc.get(cc) or by_cc.get("US") or fallback_authors
                # Per-task RNG so concurrent workers don't share Random state.
                n = replace_comments(
                    db, pid, comments, authors, random.Random(hash(pid) & 0xFFFFFFFF), args.dry_run
                )
                return ("empty" if n == 0 else "ok"), n, pid
            except Exception as e:
                return "err", 0, f"{pid}: {e}"

        with ThreadPoolExecutor(max_workers=max(1, args.workers)) as ex:
            futs = [ex.submit(work, p) for p in posts]
            done = 0
            for f in as_completed(futs):
                status, n, detail = f.result()
                with stats_lock:
                    key = status if status in stats else "err"
                    stats[key] = stats.get(key, 0) + 1
                    if status == "ok":
                        stats["comments"] += n
                    err_n = stats["err"]
                if status == "err" and err_n <= 8:
                    print("  err", detail)
                done += 1
                if done % 100 == 0 or done == len(posts):
                    elapsed = time.time() - t0
                    with stats_lock:
                        snap = dict(stats)
                    print(
                        f"  {done}/{len(posts)} ok={snap['ok']} empty={snap['empty']} "
                        f"err={snap['err']} comments+={snap['comments']} {elapsed:.0f}s"
                    )

        print(f"[resync] origins done: {stats}")

    if not args.skip_shares:
        print("[resync] re-copying full comments onto spark shares…")
        shares = db.get_all(
            "/rest/v1/posts",
            {
                "select": "id,body,shared_post_id,country_code,comment_count",
                "body": "like.__spark_share__*",
                "order": "created_at.desc",
            },
        )
        if args.limit and args.limit > 0 and args.only_shares:
            shares = shares[: args.limit]
        print(f"[resync] shares: {len(shares)}")

        # Preload origin comments
        origin_ids = set()
        for s in shares:
            sid = s.get("shared_post_id") or parse_share_sid(s.get("body") or "")
            if sid:
                origin_ids.add(sid)

        origin_comments: Dict[str, List[dict]] = {}
        # Fetch in chunks by id — PostgREST in.() has URL limits; page origins.
        origin_list = list(origin_ids)
        for i in range(0, len(origin_list), 50):
            chunk = origin_list[i : i + 50]
            ids = ",".join(chunk)
            rows = db.get_all(
                "/rest/v1/post_comments",
                {
                    "select": "post_id,body,created_at",
                    "post_id": f"in.({ids})",
                    "order": "created_at",
                },
            )
            for r in rows:
                origin_comments.setdefault(r["post_id"], []).append(r)

        print(f"[resync] origin threads loaded for {len(origin_comments)} posts")

        s_ok = s_skip = s_err = s_com = 0
        t1 = time.time()

        def fix_share(share: dict) -> str:
            nonlocal s_ok, s_skip, s_err, s_com
            sid = share.get("shared_post_id") or parse_share_sid(share.get("body") or "")
            if not sid:
                s_skip += 1
                return "skip"
            ocomments = origin_comments.get(sid) or []
            if not ocomments:
                s_skip += 1
                return "skip"
            # Always rewrite from origin so badge + rows match full R2 thread
            # (comment_count often drifted, e.g. 50 with only 25 rows).

            cc = (share.get("country_code") or "US").upper()
            authors = by_cc.get(cc) or by_cc.get("US") or fallback_authors
            comments = [{"text": (c.get("body") or "").strip()} for c in ocomments]
            comments = [c for c in comments if c["text"]]
            try:
                n = replace_comments(
                    db, share["id"], comments, authors, rng, args.dry_run
                )
                s_ok += 1
                s_com += n
                return "ok"
            except Exception as e:
                s_err += 1
                if s_err <= 5:
                    print("  share err", e)
                return "err"

        with ThreadPoolExecutor(max_workers=max(1, args.workers)) as ex:
            futs = [ex.submit(fix_share, s) for s in shares]
            done = 0
            for f in as_completed(futs):
                f.result()
                done += 1
                if done % 200 == 0 or done == len(shares):
                    print(
                        f"  shares {done}/{len(shares)} ok={s_ok} skip={s_skip} "
                        f"err={s_err} comments+={s_com} {time.time()-t1:.0f}s"
                    )

        print(f"[resync] shares done ok={s_ok} skip={s_skip} err={s_err} comments={s_com}")

    print("[resync] complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
