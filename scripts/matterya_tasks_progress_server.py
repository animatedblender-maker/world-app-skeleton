#!/usr/bin/env python3
"""Unified Matterya progress dashboard for every running campaign / flood.

  python3 scripts/matterya_tasks_progress_server.py
  open http://127.0.0.1:8788/
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = int(os.environ.get("MATTERYA_TASKS_PORT", "8788"))
DEV = Path("/Volumes/MatteryaSSD/Development")
FLOOD_LOG = Path("/tmp/matterya-pipeline/flood.log")
FLOOD_PID = Path("/tmp/matterya-pipeline/flood.pid")
COMMENTS_LOG = Path(
    os.environ.get(
        "COMMENTS_REPAIR_LOG",
        str(
            Path.home()
            / ".grok/sessions/%2FUsers%2Fanimated/019f3333-0746-7182-ac11-2f85a85a5ee7/terminal/call-83951874-c341-417b-8a51-a0542b136180-174.log"
        ),
    )
)

HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Matterya · all tasks</title>
<style>
  :root {
    --bg:#0a0c12; --card:#12151e; --ink:#e8ecf4; --muted:#8b93a7;
    --accent:#00b4e4; --ok:#3dd68c; --warn:#f5a524; --err:#ff6b81; --bar:#1c2230;
  }
  * { box-sizing: border-box; }
  body {
    margin:0; font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
    background: radial-gradient(1100px 520px at 8% -8%, #0d3a4a 0%, transparent 50%),
                radial-gradient(900px 480px at 100% 0%, #1a1040 0%, transparent 45%), var(--bg);
    color: var(--ink); min-height:100vh; padding:28px 20px 56px;
  }
  h1 { font-size:24px; font-weight:800; letter-spacing:-0.03em; margin:0 0 4px; }
  .sub { color:var(--muted); font-size:13px; margin-bottom:22px; }
  .grid { display:grid; gap:14px; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); max-width:1100px; }
  .card {
    background: linear-gradient(180deg, #161a26, var(--card));
    border:1px solid rgba(255,255,255,0.06); border-radius:16px; padding:16px 18px;
  }
  .row { display:flex; align-items:center; justify-content:space-between; gap:10px; }
  .name { font-size:15px; font-weight:750; }
  .pill {
    display:inline-flex; align-items:center; gap:6px; padding:3px 10px; border-radius:999px;
    font-size:11px; font-weight:750;
  }
  .pill.running { background:rgba(61,214,140,0.14); color:var(--ok); }
  .pill.idle { background:rgba(139,147,167,0.14); color:var(--muted); }
  .pill.done { background:rgba(0,180,228,0.14); color:var(--accent); }
  .pill.dead { background:rgba(255,107,129,0.14); color:var(--err); }
  .dot { width:7px; height:7px; border-radius:50%; background:currentColor; box-shadow:0 0 8px currentColor; }
  .value { font-size:26px; font-weight:850; margin-top:10px; font-variant-numeric:tabular-nums; }
  .meta { color:var(--muted); font-size:12px; margin-top:8px; line-height:1.45; word-break:break-word; }
  .bar { height:10px; background:var(--bar); border-radius:999px; overflow:hidden; margin-top:12px; }
  .bar > i { display:block; height:100%; width:0%; background:linear-gradient(90deg,#0088b0,var(--accent),#5eead4); border-radius:999px; transition:width .4s ease; }
  a.link { color:var(--accent); text-decoration:none; font-weight:650; font-size:12px; }
  a.link:hover { text-decoration:underline; }
  .footer { max-width:1100px; margin-top:18px; color:var(--muted); font-size:12px; }
</style>
</head>
<body>
  <h1>Matterya · all running tasks</h1>
  <p class="sub">Live snapshot · auto-refresh every 2s · open a card’s detail page for full logs</p>
  <div class="grid" id="root"><div class="card"><div class="meta">Loading…</div></div></div>
  <p class="footer" id="updated"></p>
<script>
function pct(c,t){ if(!t||t<=0) return 0; return Math.max(0, Math.min(100, Math.round(100*c/t))); }
function render(s){
  const root = document.getElementById('root');
  root.innerHTML = (s.tasks||[]).map(t => {
    const p = pct(t.current||0, t.total||0);
    const cls = t.state||'idle';
    const bar = t.total ? `<div class="bar"><i style="width:${p}%"></i></div>` : '';
    const nums = t.total
      ? `<div class="value">${(t.current||0).toLocaleString()} <span style="font-size:14px;color:var(--muted);font-weight:600">/ ${(t.total||0).toLocaleString()}</span></div>`
      : `<div class="value sm" style="font-size:18px;margin-top:10px">${t.detail||'—'}</div>`;
    return `<div class="card">
      <div class="row">
        <div class="name">${t.name}</div>
        <span class="pill ${cls}"><span class="dot"></span>${cls}</span>
      </div>
      ${nums}
      ${bar}
      <div class="meta">${t.message||''}${t.extra?('<br/>'+t.extra):''}</div>
      ${t.href?`<div class="meta"><a class="link" href="${t.href}" target="_blank" rel="noopener">Open detail →</a></div>`:''}
    </div>`;
  }).join('');
  document.getElementById('updated').textContent = 'Updated ' + (s.updated_at||'') + (s.note?(' · '+s.note):'');
}
async function tick(){
  try{
    const r = await fetch('/api/status.json?t='+Date.now());
    render(await r.json());
  }catch(e){
    document.getElementById('root').innerHTML = '<div class="card"><div class="meta" style="color:var(--err)">'+e+'</div></div>';
  }
}
tick(); setInterval(tick, 2000);
</script>
</body>
</html>
"""


