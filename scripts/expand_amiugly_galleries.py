#!/usr/bin/env python3
"""Expand existing au_* image posts so media_url.urls includes every media/NN file.

Dry-run:
  DRY_RUN=1 python3 scripts/expand_amiugly_galleries.py
Apply:
  python3 scripts/expand_amiugly_galleries.py
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path("/Volumes/MatteryaSSD/Development/Projects/World_App/world-app-skeleton")
R2_ENV = Path("/Volumes/MatteryaSSD/Development/TikTok-Api/TikTokDashboard/.env.r2")
SR = Path("/tmp/matterya_sr.key")
DEFAULT_SB = "https://bpdkltgikgbnfjswdbaj.supabase.co"
IMAGE_RE = re.compile(r"media/\d+\.(jpe?g|png|gif|webp)$", re.I)


def load_dotenv(path: Path) -> Dict[str, str]:
    out: Dict[str, str] = {}
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def sb_key() -> str:
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY") or ""
    if not key and SR.exists():
        key = SR.read_text().strip()
    if not key:
        env = load_dotenv(ROOT / "apps/api/.env")
        key = env.get("SUPABASE_SERVICE_ROLE_KEY") or env.get("SERVICE_ROLE_KEY") or ""
    if not key:
        raise SystemExit("missing service role key")
    return key


def main() -> int:
    dry = os.environ.get("DRY_RUN", "0") not in ("0", "false", "False", "")
    limit = int(os.environ.get("LIMIT", "400") or "400")
    key = sb_key()
    base = os.environ.get("SUPABASE_URL", DEFAULT_SB).rstrip("/")

    file_env = load_dotenv(R2_ENV)
    account = file_env.get("R2_ACCOUNT_ID", "")
    access = file_env.get("R2_ACCESS_KEY_ID", "")
    secret = file_env.get("R2_SECRET_ACCESS_KEY", "")
    bucket = file_env.get("R2_BUCKET", "matterya-sparks")
    endpoint = file_env.get("R2_ENDPOINT") or (f"https://{account}.r2.cloudflarestorage.com" if account else "")
    if not (access and secret and endpoint):
        raise SystemExit("incomplete R2 creds")

    import boto3
    from botocore.config import Config

    s3 = boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=access,
        aws_secret_access_key=secret,
        config=Config(signature_version="s3v4"),
        region_name="auto",
    )

    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }
    # Posts whose path is .../au_*/media/01.*
    start = 0
    scanned = updated = skipped = 0
    while scanned < limit:
        page = min(100, limit - scanned)
        h = dict(headers)
        h["Range"] = f"{start}-{start + page - 1}"
        q = {
            "select": "id,media_url,media_path,media_type",
            "media_path": "like.*au_*",
            "media_type": "eq.image",
            "order": "created_at.desc",
        }
        url = base + "/rest/v1/posts?" + urllib.parse.urlencode(q)
        req = urllib.request.Request(url, headers=h)
        with urllib.request.urlopen(req, timeout=120) as r:
            rows = json.loads(r.read().decode() or "[]")
        if not rows:
            break
        for row in rows:
            scanned += 1
            mp = row.get("media_path") or ""
            # Real amiugly: folder segment au_<id>
            m = re.search(r"(ShortForm|Posts)/([^/]+)/(au_[a-z0-9]+)/", mp)
            if not m:
                skipped += 1
                continue
            folder, country, pack_id = m.group(1), m.group(2), m.group(3)
            prefix = f"{folder}/{country}/{pack_id}/"
            # List media/*
            keys: List[str] = []
            token = None
            while True:
                kwargs: Dict[str, Any] = {"Bucket": bucket, "Prefix": prefix + "media/", "MaxKeys": 100}
                if token:
                    kwargs["ContinuationToken"] = token
                resp = s3.list_objects_v2(**kwargs)
                for obj in resp.get("Contents") or []:
                    key = obj["Key"]
                    rel = key[len(prefix) :] if key.startswith(prefix) else key
                    if IMAGE_RE.match(rel):
                        keys.append(key)
                token = resp.get("NextContinuationToken")
                if not token:
                    break
            keys = sorted(set(keys))
            if len(keys) <= 1:
                skipped += 1
                continue

            # Parse existing media_url
            raw = row.get("media_url")
            if isinstance(raw, str):
                try:
                    obj = json.loads(raw)
                except Exception:
                    obj = {"urls": [raw], "types": ["image"]}
            elif isinstance(raw, dict):
                obj = dict(raw)
            else:
                obj = {"urls": [], "types": []}

            existing = [u for u in (obj.get("urls") or []) if isinstance(u, str) and u]
            if len(existing) >= len(keys):
                skipped += 1
                continue

            signed = []
            for k in keys[:12]:
                signed.append(
                    s3.generate_presigned_url(
                        "get_object",
                        Params={"Bucket": bucket, "Key": k},
                        ExpiresIn=7 * 24 * 3600,
                    )
                )
            obj["urls"] = signed
            obj["types"] = ["image"] * len(signed)
            obj["image_keys"] = keys[:12]
            obj["r2_key"] = keys[0]
            obj["kind"] = obj.get("kind") or "feed"
            obj["signed_at"] = __import__("datetime").datetime.utcnow().isoformat() + "Z"

            if dry:
                print(f"would expand {row['id'][:8]} {pack_id} → {len(signed)} images")
                updated += 1
                continue

            body = json.dumps({"media_url": json.dumps(obj)}).encode()
            patch = urllib.request.Request(
                base + "/rest/v1/posts?" + urllib.parse.urlencode({"id": f"eq.{row['id']}"}),
                data=body,
                headers={**headers, "Prefer": "return=minimal"},
                method="PATCH",
            )
            with urllib.request.urlopen(patch, timeout=60) as r:
                r.read()
            updated += 1
            if updated % 25 == 0:
                print(f"… updated={updated} scanned={scanned}")

        if len(rows) < page:
            break
        start += page

    print(f"done dry={dry} scanned={scanned} updated={updated} skipped={skipped}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
