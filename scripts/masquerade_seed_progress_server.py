#!/usr/bin/env python3
"""
Masquerade Reddit-seed progress — http://127.0.0.1:8783/

Reads seed log + live DB space/post counts while
seed_masquerade_spaces_from_reddit.py runs.
"""

from __future__ import annotations

import html
import json
import os
import re
import subprocess
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, List, Optional

PORT = 8783
ROOT = Path("/Volumes/MatteryaSSD/Development/Projects/World_App/world-app-skeleton")
API_ENV = ROOT / "apps" / "api" / ".env"
PACKS = Path("/Volumes/MatteryaSSD/Development/RedditPosts")
MIX = PACKS / "SecretsStrangeMix"
STATUS_FILE = Path("/tmp/STATUS_MASQUERADE_SEED.json")
LOG_CANDIDATES = [
    Path("/tmp/masquerade_seed_mix3.log"),
    Path("/tmp/masquerade_seed_mix2.log"),
    Path("/tmp/masquerade_seed_mix.log"),
]

SUB_TO_SPACE = {
    "TrueOffMyChest": "offmychest",
    "confessions": "confessions",
    "offmychest": "offmychest",
    "confession": "confessions",
    "Glitch_in_the_Matrix": "glitch",
    "HighStrangeness": "highlystrange",
    "Paranormal": "paranormal",
    "Ghosts": "ghosts",
    "Thetruthishere": "highlystrange",
    "Ghoststories": "ghosts",
}

SPACE_TITLES = {
    "secrets": "Secrets (hub)",
    "highlystrange": "HighlyStrange (hub)",
    "confessions": "Confessions",
    "offmychest": "Off My Chest",
    "glitch": "Glitch",
    "paranormal": "Paranormal",
    "ghosts": "Ghosts",
}


def esc(s: Any) -> str:
    return html.escape(str(s or ""), quote=True)


def load_env() -> Dict[str, str]:
    env: Dict[str, str] = {}
    if not API_ENV.exists():
        return env
    for line in API_ENV.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def seed_proc() -> Optional[dict]:
    try:
        out = subprocess.check_output(
            ["ps", "-ax", "-o", "pid=,etime=,%cpu=,command="], text=True
        )
    except Exception:
        return None
    for ln in out.splitlines():
        if "seed_masquerade_spaces_from_reddit.py" in ln and "grep" not in ln:
            parts = ln.split(None, 3)
            if len(parts) >= 4:
                return {
                    "pid": parts[0],
                    "etime": parts[1],
                    "cpu": parts[2],
                    "cmd": parts[3][:160],
                }
    return None


def latest_log() -> Optional[Path]:
    existing = [p for p in LOG_CANDIDATES if p.exists()]
    if not existing:
        return None
    return max(existing, key=lambda p: p.stat().st_mtime)


def parse_log(path: Optional[Path]) -> dict:
    out = {
        "path": str(path) if path else None,
        "lines": 0,
        "phases": [],
        "mix_rows": [],
        "hub_rows": [],
        "last_lines": [],
        "inserted_total": 0,
        "skipped_total": 0,
        "done": False,
        "message": "—",
    }
    if not path or not path.exists():
        return out
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return out
    lines = [ln for ln in text.splitlines() if ln.strip()]
    out["lines"] = len(lines)
    out["last_lines"] = lines[-18:]
    inserted = skipped = 0
    for ln in lines:
        m = re.search(r"mix→(\w+):\s*inserted=(\d+)\s*skipped=(\d+)\s*packs=(\d+)", ln)
        if m:
            row = {
                "slug": m.group(1),
                "inserted": int(m.group(2)),
                "skipped": int(m.group(3)),
                "packs": int(m.group(4)),
            }
            out["mix_rows"] = [r for r in out["mix_rows"] if r["slug"] != row["slug"]]
            out["mix_rows"].append(row)
            inserted += row["inserted"]
            skipped += row["skipped"]
            out["message"] = f"mix→{row['slug']} +{row['inserted']} (skip {row['skipped']})"
            continue
        m = re.search(r"mixhub→(\w+):\s*inserted=(\d+)\s*skipped=(\d+)", ln)
        if m:
            row = {
                "slug": m.group(1),
                "inserted": int(m.group(2)),
                "skipped": int(m.group(3)),
            }
            out["hub_rows"] = [r for r in out["hub_rows"] if r["slug"] != row["slug"]]
            out["hub_rows"].append(row)
            inserted += row["inserted"]
            skipped += row["skipped"]
            out["message"] = f"mixhub→{row['slug']} +{row['inserted']}"
            continue
        m = re.search(r"…(\w+)\s+inserted=(\d+)\s+skipped=(\d+)", ln)
        if m:
            out["message"] = f"{m.group(1)} … {m.group(2)} inserted"
            continue
        m = re.search(r"^(\w+):\s*inserted=(\d+)\s*skipped=(\d+)$", ln.strip())
        if m and m.group(1) in ("secrets", "highlystrange"):
            out["phases"].append(
                {
                    "slug": m.group(1),
                    "inserted": int(m.group(2)),
                    "skipped": int(m.group(3)),
                }
            )
        if ln.startswith("done inserted="):
            out["done"] = True
            mm = re.search(r"inserted=(\d+)\s+skipped=(\d+)", ln)
            if mm:
                out["inserted_total"] = int(mm.group(1))
                out["skipped_total"] = int(mm.group(2))
            out["message"] = ln
    if not out["done"]:
        out["inserted_total"] = inserted
        out["skipped_total"] = skipped
    return out


