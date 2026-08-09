#!/usr/bin/env python3
"""Flood the home feed with R2 Spark *shares* (+ freshen longform).

Product rule:
  - Original Sparks (`__spark__|`) stay in the infinite Sparks player only.
  - Home feed shows **Spark shares** (`__spark_share__|sid=…`) as SparkFeedCards.

This script:
  1. For each R2 spark original, creates 1–2 share posts by other same-country users.
  2. Copies media (reel payload) so the share plays in-feed.
  3. Stamps recent created_at so they dominate `recentPosts`.
  4. Bumps R2 longform `created_at` so long videos also surface on feed.

Usage:
  python3 scripts/seed_r2_spark_shares_for_feed.py --dry-run
  python3 scripts/seed_r2_spark_shares_for_feed.py
  python3 scripts/seed_r2_spark_shares_for_feed.py --shares-per-spark 2 --limit 500
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

DEFAULT_SR = Path("/tmp/matterya_sr.key")
DEFAULT_SUPABASE = "https://bpdkltgikgbnfjswdbaj.supabase.co"

CAPTIONS = [
    "",
    "this one 🔥",
    "need this on loop",
    "sending this to everyone",
    "no notes",
    "how is this real",
    "ok wait",
    "the audio though",
    "I'm obsessed",
    "more of this please",
    "mood",
    "saw this and had to share",
    "😂😂😂",
    "//",
    "too good",
    "watch till the end",
]


class SupabaseREST:
    def __init__(self, base: str, key: str):
        self.base = base.rstrip("/")
        self.key = key

    def _headers(self, prefer: Optional[str] = None, extra: Optional[Dict[str, str]] = None) -> Dict[str, str]:
        h = {
            "apikey": self.key,
            "Authorization": f"Bearer {self.key}",
            "Content-Type": "application/json",
        }
        if prefer:
            h["Prefer"] = prefer
        if extra:
            h.update(extra)
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
            err = e.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"HTTP {e.code} {method} {path}: {err[:600]}") from e

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


def resolve_supabase() -> Tuple[str, str]:
    url = (os.environ.get("SUPABASE_URL") or DEFAULT_SUPABASE).rstrip("/")
    key = (os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or "").strip()
    if not key and DEFAULT_SR.exists():
        key = DEFAULT_SR.read_text().strip()
    if not key:
        raise SystemExit("Missing service role key")
    return url, key


def is_spark_original(body: str) -> bool:
    if "__spark_share__|" in (body or ""):
        return False
    return "__spark__|" in (body or "") or '"reel":true' in (body or "").lower()


def is_longform_path(media_path: str) -> bool:
    return "/LongForm/" in (media_path or "")


def share_media_path(origin_path: str) -> str:
    # r2:matterya-sparks/... → r2-share:matterya-sparks/...
    if origin_path.startswith("r2:"):
        return "r2-share:" + origin_path[3:]
    return f"r2-share:{origin_path}"


def mark_share_body(origin_id: str, caption: str) -> str:
    sid = origin_id.replace("|", "")
    header = f"__spark_share__|sid={sid}"
    cap = (caption or "").strip()
    if not cap:
        return header
    return f"{header}\n{cap}"


def ensure_reel_payload(media_url: Optional[str]) -> Optional[str]:
    if not media_url:
        return None
    raw = media_url.strip()
    if raw.startswith("{"):
        try:
            obj = json.loads(raw)
            if isinstance(obj, dict):
                obj["reel"] = True
                if "types" not in obj and "urls" in obj:
                    obj["types"] = ["video"] * len(obj.get("urls") or [])
                return json.dumps(obj, separators=(",", ":"))
        except json.JSONDecodeError:
            pass
    # Plain URL → wrap
    return json.dumps(
        {"urls": [raw], "types": ["video"], "reel": True, "source": "r2_spark_share"},
        separators=(",", ":"),
    )


def recent_ts(rng: random.Random, days: float = 5.0) -> str:
    # Bias toward the last 36h so the home feed head is full of shares.
    if rng.random() < 0.65:
        offset = rng.uniform(0, 36 * 3600)
    else:
        offset = rng.uniform(0, days * 24 * 3600)
    dt = datetime.now(timezone.utc) - timedelta(seconds=offset)
    return dt.isoformat().replace("+00:00", "Z")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--shares-per-spark", type=int, default=1, help="Shares per original Spark (1–2)")
    ap.add_argument("--limit", type=int, default=None, help="Max originals to share")
    ap.add_argument("--workers", type=int, default=10)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--skip-longform-bump", action="store_true")
    args = ap.parse_args()
    rng = random.Random(args.seed)
    shares_n = max(1, min(3, args.shares_per_spark))

    url, key = resolve_supabase()
    db = SupabaseREST(url, key)

    print("[feed-seed] loading profiles…")
    profiles_by_cc: Dict[str, List[dict]] = {}
    for cc in ("US", "DE", "EG", "AL"):
        profiles_by_cc[cc] = db.get_all(
            "/rest/v1/profiles",
            {
                "select": "user_id,country_code,country_name,city_name",
                "country_code": f"eq.{cc}",
            },
        )
        print(f"  {cc}: {len(profiles_by_cc[cc])} profiles")

    print("[feed-seed] loading R2 posts…")
    r2_posts = db.get_all(
        "/rest/v1/posts",
        {
            "select": "id,author_id,body,media_url,media_path,thumb_url,country_code,country_name,city_name,category_id,like_count,title",
            "media_path": "like.r2:matterya-sparks/*",
            "order": "created_at.desc",
        },
    )
    sparks = [
        p
        for p in r2_posts
        if not is_longform_path(p.get("media_path") or "")
        and is_spark_original(p.get("body") or "")
    ]
    longforms = [p for p in r2_posts if is_longform_path(p.get("media_path") or "")]
    print(f"  r2 total={len(r2_posts)} sparks={len(sparks)} longform={len(longforms)}")

    print("[feed-seed] existing shares…")
    existing_paths = {
        p.get("media_path")
        for p in db.get_all(
            "/rest/v1/posts",
            {"select": "media_path", "media_path": "like.r2-share:*"},
        )
        if p.get("media_path")
    }
    print(f"  existing r2-share paths: {len(existing_paths)}")

    if args.limit:
        rng.shuffle(sparks)
        sparks = sparks[: args.limit]

    # Build share jobs
    jobs: List[dict] = []
    for origin in sparks:
        cc = (origin.get("country_code") or "US").upper()
        pool = [u for u in profiles_by_cc.get(cc, []) if u["user_id"] != origin.get("author_id")]
        if not pool:
            pool = profiles_by_cc.get(cc) or []
        if not pool:
            continue
        base_path = share_media_path(origin.get("media_path") or origin["id"])
        for i in range(shares_n):
            path = base_path if i == 0 else f"{base_path}#{i}"
            if path in existing_paths:
                continue
            sharer = rng.choice(pool)
            caption = rng.choice(CAPTIONS)
            jobs.append(
                {
                    "origin": origin,
                    "sharer": sharer,
                    "media_path": path,
                    "caption": caption,
                    "created_at": recent_ts(rng),
                }
            )

    print(f"[feed-seed] share jobs: {len(jobs)} dry_run={args.dry_run}")
    if args.dry_run:
        for j in jobs[:5]:
            o = j["origin"]
            print(
                f"  sample {o.get('country_code')} sid={o['id'][:8]} "
                f"→ {j['sharer']['user_id'][:8]} cap={j['caption']!r}"
            )
        return 0

    ok = err = 0
    t0 = time.time()

    def insert_share(job: dict) -> str:
        origin = job["origin"]
        sharer = job["sharer"]
        media = ensure_reel_payload(origin.get("media_url"))
        body = mark_share_body(origin["id"], job["caption"])
        created = job["created_at"]
        likes = max(0, int(origin.get("like_count") or 0) // rng.randint(3, 12) + rng.randint(0, 40))
        row = {
            "author_id": sharer["user_id"],
            "category_id": origin.get("category_id"),
            "country_name": sharer.get("country_name") or origin.get("country_name") or "United States",
            "country_code": (sharer.get("country_code") or origin.get("country_code") or "US").upper(),
            "city_name": sharer.get("city_name") or origin.get("city_name"),
            "title": None,
            "body": body,
            "media_type": "video",
            "media_url": media,
            "thumb_url": origin.get("thumb_url"),
            "media_path": job["media_path"],
            "visibility": "public",
            "like_count": likes,
            "comment_count": 0,
            "shared_post_id": origin["id"],
            "channel_id": None,
            "created_at": created,
            "updated_at": created,
            "moderation_status": "active",
        }
        db.request(
            "POST",
            "/rest/v1/posts",
            body=row,
            prefer="return=minimal",
        )
        return "ok"

    with ThreadPoolExecutor(max_workers=max(1, min(args.workers, 16))) as ex:
        futs = {ex.submit(insert_share, j): j for j in jobs}
        done = 0
        for fut in as_completed(futs):
            done += 1
            try:
                fut.result()
                ok += 1
            except Exception as e:
                err += 1
                if err <= 10:
                    print(f"  ERR: {e}")
            if done % 100 == 0 or done == len(jobs):
                print(f"  shares {done}/{len(jobs)} ok={ok} err={err}")

    # Freshen longform so they also appear near the top of feed (not sparks — long video cards).
    if not args.skip_longform_bump and longforms:
        print(f"[feed-seed] bumping {len(longforms)} longform timestamps…")
        bumped = 0
        for post in longforms:
            created = recent_ts(rng, days=7.0)
            try:
                db.request(
                    "PATCH",
                    "/rest/v1/posts",
                    body={"created_at": created, "updated_at": created},
                    query={"id": f"eq.{post['id']}"},
                    prefer="return=minimal",
                )
                bumped += 1
            except Exception as e:
                if bumped < 3:
                    print(f"  longform bump err: {e}")
        print(f"  longform bumped={bumped}")

    # Also freshen a sample of original sparks' created_at so Sparks-for-you rail stays rich
    # (they stay excluded from home list, but rails may load them).
    print("[feed-seed] freshening spark originals (player pool)…")
    freshened = 0
    sample = sparks if len(sparks) <= 800 else rng.sample(sparks, 800)
    for post in sample:
        created = recent_ts(rng, days=4.0)
        try:
            db.request(
                "PATCH",
                "/rest/v1/posts",
                body={"created_at": created, "updated_at": created},
                query={"id": f"eq.{post['id']}"},
                prefer="return=minimal",
            )
            freshened += 1
        except Exception:
            pass
    print(f"  spark originals freshened={freshened}")

    elapsed = time.time() - t0
    print(f"[feed-seed] done shares_ok={ok} err={err} in {elapsed:.1f}s")

    # Verify
    headers, _ = db.request(
        "GET",
        "/rest/v1/posts",
        query={"select": "id", "body": "like.*__spark_share__|*", "limit": "1"},
        prefer="count=exact",
    )
    # Prefer header via get with Range
    req_headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Prefer": "count=exact",
        "Range": "0-0",
    }
    req = urllib.request.Request(
        url + "/rest/v1/posts?select=id&body=like.*__spark_share__%7C*&limit=1",
        headers=req_headers,
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        print("  spark_share total:", resp.headers.get("Content-Range"))
    req = urllib.request.Request(
        url + "/rest/v1/posts?select=id&media_path=like.r2-share:*&limit=1",
        headers=req_headers,
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        print("  r2-share total:", resp.headers.get("Content-Range"))
    return 0 if err == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
