#!/bin/sh
set -euo pipefail

echo "==> Xcode Cloud pre-build"

PROJECT_DIR="${CI_WORKSPACE}/apps/mobile/ios/WorldApp"
PBXPROJ="${PROJECT_DIR}/WorldApp.xcodeproj/project.pbxproj"
if [[ ! -f "$PBXPROJ" ]]; then
  PBXPROJ="${CI_WORKSPACE}/apps/mobile/ios/WorldApp/WorldApp.xcodeproj/project.pbxproj"
fi

if [[ -f "$PBXPROJ" ]]; then
  BUILD_NUMBER="$(awk -F' = ' '/CURRENT_PROJECT_VERSION/{print $2; exit}' "$PBXPROJ" | tr -d ' ;')"
  MARKETING_VERSION="$(awk -F' = ' '/MARKETING_VERSION/{print $2; exit}' "$PBXPROJ" | tr -d ' ;')"
  echo "Target version: ${MARKETING_VERSION} (${BUILD_NUMBER})"
fi

echo "==> Pre-build checks complete."