_CACHE: dict = {"disk": None, "disk_at": 0.0, "db": None, "db_at": 0.0}


def disk_mix_expected() -> dict:
    now = time.time()
    hit = _CACHE.get("disk")
    if hit and now - float(_CACHE.get("disk_at") or 0) < 60:
        return hit
    by_sub: Dict[str, int] = {}
    by_hub = {"secrets": 0, "highlystrange": 0}
    total = 0
    if MIX.exists():
        for d in MIX.iterdir():
            meta_p = d / "meta.json"
            if not d.is_dir() or not meta_p.exists():
                continue
            try:
                meta = json.loads(meta_p.read_text(encoding="utf-8", errors="ignore"))
            except Exception:
                continue
            total += 1
            sub = str(meta.get("subreddit") or "?")
            by_sub[sub] = by_sub.get(sub, 0) + 1
            hub = str(meta.get("masquerade_space") or "secrets").lower()
            if hub not in by_hub:
                hub = "secrets"
            by_hub[hub] += 1
    by_space_expected: Dict[str, int] = {}
    for sub, n in by_sub.items():
        slug = SUB_TO_SPACE.get(sub) or "secrets"
        by_space_expected[slug] = by_space_expected.get(slug, 0) + n
    out = {
        "mix_packs": total,
        "by_sub": dict(sorted(by_sub.items(), key=lambda x: -x[1])),
        "by_hub": by_hub,
        "by_themed_expected": by_space_expected,
        "om_packs": sum(
            1
            for d in (PACKS / "OffMyChest").iterdir()
            if d.is_dir() and (d / "meta.json").exists()
        )
        if (PACKS / "OffMyChest").exists()
        else 0,
        "pn_packs": sum(
            1
            for d in (PACKS / "Paranormal").iterdir()
            if d.is_dir() and (d / "meta.json").exists()
        )
        if (PACKS / "Paranormal").exists()
        else 0,
    }
    _CACHE["disk"] = out
    _CACHE["disk_at"] = now
    return out


