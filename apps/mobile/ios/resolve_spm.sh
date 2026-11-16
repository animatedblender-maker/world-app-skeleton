#!/usr/bin/env bash
# Resolve WorldApp SPM (LiveKit + WhisperKit) into a permanent MatteryaSSD store
# and wire the IDE DerivedData folder to it. Safe to re-run after
# generate_xcode_project.py or Xcode "Reset Package Caches".
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "error: Xcode missing at $DEVELOPER_DIR" >&2
  exit 1
fi
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJ="$ROOT/WorldApp"
XCODEPROJ="$PROJ/WorldApp.xcodeproj"
DD_ROOT="/Volumes/MatteryaSSD/Development/Xcode/DerivedData"
DD_PROJ="$DD_ROOT/WorldApp"
# Permanent store OUTSIDE DerivedData so Clean / casual DD wipes do not erase checkouts.
PKG_STORE="/Volumes/MatteryaSSD/Development/Xcode/WorldAppPackages"
TMPDIR="${TMPDIR:-/Volumes/MatteryaSSD/Development/tmp}"
mkdir -p "$TMPDIR" "$DD_PROJ" "$PKG_STORE" \
  "$PROJ/WorldApp.xcodeproj/project.xcworkspace/xcuserdata/animated.xcuserdatad" \
  "$PROJ/WorldApp.xcodeproj/xcuserdata/animated.xcuserdatad"

if [[ ! -d /Volumes/MatteryaSSD/Development ]]; then
  echo "error: MatteryaSSD Development tree not mounted" >&2
  exit 1
fi

# Workspace Absolute DerivedData → project folder (never the shared DD root).
write_workspace_settings() {
  local dest="$1"
  /usr/bin/python3 - "$dest" <<'PY'
import plistlib, sys
from pathlib import Path
p = Path(sys.argv[1])
p.parent.mkdir(parents=True, exist_ok=True)
plistlib.dump({
    "BuildSystemType": "Latest",
    "DerivedDataLocationStyle": 2,
    "DerivedDataCustomLocation": "/Volumes/MatteryaSSD/Development/Xcode/DerivedData/WorldApp",
}, p.open("wb"))
print("wrote", p)
PY
}
write_workspace_settings "$PROJ/WorldApp.xcodeproj/project.xcworkspace/xcuserdata/animated.xcuserdatad/WorkspaceSettings.xcsettings"
write_workspace_settings "$PROJ/WorldApp.xcodeproj/xcuserdata/animated.xcuserdatad/WorkspaceSettings.xcsettings"

# Point DD SourcePackages at the permanent store (recreate if Reset Package Caches removed it).
ensure_source_packages_link() {
  local link="$DD_PROJ/SourcePackages"
  if [[ -L "$link" ]]; then
    local target
    target="$(readlink "$link")"
    if [[ "$target" == "$PKG_STORE" ]]; then
      return 0
    fi
    rm -f "$link"
  elif [[ -d "$link" ]]; then
    # Migrate one-shot into permanent store if store looks empty.
    if [[ ! -d "$PKG_STORE/checkouts/client-sdk-swift" && -d "$link/checkouts" ]]; then
      echo "migrating existing SourcePackages → $PKG_STORE"
      rsync -a "$link/" "$PKG_STORE/"
    fi
    rm -rf "$link"
  elif [[ -e "$link" ]]; then
    rm -f "$link"
  fi
  ln -sfn "$PKG_STORE" "$link"
  echo "SourcePackages → $PKG_STORE"
}
ensure_source_packages_link

# Soft-stop builders that would race the resolve (do not quit Xcode here).
pkill -f 'xcodebuild.*WorldApp' 2>/dev/null || true
killall SWBBuildService 2>/dev/null || true
sleep 1

# Prefetch LiveKit protocol submodule when a bare checkout already exists.
if [[ -d "$PKG_STORE/checkouts/client-sdk-swift/.git" || -f "$PKG_STORE/checkouts/client-sdk-swift/.git" ]]; then
  git -C "$PKG_STORE/checkouts/client-sdk-swift" submodule update --init --recursive 2>/dev/null || true
fi

echo "Resolving packages into $DD_PROJ …"
cd "$PROJ"
xcodebuild \
  -project WorldApp.xcodeproj \
  -scheme WorldApp \
  -resolvePackageDependencies \
  -derivedDataPath "$DD_PROJ" \
  2>&1 | tee /tmp/worldapp-resolve-spm.log | tail -40

# Re-assert symlink in case xcodebuild replaced SourcePackages with a real directory.
if [[ -d "$DD_PROJ/SourcePackages" && ! -L "$DD_PROJ/SourcePackages" ]]; then
  echo "xcodebuild wrote a real SourcePackages dir — syncing into permanent store"
  rsync -a "$DD_PROJ/SourcePackages/" "$PKG_STORE/"
  rm -rf "$DD_PROJ/SourcePackages"
  ln -sfn "$PKG_STORE" "$DD_PROJ/SourcePackages"
fi
ensure_source_packages_link

# Also keep shared-root symlinks so mistaken Absolute-root settings still find packages.
ln -sfn "$DD_PROJ/Build" "$DD_ROOT/Build" 2>/dev/null || true
ln -sfn "$PKG_STORE" "$DD_ROOT/SourcePackages" 2>/dev/null || true

test -d "$PKG_STORE/checkouts/client-sdk-swift" || { echo "error: LiveKit checkout missing" >&2; exit 1; }
test -d "$PKG_STORE/checkouts/WhisperKit" || { echo "error: WhisperKit checkout missing" >&2; exit 1; }

echo "OK: LiveKit + WhisperKit resolved"
echo "  store: $PKG_STORE"
echo "  DD:    $DD_PROJ"
ls "$PKG_STORE/checkouts" | tr '\n' ' '; echo
