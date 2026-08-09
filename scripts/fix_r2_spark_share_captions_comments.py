#!/usr/bin/env python3
"""Replace seeder fluff on spark *shares* with R2 captions + R2 comments from the original.

Shares currently look like:
  body: __spark_share__|sid=…\\nno notes
  comments: 0

After:
  body: __spark_share__|sid=…\\n{original R2 title/caption}
  comments: copied from original (same text, country users as authors)
  comment_count: matches
"""

from __future__ import annotations

import json
import os
import random
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

DEFAULT_SR = Path("/tmp/matterya_sr.key")
DEFAULT_SUPABASE = "https://bpdkltgikgbnfjswdbaj.supabase.co"

# Seeder fluff we must never show as captions
FAKE_CAPTIONS = {
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
}


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
        self, method: str, path: str, *, body: Any = None, prefer: Optional[str] = None, query=None
    ):
        url = self.base + path
        if query:
            url += "?" + urllib.parse.urlencode(query, doseq=True)
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(url, data=data, headers=self.headers(prefer), method=method)
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                raw = r.read().decode()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            raise RuntimeError(f"{e.code} {method} {path}: {e.read()[:400]}") from e

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


def strip_markers(body: str) -> str:
    lines = []
    for line in (body or "").splitlines():
        t = line.strip()
        if not t:
            continue
        if t.startswith("__"):
            # keep text after __spark__| on same line
            if t.startswith("__spark__|"):
                rest = t[len("__spark__|") :].strip()
                if rest:
                    lines.append(rest)
            continue
        lines.append(t)
    text = "\n".join(lines).strip()
    # Drop known fake share lines
    if text in FAKE_CAPTIONS:
        return ""
    return text


def parse_sid(body: str) -> Optional[str]:
    for line in (body or "").splitlines():
        t = line.strip()
        if t.startswith("__spark_share__|"):
            rest = t[len("__spark_share__|") :]
            for part in rest.split("|"):
                if part.startswith("sid="):
                    return part[4:].strip() or None
    return None