def db_snapshot() -> dict:
    now = time.time()
    hit = _CACHE.get("db")
    if hit and now - float(_CACHE.get("db_at") or 0) < 8:
        return hit
    env = load_env()
    db_url = env.get("DATABASE_URL")
    empty = {
        "ok": False,
        "error": "no DATABASE_URL" if not db_url else "query failed",
        "spaces": [],
        "mix_themed": 0,
        "mix_hub": 0,
        "reddit_total": 0,
        "comments": 0,
    }
    if not db_url:
        return empty
    try:
        import psycopg2
        from psycopg2.extras import RealDictCursor

        conn = psycopg2.connect(db_url, connect_timeout=12)
        cur = conn.cursor(cursor_factory=RealDictCursor)
        cur.execute(
            """
            select s.normalized_slug, s.title, s.post_count,
              (select count(*)::int from anonymous.posts p
               where p.space_id = s.id and p.state = 'active') as live_posts,
              (select count(*)::int from anonymous.posts p
               where p.space_id = s.id and p.state = 'active'
                 and p.source_ref like 'reddit:%%') as reddit_posts,
              (select count(*)::int from anonymous.posts p
               where p.space_id = s.id and p.state = 'active'
                 and p.source_ref like 'reddit:mix:%%') as mix_posts,
              (select count(*)::int from anonymous.posts p
               where p.space_id = s.id and p.state = 'active'
                 and p.source_ref like 'reddit:mixhub:%%') as mixhub_posts
            from anonymous.spaces s
            where s.status = 'active'
            order by live_posts desc, s.normalized_slug
            """
        )
        spaces = [dict(r) for r in cur.fetchall()]
        cur.execute(
            "select count(*)::int as n from anonymous.posts where source_ref like 'reddit:mix:%'"
        )
        mix_themed = int(cur.fetchone()["n"])
        cur.execute(
            "select count(*)::int as n from anonymous.posts where source_ref like 'reddit:mixhub:%'"
        )
        mix_hub = int(cur.fetchone()["n"])
        cur.execute(
            "select count(*)::int as n from anonymous.posts where source_ref like 'reddit:%'"
        )
        reddit_total = int(cur.fetchone()["n"])
        cur.execute(
            """
            select count(*)::int as n from anonymous.comments c
            join anonymous.posts p on p.id = c.post_id
            where p.source_ref like 'reddit:%'
            """
        )
        try:
            comments = int(cur.fetchone()["n"])
        except Exception:
            # schema may use different comments table
            comments = 0
            try:
                cur.execute(
                    """
                    select count(*)::int as n from anonymous.post_comments c
                    join anonymous.posts p on p.id = c.post_id
                    where p.source_ref like 'reddit:%'
                    """
                )
                comments = int(cur.fetchone()["n"])
            except Exception:
                comments = 0
        conn.close()
        out = {
            "ok": True,
            "error": None,
            "spaces": spaces,
            "mix_themed": mix_themed,
            "mix_hub": mix_hub,
            "reddit_total": reddit_total,
            "comments": comments,
        }
        _CACHE["db"] = out
        _CACHE["db_at"] = now
        return out
    except Exception as e:
        empty["error"] = str(e)[:200]
        return empty


