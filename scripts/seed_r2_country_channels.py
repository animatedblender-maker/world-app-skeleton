#!/usr/bin/env python3
"""Create Hubs channels for R2 focus-country content and attach seeded posts.

One channel per owner (DB constraint). Picks free profiles per country, creates
named channels, stamps posts with __hub_channel__|, reassigns author_id + channel_id.

Usage:
  python3 scripts/seed_r2_country_channels.py --dry-run
  python3 scripts/seed_r2_country_channels.py
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
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SR = Path("/tmp/matterya_sr.key")
DEFAULT_SUPABASE = "https://bpdkltgikgbnfjswdbaj.supabase.co"
PLATFORM_READY = Path("/Volumes/MatteryaSSD/Development/TikTokVideos/PlatformReady")

# genre folder / meta genre → channel slot key
GENRE_SLOT = {
    "music": "music",
    "comedy": "comedy",
    "dance": "dance",
    "travel": "lifestyle",
    "tech": "lifestyle",
    "sports": "lifestyle",
    "romance": "lifestyle",
    "animals": "lifestyle",
    "education": "lifestyle",
    "asmr": "lifestyle",
    "food": "lifestyle",
    "other": "flagship",
    "fitness": "lifestyle",
    "nature": "lifestyle",
    "film": "lifestyle",
    "culture": "lifestyle",
}

# Thematic channels per launch country.
# slot keys: flagship | music | comedy | dance | lifestyle | longform
COUNTRY_CHANNELS: Dict[str, List[Dict[str, str]]] = {
    "US": [
        {
            "slot": "flagship",
            "name": "America Live",
            "handle": "america_live",
            "about": "Daily Sparks from across the United States — trends, streets, and moments.",
        },
        {
            "slot": "music",
            "name": "US Music Room",
            "handle": "us_music_room",
            "about": "American music Sparks — beats, covers, and sound-on energy.",
        },
        {
            "slot": "comedy",
            "name": "Laugh USA",
            "handle": "laugh_usa",
            "about": "Comedy Sparks from the States. Keep it light.",
        },
        {
            "slot": "dance",
            "name": "Dance Floor USA",
            "handle": "dance_floor_usa",
            "about": "US dance challenges, freestyle, and choreo Sparks.",
        },
        {
            "slot": "lifestyle",
            "name": "Daily America",
            "handle": "daily_america",
            "about": "Travel, tech, sports, and everyday US Sparks.",
        },
        {
            "slot": "longform",
            "name": "Stateside Stories",
            "handle": "stateside_stories",
            "about": "Long-form documentaries and deep cuts from the American catalog.",
        },
    ],
    "DE": [
        {
            "slot": "flagship",
            "name": "Deutschland Jetzt",
            "handle": "deutschland_jetzt",
            "about": "Sparks aus Deutschland — Trends, Straßen, Alltagsmomente.",
        },
        {
            "slot": "music",
            "name": "Musik DE",
            "handle": "musik_de",
            "about": "Deutsche Musik-Sparks — Beats, Covers und Ohrwürmer.",
        },
        {
            "slot": "comedy",
            "name": "Lachen DE",
            "handle": "lachen_de",
            "about": "Comedy-Sparks aus Deutschland.",
        },
        {
            "slot": "dance",
            "name": "Tanz DE",
            "handle": "tanz_de",
            "about": "Tanz-Challenges und Moves aus DE.",
        },
        {
            "slot": "lifestyle",
            "name": "Alltag DE",
            "handle": "alltag_de",
            "about": "Reise, Tech, Sport und Alltag aus Deutschland.",
        },
        {
            "slot": "longform",
            "name": "Doku Deutschland",
            "handle": "doku_deutschland",
            "about": "Lange Videos und Dokus aus dem deutschen Katalog.",
        },
    ],
    "EG": [
        {
            "slot": "flagship",
            "name": "مصر الآن",
            "handle": "egypt_now",
            "about": "Sparks from Egypt — Cairo energy, trends, and daily life. مصر على Matterya.",
        },
        {
            "slot": "music",
            "name": "نغم مصر",
            "handle": "egypt_music",
            "about": "موسيقى مصرية — beats, covers, and sound-on Sparks.",
        },
        {
            "slot": "comedy",
            "name": "ضحك مصر",
            "handle": "egypt_comedy",
            "about": "كوميديا مصرية — comedy Sparks from Egypt.",
        },
        {
            "slot": "dance",
            "name": "رقص مصر",
            "handle": "egypt_dance",
            "about": "رقص وتحديات — dance Sparks from Egypt.",
        },
        {
            "slot": "lifestyle",
            "name": "يوميات مصر",
            "handle": "egypt_daily",
            "about": "سفر، رياضة، وتكنولوجيا — lifestyle Sparks from Egypt.",
        },
        {
            "slot": "longform",
            "name": "وثائقيات مصر",
            "handle": "egypt_docs",
            "about": "فيديوهات طويلة ووثائقيات من كتالوج مصر.",
        },
    ],
    "AL": [
        {
            "slot": "flagship",
            "name": "Shqipëria Live",
            "handle": "shqiperia_live",
            "about": "Sparks nga Shqipëria — trendet, rrugët dhe momentet e përditshme.",
        },
        {
            "slot": "music",
            "name": "Muzikë AL",
            "handle": "muzike_al",
            "about": "Muzikë shqiptare — beats, lyrics dhe Sparks me zë.",
        },
        {
            "slot": "comedy",
            "name": "Humor AL",
            "handle": "humor_al",
            "about": "Komedi dhe Sparks argëtuese nga Shqipëria.",
        },
        {
            "slot": "dance",
            "name": "Valle AL",
            "handle": "valle_al",
            "about": "Valle dhe sfida kërcimi nga Shqipëria.",
        },
        {
            "slot": "lifestyle",
            "name": "Jeta AL",
            "handle": "jeta_al",
            "about": "Udhëtime, sport, tech dhe jeta e përditshme.",
        },
        {
            "slot": "longform",
            "name": "Dokumentar AL",
            "handle": "dokumentar_al",
            "about": "Video të gjata dhe dokumentarë nga katalogu shqiptar.",
        },
    ],
}

COUNTRY_FOLDER = {
    "US": "United_States",
    "DE": "Germany",
    "EG": "Egypt",
    "AL": "Albania",
}


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
        extra_headers: Optional[Dict[str, str]] = None,
        timeout: int = 120,
    ) -> Tuple[Dict[str, str], Any]:
        url = self.base + path
        if query:
            url += "?" + urllib.parse.urlencode(query, doseq=True)
        data = None if body is None else json.dumps(body).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=data,
            headers=self._headers(prefer, extra_headers),
            method=method,
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
            raise RuntimeError(f"HTTP {e.code} {method} {path}: {err[:800]}") from e

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
        raise SystemExit("Missing SUPABASE_SERVICE_ROLE_KEY /tmp/matterya_sr.key")
    return url, key


def build_genre_map() -> Dict[str, str]:
    """Map tiktok video_id → genre from local PlatformReady layout."""
    out: Dict[str, str] = {}
    if not PLATFORM_READY.exists():
        print(f"[channels] WARN local staging missing: {PLATFORM_READY}")
        return out
    for folder in COUNTRY_FOLDER.values():
        root = PLATFORM_READY / folder
        if not root.exists():
            continue
        for genre_dir in root.iterdir():
            if not genre_dir.is_dir():
                continue
            genre = genre_dir.name
            for pack in genre_dir.iterdir():
                if pack.is_dir():
                    out[pack.name] = genre
    print(f"[channels] genre map size={len(out)}")
    return out


def parse_r2_pack(media_path: str) -> Optional[Tuple[str, str, str]]:
    """Return (kind, country_folder, video_id) from media_path."""
    # r2:matterya-sparks/United_States/123/video.mp4
    # r2:matterya-sparks/LongForm/Egypt/abc/video.mp4
    if not media_path or not media_path.startswith("r2:matterya-sparks/"):
        return None
    rest = media_path[len("r2:matterya-sparks/") :]
    parts = rest.split("/")
    if len(parts) >= 3 and parts[0] == "LongForm":
        return "longform", parts[1], parts[2]
    if len(parts) >= 2:
        return "spark", parts[0], parts[1]
    return None


def stamp_hub_channel(body: str) -> str:
    body = (body or "").strip()
    if "__hub_channel__|" in body:
        return body
    if not body:
        return "__hub_channel__|"
    return f"__hub_channel__|\n{body}"


def living_bio(about: str, channel_name: str) -> str:
    about = (about or "").strip()
    lines = []
    if about:
        lines.append(about)
    lines.append(f"__living_channel__|name={channel_name}")
    return "\n".join(lines)


def clean_handle(raw: str) -> str:
    h = re.sub(r"[^a-z0-9_]", "", raw.lower().lstrip("@"))[:32]
    return h or "channel"


def pick_owners(
    db: SupabaseREST, country_code: str, n: int, rng: random.Random
) -> Tuple[List[dict], Set[str]]:
    profiles = db.get_all(
        "/rest/v1/profiles",
        {
            "select": "user_id,username,display_name,bio,avatar_url,country_code,country_name,city_name",
            "country_code": f"eq.{country_code}",
            "order": "user_id",
        },
    )
    channels = db.get_all("/rest/v1/channels", {"select": "owner_user_id,handle"})
    owned = {c["owner_user_id"] for c in channels}
    used_handles = {
        (c.get("handle") or "").lower() for c in channels if c.get("handle")
    }
    free = [p for p in profiles if p["user_id"] not in owned]
    rng.shuffle(free)
    if len(free) < n:
        raise SystemExit(
            f"Not enough free owners for {country_code}: need {n}, have {len(free)}"
        )
    return free[:n], used_handles


def ensure_channel(
    db: SupabaseREST,
    *,
    owner: dict,
    name: str,
    handle: str,
    about: str,
    dry_run: bool,
) -> dict:
    """Create channel or return existing by handle."""
    existing = db.get_all(
        "/rest/v1/channels",
        {"select": "*", "handle": f"eq.{handle}", "limit": "1"},
    )
    if existing:
        return existing[0]

    # Also match by owner
    by_owner = db.get_all(
        "/rest/v1/channels",
        {"select": "*", "owner_user_id": f"eq.{owner['user_id']}", "limit": "1"},
    )
    if by_owner:
        return by_owner[0]

    row = {
        "owner_user_id": owner["user_id"],
        "name": name[:80],
        "handle": handle,
        "about": about[:2000],
        "avatar_url": owner.get("avatar_url"),
    }
    if dry_run:
        return {**row, "id": f"dry-{handle}"}

    _, created = db.request(
        "POST",
        "/rest/v1/channels",
        body=row,
        prefer="return=representation",
    )
    ch = created[0] if isinstance(created, list) else created

    # Dual-write profile: channel name as display + living marker bio
    profile_patch = {
        "display_name": name[:80],
        "username": handle,
        "bio": living_bio(about, name),
    }
    try:
        db.request(
            "PATCH",
            "/rest/v1/profiles",
            body=profile_patch,
            query={"user_id": f"eq.{owner['user_id']}"},
            prefer="return=minimal",
        )
    except Exception as e:
        # username collision — keep display/bio only
        print(f"  profile patch soft-fail {handle}: {e}")
        try:
            db.request(
                "PATCH",
                "/rest/v1/profiles",
                body={"display_name": name[:80], "bio": living_bio(about, name)},
                query={"user_id": f"eq.{owner['user_id']}"},
                prefer="return=minimal",
            )
        except Exception as e2:
            print(f"  profile patch failed {handle}: {e2}")

    return ch


def assign_slot(kind: str, genre: Optional[str]) -> str:
    if kind == "longform":
        return "longform"
    g = (genre or "other").strip().lower()
    return GENRE_SLOT.get(g, "flagship")


def chunked(seq: List[Any], size: int):
    for i in range(0, len(seq), size):
        yield seq[i : i + size]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument(
        "--countries",
        default="US,DE,EG,AL",
        help="Comma country codes",
    )
    args = ap.parse_args()
    rng = random.Random(args.seed)
    countries = [c.strip().upper() for c in args.countries.split(",") if c.strip()]

    sb_url, sb_key = resolve_supabase()
    db = SupabaseREST(sb_url, sb_key)
    genre_map = build_genre_map()

    # Load all R2 seeded posts
    print("[channels] loading r2 posts…")
    posts = db.get_all(
        "/rest/v1/posts",
        {
            "select": "id,author_id,body,country_code,media_path,media_type,channel_id",
            "media_path": "like.r2:matterya-sparks/*",
            "order": "created_at",
        },
    )
    print(f"  r2 posts: {len(posts)}")

    # Build channels per country
    channel_by_cc_slot: Dict[Tuple[str, str], dict] = {}
    owner_by_channel: Dict[str, str] = {}

    for cc in countries:
        templates = COUNTRY_CHANNELS.get(cc)
        if not templates:
            print(f"  skip unknown country {cc}")
            continue
        owners, used_handles = pick_owners(db, cc, len(templates), rng)
        print(f"[channels] {cc}: creating {len(templates)} channels…")
        for i, tmpl in enumerate(templates):
            owner = owners[i]
            handle = clean_handle(tmpl["handle"])
            # ensure unique handle
            base = handle
            n = 0
            while handle in used_handles:
                n += 1
                handle = f"{base}{n}"[:32]
            used_handles.add(handle)
            ch = ensure_channel(
                db,
                owner=owner,
                name=tmpl["name"],
                handle=handle,
                about=tmpl["about"],
                dry_run=args.dry_run,
            )
            channel_by_cc_slot[(cc, tmpl["slot"])] = ch
            owner_by_channel[ch["id"]] = owner["user_id"]
            print(
                f"  {cc}/{tmpl['slot']}: {tmpl['name']} @{handle} → {ch.get('id')}"
            )

    # Bucket posts
    buckets: Dict[str, List[dict]] = defaultdict(list)  # channel_id → posts
    skipped = 0
    for post in posts:
        cc = (post.get("country_code") or "").upper()
        if cc not in countries:
            skipped += 1
            continue
        parsed = parse_r2_pack(post.get("media_path") or "")
        if not parsed:
            skipped += 1
            continue
        kind, folder, vid = parsed
        genre = genre_map.get(vid)
        slot = assign_slot(kind, genre)
        ch = channel_by_cc_slot.get((cc, slot)) or channel_by_cc_slot.get((cc, "flagship"))
        if not ch:
            skipped += 1
            continue
        buckets[ch["id"]].append(post)

    print(f"[channels] assign plan: {sum(len(v) for v in buckets.values())} posts, skip={skipped}")
    for (cc, slot), ch in sorted(channel_by_cc_slot.items()):
        n = len(buckets.get(ch["id"], []))
        print(f"  {cc}/{slot} @{ch.get('handle')}: {n} videos")

    if args.dry_run:
        print("[channels] dry-run — no post updates")
        return 0

    # Apply updates
    updated = 0
    errors = 0
    t0 = time.time()
    for ch_id, plist in buckets.items():
        owner_id = owner_by_channel[ch_id]
        for batch in chunked(plist, 40):
            # Update one-by-one is safer for body stamp; batch by id filter when body same is hard
            for post in batch:
                new_body = stamp_hub_channel(post.get("body") or "")
                patch = {
                    "author_id": owner_id,
                    "channel_id": ch_id,
                    "posted_by_user_id": owner_id,
                    "body": new_body,
                }
                # Already correctly assigned?
                if (
                    post.get("author_id") == owner_id
                    and post.get("channel_id") == ch_id
                    and "__hub_channel__|" in (post.get("body") or "")
                ):
                    continue
                try:
                    db.request(
                        "PATCH",
                        "/rest/v1/posts",
                        body=patch,
                        query={"id": f"eq.{post['id']}"},
                        prefer="return=minimal",
                    )
                    updated += 1
                except Exception as e:
                    errors += 1
                    if errors <= 8:
                        print(f"  ERR post {post['id'][:8]}: {e}")
            if updated and updated % 200 == 0:
                print(f"  updated {updated}…")

    elapsed = time.time() - t0
    print(f"[channels] done updated={updated} errors={errors} in {elapsed:.1f}s")

    # Verify counts
    for (cc, slot), ch in sorted(channel_by_cc_slot.items()):
        rows = db.get_all(
            "/rest/v1/posts",
            {
                "select": "id",
                "channel_id": f"eq.{ch['id']}",
                "limit": "1",
            },
        )
        # get count via range
        headers, _ = db.request(
            "GET",
            "/rest/v1/posts",
            query={"select": "id", "channel_id": f"eq.{ch['id']}", "limit": "1"},
            prefer="count=exact",
            extra_headers={"Range": "0-0"},
        )
        cr = headers.get("content-range", "")
        print(f"  verify {cc}/{slot}: channel={ch['id'][:8]} posts={cr}")

    return 0 if errors == 0 else 1


if __name__ == "__main__":
    # Fix pick_owners return type annotation usage
    raise SystemExit(main())