def _pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def _read_pid(path: Path) -> int:
    try:
        return int(path.read_text().strip())
    except Exception:
        return 0


def _fetch_json(url: str, timeout: float = 1.5) -> dict | None:
    try:
        req = urllib.request.Request(url, headers={"Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception:
        return None


def _read_json(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text())
    except Exception:
        return None


def _port_up(port: int) -> bool:
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=0.8) as resp:
            return 200 <= resp.status < 500
    except Exception:
        return False


def _pgrep(pattern: str) -> list[int]:
    try:
        out = subprocess.check_output(["pgrep", "-f", pattern], text=True)
        return [int(x) for x in out.split() if x.strip().isdigit()]
    except Exception:
        return []


def _frame0_backfill_task() -> dict:
    """Newest videos missing Frame 0 posters (fast flood skipped inline extract)."""
    d = _read_json(Path("/tmp/matterya-frame0/progress.json")) or {}
    pid = int(d.get("pid") or _read_pid(Path("/tmp/matterya-pipeline/frame0.pid")) or 0)
    alive = _pid_alive(pid) or bool(_pgrep("frame0-backfill"))
    current = int(d.get("ok") or d.get("processed") or 0)
    total = int(d.get("candidates") or d.get("limit") or 0)
    failed = int(d.get("failed") or 0)
    running_flag = bool(d.get("running"))
    if d.get("finishedAt") and not running_flag:
        state = "done"
    elif alive or running_flag:
        state = "running"
    else:
        state = "idle" if current == 0 else "done"
    thumb = str(d.get("lastThumbPath") or "")
    message = (
        f"ok={current} fail={failed}"
        + (f" · {thumb[-90:]}" if thumb else "")
    )
    return {
        "id": "frame0_backfill",
        "name": "Frame 0 posters (feed first frame)",
        "state": state,
        "current": current,
        "total": total,
        "message": message or "Waiting…",
        "extra": "Fast flood skipped Frame0 — backfill writes thumb_url so feed is not blank",
        "href": None,
    }


def _comments_repair_task() -> dict:
    """Parse the reddit/image comment backfill log."""
    state = "idle"
    current = 0
    total = 2500
    fixed = 0
    empty = 0
    message = "Waiting…"
    pids = _pgrep("repair_fy_comments|media_type = 'image'")
    # Heuristic: node with post_comments insert for image repair
    node_pids = _pgrep("node --input-type=module")
    running = bool(pids or (COMMENTS_LOG.exists() and any(_pid_alive(p) for p in node_pids)))
    # Prefer reading the known log
    if COMMENTS_LOG.exists():
        try:
            text = COMMENTS_LOG.read_text(errors="ignore")
            m = re.findall(r"progress\s+(\d+)/(\d+)\s+fixed=(\d+)\s+empty=(\d+)", text)
            if m:
                current, total, fixed, empty = (int(x) for x in m[-1])
                message = f"Seeded comments on {fixed} posts · empty R2={empty}"
            if "{ fixed:" in text or '"fixed":' in text or "fixed," in text.splitlines()[-3:]:
                # completed marker
                fin = re.search(r"\{ fixed:\s*(\d+),\s*empty:\s*(\d+)", text)
                if fin:
                    fixed, empty = int(fin.group(1)), int(fin.group(2))
                    current = total
                    state = "done"
                    message = f"Done · fixed={fixed} empty={empty}"
                    running = False
        except Exception:
            pass
    if running and state != "done":
        state = "running"
    elif state != "done":
        state = "idle" if current == 0 else "done"
    return {
        "id": "comments_repair",
        "name": "Reddit image comments backfill",
        "state": state,
        "current": current,
        "total": total,
        "message": message,
        "extra": "Demoted fy_* meme posts get comments.json threads",
        "href": None,
    }


def _flood_task() -> dict:
    data = _fetch_json("http://127.0.0.1:8777/api/status.json") or {}
    pid = _read_pid(FLOOD_PID) or int(data.get("pid") or 0)
    alive = _pid_alive(pid) or bool(data.get("running"))
    current = int(data.get("current") or 0)
    total = int(data.get("total") or 0)
    latest = str(data.get("latest") or "")
    # Fallback parse log if API thin during discover
    if total <= 0 and FLOOD_LOG.exists():
        try:
            tail = FLOOD_LOG.read_text(errors="ignore")[-120000:]
            m = re.findall(r"\[(\d+)/(\d+)\]\s+INGEST", tail)
            if m:
                current, total = int(m[-1][0]), int(m[-1][1])
                latest = [ln for ln in tail.splitlines() if "INGEST" in ln][-1]
        except Exception:
            pass
    state = "running" if alive else ("done" if data.get("done") else "dead")
    if not alive and current > 0 and total > 0 and current >= total:
        state = "done"
    return {
        "id": "r2_flood",
        "name": "R2 → Matterya flood (newest-first)",
        "state": state,
        "current": current,
        "total": total,
        "message": latest[-180:] if latest else ("Discovering packs…" if alive else "Stopped"),
        "extra": f"pid={pid} · page :8777 · real videos first, fy_ demoted to feed images",
        "href": "http://127.0.0.1:8777/",
    }


def _status_file_task(
    *,
    tid: str,
    name: str,
    status_path: Path,
    href: str,
    port: int,
    current_keys: tuple[str, ...] = ("saved", "ok", "current"),
    total_keys: tuple[str, ...] = ("target", "total"),
) -> dict:
    d = _read_json(status_path) or {}
    page_up = _port_up(port)
    running_flag = bool(d.get("running"))
    state = "running" if running_flag else ("idle" if page_up else "dead")
    current = 0
    for k in current_keys:
        if d.get(k) is not None:
            try:
                current = int(d.get(k) or 0)
                break
            except Exception:
                pass
    total = 0
    for k in total_keys:
        if d.get(k) is not None:
            try:
                total = int(d.get(k) or 0)
                break
            except Exception:
                pass
    msg = str(d.get("message") or d.get("msg") or "")
    return {
        "id": tid,
        "name": name,
        "state": state,
        "current": current,
        "total": total,
        "message": msg[:220] or ("Progress page up" if page_up else "No status yet"),
        "extra": f"detail :{port}",
        "href": href,
    }


def _amiugly_ingest_task() -> dict:
    """Local content-pipeline --amiugly-only --ingest-only progress from log."""
    log = Path("/tmp/matterya-amiugly-apply200.log")
    pids = _pgrep("content-pipeline/cli.ts --amiugly-only")
    current = 0
    total = 0
    latest = ""
    if log.exists():
        try:
            text = log.read_text(errors="ignore")[-80000:]
            m = re.findall(r"\[(\d+)/(\d+)\]\s+INGEST", text)
            if m:
                current, total = int(m[-1][0]), int(m[-1][1])
            lines = [ln for ln in text.splitlines() if "INGEST" in ln or "original created" in ln]
            if lines:
                latest = lines[-1][-180:]
        except Exception:
            pass
    alive = bool(pids)
    if alive:
        state = "running"
    elif total > 0 and current >= total:
        state = "done"
    elif current > 0:
        state = "idle"
    else:
        state = "idle"
    return {
        "id": "amiugly_ingest",
        "name": "Amiugly → Matterya ingest",
        "state": state,
        "current": current,
        "total": total or 2650,
        "message": latest or ("Pipeline running…" if alive else "Waiting…"),
        "extra": f"pids={pids[:3]} · --amiugly-only --ingest-only",
        "href": None,
    }


def status_payload() -> dict:
    tasks = [
        _flood_task(),
        _amiugly_ingest_task(),
        _frame0_backfill_task(),
        _comments_repair_task(),
        _status_file_task(
            tid="shortform",
            name="YouTube ShortForm download",
            status_path=DEV / "YouTubeVideos/ShortForm/STATUS.json",
            href="http://127.0.0.1:8770/",
            port=8769,
        ),
        _status_file_task(
            tid="shortform_r2",
            name="ShortForm → R2 upload",
            status_path=DEV / "YouTubeVideos/ShortForm/R2_UPLOAD_STATUS.json",
            href="http://127.0.0.1:8770/",
            port=8769,
            current_keys=("uploaded", "ok"),
            total_keys=("target", "total"),
        ),
        _status_file_task(
            tid="food",
            name="Food campaign (Shorts + TikTok)",
            status_path=DEV / "TikTokVideos/PlatformReady/STATUS.json",
            href="http://127.0.0.1:8775/",
            port=8775,
            current_keys=("ok", "saved"),
            total_keys=("target",),
        ),
        _status_file_task(
            tid="amiugly",
            name="r/amiuglytruth scrape",
            status_path=DEV / "RedditPosts/STATUS_AMIUGLY.json",
            href="http://127.0.0.1:8778/",
            port=8778,
        ),
        _status_file_task(
            tid="amiugly_r2",
            name="amiuglytruth → R2 upload",
            status_path=DEV / "RedditPosts/R2_AMIUGLY_STATUS.json",
            href="http://127.0.0.1:8778/",
            port=8778,
            current_keys=("uploaded", "ok"),
            total_keys=("local_ready", "target"),
        ),
        _status_file_task(
            tid="selfies",
            name="r/SelfiesCouples scrape",
            status_path=DEV / "RedditPosts/STATUS_SELFIESCOUPLES.json",
            href="http://127.0.0.1:8779/",
            port=8779,
        ),
        _status_file_task(
            tid="selfies_r2",
            name="SelfiesCouples → R2 upload",
            status_path=DEV / "RedditPosts/R2_SELFIESCOUPLES_STATUS.json",
            href="http://127.0.0.1:8779/",
            port=8779,
            current_keys=("uploaded", "ok"),
            total_keys=("local_ready", "target"),
        ),
        _status_file_task(
            tid="funny",
            name="r/funny (paused / soft-hidden)",
            status_path=DEV / "RedditPosts/STATUS_FUNNY.json",
            href="http://127.0.0.1:8776/",
            port=8776,
        ),
    ]
    # Food STATUS uses multi-country message; improve current if possible
    food = next((t for t in tasks if t["id"] == "food"), None)
    food_d = _read_json(DEV / "TikTokVideos/PlatformReady/STATUS.json") or {}
    if food and food_d:
        # Prefer summing focus country progress from message "United_States:3455/5200 | ..."
        msg = str(food_d.get("message") or "")
        pairs = re.findall(r":(\d+)/(\d+)", msg)
        if pairs:
            food["current"] = sum(int(a) for a, _ in pairs)
            food["total"] = sum(int(b) for _, b in pairs)
    funny = next((t for t in tasks if t["id"] == "funny"), None)
    if funny and funny.get("state") == "running":
        funny["state"] = "idle"
        funny["message"] = (funny.get("message") or "") + " · fy_* soft-hidden; do not resume upload"
    return {
        "updated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "note": "Unified agents · r/funny fy_* soft-hidden · feed images from Posts/au_ (amiuglytruth)",
        "tasks": tasks,
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:  # noqa: A003
        return

    def _send(self, code: int, body: bytes, ctype: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0] or "/"
        if path in ("/api/status.json", "/api/status"):
            payload = json.dumps(status_payload()).encode("utf-8")
            self._send(200, payload, "application/json; charset=utf-8")
            return
        self._send(200, HTML.encode("utf-8"), "text/html; charset=utf-8")


def main() -> None:
    for p in subprocess.check_output(["lsof", "-tiTCP:%d" % PORT, "-sTCP:LISTEN"], text=True).split() if False else []:
        pass
    try:
        stale = subprocess.check_output(["lsof", f"-tiTCP:{PORT}", "-sTCP:LISTEN"], text=True).strip()
        for pid in stale.split():
            try:
                os.kill(int(pid), 15)
            except Exception:
                pass
        time.sleep(0.4)
    except Exception:
        pass
    httpd = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"Matterya tasks progress → http://127.0.0.1:{PORT}/", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