def snapshot() -> dict:
    proc = seed_proc()
    log_path = latest_log()
    log = parse_log(log_path)
    disk = disk_mix_expected()
    db = db_snapshot()
    expected_themed = disk["mix_packs"]
    expected_hub = disk["mix_packs"]  # each pack also lands on a hub
    mix_themed = int(db.get("mix_themed") or 0)
    mix_hub = int(db.get("mix_hub") or 0)
    # Overall progress: themed + hub fills
    done_units = mix_themed + mix_hub
    total_units = max(1, expected_themed + expected_hub)
    pct = min(100.0, 100.0 * done_units / total_units)
    running = proc is not None
    status = {
        "running": running,
        "done": bool(log.get("done")) and not running,
        "message": log.get("message") or ("running" if running else "idle"),
        "pct": round(pct, 2),
        # Compatible with all_campaigns_dashboard cards
        "saved": done_units,
        "target": total_units,
        "phase": "seeding" if running else ("done" if log.get("done") else "idle"),
        "mix_themed_seeded": mix_themed,
        "mix_hub_seeded": mix_hub,
        "mix_packs_disk": expected_themed,
        "expected_themed": expected_themed,
        "expected_hub": expected_hub,
        "proc": proc,
        "log": log,
        "disk": disk,
        "db": db,
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }
    try:
        STATUS_FILE.write_text(json.dumps(status, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception:
        pass
    return status


def page() -> str:
    s = snapshot()
    db = s.get("db") or {}
    disk = s.get("disk") or {}
    log = s.get("log") or {}
    proc = s.get("proc")
    running = s.get("running")
    pct = float(s.get("pct") or 0)
    spaces = db.get("spaces") or []
    expected = disk.get("by_themed_expected") or {}
    mix_by_space = {sp.get("normalized_slug"): int(sp.get("mix_posts") or 0) for sp in spaces}
    hub_by_space = {sp.get("normalized_slug"): int(sp.get("mixhub_posts") or 0) for sp in spaces}

    space_rows = []
    for slug, title in SPACE_TITLES.items():
        live = next((x for x in spaces if x.get("normalized_slug") == slug), {})
        exp = int(expected.get(slug) or 0)
        if slug in ("secrets", "highlystrange"):
            exp = int((disk.get("by_hub") or {}).get(slug) or 0)
            seeded = int(hub_by_space.get(slug) or 0)
            kind = "hub"
        else:
            seeded = int(mix_by_space.get(slug) or 0)
            kind = "themed"
        total_live = int(live.get("live_posts") or 0)
        bar_pct = min(100.0, 100.0 * seeded / exp) if exp else (100.0 if seeded else 0.0)
        space_rows.append(
            f"""<tr>
              <td><b>{esc(title)}</b><div class="muted"><code>{esc(slug)}</code> · {kind}</div></td>
              <td class="num">{seeded:,} / {exp:,}</td>
              <td class="num">{total_live:,}</td>
              <td><div class="bar thin"><i style="width:{bar_pct:.1f}%"></i></div></td>
            </tr>"""
        )

    log_rows = "".join(f"<div class='logline'>{esc(ln)}</div>" for ln in (log.get("last_lines") or [])[-14:])
    mix_done = "".join(
        f"<div class='pill'>{esc(r['slug'])}: +{r['inserted']} skip {r['skipped']} / {r['packs']}</div>"
        for r in (log.get("mix_rows") or [])
    )
    hub_done = "".join(
        f"<div class='pill hub'>{esc(r['slug'])}: +{r['inserted']} skip {r['skipped']}</div>"
        for r in (log.get("hub_rows") or [])
    )

    return f"""<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Masquerade seed</title>
<style>
  :root {{
    --bg:#0b0f14; --card:#151b24; --border:#2a3441; --text:#eef2f7;
    --muted:#8b9bb0; --accent:#a78bfa; --ok:#34d399; --sf:#38bdf8; --warn:#f97316;
  }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; font-family:Inter,system-ui,sans-serif; background:var(--bg); color:var(--text); }}
  .wrap {{ max-width:1100px; margin:0 auto; padding:24px 18px 56px; }}
  h1 {{ margin:0 0 6px; font-size:26px; font-weight:800; }}
  .sub {{ color:var(--muted); margin-bottom:18px; font-size:14px; line-height:1.5; }}
  .grid {{ display:grid; grid-template-columns:1fr 1fr; gap:12px; margin-bottom:12px; }}
  @media(max-width:800px){{ .grid {{ grid-template-columns:1fr; }} }}
  .panel {{ background:var(--card); border:1px solid var(--border); border-radius:16px; padding:16px; }}
  .panel h2 {{ margin:0 0 10px; font-size:12px; color:var(--muted); text-transform:uppercase; letter-spacing:.04em; }}
  .big {{ font-size:34px; font-weight:800; font-variant-numeric:tabular-nums; }}
  .bar {{ height:12px; background:#1a222d; border-radius:999px; overflow:hidden; border:1px solid var(--border); margin:10px 0 6px; }}
  .bar.thin {{ height:8px; margin:0; }}
  .bar > i {{ display:block; height:100%; background:linear-gradient(90deg,var(--accent),#f97316); width:0%; transition:width .35s; }}
  .dot {{ display:inline-block; width:9px; height:9px; border-radius:50%; margin-right:6px; background:#64748b; }}
  .dot.on {{ background:var(--ok); box-shadow:0 0 10px rgba(52,211,153,.5); }}
  .muted {{ color:var(--muted); font-size:13px; }}
  .stats {{ display:flex; flex-wrap:wrap; gap:8px; margin:12px 0; }}
  .pill {{ background:#1a222d; border:1px solid var(--border); border-radius:999px; padding:6px 12px; font-size:12px; }}
  .pill.hub {{ border-color:#7c3aed66; }}
  table {{ width:100%; border-collapse:collapse; font-size:13px; }}
  th, td {{ padding:8px 6px; border-bottom:1px solid var(--border); text-align:left; vertical-align:middle; }}
  th {{ color:var(--muted); font-size:11px; text-transform:uppercase; letter-spacing:.04em; }}
  td.num {{ font-variant-numeric:tabular-nums; white-space:nowrap; }}
  .logline {{ font-family:ui-monospace,menlo,monospace; font-size:11px; color:#cbd5e1; padding:2px 0; border-bottom:1px solid #1a222d; white-space:pre-wrap; word-break:break-all; }}
  a {{ color:var(--sf); }}
  code {{ font-size:11px; }}
</style>
</head><body>
<div class="wrap">
  <h1>Masquerade seed</h1>
  <div class="sub">
    Seeding <code>SecretsStrangeMix</code> (+ OffMyChest / Paranormal) into Masquerade Spaces.<br/>
    Each mix pack lands in a <b>themed Space</b> (by subreddit) and a <b>hub</b> (<code>secrets</code> / <code>HighlyStrange</code>).
  </div>

  <div class="grid">
    <div class="panel">
      <h2>Overall</h2>
      <div class="big"><span id="pct">{pct:.1f}</span>%</div>
      <div class="bar"><i id="bar" style="width:{pct:.1f}%"></i></div>
      <div class="muted">
        <span class="dot {"on" if running else ""}" id="run-dot"></span>
        <span id="run-label">{"seeding" if running else ("done" if s.get("done") else "idle")}</span>
        · <span id="msg">{esc(s.get("message"))}</span>
      </div>
      <div class="muted" style="margin-top:8px">
        themed <b id="themed">{int(s.get("mix_themed_seeded") or 0):,}</b> /
        <span id="themed-exp">{int(s.get("expected_themed") or 0):,}</span>
        · hub <b id="hub">{int(s.get("mix_hub_seeded") or 0):,}</b> /
        <span id="hub-exp">{int(s.get("expected_hub") or 0):,}</span>
      </div>
    </div>
    <div class="panel">
      <h2>Process</h2>
      <div class="muted" id="proc">
        {"pid "+esc(proc.get("pid"))+" · elapsed "+esc(proc.get("etime"))+" · cpu "+esc(proc.get("cpu"))+"%" if proc else "not running"}
      </div>
      <div class="stats" style="margin-top:12px">
        <div class="pill">disk mix <b id="disk-mix">{int(disk.get("mix_packs") or 0):,}</b></div>
        <div class="pill">OM <b>{int(disk.get("om_packs") or 0):,}</b></div>
        <div class="pill">PN <b>{int(disk.get("pn_packs") or 0):,}</b></div>
        <div class="pill">reddit posts <b id="reddit-total">{int(db.get("reddit_total") or 0):,}</b></div>
        <div class="pill">comments ≈ <b id="comments">{int(db.get("comments") or 0):,}</b></div>
      </div>
      <div class="muted" style="margin-top:8px">log: <code id="log-path">{esc(log.get("path") or "—")}</code></div>
      <div class="muted">updated <span id="upd">{esc(s.get("updated_at"))}</span></div>
    </div>
  </div>

  <div class="panel" style="margin-bottom:12px">
    <h2>Spaces</h2>
    <table>
      <thead><tr><th>Space</th><th>seeded / expected</th><th>live posts</th><th></th></tr></thead>
      <tbody id="space-body">{''.join(space_rows)}</tbody>
    </table>
  </div>

  <div class="grid">
    <div class="panel">
      <h2>Log milestones (themed)</h2>
      <div class="stats" id="mix-pills">{mix_done or '<span class="muted">waiting…</span>'}</div>
      <h2 style="margin-top:14px">Hub milestones</h2>
      <div class="stats" id="hub-pills">{hub_done or '<span class="muted">hub pass not started yet</span>'}</div>
    </div>
    <div class="panel">
      <h2>Recent log</h2>
      <div id="log">{log_rows or '<div class="muted">no log yet</div>'}</div>
    </div>
  </div>

  <div class="muted" style="margin-top:16px">
    <a href="/api/status">JSON</a> ·
    <a href="http://127.0.0.1:8782/">Secrets+Strange scrape</a> ·
    <a href="http://127.0.0.1:8785/">All campaigns</a> ·
    refresh 5s
  </div>
</div>
<script>
async function refresh() {{
  try {{
    const r = await fetch('/api/status', {{cache:'no-store'}});
    const s = await r.json();
    const db = s.db || {{}};
    const disk = s.disk || {{}};
    const log = s.log || {{}};
    const proc = s.proc;
    document.getElementById('pct').textContent = Number(s.pct||0).toFixed(1);
    document.getElementById('bar').style.width = Number(s.pct||0).toFixed(1) + '%';
    document.getElementById('run-dot').className = 'dot' + (s.running ? ' on' : '');
    document.getElementById('run-label').textContent = s.running ? 'seeding' : (s.done ? 'done' : 'idle');
    document.getElementById('msg').textContent = s.message || '—';
    document.getElementById('themed').textContent = Number(s.mix_themed_seeded||0).toLocaleString();
    document.getElementById('themed-exp').textContent = Number(s.expected_themed||0).toLocaleString();
    document.getElementById('hub').textContent = Number(s.mix_hub_seeded||0).toLocaleString();
    document.getElementById('hub-exp').textContent = Number(s.expected_hub||0).toLocaleString();
    document.getElementById('disk-mix').textContent = Number(disk.mix_packs||0).toLocaleString();
    document.getElementById('reddit-total').textContent = Number(db.reddit_total||0).toLocaleString();
    document.getElementById('comments').textContent = Number(db.comments||0).toLocaleString();
    document.getElementById('log-path').textContent = log.path || '—';
    document.getElementById('upd').textContent = s.updated_at || '—';
    document.getElementById('proc').textContent = proc
      ? (`pid ${{proc.pid}} · elapsed ${{proc.etime}} · cpu ${{proc.cpu}}%`)
      : 'not running';
    // rebuild space table from API for live counts
    const titles = {json.dumps(SPACE_TITLES)};
    const expected = disk.by_themed_expected || {{}};
    const hubs = disk.by_hub || {{}};
    const spaces = db.spaces || [];
    const mixMap = Object.fromEntries(spaces.map(x => [x.normalized_slug, x.mix_posts||0]));
    const hubMap = Object.fromEntries(spaces.map(x => [x.normalized_slug, x.mixhub_posts||0]));
    const liveMap = Object.fromEntries(spaces.map(x => [x.normalized_slug, x.live_posts||0]));
    let html = '';
    for (const [slug, title] of Object.entries(titles)) {{
      const isHub = slug === 'secrets' || slug === 'highlystrange';
      const exp = isHub ? Number(hubs[slug]||0) : Number(expected[slug]||0);
      const seeded = isHub ? Number(hubMap[slug]||0) : Number(mixMap[slug]||0);
      const live = Number(liveMap[slug]||0);
      const bar = exp ? Math.min(100, 100*seeded/exp) : (seeded ? 100 : 0);
      html += `<tr><td><b>${{title}}</b><div class="muted"><code>${{slug}}</code> · ${{isHub?'hub':'themed'}}</div></td>
        <td class="num">${{seeded.toLocaleString()}} / ${{exp.toLocaleString()}}</td>
        <td class="num">${{live.toLocaleString()}}</td>
        <td><div class="bar thin"><i style="width:${{bar.toFixed(1)}}%"></i></div></td></tr>`;
    }}
    document.getElementById('space-body').innerHTML = html;
    document.getElementById('mix-pills').innerHTML = (log.mix_rows||[]).map(r =>
      `<div class="pill">${{r.slug}}: +${{r.inserted}} skip ${{r.skipped}} / ${{r.packs}}</div>`
    ).join('') || '<span class="muted">waiting…</span>';
    document.getElementById('hub-pills').innerHTML = (log.hub_rows||[]).map(r =>
      `<div class="pill hub">${{r.slug}}: +${{r.inserted}} skip ${{r.skipped}}</div>`
    ).join('') || '<span class="muted">hub pass not started yet</span>';
    document.getElementById('log').innerHTML = (log.last_lines||[]).slice(-14).map(ln =>
      `<div class="logline">${{ln.replace(/[&<>]/g, c => ({{'&':'&amp;','<':'&lt;','>':'&gt;'}})[c])}}</div>`
    ).join('') || '<div class="muted">no log yet</div>';
  }} catch (e) {{}}
}}
setInterval(refresh, 5000);
</script>
</body></html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code: int, body: bytes, ctype: str = "text/html; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html", "/seed"):
            return self._send(200, page().encode("utf-8"))
        if path == "/api/status":
            return self._send(
                200,
                json.dumps(snapshot(), ensure_ascii=False, indent=2).encode("utf-8"),
                "application/json; charset=utf-8",
            )
        return self._send(404, b"not found")


def main() -> int:
    print(f"Masquerade seed progress → http://127.0.0.1:{PORT}/", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