def main():
    url = os.environ.get("SUPABASE_URL", DEFAULT_SUPABASE).rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not key and DEFAULT_SR.exists():
        key = DEFAULT_SR.read_text().strip()
    db = SB(url, key)
    rng = random.Random(3)

    print("[fix] loading profiles for comment authors…")
    profiles_by_cc = {}
    for cc in ("US", "DE", "EG", "AL"):
        profiles_by_cc[cc] = db.get_all(
            "/rest/v1/profiles",
            {"select": "user_id", "country_code": f"eq.{cc}"},
        )
        print(f"  {cc}: {len(profiles_by_cc[cc])}")

    print("[fix] loading spark shares…")
    shares = db.get_all(
        "/rest/v1/posts",
        {
            "select": "id,body,shared_post_id,country_code,comment_count,media_path",
            "media_path": "like.r2-share:*",
        },
    )
    print(f"  shares: {len(shares)}")

    print("[fix] loading R2 spark originals…")
    origins = {
        p["id"]: p
        for p in db.get_all(
            "/rest/v1/posts",
            {
                "select": "id,body,comment_count,country_code",
                "media_path": "like.r2:matterya-sparks/*",
            },
        )
    }
    print(f"  origins: {len(origins)}")

    # Preload origin comments in batches by querying per-origin only when needed (lazy).
    origin_comments_cache: Dict[str, List[dict]] = {}

    def get_origin_comments(oid: str) -> List[dict]:
        if oid in origin_comments_cache:
            return origin_comments_cache[oid]
        rows = db.get_all(
            "/rest/v1/post_comments",
            {
                "select": "body,author_id,created_at",
                "post_id": f"eq.{oid}",
                "order": "created_at",
            },
        )
        origin_comments_cache[oid] = rows
        return rows

    ok_cap = ok_com = err = 0
    t0 = time.time()

    def fix_one(share: dict) -> str:
        nonlocal ok_cap, ok_com, err
        sid = share.get("shared_post_id") or parse_sid(share.get("body") or "")
        if not sid or sid not in origins:
            return "skip"
        origin = origins[sid]
        caption = strip_markers(origin.get("body") or "")
        if not caption:
            caption = ""  # leave empty rather than fake

        new_body = f"__spark_share__|sid={sid}"
        if caption:
            new_body = f"{new_body}\n{caption}"

        # Always rewrite body to R2 caption (removes seeder fluff)
        try:
            db.request(
                "PATCH",
                "/rest/v1/posts",
                body={"body": new_body},
                prefer="return=minimal",
                query={"id": f"eq.{share['id']}"},
            )
            ok_cap += 1
        except Exception as e:
            err += 1
            if err <= 5:
                print("cap err", e)
            return "err"

        # Copy comments if share empty
        if int(share.get("comment_count") or 0) > 0:
            return "ok"
        ocomments = get_origin_comments(sid)
        if not ocomments:
            return "ok"

        cc = (share.get("country_code") or origin.get("country_code") or "US").upper()
        pool = profiles_by_cc.get(cc) or profiles_by_cc.get("US") or []
        if not pool:
            return "ok"

        # Copy full origin thread (no artificial cap — matches R2 comments.json size).
        rows = []
        for i, c in enumerate(ocomments):
            text = (c.get("body") or "").strip()
            if not text or len(text) > 5000:
                continue
            author = pool[i % len(pool)]["user_id"]
            # Prefer original comment author if still a real uuid in our DB — skip check, use pool for safety
            rows.append(
                {
                    "post_id": share["id"],
                    "author_id": author,
                    "body": text[:5000],
                    "created_at": c.get("created_at"),
                    "updated_at": c.get("created_at"),
                }
            )
        if not rows:
            return "ok"
        try:
            # batch insert
            for i in range(0, len(rows), 40):
                chunk = rows[i : i + 40]
                db.request(
                    "POST",
                    "/rest/v1/post_comments",
                    body=chunk,
                    prefer="return=minimal",
                )
            ok_com += 1
        except Exception as e:
            # one-by-one
            n = 0
            for row in rows:
                try:
                    db.request(
                        "POST",
                        "/rest/v1/post_comments",
                        body=row,
                        prefer="return=minimal",
                    )
                    n += 1
                except Exception:
                    pass
            if n:
                ok_com += 1
            else:
                err += 1
                if err <= 5:
                    print("com err", e)
        return "ok"

    print(f"[fix] fixing {len(shares)} shares…")
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = [ex.submit(fix_one, s) for s in shares]
        done = 0
        for f in as_completed(futs):
            done += 1
            if done % 200 == 0:
                print(f"  {done}/{len(shares)} cap={ok_cap} com={ok_com} err={err}")
            try:
                f.result()
            except Exception as e:
                err += 1
                if err <= 5:
                    print(e)

    print(
        f"[fix] done in {time.time()-t0:.1f}s captions={ok_cap} comments_batches={ok_com} err={err}"
    )

    # Sample
    sample = db.get_all(
        "/rest/v1/posts",
        {
            "select": "id,body,comment_count",
            "media_path": "like.r2-share:*",
            "order": "comment_count.desc",
            "limit": "3",
        },
    )
    # order+limit in get_all via query - PostgREST uses order=
    sample = db.request(
        "GET",
        "/rest/v1/posts",
        query={
            "select": "id,body,comment_count",
            "media_path": "like.r2-share:*",
            "order": "comment_count.desc",
            "limit": "3",
        },
        prefer="return=representation",
    )
    # GET with Prefer return doesn't work that way - use urllib
    headers = db.headers()
    req = urllib.request.Request(
        url
        + "/rest/v1/posts?select=id,body,comment_count&media_path=like.r2-share:*&order=comment_count.desc&limit=3",
        headers=headers,
    )
    rows = json.loads(urllib.request.urlopen(req).read())
    for r in rows:
        print("SAMPLE", r["comment_count"], (r["body"] or "")[:100].replace("\n", " | "))


if __name__ == "__main__":
    main()
