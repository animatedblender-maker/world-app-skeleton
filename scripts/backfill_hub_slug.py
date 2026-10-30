#!/usr/bin/env python3
"""Backfill posts.hub_slug for LongForm / Hubs videos using word-boundary classify.

Mirrors apps/api/src/recommendation/shelf.service.ts classifyHubSlug so shelves
stop dumping everything into daily and stop mislabeling Food/Music/etc.

Usage:
  DRY_RUN=1 python3 scripts/backfill_hub_slug.py          # report only
  python3 scripts/backfill_hub_slug.py                   # write updates
  LIMIT=500 python3 scripts/backfill_hub_slug.py          # cap rows
  ONLY_EMPTY=1 python3 scripts/backfill_hub_slug.py       # skip already-set slugs

Requires service role key at /tmp/matterya_sr.key (or SUPABASE_SERVICE_ROLE_KEY).
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path
from typing import Dict, List, Optional, Tuple

DEFAULT_SR = Path("/tmp/matterya_sr.key")
DEFAULT_SUPABASE = "https://bpdkltgikgbnfjswdbaj.supabase.co"

HUB_PARENT_SLUGS = [
    "comedy",
    "music",
    "travel",
    "nature",
    "food",
    "sports",
    "tech",
    "fitness",
    "film",
    "culture",
    "history",
    "education",
    "animals",
    "cars",
    "news",
    "fashion",
    "gaming",
    "kids",
    "social",
    "daily",
]

KEYWORD_BUCKETS: List[Tuple[str, List[str]]] = [
    ("comedy", ["comedy", "funny", "humor", "humour", "joke", "sketch comedy", "standup", "stand-up", "sitcom", "prank", "parody", "satire", "slapstick", "outtakes", "blooper"]),
    ("music", ["music video", "music", "song", "jazz", "blues", "concert", "orchestra", "singer", "piano", "guitar", "opera", "symphony", "choir", "melody", "soundtrack", "hip hop", "hip-hop", "rap song", "album"]),
    ("travel", ["travel", "tourist", "tourism", "voyage", "journey", "city walk", "city tour", "paris", "london", "tokyo", "abroad", "cruise", "railway", "airport", "hotel", "backpack", "road trip"]),
    ("nature", ["nature", "forest", "wildlife", "mountain", "river", "ocean", "lake", "garden", "flower", "landscape", "weather", "storm", "volcano", "glacier", "timelapse", "time lapse", "national park", "wilderness"]),
    ("food", ["food", "recipe", "cooking", "cook", "kitchen", "breakfast", "dinner", "coffee", "restaurant", "bakery", "bread", "fruit", "vegetable", "meal", "chef", "cuisine", "baking"]),
    ("sports", ["sports", "sport", "football", "baseball", "basketball", "soccer", "tennis", "golf", "olympics", "olympic", "racing", "boxing", "wrestling", "athletic", "stadium", "nba", "nfl", "fifa", "world cup"]),
    ("tech", ["technology", "tech talk", "computer", "robot", "robotics", "electronics", "engineering", "invention", "rocket", "satellite", "digital", "software", "hardware", "artificial intelligence", "machine learning", "smartphone", "ps5", "iphone"]),
    ("fitness", ["fitness", "exercise", "workout", "yoga", "gym", "aerobics", "strength training", "crossfit", "calisthenics", "bodybuilding"]),
    ("film", ["full movie", "movie", "cinema", "trailer", "cartoon", "animation", "animated", "feature film", "disney", "film", "silent film", "short film"]),
    ("culture", ["culture", "museum", "ballet", "theatre", "theater", "architecture", "literature", "poetry", "art museum", "art history", "cultural"]),
    ("history", ["history", "historical", "world war", "wwii", "ww2", "civil war", "newsreel", "archival", "ancient", "medieval", "empire", "dynasty"]),
    ("education", ["education", "classroom", "lesson", "how to", "howto", "tutorial", "instruction", "lecture", "course", "teaching", "learn english", "learn spanish", "learn french", "learn german", "learn italian", "learn greek", "language learning"]),
    ("animals", ["animals", "animal", "wildlife", "dog farm", "dogs", "dog", "cats", "cat", "pets", "pet", "birds", "bird", "horse", "zoo", "puppy", "kitten", "leopard", "lion", "tiger", "elephant"]),
    ("cars", ["cars", "car review", "automobile", "motorcycle", "vehicle", "truck", "supercar", "hypercar", "tesla", "porsche", "ferrari", "lamborghini", "bmw", "honda", "ford", "chevrolet"]),
    ("news", ["news", "breaking news", "broadcast", "reporter", "headline", "bulletin", "newscast", "news anchor", "journalism"]),
    ("fashion", ["fashion", "runway", "wardrobe", "haute couture", "streetwear", "clothing brand", "beauty tutorial", "makeup tutorial"]),
    ("gaming", ["gaming", "video game", "videogame", "gameplay", "arcade", "nintendo", "playstation", "xbox", "steam", "esports", "speedrun"]),
    ("kids", ["for kids", "kids", "children", "nursery rhyme", "story time", "storytime", "babies", "toddler", "cartoon for kids"]),
    ("social", ["social media", "community", "wedding", "friends", "family life", "street interview", "vlog"]),
    ("daily", ["daily vlog", "morning routine", "evening routine", "housework", "domestic", "day in the life"]),
]


def word_hit(blob: str, word: str) -> bool:
    w = word.strip().lower()
    if not w:
        return False
    esc = re.escape(w)
    return re.search(rf"(?:^|[^a-z0-9]){esc}(?:[^a-z0-9]|$)", blob, re.I) is not None


def classify_hub_slug(
    title: Optional[str],
    body: Optional[str],
    seed_slug: Optional[str] = None,
    creator: Optional[str] = None,
) -> str:
    raw = (seed_slug or "").strip().lower()
    if raw:
        cleaned = re.sub(r"[^a-z0-9_]+", "_", raw)
        parent = cleaned.split("_")[0] if cleaned else ""
        if cleaned in HUB_PARENT_SLUGS:
            return cleaned
        if parent in HUB_PARENT_SLUGS:
            return parent

    title_blob = (title or "").lower()
    weak_blob = f"{body or ''} {creator or ''}".lower()
    scores: Dict[str, int] = {}
    for cat, words in KEYWORD_BUCKETS:
        score = 0
        for w in words:
            weight = 5 if len(w) >= 10 else 3 if len(w) >= 6 else 2
            if word_hit(title_blob, w):
                score += weight * 2
            elif word_hit(weak_blob, w):
                score += weight
        if score:
            scores[cat] = score

    override = f"{title_blob} {weak_blob}"
    if word_hit(override, "true crime") or word_hit(override, "forensic files") or word_hit(override, "serial killer"):
        return "history"
    if word_hit(override, "wildlife") or word_hit(override, "snow leopard"):
        return "animals"

    if not scores:
        return "daily"
    best = max(scores, key=scores.get)
    return best if scores[best] >= 4 else "daily"


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

    def request(self, method: str, path: str, *, body=None, prefer=None, query=None, extra_headers=None):
        url = self.base + path
        if query:
            url += "?" + urllib.parse.urlencode(query, doseq=True)
        data = None if body is None else json.dumps(body).encode()
        headers = self.headers(prefer)
        if extra_headers:
            headers.update(extra_headers)
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                raw = r.read().decode()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            raise RuntimeError(f"{e.code} {method} {path}: {e.read()[:500]}") from e

    def patch(self, path: str, body: dict, query: dict):
        return self.request("PATCH", path, body=body, prefer="return=minimal", query=query)


def is_longform_row(row: dict) -> bool:
    media = row.get("media_url")
    blob = ""
    if isinstance(media, dict):
        blob = json.dumps(media)
    elif isinstance(media, str):
        blob = media
    body = row.get("body") or ""
    return (
        "/LongForm/" in blob
        or "LongForm" in blob
        or "__hub_origin__" in body
        or (row.get("media_type") or "").lower() in ("video", "hub")
    )


def main() -> int:
    dry = os.environ.get("DRY_RUN", "0") not in ("0", "false", "False", "")
    only_empty = os.environ.get("ONLY_EMPTY", "1") not in ("0", "false", "False")
    limit = int(os.environ.get("LIMIT", "0") or "0")
    page = int(os.environ.get("PAGE", "200") or "200")

    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or ""
    if not key and DEFAULT_SR.exists():
        key = DEFAULT_SR.read_text().strip()
    if not key:
        print("Missing service role key (/tmp/matterya_sr.key or SUPABASE_SERVICE_ROLE_KEY)", file=sys.stderr)
        return 2

    base = os.environ.get("SUPABASE_URL", DEFAULT_SUPABASE)
    sb = SB(base, key)

    print(f"backfill_hub_slug dry_run={dry} only_empty={only_empty} limit={limit or '∞'}")

    start = 0
    scanned = 0
    updated = 0
    skipped = 0
    dist: Counter[str] = Counter()
    changes: Counter[str] = Counter()

    while True:
        if limit and scanned >= limit:
            break
        headers = sb.headers("count=exact")
        end = start + page - 1
        if limit:
            end = min(end, start + (limit - scanned) - 1)
        headers["Range"] = f"{start}-{end}"
        # Long-form-ish: video media; filter LongForm in Python for JSON media_url shapes.
        query = {
            "select": "id,title,body,hub_slug,media_type,media_url",
            "media_type": "in.(video,reel,hub)",
            "order": "created_at.desc",
        }
        url = sb.base + "/rest/v1/posts?" + urllib.parse.urlencode(query, doseq=True)
        req = urllib.request.Request(url, headers=headers, method="GET")
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                raw = r.read().decode()
                rows = json.loads(raw) if raw else []
                content_range = r.headers.get("Content-Range", "")
        except urllib.error.HTTPError as e:
            print(f"fetch failed: {e.code} {e.read()[:300]}", file=sys.stderr)
            return 1

        if not rows:
            break

        for row in rows:
            scanned += 1
            if not is_longform_row(row):
                skipped += 1
                continue
            old = (row.get("hub_slug") or "").strip().lower() or None
            if only_empty and old:
                skipped += 1
                dist[old] += 1
                continue
            # Reclassify from title/body; ignore stale seed so empty+wrong both get fixed when ONLY_EMPTY=0.
            new = classify_hub_slug(row.get("title"), row.get("body"), seed_slug=None)
            dist[new] += 1
            if old == new:
                skipped += 1
                continue
            changes[f"{old or '∅'}→{new}"] += 1
            if dry:
                if updated < 12:
                    title = (row.get("title") or "")[:60].replace("\n", " ")
                    print(f"  would {old or '∅'}→{new}  {title}")
                updated += 1
                continue
            sb.patch(
                "/rest/v1/posts",
                {"hub_slug": new},
                {"id": f"eq.{row['id']}"},
            )
            updated += 1

        print(f"… scanned={scanned} updated={updated} skipped={skipped} range={content_range}")
        if len(rows) < page:
            break
        start += page

    print("distribution (classified targets):", dict(dist.most_common()))
    print("changes:", dict(changes.most_common(30)))
    print(f"done scanned={scanned} updated={updated} skipped={skipped} dry_run={dry}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
