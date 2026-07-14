#!/bin/sh
set -euo pipefail

echo "==> Xcode Cloud post-clone: resolve Swift package dependencies"

if [[ -z "${CI_WORKSPACE:-}" ]]; then
  echo "CI_WORKSPACE is not set; skipping package resolution."
  exit 0
fi

PROJECT_PATH="${CI_WORKSPACE}/apps/mobile/ios/WorldApp/WorldApp.xcodeproj"
if [[ ! -d "$PROJECT_PATH" && -e "${CI_WORKSPACE}/apps/mobile/ios/WorldApp.xcodeproj" ]]; then
  PROJECT_PATH="${CI_WORKSPACE}/apps/mobile/ios/WorldApp.xcodeproj"
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
  echo "WorldApp.xcodeproj not found at expected paths."
  exit 1
fi

xcodebuild -resolvePackageDependencies \
  -project "$PROJECT_PATH" \
  -scheme WorldApp \
  -clonedSourcePackagesDirPath "${CI_DERIVED_DATA_PATH:-$HOME/Library/Developer/Xcode/DerivedData}/SourcePackages"

echo "==> Swift packages resolved."