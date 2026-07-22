#!/bin/sh
# Xcode Cloud — immediately before xcodebuild.
set -euo pipefail

echo "==> Xcode Cloud pre-build"

if [ -z "${CI_WORKSPACE:-}" ]; then
  echo "CI_WORKSPACE is not set; skipping."
  exit 0
fi

find_pbxproj() {
  for candidate in \
    "${CI_WORKSPACE}/apps/mobile/ios/WorldApp/WorldApp.xcodeproj/project.pbxproj" \
    "${CI_WORKSPACE}/apps/mobile/ios/WorldApp.xcodeproj/project.pbxproj" \
    "${CI_WORKSPACE}/WorldApp/WorldApp.xcodeproj/project.pbxproj" \
    "${CI_WORKSPACE}/WorldApp.xcodeproj/project.pbxproj"
  do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  candidate="$(find "${CI_WORKSPACE}" -maxdepth 6 -type f -name project.pbxproj 2>/dev/null | head -1 || true)"
  if [ -n "${candidate}" ]; then
    echo "$candidate"
    return 0
  fi
  return 1
}

if PBXPROJ="$(find_pbxproj)"; then
  echo "Using pbxproj: ${PBXPROJ}"
  BUILD_NUMBER="$(awk -F' = ' '/CURRENT_PROJECT_VERSION/{print $2; exit}' "$PBXPROJ" | tr -d ' ;')"
  MARKETING_VERSION="$(awk -F' = ' '/MARKETING_VERSION/{print $2; exit}' "$PBXPROJ" | tr -d ' ;')"
  echo "Target version: ${MARKETING_VERSION} (${BUILD_NUMBER})"
  PROJECT_DIR="$(dirname "$PBXPROJ")"
  if [ ! -d "$PROJECT_DIR" ]; then
    echo "ERROR: project directory missing: $PROJECT_DIR"
    exit 1
  fi
  echo "Project bundle OK: $PROJECT_DIR"
else
  echo "ERROR: project.pbxproj not found under CI_WORKSPACE=${CI_WORKSPACE}"
  find "${CI_WORKSPACE}" -maxdepth 5 \( -name '*.xcodeproj' -o -name project.pbxproj \) 2>/dev/null || true
  exit 1
fi

echo "==> Pre-build checks complete."
