#!/bin/bash
# Fetch WhisperKit Small into iOS Resources (copied into the app at build time).
# Model files are gitignored — download once per machine / CI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MODEL_VARIANT="${WHISPERKIT_MODEL_VARIANT:-openai_whisper-small}"
DEST_ROOT="${WHISPERKIT_MODEL_DIR:-$PROJECT_DIR/WorldApp/Resources/WhisperKit}"
DEST="$DEST_ROOT/$MODEL_VARIANT"
MARKER="$DEST/.matterya_model_ready"
CACHE_ROOT="${WHISPERKIT_HF_CACHE:-/Volumes/MatteryaSSD/Development/Caches/whisperkit-hf}"

if [ -f "$MARKER" ]; then
  if ls "$DEST"/MelSpectrogram.mlmodelc >/dev/null 2>&1 \
    || ls "$DEST"/MelSpectrogram.mlpackage >/dev/null 2>&1; then
    echo "[whisperkit] model already present: $DEST"
    exit 0
  fi
  echo "[whisperkit] marker present but model files missing — re-fetching"
  rm -f "$MARKER"
fi

mkdir -p "$DEST_ROOT" "$CACHE_ROOT"
echo "[whisperkit] downloading $MODEL_VARIANT → $DEST"

export WHISPERKIT_MODEL_VARIANT="$MODEL_VARIANT"
export WHISPERKIT_DEST="$DEST"
export WHISPERKIT_HF_CACHE="$CACHE_ROOT"

python3 - <<'PY'
import os
import shutil
import sys
from pathlib import Path

variant = os.environ["WHISPERKIT_MODEL_VARIANT"]
dest = Path(os.environ["WHISPERKIT_DEST"])
cache = Path(os.environ["WHISPERKIT_HF_CACHE"])
cache.mkdir(parents=True, exist_ok=True)

try:
    from huggingface_hub import snapshot_download
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", "huggingface_hub"])
    from huggingface_hub import snapshot_download

repo_local = snapshot_download(
    repo_id="argmaxinc/whisperkit-coreml",
    allow_patterns=[f"{variant}/*", f"{variant}/**"],
    local_dir=str(cache / "repo"),
    local_dir_use_symlinks=False,
)

src = Path(repo_local) / variant
if not src.is_dir():
    matches = list(Path(repo_local).rglob("MelSpectrogram.mlmodelc")) + list(
        Path(repo_local).rglob("MelSpectrogram.mlpackage")
    )
    if not matches:
        raise SystemExit(f"Model folder not found after download (variant={variant})")
    src = matches[0].parent

if dest.exists():
    shutil.rmtree(dest)
shutil.copytree(src, dest, symlinks=False)
(dest / ".matterya_model_ready").write_text(variant + "\n", encoding="utf-8")
print(f"[whisperkit] ready at {dest}")
PY
