#!/usr/bin/env bash
set -euo pipefail

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/WorldApp/WorldApp.xcodeproj"
ARCHIVE="$ROOT/build/WorldApp.xcarchive"
EXPORT="$ROOT/build/export"
EXPORT_PLIST="$ROOT/ExportOptions.plist"

mkdir -p "$ROOT/build"
rm -rf "$ARCHIVE" "$EXPORT"

echo "==> Resolving Swift packages..."
xcodebuild -resolvePackageDependencies \
  -project "$PROJECT" \
  -scheme WorldApp \
  -quiet

echo "==> Archiving Matterya (Release)..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme WorldApp \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=XQ4HXZN6Y5 \
  -allowProvisioningUpdates

echo "==> Uploading to App Store Connect (TestFlight)..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -allowProvisioningUpdates

echo "==> Done."
echo "Archive: $ARCHIVE"
if [[ -f "$EXPORT/WorldApp.ipa" ]]; then
  echo "IPA: $EXPORT/WorldApp.ipa"
fi
echo "Next: App Store Connect → TestFlight → enable External Testing for build $(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$ARCHIVE/Info.plist")."