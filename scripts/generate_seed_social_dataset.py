#!/usr/bin/env python3
"""
Generate a bundled, local-first social dataset for the native app.

The output is intentionally split by country so the iOS feed can read one small
file per country instead of scanning one huge global timeline.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import re
import shutil
from datetime import datetime, timedelta, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IOS_PUBLIC = ROOT / "apps" / "mobile" / "ios" / "App" / "App" / "public"
COUNTRIES_GEOJSON = IOS_PUBLIC / "countries50m.geojson"
NAMES_BY_COUNTRY = IOS_PUBLIC / "names-by-country.json"
OUTPUT_DIR = IOS_PUBLIC / "seed_social"

TOPICS = [
    "daily life",
    "food",
    "work",
    "travel",
    "relationships",
    "sports",
    "tech",
    "music",
    "nightlife",
    "weather",
    "local news",
    "family",
    "culture",
    "commute",
    "study",
    "fitness",
    "markets",
    "nature",
]

POST_PATTERNS = [
    "Anyone else in {place} noticing {detail}? It feels like the whole week has this {mood} energy.",
    "{place} is moving differently today. {detail}, and somehow everyone has an opinion about it.",
    "Small update from {place}: {detail}. Not dramatic, just one of those things you only understand if you live here.",
    "I thought today would be quiet in {place}, then {detail}. What is everyone seeing around them?",
    "{topic_title} check-in from {place}: {detail}. Curious if this is local or happening everywhere.",
    "The best part of living around {place} lately is {detail}. The worst part is that nobody can agree on why.",
    "People keep talking about {detail} in {place}. I did not expect this to become the topic of the day.",
    "Real question for {place}: is {detail} normal now, or are we all just pretending it is fine?",
    "{place} today feels like a group chat in public. {detail}, random debates, and everyone rushing somewhere.",
    "Quick note from {place}: {detail}. It made the day feel weirdly memorable.",
]

DETAILS = {
    "daily life": [
        "the cafes are full before noon",
        "the streets feel busier than they did last month",
        "people are staying outside even after sunset",
        "everyone seems to be running errands at the same time",
    ],
    "food": [
        "a tiny bakery suddenly has a line around the corner",
        "street food prices are somehow the main conversation",
        "people are arguing about the best late-night snack",
        "a new place opened and half the neighborhood already has a review",
    ],
    "work": [
        "commuters look exhausted but weirdly polite",
        "remote work cafes are packed again",
        "everyone is talking about shorter weeks and longer meetings",
        "the morning rush felt heavier than usual",
    ],
    "travel": [
        "the station felt like a movie scene",
        "tourists are discovering the quiet streets locals actually use",
        "the airport stories are getting more chaotic every week",
        "weekend plans somehow became everyone’s personality",
    ],
    "relationships": [
        "half my friends are giving dating advice they do not follow",
        "people are treating voice notes like emotional contracts",
        "everyone has a theory about why texting feels different now",
        "friend groups are planning things and cancelling them instantly",
    ],
    "sports": [
        "the local match turned every cafe into a stadium",
        "everyone became a coach after the final whistle",
        "kids were playing outside like it was a tournament",
        "the gym was full of people making serious summer promises",
    ],
    "tech": [
        "everyone is suddenly testing new apps",
        "people are using AI for the most random daily problems",
        "phone batteries are dying before the day even starts",
        "the group chat discovered a new feature and will not stop talking about it",
    ],
    "music": [
        "one song is playing from every car and every shop",
        "a small live set pulled more people than expected",
        "everyone is nostalgic for music from ten years ago",
        "the neighborhood has a soundtrack today",
    ],
    "nightlife": [
        "the city woke up after midnight",
        "every quiet plan somehow turned into a late night",
        "the best conversations happened outside after closing",
        "people dressed like the weekend started early",
    ],
    "weather": [
        "the weather changed three times in one afternoon",
        "everyone dressed for a different season",
        "the sky looked dramatic enough to stop people walking",
        "the heat made every small task feel personal",
    ],
    "local news": [
        "one local story became the whole timeline",
        "the neighborhood rumor mill is faster than any news app",
        "everyone heard a different version of the same update",
        "a tiny public change somehow made everyone comment",
    ],
    "family": [
        "families are filling the parks again",
        "parents are coordinating plans like military operations",
        "everyone is preparing for a gathering this weekend",
        "kids have more energy than the whole city combined",
    ],
    "culture": [
        "a local tradition suddenly feels fresh again",
        "people are debating what counts as modern and what should stay classic",
        "the old streets are getting more attention than the new places",
        "a small festival made the whole area feel alive",
    ],
    "commute": [
        "traffic turned a ten-minute trip into a personality test",
        "public transport was calm for once, which felt suspicious",
        "everyone had the same delayed-arrival story",
        "the route everyone avoids was somehow the fastest today",
    ],
    "study": [
        "students have taken over every quiet corner",
        "exam season is visible in every coffee shop",
        "people are pretending to study and actually gossiping",
        "the library energy is intense right now",
    ],
    "fitness": [
        "morning runners were out like they had a secret agreement",
        "everyone is trying a new routine this month",
        "the parks are full of people stretching with purpose",
        "fitness plans are getting more ambitious than realistic",
    ],
    "markets": [
        "prices are making strangers talk to each other",
        "the market was loud in the best way",
        "vendors knew the news before anyone else",
        "everyone is comparing deals like it is a sport",
    ],
    "nature": [
        "the quiet spots are becoming less quiet",
        "the sunset made everyone pause for a second",
        "birds were louder than the traffic for once",
        "people are rediscovering the parks like they were hidden",
    ],
}

COMMENT_PATTERNS = [
    "I noticed this too.",
    "This is exactly how it felt here today.",
    "Not everyone will agree, but I get what you mean.",
    "That last line is too real.",
    "Same thing happened near me.",
    "Honestly this depends on the neighborhood.",
    "People have been saying this all week.",
    "I thought I was the only one seeing it.",
    "This made me laugh because it is true.",
    "Give it two days and everyone will move on to a new topic.",
    "There is more context here than people realize.",
    "I love when small local things become the whole conversation.",
]

REPLY_PATTERNS = [
    "Exactly.",
    "That part.",
    "I was thinking the same.",
    "Fair point.",
    "Depends where you are.",
    "This is why I asked.",
    "Could be both honestly.",
]

BIO_PATTERNS = [
    "Usually outside, usually curious.",
    "Local notes, food opinions, and too many photos.",
    "Here for real conversations and small details.",
    "Trying to understand the city one day at a time.",
    "Posts about life, people, and whatever the week brings.",
    "Quiet observer with loud opinions sometimes.",
]

CITY_FALLBACKS = [
    "Central District",
    "Old Town",
    "North Side",
    "West End",
    "Riverside",
    "Market Quarter",
    "University Area",
    "Harbor Side",
]


def stable_int(value: str) -> int:
    return int(hashlib.sha1(value.encode("utf-8")).hexdigest()[:12], 16)


def slug(value: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")
    return normalized or "item"


def pick_name(rng: random.Random, names: dict, code: str) -> tuple[str, str]:
    pool = names.get(code) or names.get("GLOBAL") or {}
    first = pool.get("first") or ["Alex", "Sam", "Maya", "Noah", "Lina", "Omar"]
    last = pool.get("last") or ["Khan", "Smith", "Garcia", "Kim", "Nasser", "Ivanov"]
    return rng.choice(first), rng.choice(last)


def country_rows() -> list[dict]:
    data = json.loads(COUNTRIES_GEOJSON.read_text())
    rows = []
    seen = set()
    for feature in data.get("features", []):
        props = feature.get("properties", {})
        code = (props.get("ISO_A2") or props.get("WB_A2") or "").strip().upper()
        if not code or code == "-99" or code in seen:
            continue
        seen.add(code)
        name = props.get("NAME_EN") or props.get("NAME") or props.get("ADMIN") or code
        formal = props.get("FORMAL_EN") or props.get("NAME_LONG") or name
        pop = int(float(props.get("POP_EST") or 0))
        rows.append(
            {
                "code": code,
                "iso3": (props.get("ISO_A3") or props.get("ADM0_A3") or code).strip().upper(),
                "name": name,
                "formal_name": formal,
                "continent": props.get("CONTINENT") or "Unknown",
                "region": props.get("REGION_UN") or props.get("REGION_WB") or "Unknown",
                "population": pop,
            }
        )
    return rows


def post_count_for_country(country: dict, rng: random.Random, average: int) -> int:
    pop = max(country["population"], 50_000)
    pop_factor = math.log10(pop) - 4.5
    base = average * (0.45 + max(0.0, pop_factor) * 0.28)
    jitter = rng.uniform(0.68, 1.42)
    count = int(base * jitter)
    if pop > 100_000_000:
        count = max(count, int(average * rng.uniform(1.4, 2.6)))
    elif pop < 1_000_000:
        count = min(count, int(average * rng.uniform(0.18, 0.55)))
    return max(120, min(3600, count))


def make_user(country: dict, index: int, names: dict) -> dict:
    rng = random.Random(stable_int(f"user|{country['code']}|{index}"))
    first, last = pick_name(rng, names, country["code"])
    base_username = slug(f"{first}_{last}")[:24]
    suffix = stable_int(f"{country['code']}|{index}") % 9999
    username = f"{base_username}{suffix:04d}"
    user_id = f"seed_user_{country['code'].lower()}_{index:04d}"
    city = rng.choice(CITY_FALLBACKS)
    return {
        "user_id": user_id,
        "email": None,
        "display_name": f"{first} {last}",
        "username": username,
        "avatar_url": f"https://api.dicebear.com/7.x/thumbs/png?seed={username}",
        "country_name": country["name"],
        "country_code": country["code"],
        "city_name": city,
        "bio": rng.choice(BIO_PATTERNS),
        "followers_count": int(rng.random() ** 2 * 16000),
        "following_count": int(rng.random() ** 1.7 * 2400),
    }


def make_post(country: dict, user: dict, index: int, created_at: datetime) -> dict:
    rng = random.Random(stable_int(f"post|{country['code']}|{index}|{user['user_id']}"))
    topic = rng.choice(TOPICS)
    detail = rng.choice(DETAILS[topic])
    place = rng.choice([country["name"], user["city_name"], "the city", "this area", "around here"])
    body = rng.choice(POST_PATTERNS).format(
        place=place,
        detail=detail,
        mood=rng.choice(["strange", "warm", "busy", "hopeful", "chaotic", "quiet"]),
        topic_title=topic.title(),
    )
    has_title = rng.random() < 0.42
    media_roll = rng.random()
    media_type = "none"
    if media_roll < 0.11:
        media_type = "image"
    elif media_roll < 0.16:
        media_type = "video"
    post_id = f"seed_{country['code'].lower()}_{index:05d}"
    like_count = int((rng.random() ** 2.2) * 5200)
    view_count = max(like_count * rng.randint(7, 28), int((rng.random() ** 1.8) * 120_000))
    return {
        "id": post_id,
        "author_id": user["user_id"],
        "country_code": country["code"],
        "country_name": country["name"],
        "city_name": user["city_name"],
        "category_slug": slug(topic),
        "title": rng.choice(
            [
                topic.title(),
                f"{country['name']} today",
                f"Small {topic} thought",
                f"Local {topic} check",
            ]
        )
        if has_title
        else None,
        "body": body,
        "visibility": "public",
        "like_count": like_count,
        "view_count": view_count,
        "created_at": created_at.isoformat().replace("+00:00", "Z"),
        "media": {
            "type": media_type,
            "query": f"{country['name']} {topic}",
            "url": None,
            "thumb_url": None,
        },
    }


def make_comments(country: dict, post: dict, users: list[dict], average_comments: float) -> list[dict]:
    rng = random.Random(stable_int(f"comments|{post['id']}"))
    count = max(0, int(rng.expovariate(1 / average_comments)))
    if rng.random() < 0.72:
        count += rng.randint(1, 3)
    count = min(count, 18)
    comments = []
    base_time = datetime.fromisoformat(post["created_at"].replace("Z", "+00:00"))
    for i in range(count):
        author = rng.choice(users)
        created = base_time + timedelta(minutes=rng.randint(3, 7200))
        comment_id = f"seed_cmt_{post['id']}_{i:02d}"
        comments.append(
            {
                "id": comment_id,
                "post_id": post["id"],
                "parent_id": None,
                "author_id": author["user_id"],
                "body": rng.choice(COMMENT_PATTERNS),
                "like_count": int((rng.random() ** 2) * 180),
                "liked_by_me": False,
                "created_at": created.isoformat().replace("+00:00", "Z"),
            }
        )
        if rng.random() < 0.28:
            reply_author = rng.choice(users)
            reply_created = created + timedelta(minutes=rng.randint(2, 240))
            comments.append(
                {
                    "id": f"seed_reply_{post['id']}_{i:02d}",
                    "post_id": post["id"],
                    "parent_id": comment_id,
                    "author_id": reply_author["user_id"],
                    "body": rng.choice(REPLY_PATTERNS),
                    "like_count": int((rng.random() ** 2) * 80),
                    "liked_by_me": False,
                    "created_at": reply_created.isoformat().replace("+00:00", "Z"),
                }
            )
    return comments


def write_jsonl(path: Path, rows) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with path.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
            count += 1
    return count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--average-posts", type=int, default=1000)
    parser.add_argument("--average-comments", type=float, default=4.0)
    parser.add_argument("--users-per-country", type=int, default=260)
    parser.add_argument("--seed", type=int, default=20260604)
    parser.add_argument("--output", type=Path, default=OUTPUT_DIR)
    args = parser.parse_args()

    rng = random.Random(args.seed)
    countries = country_rows()
    names = json.loads(NAMES_BY_COUNTRY.read_text()) if NAMES_BY_COUNTRY.exists() else {}

    if args.output.exists():
        shutil.rmtree(args.output)
    (args.output / "feeds").mkdir(parents=True, exist_ok=True)
    (args.output / "comments").mkdir(parents=True, exist_ok=True)

    all_users = []
    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "average_posts": args.average_posts,
        "countries": [],
        "totals": {"countries": 0, "users": 0, "posts": 0, "comments": 0},
    }

    now = datetime(2026, 6, 1, tzinfo=timezone.utc)
    for country in countries:
        country_rng = random.Random(stable_int(f"{args.seed}|{country['code']}"))
        user_count = max(60, min(900, int(args.users_per_country * country_rng.uniform(0.55, 1.8))))
        post_count = post_count_for_country(country, country_rng, args.average_posts)
        users = [make_user(country, i, names) for i in range(user_count)]
        all_users.extend(users)

        posts = []
        comments = []
        for index in range(post_count):
            user = country_rng.choice(users)
            created = now - timedelta(
                minutes=country_rng.randint(0, 240_000),
                seconds=country_rng.randint(0, 59),
            )
            post = make_post(country, user, index, created)
            post_comments = make_comments(country, post, users, args.average_comments)
            post["comment_count"] = len(post_comments)
            posts.append(post)
            comments.extend(post_comments)

        posts.sort(key=lambda item: item["created_at"], reverse=True)
        comments.sort(key=lambda item: item["created_at"])
        write_jsonl(args.output / "feeds" / f"{country['code']}.jsonl", posts)
        write_jsonl(args.output / "comments" / f"{country['code']}.jsonl", comments)
        manifest["countries"].append(
            {
                "code": country["code"],
                "iso3": country["iso3"],
                "name": country["name"],
                "users": len(users),
                "posts": len(posts),
                "comments": len(comments),
            }
        )

    write_jsonl(args.output / "users.jsonl", all_users)
    manifest["totals"] = {
        "countries": len(countries),
        "users": len(all_users),
        "posts": sum(item["posts"] for item in manifest["countries"]),
        "comments": sum(item["comments"] for item in manifest["countries"]),
    }
    (args.output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(manifest["totals"], indent=2))


if __name__ == "__main__":
    main()
