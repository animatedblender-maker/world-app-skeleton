#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" ]]; then
  echo "Usage: $0 /path/to/WorldApp.app" >&2
  exit 1
fi

INFO_PLIST="${APP_PATH}/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Missing Info.plist in ${APP_PATH}" >&2
  exit 1
fi

# All three are required for calls (VoIP push + CallKit + in-call audio).
REQUIRED_MODES=(audio remote-notification voip)
MISSING=()

MODES_TEXT="$(/usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$INFO_PLIST" 2>/dev/null || true)"
for mode in "${REQUIRED_MODES[@]}"; do
  if ! grep -Fq "$mode" <<<"$MODES_TEXT"; then
    MISSING+=("$mode")
  fi
done

if ((${#MISSING[@]} > 0)); then
  echo "Background modes missing from built app: ${MISSING[*]}" >&2
  echo "Current UIBackgroundModes:" >&2
  /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$INFO_PLIST" 2>/dev/null || echo "(not set)" >&2
  exit 1
fi

echo "Background modes OK: ${REQUIRED_MODES[*]}"