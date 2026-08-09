#!/usr/bin/env python3
"""Attach R2 LongForm to country Hubs channels + create feed shares from those channels.

Product:
  - LongForm lives on the country longform channel (Stateside Stories, Doku DE, …)
  - Feed shows them as **Hubs shares** (`__hub_origin__|…`) so they open as channel content
  - Balanced across US / DE / EG / AL

Usage:
  python3 scripts/seed_r2_longform_hub_shares.py
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
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

DEFAULT_SR = Path("/tmp/matterya_sr.key")
DEFAULT_SUPABASE = "https://bpdkltgikgbnfjswdbaj.supabase.co"

# Prefer handles that already have spark catalogs (*1), fall back to base names.
LONGFORM_HANDLES = {
    "US": ["stateside_stories1", "stateside_stories"],
    "DE": ["doku_deutschland1", "doku_deutschland"],
    "EG": ["egypt_docs1", "egypt_docs"],
    "AL": ["dokumentar_al1", "dokumentar_al"],
}

COUNTRY_NAME = {
    "US": "United States",
    "DE": "Germany",
    "EG": "Egypt",
    "AL": "Albania",
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

    def request(self, method: str, path: str, *, body=None, prefer=None, query=None):
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
            raise RuntimeError(f"{e.code} {method} {path}: {e.read()[:500]}") from e

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


def recent_ts(rng: random.Random, hours: float = 48) -> str:
    # Bias last 24h so feed head is full of multi-country hub shares
    if rng.random() < 0.7:
        offset = rng.uniform(0, 24 * 3600)
    else:
        offset = rng.uniform(0, hours * 3600)
    return (datetime.now(timezone.utc) - timedelta(seconds=offset)).isoformat().replace(
        "+00:00", "Z"
    )


def strip_hub_markers(body: str) -> str:
    lines = []
    for line in (body or "").splitlines():
        t = line.strip()
        if not t:
            continue
        if t.startswith("__hub_channel__") or t.startswith("__hub_origin__") or t.startswith("__spark"):
            continue
        lines.append(t)
    return "\n".join(lines).strip()


def hub_channel_body(title: str) -> str:
    t = strip_hub_markers(title) or "Long form"
    return f"__hub_channel__|\n{t}"


def hub_origin_body(
    *,
    sid: str,
    aid: str,
    an: str,
    au: str,
    caption: str,
) -> str:
    an = (an or "Channel").replace("|", " ").strip() or "Channel"
    au = re.sub(r"[^a-zA-Z0-9_]", "", (au or "").lstrip("@"))[:32]
    header = f"__hub_origin__|sid={sid}|aid={aid}|an={an}"
    if au:
        header += f"|au={au}"
    cap = (caption or "").strip()
    if not cap:
        return header
    return f"{header}\n{cap}"


def main():
    url = os.environ.get("SUPABASE_URL", DEFAULT_SUPABASE).rstrip("/")
    key = (os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or "").strip()
    if not key and DEFAULT_SR.exists():
        key = DEFAULT_SR.read_text().strip()
    db = SB(url, key)
    rng = random.Random(17)

    print("[hub-lf] loading channels…")
    channels = db.get_all("/rest/v1/channels", {"select": "id,name,handle,owner_user_id"})
    by_handle = {(c.get("handle") or "").lower(): c for c in channels}

    lf_channel: Dict[str, dict] = {}
    for cc, handles in LONGFORM_HANDLES.items():
        ch = None
        for h in handles:
            if h in by_handle:
                ch = by_handle[h]
                break
        if not ch:
            raise SystemExit(f"Missing longform channel for {cc}: {handles}")
        lf_channel[cc] = ch
        print(f"  {cc} → @{ch.get('handle')} {ch.get('name')} owner={ch['owner_user_id'][:8]}")

    # Load owner profiles for display names
    owners = {}
    for ch in lf_channel.values():
        oid = ch["owner_user_id"]
        if oid in owners:
            continue
        rows = db.request(
            "GET",
            "/rest/v1/profiles",
            query={"select": "user_id,display_name,username", "user_id": f"eq.{oid}", "limit": "1"},
        )
        owners[oid] = (rows or [{}])[0] if isinstance(rows, list) else {}

    print("[hub-lf] loading profiles for sharers…")
    profiles_by_cc = {}
    for cc in LONGFORM_HANDLES:
        profiles_by_cc[cc] = db.get_all(
            "/rest/v1/profiles",
            {"select": "user_id,country_code,country_name,city_name", "country_code": f"eq.{cc}"},
        )
        print(f"  {cc} profiles={len(profiles_by_cc[cc])}")

    print("[hub-lf] loading longform posts…")
    longforms = db.get_all(
        "/rest/v1/posts",
        {
            "select": "id,author_id,body,title,media_url,media_path,thumb_url,country_code,country_name,city_name,category_id,like_count,channel_id",
            "media_path": "like.r2:matterya-sparks/LongForm/*",
        },
    )
    print(f"  longform={len(longforms)}")

    # Existing hub shares
    existing_share_paths = {
        p.get("media_path")
        for p in db.get_all(
            "/rest/v1/posts",
            {"select": "media_path", "media_path": "like.r2-hubshare:*"},
        )
        if p.get("media_path")
    }
    print(f"  existing hubshares={len(existing_share_paths)}")

    attached = shared = err = 0
    t0 = time.time()

    for post in longforms:
        path = post.get("media_path") or ""
        # LongForm/<Country>/id/video.mp4
        m = re.search(r"LongForm/(United_States|Germany|Egypt|Albania)/", path)
        folder = m.group(1) if m else None
        cc_map = {
            "United_States": "US",
            "Germany": "DE",
            "Egypt": "EG",
            "Albania": "AL",
        }
        cc = cc_map.get(folder) or (post.get("country_code") or "US").upper()
        ch = lf_channel.get(cc)
        if not ch:
            err += 1
            continue

        owner = ch["owner_user_id"]
        title = (post.get("title") or strip_hub_markers(post.get("body") or "") or "Long form")[:200]
        body = hub_channel_body(title)

        # 1) Attach to channel as intentional Hubs upload
        try:
            db.request(
                "PATCH",
                "/rest/v1/posts",
                body={
                    "author_id": owner,
                    "channel_id": ch["id"],
                    "posted_by_user_id": owner,
                    "body": body,
                    "title": title,
                    "country_code": cc,
                    "country_name": COUNTRY_NAME.get(cc, post.get("country_name") or cc),
                },
                prefer="return=minimal",
                query={"id": f"eq.{post['id']}"},
            )
            attached += 1
        except Exception as e:
            err += 1
            if err <= 8:
                print("attach err", e)
            continue

        # 2) Feed share from a same-country user (hub origin → opens channel, not sharer's channel)
        share_path = f"r2-hubshare:{path[len('r2:') :]}" if path.startswith("r2:") else f"r2-hubshare:{post['id']}"
        if share_path in existing_share_paths:
            continue

        pool = [p for p in profiles_by_cc.get(cc, []) if p["user_id"] != owner]
        if not pool:
            pool = profiles_by_cc.get(cc, [])
        if not pool:
            continue
        sharer = rng.choice(pool)
        owner_prof = owners.get(owner) or {}
        an = ch.get("name") or owner_prof.get("display_name") or "Channel"
        au = ch.get("handle") or owner_prof.get("username") or ""
        share_body = hub_origin_body(
            sid=post["id"],
            aid=owner,
            an=an,
            au=au,
            caption=title,
        )
        created = recent_ts(rng)
        likes = max(1, int(post.get("like_count") or 10) // rng.randint(2, 8) + rng.randint(2, 40))
        row = {
            "author_id": sharer["user_id"],
            "category_id": post.get("category_id"),
            "country_name": sharer.get("country_name") or COUNTRY_NAME.get(cc, cc),
            "country_code": cc,
            "city_name": sharer.get("city_name"),
            "title": title,
            "body": share_body,
            "media_type": "video",
            "media_url": post.get("media_url"),
            "thumb_url": post.get("thumb_url"),
            "media_path": share_path,
            "visibility": "public",
            "like_count": likes,
            "comment_count": 0,
            "shared_post_id": post["id"],
            "channel_id": None,  # feed share — never attach to sharer's channel
            "created_at": created,
            "updated_at": created,
            "moderation_status": "active",
        }
        try:
            db.request("POST", "/rest/v1/posts", body=row, prefer="return=minimal")
            shared += 1
            existing_share_paths.add(share_path)
        except Exception as e:
            err += 1
            if err <= 8:
                print("share err", e)

    # Also freshen timestamps of existing multi-country spark shares so DE doesn't dominate recency alone
    print("[hub-lf] balancing spark-share timestamps across US/DE/EG/AL…")
    balanced = 0
    for cc in ("US", "DE", "EG", "AL"):
        shares = db.get_all(
            "/rest/v1/posts",
            {
                "select": "id",
                "media_path": "like.r2-share:*",
                "country_code": f"eq.{cc}",
            },
        )
        # Bump a head sample per country into the last day so recentPosts is multi-market
        sample = shares if len(shares) <= 200 else rng.sample(shares, 200)
        for s in sample:
            try:
                created = recent_ts(rng, hours=36)
                db.request(
                    "PATCH",
                    "/rest/v1/posts",
                    body={"created_at": created, "updated_at": created},
                    prefer="return=minimal",
                    query={"id": f"eq.{s['id']}"},
                )
                balanced += 1
            except Exception:
                pass
        print(f"  {cc} freshened {len(sample)} spark shares")

    print(
        f"[hub-lf] done in {time.time()-t0:.1f}s attached={attached} hub_shares={shared} "
        f"spark_share_fresh={balanced} err={err}"
    )

    # Verify
    for cc, ch in lf_channel.items():
        headers = db.headers("count=exact")
        headers["Range"] = "0-0"
        req = urllib.request.Request(
            url + f"/rest/v1/posts?select=id&channel_id=eq.{ch['id']}&limit=1",
            headers=headers,
        )
        with urllib.request.urlopen(req, timeout=60) as r:
            print(f"  channel @{ch.get('handle')} posts={r.headers.get('Content-Range')}")
    headers = db.headers("count=exact")
    headers["Range"] = "0-0"
    req = urllib.request.Request(
        url + "/rest/v1/posts?select=id&media_path=like.r2-hubshare:*&limit=1",
        headers=headers,
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        print("  hubshares", r.headers.get("Content-Range"))


if __name__ == "__main__":
    main()
