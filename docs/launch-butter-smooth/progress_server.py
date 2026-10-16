#!/usr/bin/env python3
"""Launch butter-smooth progress page.

  python3 docs/launch-butter-smooth/progress_server.py
  open http://127.0.0.1:8780/
"""

from __future__ import annotations

import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
STATUS = ROOT / "STATUS.json"
PORT = int((__import__("os").environ.get("LAUNCH_PROGRESS_PORT") or "8780"))

HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Matterya · Launch Butter-Smooth</title>
<style>
  :root {
    --bg: #0a0c12;
    --card: #12151e;
    --ink: #e8ecf4;
    --muted: #8b93a7;
    --accent: #c4a574;
    --ok: #3dd68c;
    --warn: #f5a524;
    --err: #ff6b81;
    --bar: #1c2230;
    --paper: #f8f6f2;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
    background:
      radial-gradient(1100px 560px at 8% -12%, #3a2a18 0%, transparent 55%),
      radial-gradient(900px 480px at 100% 0%, #1a1040 0%, transparent 45%),
      var(--bg);
    color: var(--ink);
    min-height: 100vh;
    padding: 28px 20px 64px;
  }
  h1 { font-size: 24px; font-weight: 750; letter-spacing: -0.03em; margin: 0 0 4px; }
  .sub { color: var(--muted); font-size: 13px; margin: 0 0 22px; line-height: 1.45; max-width: 820px; }
  .grid { display: grid; gap: 14px; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); max-width: 1100px; }
  .card {
    background: linear-gradient(180deg, #161a26, var(--card));
    border: 1px solid rgba(255,255,255,0.06);
    border-radius: 16px; padding: 16px 18px;
  }
  .card.wide { grid-column: 1 / -1; }
  .label { font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--muted); font-weight: 700; }
  .value { font-size: 30px; font-weight: 800; margin-top: 6px; font-variant-numeric: tabular-nums; }
  .value.sm { font-size: 16px; font-weight: 650; line-height: 1.35; }
  .ok { color: var(--ok); } .warn { color: var(--warn); } .err { color: var(--err); } .accent { color: var(--accent); }
  .bar { height: 12px; background: var(--bar); border-radius: 999px; overflow: hidden; margin-top: 12px; }
  .bar > i {
    display: block; height: 100%;
    background: linear-gradient(90deg, #8a6a3e, var(--accent), #e8d5b5);
    border-radius: 999px; width: 0%; transition: width 0.45s ease;
  }
  .pill {
    display: inline-flex; align-items: center; gap: 6px; padding: 4px 10px; border-radius: 999px;
    font-size: 12px; font-weight: 700; background: rgba(196,165,116,0.14); color: var(--accent);
  }
  .pill.running { background: rgba(61,214,140,0.12); color: var(--ok); }
  .pill.done { background: rgba(61,214,140,0.18); color: var(--ok); }
  .pill.blocked { background: rgba(255,107,129,0.12); color: var(--err); }
  .pill.pending { background: rgba(245,165,36,0.12); color: var(--warn); }
  .dot { width: 7px; height: 7px; border-radius: 50%; background: currentColor; box-shadow: 0 0 8px currentColor; }
  .meta { color: var(--muted); font-size: 12px; margin-top: 8px; line-height: 1.5; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; margin-top: 10px; }
  th, td { text-align: left; padding: 9px 6px; border-bottom: 1px solid rgba(255,255,255,0.05); vertical-align: top; }
  th { color: var(--muted); font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; }
  td.num { font-variant-numeric: tabular-nums; text-align: right; white-space: nowrap; }
  .check { list-style: none; padding: 0; margin: 10px 0 0; }
  .check li {
    display: flex; gap: 10px; align-items: flex-start; padding: 8px 0;
    border-bottom: 1px solid rgba(255,255,255,0.04); font-size: 13px;
  }
  .box {
    width: 16px; height: 16px; border-radius: 4px; flex: 0 0 auto; margin-top: 1px;
    border: 1.5px solid rgba(255,255,255,0.25);
  }
  .box.on { background: var(--ok); border-color: var(--ok); }
  .log { max-height: 280px; overflow: auto; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; }
  .log div { padding: 6px 0; border-bottom: 1px solid rgba(255,255,255,0.04); color: #b8c0d4; }
  .log time { color: var(--muted); margin-right: 8px; }
  a { color: var(--accent); }
</style>
</head>
<body>
  <h1>Matterya Launch · Butter-Smooth</h1>
  <p class="sub">
    Premium pass for Feed · Sparks · Hubs · Hubs player · Chat.
    Auto-refreshes every 3s. Open this while the agent works:
    <a href="http://127.0.0.1:8780/">http://127.0.0.1:8780/</a>
  </p>
  <div class="grid" id="root">
    <div class="card wide"><div class="label">Loading…</div></div>
  </div>
<script>
async function tick() {
  try {
    const r = await fetch('/api/status?t=' + Date.now());
    const s = await r.json();
    render(s);
  } catch (e) {
    document.getElementById('root').innerHTML =
      '<div class="card wide"><div class="label err">Cannot reach progress API</div><div class="meta">'+e+'</div></div>';
  }
}
function esc(x) {
  return String(x ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}
function statusPill(st) {
  const s = String(st || 'pending');
  const cls = s === 'done' || s === 'completed' ? 'done'
    : s === 'in_progress' || s === 'running' ? 'running'
    : s === 'blocked' || s === 'failed' ? 'blocked' : 'pending';
  return `<span class="pill ${cls}"><span class="dot"></span>${esc(s.replace('_',' '))}</span>`;
}
function render(s) {
  const surfaces = s.surfaces || [];
  const checks = s.checklist || [];
  const log = (s.log || []).slice().reverse().slice(0, 40);
  const done = checks.filter(c => c.done).length;
  const root = document.getElementById('root');
  root.innerHTML = `
    <div class="card">
      <div class="label">Overall</div>
      <div class="value accent">${Math.round(s.overall_pct || 0)}%</div>
      <div class="bar"><i style="width:${Math.min(100, s.overall_pct||0)}%"></i></div>
      <div class="meta">${statusPill(s.running ? 'running' : 'idle')} · phase <b>${esc(s.phase)}</b></div>
    </div>
    <div class="card">
      <div class="label">Checklist</div>
      <div class="value">${done}<span style="font-size:16px;color:var(--muted)"> / ${checks.length}</span></div>
      <div class="meta">Ship gates for launch-day butter-smooth</div>
    </div>
    <div class="card wide">
      <div class="label">Now</div>
      <div class="value sm">${esc(s.headline || '')}</div>
      <div class="meta">Updated ${esc(s.updated_at || '')}</div>
    </div>
    <div class="card wide">
      <div class="label">Surfaces</div>
      <table>
        <thead><tr><th>Surface</th><th>Status</th><th>Progress</th><th>Goal / notes</th></tr></thead>
        <tbody>
          ${surfaces.map(x => `
            <tr>
              <td><b>${esc(x.name)}</b></td>
              <td>${statusPill(x.status)}</td>
              <td class="num">${Math.round(x.pct||0)}%
                <div class="bar"><i style="width:${Math.min(100,x.pct||0)}%"></i></div>
              </td>
              <td><div>${esc(x.goal||'')}</div><div class="meta">${esc(x.notes||'')}</div></td>
            </tr>`).join('')}
        </tbody>
      </table>
    </div>
    <div class="card wide">
      <div class="label">Ship checklist</div>
      <ul class="check">
        ${checks.map(c => `
          <li><span class="box ${c.done ? 'on' : ''}"></span>
            <span>${esc(c.label)}${c.done ? '' : ''}</span>
          </li>`).join('')}
      </ul>
    </div>
    <div class="card wide">
      <div class="label">Activity log</div>
      <div class="log">
        ${log.map(e => `<div><time>${esc(e.t||'')}</time>${esc(e.msg||'')}</div>`).join('') || '<div class="meta">No events yet</div>'}
      </div>
    </div>
  `;
}
tick();
setInterval(tick, 3000);
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:  # quiet
        return

    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html"):
            body = HTML.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/api/status":
            try:
                raw = STATUS.read_text(encoding="utf-8")
                # validate json
                json.loads(raw)
                body = raw.encode("utf-8")
            except Exception as e:
                body = json.dumps({"error": str(e), "running": False}).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(404)
        self.end_headers()


def main() -> None:
    if not STATUS.exists():
        STATUS.write_text("{}", encoding="utf-8")
    httpd = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"Launch butter-smooth progress → http://127.0.0.1:{PORT}/", flush=True)
    print(f"STATUS → {STATUS}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
