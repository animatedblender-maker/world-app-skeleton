#!/usr/bin/env python3
"""Re-presign media_url for every R2 original + share so playback never dies on 7d expiry.

Idempotent. Reads posts with media_path like r2: / r2-share: / r2-hubshare:
and rewrites media_url JSON with a fresh 7-day GET URL.

Usage:
  python3 scripts/resign_r2_media_urls.py
  python3 scripts/resign_r2_media_urls.py --limit 100
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    import boto3
    from botocore.config import Config
except ImportError:
    print("boto3 required", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_R2_ENV = Path("/Volumes/MatteryaSSD/Development/TikTok-Api/TikTokDashboard/.env.r2")
DEFAULT_SR = Path("/tmp/matterya_sr.key")
DEFAULT_SUPABASE = "https://bpdkltgikgbnfjswdbaj.supabase.co"
PRESIGN = 7 * 24 * 3600


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


def r2_client(env_path: Path):
    file_env = load_dotenv(env_path)
    account = os.environ.get("R2_ACCOUNT_ID") or file_env.get("R2_ACCOUNT_ID", "")
    access = os.environ.get("R2_ACCESS_KEY_ID") or file_env.get("R2_ACCESS_KEY_ID", "")
    secret = os.environ.get("R2_SECRET_ACCESS_KEY") or file_env.get("R2_SECRET_ACCESS_KEY", "")
    bucket = os.environ.get("R2_BUCKET") or file_env.get("R2_BUCKET", "matterya-sparks")
    endpoint = os.environ.get("R2_ENDPOINT") or file_env.get("R2_ENDPOINT", "")
    if not endpoint and account:
        endpoint = f"https://{account}.r2.cloudflarestorage.com"
    client = boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=access,
        aws_secret_access_key=secret,
        config=Config(signature_version="s3v4", retries={"max_attempts": 5}),
        region_name="auto",
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

    def get_all(self, path: str, query: dict, page=1000) -> List[dict]:
        out: List[dict] = []
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
            start += len(batch)
            if len(batch) < page:
                break
        return out

    def patch(self, post_id: str, body: dict) -> None:
        url = self.base + "/rest/v1/posts?" + urllib.parse.urlencode({"id": f"eq.{post_id}"})
        data = json.dumps(body).encode()
        req = urllib.request.Request(url, data=data, headers=self.headers("return=minimal"), method="PATCH")
        with urllib.request.urlopen(req, timeout=60) as r:
            r.read()


def object_key_from_media_path(path: str) -> Optional[str]:
    """r2:matterya-sparks/X → X; r2-share:matterya-sparks/X → X; r2-hubshare:matterya-sparks/X → X"""
    if not path:
        return None
    for prefix in ("r2-hubshare:", "r2-share:", "r2:"):
        if path.startswith(prefix):
            rest = path[len(prefix) :]
            # strip bucket name if present
            if rest.startswith("matterya-sparks/"):
                rest = rest[len("matterya-sparks/") :]
            # strip #suffix for multi-shares
            rest = rest.split("#", 1)[0]
            return rest if rest.endswith(".mp4") or rest else None
    return None


def rebuild_media_url(old: Optional[str], signed: str, *, reel: bool) -> str:
    if old and old.strip().startswith("{"):
        try:
            obj = json.loads(old)
            if isinstance(obj, dict):
                urls = obj.get("urls")
                if isinstance(urls, list) and urls:
                    obj["urls"] = [signed] + list(urls[1:])
                else:
                    obj["urls"] = [signed]
                obj["types"] = obj.get("types") or ["video"]
                if reel:
                    obj["reel"] = True
                return json.dumps(obj, separators=(",", ":"))
        except json.JSONDecodeError:
            pass
    return json.dumps(
        {"urls": [signed], "types": ["video"], "reel": reel, "source": "r2_resign"},
        separators=(",", ":"),
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--r2-env", default=str(DEFAULT_R2_ENV))
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--workers", type=int, default=12)
    args = ap.parse_args()

    key = (os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or "").strip()
    if not key and DEFAULT_SR.exists():
        key = DEFAULT_SR.read_text().strip()
    if not key:
        raise SystemExit("Missing service role key")
    db = SB(os.environ.get("SUPABASE_URL", DEFAULT_SUPABASE), key)
    client, bucket = r2_client(Path(args.r2_env))

    print("[resign] loading R2 posts…")
    posts: List[dict] = []
    for like in (
        "r2:matterya-sparks*",
        "r2-share:matterya-sparks*",
        "r2-hubshare:matterya-sparks*",
    ):
        batch = db.get_all(
            "/rest/v1/posts",
            {"select": "id,body,media_url,media_path", "media_path": f"like.{like}"},
        )
        posts.extend(batch)
        print(f"  {like}: {len(batch)}")

    # dedupe by id
    by_id = {p["id"]: p for p in posts if p.get("id")}
    posts = list(by_id.values())
    if args.limit:
        posts = posts[: args.limit]
    print(f"[resign] to process: {len(posts)}")

    ok = err = skip = 0
    t0 = time.time()
    for i, post in enumerate(posts, 1):
        key_obj = object_key_from_media_path(post.get("media_path") or "")
        if not key_obj:
            skip += 1
            continue
        try:
            signed = client.generate_presigned_url(
                "get_object",
                Params={"Bucket": bucket, "Key": key_obj},
                ExpiresIn=PRESIGN,
            )
            body = post.get("body") or ""
            reel = "__spark__|" in body or "__spark_share__|" in body or "/LongForm/" not in (
                post.get("media_path") or ""
            )
            if "/LongForm/" in (post.get("media_path") or ""):
                reel = False
            media_url = rebuild_media_url(post.get("media_url"), signed, reel=reel)
            db.patch(post["id"], {"media_url": media_url})
            ok += 1
        except Exception as e:
            err += 1
            if err <= 8:
                print("err", post.get("media_path"), e)
        if i % 200 == 0:
            rate = i / max(time.time() - t0, 0.1)
            print(f"  [{i}/{len(posts)}] ok={ok} err={err} skip={skip} {rate:.1f}/s")

    print(f"[resign] done ok={ok} err={err} skip={skip} in {time.time()-t0:.1f}s")
    return 0 if err == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
