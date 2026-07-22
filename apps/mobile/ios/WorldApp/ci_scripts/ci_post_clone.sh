#!/bin/sh
# Xcode Cloud — after clone. Ensure WorldApp.xcodeproj exists; resolve SPM.
set -euo pipefail

echo "==> Xcode Cloud post-clone"

if [ -z "${CI_WORKSPACE:-}" ]; then
  echo "CI_WORKSPACE is not set; skipping."
  exit 0
fi

echo "CI_WORKSPACE=${CI_WORKSPACE}"
echo "PWD=$(pwd)"

# Preferred monorepo path:
#   apps/mobile/ios/WorldApp/WorldApp.xcodeproj
find_project() {
  for candidate in \
    "${CI_WORKSPACE}/apps/mobile/ios/WorldApp/WorldApp.xcodeproj" \
    "${CI_WORKSPACE}/apps/mobile/ios/WorldApp.xcodeproj" \
    "${CI_WORKSPACE}/WorldApp/WorldApp.xcodeproj" \
    "${CI_WORKSPACE}/WorldApp.xcodeproj"
  do
    if [ -f "${candidate}/project.pbxproj" ]; then
      echo "$candidate"
      return 0
    fi
  done

  candidate="$(find "${CI_WORKSPACE}" -maxdepth 6 -type f -name project.pbxproj 2>/dev/null | head -1 || true)"
  if [ -n "${candidate}" ]; then
    dirname "$candidate"
    return 0
  fi
  return 1
}

PROJECT_PATH=""
if PROJECT_PATH="$(find_project)"; then
  echo "==> Found project at: ${PROJECT_PATH}"
else
  echo "==> WorldApp.xcodeproj missing — generating"
  GEN_DIR="${CI_WORKSPACE}/apps/mobile/ios"
  if [ ! -f "${GEN_DIR}/generate_xcode_project.py" ]; then
    echo "ERROR: generate_xcode_project.py not found under ${GEN_DIR}"
    ls -la "${CI_WORKSPACE}" || true
    ls -la "${CI_WORKSPACE}/apps/mobile/ios" 2>/dev/null || true
    exit 1
  fi
  python3 "${GEN_DIR}/generate_xcode_project.py"
  if ! PROJECT_PATH="$(find_project)"; then
    echo "ERROR: still no WorldApp.xcodeproj after generate."
    find "${CI_WORKSPACE}/apps/mobile/ios" -maxdepth 4 \( -name '*.xcodeproj' -o -name project.pbxproj \) 2>/dev/null || true
    exit 1
  fi
  echo "==> Generated project at: ${PROJECT_PATH}"
fi

SCHEME_DIR="${PROJECT_PATH}/xcshareddata/xcschemes"
SCHEME_FILE="${SCHEME_DIR}/WorldApp.xcscheme"
if [ ! -f "${SCHEME_FILE}" ]; then
  echo "==> Writing shared WorldApp.xcscheme"
  mkdir -p "${SCHEME_DIR}"
  cat > "${SCHEME_FILE}" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="WorldApp" BuildableName="WorldApp.app" BlueprintName="WorldApp" ReferencedContainer="container:WorldApp.xcodeproj"/>
      </BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="WorldApp" BuildableName="WorldApp.app" BlueprintName="WorldApp" ReferencedContainer="container:WorldApp.xcodeproj"/>
    </BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="WorldApp" BuildableName="WorldApp.app" BlueprintName="WorldApp" ReferencedContainer="container:WorldApp.xcodeproj"/>
    </BuildableProductRunnable>
  </ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
EOF
fi

WS="${PROJECT_PATH}/project.xcworkspace"
mkdir -p "${WS}/xcshareddata/swiftpm"
if [ ! -f "${WS}/contents.xcworkspacedata" ]; then
  cat > "${WS}/contents.xcworkspacedata" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Workspace version="1.0">
   <FileRef location="self:"/>
</Workspace>
EOF
fi

echo "==> Resolving Swift package dependencies (LiveKit)"
# Clear stale SPM state that can leave “Missing package product 'LiveKit'”
rm -rf "${PROJECT_PATH}/project.xcworkspace/xcshareddata/swiftpm/configuration" 2>/dev/null || true
xcodebuild -resolvePackageDependencies \
  -project "${PROJECT_PATH}" \
  -scheme WorldApp \
  -clonedSourcePackagesDirPath "${CI_DERIVED_DATA_PATH:-$HOME/Library/Developer/Xcode/DerivedData}/SourcePackages" \
  || {
    echo "WARN: first package resolve failed; retrying once…"
    sleep 3
    xcodebuild -resolvePackageDependencies \
      -project "${PROJECT_PATH}" \
      -scheme WorldApp \
      -clonedSourcePackagesDirPath "${CI_DERIVED_DATA_PATH:-$HOME/Library/Developer/Xcode/DerivedData}/SourcePackages"
  }

echo "==> Post-clone complete. Project: ${PROJECT_PATH}"
