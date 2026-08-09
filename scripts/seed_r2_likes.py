#!/usr/bin/env python3
"""Boost like_count on all R2-origin posts so the feed looks lively.

GraphQL now exposes greatest(posts.like_count, count(post_likes)).
Real post_likes rows still need DB GRANT for service_role (see migration).
"""

from __future__ import annotations

import json
import os
import random
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Optional

DEFAULT_SR = Path("/tmp/matterya_sr.key")
DEFAULT_SUPABASE = "https://bpdkltgikgbnfjswdbaj.supabase.co"

FILTERS = [
    ("r2-share:*", "spark_share", (80, 2400)),
    ("r2-hubshare:*", "hub_share", (40, 900)),
    ("r2:matterya-sparks/LongForm/*", "longform", (60, 1800)),
    ("r2:matterya-sparks/*", "r2_orig", (120, 8000)),  # last so LongForm not double-hit if we skip
]


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

    def get_all(self, path: str, query: dict, page=1000) -> List[dict]:
        out = []
        start = 0
        while True:
            headers = self.headers("count=exact")
            headers["Range"] = f"{start}-{start + page - 1}"
            url = self.base + path + "?" + urllib.parse.urlencode(query, doseq=True)
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=120) as r:
                batch = json.loads(r.read() or "[]")
                if not batch:
                    break
                out.extend(batch)
                cr = r.headers.get("Content-Range") or ""
                total = int(cr.split("/")[-1]) if "/" in cr else len(out)
                start += len(batch)
                if start >= total or len(batch) < page:
                    break
        return out

    def patch(self, path: str, query: dict, body: dict):
        url = self.base + path + "?" + urllib.parse.urlencode(query, doseq=True)
        req = urllib.request.Request(
            url,
            data=json.dumps(body).encode(),
            headers=self.headers("return=minimal"),
            method="PATCH",
        )
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status


def social_likes(rng: random.Random, lo: int, hi: int) -> int:
    # Log-ish distribution: many mid, some viral
    u = rng.random()
    if u < 0.55:
        return rng.randint(lo, int(lo + (hi - lo) * 0.25))
    if u < 0.85:
        return rng.randint(int(lo + (hi - lo) * 0.2), int(lo + (hi - lo) * 0.55))
    if u < 0.97:
        return rng.randint(int(lo + (hi - lo) * 0.5), int(lo + (hi - lo) * 0.85))
    return rng.randint(int(lo + (hi - lo) * 0.8), hi)


def main():
    url = os.environ.get("SUPABASE_URL", DEFAULT_SUPABASE).rstrip("/")
    key = (os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or "").strip()
    if not key and DEFAULT_SR.exists():
        key = DEFAULT_SR.read_text().strip()
    db = SB(url, key)
    rng = random.Random(42)

    seen = set()
    total = 0
    for filt, label, band in FILTERS:
        posts = db.get_all(
            "/rest/v1/posts",
            {"select": "id,like_count,media_path", "media_path": f"like.{filt}"},
        )
        # Skip LongForm rows when processing broad r2:matterya-sparks/*
        rows = []
        for p in posts:
            pid = p["id"]
            if pid in seen:
                continue
            mp = p.get("media_path") or ""
            if label == "r2_orig" and "/LongForm/" in mp:
                continue
            seen.add(pid)
            rows.append(p)
        print(f"[{label}] {len(rows)} posts band={band}")
        for p in rows:
            likes = social_likes(rng, band[0], band[1])
            # Never lower an existing higher seed
            cur = int(p.get("like_count") or 0)
            likes = max(likes, cur)
            try:
                db.patch(
                    "/rest/v1/posts",
                    {"id": f"eq.{p['id']}"},
                    {"like_count": likes},
                )
                total += 1
            except Exception as e:
                print("err", e)
                break
            if total % 500 == 0:
                print(f"  updated {total}…")
    print(f"[likes] done updated={total}")


if __name__ == "__main__":
    main()
