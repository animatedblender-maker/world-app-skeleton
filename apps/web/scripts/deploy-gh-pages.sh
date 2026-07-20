#!/usr/bin/env bash
# Build Matterya web and push to origin/gh-pages ONLY (matterya.com).
# Does NOT push main / backend.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
WEB="$ROOT/apps/web"
export TMPDIR="${TMPDIR:-/var/tmp}"
mkdir -p "$TMPDIR"

echo "=== Disk ==="
df -h /System/Volumes/Data 2>/dev/null || df -h /

echo "=== Free safe caches ==="
rm -rf "${HOME}/Library/Developer/Xcode/DerivedData/"* 2>/dev/null || true
rm -rf "$ROOT/apps/mobile/ios.backup.20260319-030943" 2>/dev/null || true

echo "=== Restore globe assets if missing ==="
cd "$ROOT"
if [[ ! -f apps/web/public/countries50m.geojson ]]; then
  git checkout HEAD -- apps/web/public/countries50m.geojson 2>/dev/null || true
fi
if [[ ! -f apps/web/public/countries50m.geojson ]]; then
  echo "Downloading countries50m.geojson from GitHub..."
  curl -fsSL -o apps/web/public/countries50m.geojson \
    "https://raw.githubusercontent.com/animatedblender-maker/world-app-skeleton/main/apps/web/public/countries50m.geojson"
fi
if [[ ! -f apps/web/public/earth-day.jpg ]]; then
  git checkout HEAD -- apps/web/public/earth-day.jpg 2>/dev/null || true
fi
if [[ ! -f apps/web/src/assets/countries50m.geojson ]] && [[ -f apps/web/public/countries50m.geojson ]]; then
  mkdir -p apps/web/src/assets
  cp apps/web/public/countries50m.geojson apps/web/src/assets/countries50m.geojson
fi

test -f apps/web/public/countries50m.geojson
test -f apps/web/public/CNAME

echo "=== npm build (production) ==="
cd "$WEB"
if [[ ! -d node_modules ]]; then
  npm install
fi
npm run build -- --configuration production

DIST=""
for candidate in \
  "$WEB/dist/web/browser" \
  "$WEB/dist/web" \
  "$WEB/dist/browser" \
  "$WEB/dist"
do
  if [[ -f "$candidate/index.html" ]]; then
    DIST="$candidate"
    break
  fi
done

if [[ -z "$DIST" ]]; then
  echo "ERROR: could not find built index.html under $WEB/dist"
  find "$WEB/dist" -maxdepth 4 -type f -name 'index.html' 2>/dev/null || true
  exit 1
fi
echo "Using dist: $DIST"

cp "$DIST/index.html" "$DIST/404.html"
cp "$WEB/public/CNAME" "$DIST/CNAME"
printf '{"version":"%s"}\n' "$(date -u +%Y%m%d%H%M%S)" > "$DIST/version.json"

echo "=== Deploy to gh-pages only ==="
WORKDIR="$(mktemp -d "${TMPDIR}/matterya-gh-pages.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

REPO_URL="$(cd "$ROOT" && git remote get-url origin)"
echo "Remote: $REPO_URL"

if git ls-remote --heads "$REPO_URL" gh-pages | grep -q gh-pages; then
  git clone --depth 1 --branch gh-pages "$REPO_URL" "$WORKDIR/repo"
else
  git clone --depth 1 "$REPO_URL" "$WORKDIR/repo"
  cd "$WORKDIR/repo"
  git checkout --orphan gh-pages
  git rm -rf . >/dev/null 2>&1 || true
fi

cd "$WORKDIR/repo"
# Remove previous site files, keep .git
find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
cp -R "$DIST"/. .

git add -A
if git diff --cached --quiet; then
  echo "No site file changes; nothing to push."
  git rev-parse HEAD
  exit 0
fi

git -c user.name="Matterya Deploy" -c user.email="deploy@matterya.com" \
  commit -m "Deploy web iOS-parity UI $(date -u +%Y-%m-%dT%H:%MZ)"

git push origin HEAD:gh-pages

echo ""
echo "=== SUCCESS ==="
echo "Branch: gh-pages"
echo "Commit: $(git rev-parse HEAD)"
echo "Site:   https://matterya.com"
echo "Did NOT push main."
