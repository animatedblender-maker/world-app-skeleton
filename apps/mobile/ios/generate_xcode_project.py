#!/usr/bin/env python3
import os
import re
import uuid

ROOT = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.join(ROOT, "WorldApp")
APP_DIR = os.path.join(PROJECT_ROOT, "WorldApp")
XCODEPROJ = os.path.join(PROJECT_ROOT, "WorldApp.xcodeproj")
PBXPROJ = os.path.join(XCODEPROJ, "project.pbxproj")
DEFAULT_DEVELOPMENT_TEAM = "XQ4HXZN6Y5"


def development_team() -> str:
    env_team = os.environ.get("DEVELOPMENT_TEAM", "").strip()
    if env_team:
        return env_team

    if os.path.exists(PBXPROJ):
        with open(PBXPROJ, encoding="utf-8") as handle:
            for line in handle:
                match = re.search(r'DEVELOPMENT_TEAM = "?([^";]+)"?;', line)
                if match:
                    existing = match.group(1).strip()
                    if existing:
                        return existing

    return DEFAULT_DEVELOPMENT_TEAM


def uid() -> str:
    return uuid.uuid4().hex[:24].upper()


swift_files = []
resource_files = []
entitlements_files = []
for dirpath, _, filenames in os.walk(APP_DIR):
    for filename in sorted(filenames):
        full = os.path.join(dirpath, filename)
        rel = os.path.relpath(full, PROJECT_ROOT)
        if filename.endswith(".swift"):
            swift_files.append(rel)
        elif filename.endswith(".entitlements"):
            entitlements_files.append(rel)
        elif filename.endswith((".json", ".geojson", ".caf")) and "Assets.xcassets" not in dirpath:
            resource_files.append(rel)
        elif filename.endswith((".jpg", ".jpeg", ".png")) and "GlobeTextures" in dirpath:
            resource_files.append(rel)

# Stable ordering
swift_files.sort()
resource_files.sort()
entitlements_files.sort()

def pick_entitlements(name):
    preferred = f"WorldApp/{name}.entitlements"
    if preferred in entitlements_files:
        return preferred
    return entitlements_files[0] if entitlements_files else None

debug_entitlements_rel = pick_entitlements("Debug")
release_entitlements_rel = pick_entitlements("Release")

project_id = uid()
target_id = uid()
sources_phase = uid()
resources_phase = uid()
frameworks_phase = uid()
project_config_list = uid()
target_config_list = uid()
debug_config = uid()
release_config = uid()
debug_target_config = uid()
release_target_config = uid()
product_ref = uid()
app_group = uid()
main_group = uid()
products_group = uid()
assets_ref = uid()
assets_build = uid()
debug_entitlements_ref = uid() if debug_entitlements_rel else None
release_entitlements_ref = uid() if release_entitlements_rel else None
livekit_package_ref = uid()
livekit_product_dep = uid()
musickit_framework_ref = uid()
musickit_framework_build = uid()

file_refs = {}
build_files = {}
for rel in swift_files + resource_files:
    file_refs[rel] = uid()
    build_files[rel] = uid()

lines = []
add = lines.append

add("// !$*UTF8*$!")
add("{")
add("\tarchiveVersion = 1;")
add("\tclasses = {};")
add("\tobjectVersion = 56;")
add("\tobjects = {")
add("")
add("/* Begin PBXBuildFile section */")
add(
    f"\t\t{musickit_framework_build} /* MusicKit.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {musickit_framework_ref} /* MusicKit.framework */; }};"
)
for rel in swift_files:
    add(
        f"\t\t{build_files[rel]} /* {os.path.basename(rel)} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[rel]} /* {os.path.basename(rel)} */; }};"
    )
add(
    f"\t\t{assets_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_ref} /* Assets.xcassets */; }};"
)
for rel in resource_files:
    add(
        f"\t\t{build_files[rel]} /* {os.path.basename(rel)} in Resources */ = {{isa = PBXBuildFile; fileRef = {file_refs[rel]} /* {os.path.basename(rel)} */; }};"
    )
add("/* End PBXBuildFile section */")
add("")
add("/* Begin PBXFileReference section */")
add(
    f"\t\t{product_ref} /* WorldApp.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = WorldApp.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
)
for rel in swift_files:
    add(
        f"\t\t{file_refs[rel]} /* {os.path.basename(rel)} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {rel}; sourceTree = \"<group>\"; }};"
    )
for rel in resource_files:
    if rel.endswith(".png"):
        file_type = "image.png"
    elif rel.endswith((".jpg", ".jpeg")):
        file_type = "image.jpeg"
    elif rel.endswith(".geojson"):
        file_type = "text.json"
    else:
        file_type = "text.json"
    add(
        f"\t\t{file_refs[rel]} /* {os.path.basename(rel)} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type}; path = {rel}; sourceTree = \"<group>\"; }};"
    )
add(
    f"\t\t{assets_ref} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = WorldApp/Assets.xcassets; sourceTree = \"<group>\"; }};"
)
for entitlements_rel, entitlements_ref in (
    (debug_entitlements_rel, debug_entitlements_ref),
    (release_entitlements_rel, release_entitlements_ref),
):
    if entitlements_rel and entitlements_ref:
        add(
            f"\t\t{entitlements_ref} /* {os.path.basename(entitlements_rel)} */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = {entitlements_rel}; sourceTree = \"<group>\"; }};"
        )
add(
    f"\t\t{musickit_framework_ref} /* MusicKit.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = MusicKit.framework; path = System/Library/Frameworks/MusicKit.framework; sourceTree = SDKROOT; }};"
)
add("/* End PBXFileReference section */")
add("")
add("/* Begin PBXFrameworksBuildPhase section */")
add(f"\t\t{frameworks_phase} /* Frameworks */ = {{")
add("\t\t\tisa = PBXFrameworksBuildPhase;")
add("\t\t\tbuildActionMask = 2147483647;")
add("\t\t\tfiles = (")
add(f"\t\t\t\t{musickit_framework_build} /* MusicKit.framework in Frameworks */,")
add("\t\t\t);")
add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
add("\t\t};")
add("/* End PBXFrameworksBuildPhase section */")
add("")
add("/* Begin PBXGroup section */")
children = [f"{file_refs[rel]} /* {os.path.basename(rel)} */" for rel in swift_files + resource_files]
children.append(f"{assets_ref} /* Assets.xcassets */")
for entitlements_rel, entitlements_ref in (
    (debug_entitlements_rel, debug_entitlements_ref),
    (release_entitlements_rel, release_entitlements_ref),
):
    if entitlements_rel and entitlements_ref:
        children.append(f"{entitlements_ref} /* {os.path.basename(entitlements_rel)} */")
add(
    f"\t\t{app_group} /* WorldApp */ = {{isa = PBXGroup; children = ({', '.join(children)}); name = WorldApp; sourceTree = \"<group>\"; }};"
)
add(
    f"\t\t{products_group} /* Products */ = {{isa = PBXGroup; children = ({product_ref} /* WorldApp.app */,); name = Products; sourceTree = \"<group>\"; }};"
)
add(
    f"\t\t{main_group} /* */ = {{isa = PBXGroup; children = ({app_group} /* WorldApp */, {products_group} /* Products */); sourceTree = \"<group>\"; }};"
)
add("/* End PBXGroup section */")
add("")
add("/* Begin PBXNativeTarget section */")
add(f"\t\t{target_id} /* WorldApp */ = {{")
add("\t\t\tisa = PBXNativeTarget;")
add(f"\t\t\tbuildConfigurationList = {target_config_list} /* Build configuration list for PBXNativeTarget \"WorldApp\" */;")
add("\t\t\tbuildPhases = (")
add(f"\t\t\t\t{sources_phase} /* Sources */,")
add(f"\t\t\t\t{frameworks_phase} /* Frameworks */,")
add(f"\t\t\t\t{resources_phase} /* Resources */,")
add("\t\t\t);")
add("\t\t\tbuildRules = (")
add("\t\t\t);")
add("\t\t\tdependencies = (")
add("\t\t\t);")
add("\t\t\tpackageProductDependencies = (")
add(f"\t\t\t\t{livekit_product_dep} /* LiveKit */,")
add("\t\t\t);")
add("\t\t\tname = WorldApp;")
add(f"\t\t\tproductName = WorldApp;")
add(f"\t\t\tproductReference = {product_ref} /* WorldApp.app */;")
add("\t\t\tproductType = \"com.apple.product-type.application\";")
add("\t\t};")
add("/* End PBXNativeTarget section */")
add("")
add("/* Begin PBXProject section */")
add(f"\t\t{project_id} /* Project object */ = {{")
add("\t\t\tisa = PBXProject;")
add("\t\t\tattributes = {")
add("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
add("\t\t\t\tLastSwiftUpdateCheck = 1630;")
add("\t\t\t\tLastUpgradeCheck = 1630;")
add("\t\t\t\tTargetAttributes = {")
add(f"\t\t\t\t\t{target_id} = {{")
add("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
add("\t\t\t\t\t\tSystemCapabilities = {")
add("\t\t\t\t\t\t\tcom.apple.BackgroundModes = {")
add("\t\t\t\t\t\t\t\tenabled = 1;")
add("\t\t\t\t\t\t\t\tmodes = (")
add("\t\t\t\t\t\t\t\t\taudio,")
add('\t\t\t\t\t\t\t\t\t"remote-notification",')
add("\t\t\t\t\t\t\t\t\tvoip,")
add("\t\t\t\t\t\t\t\t);")
add("\t\t\t\t\t\t\t};")
add("\t\t\t\t\t\t\tcom.apple.Push = {")
add("\t\t\t\t\t\t\t\tenabled = 1;")
add("\t\t\t\t\t\t\t};")
add("\t\t\t\t\t\t};")
add("\t\t\t\t\t};")
add("\t\t\t\t};")
add("\t\t\t};")
add(f"\t\t\tbuildConfigurationList = {project_config_list} /* Build configuration list for PBXProject \"WorldApp\" */;")
add("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
add("\t\t\tdevelopmentRegion = en;")
add("\t\t\thasScannedForEncodings = 0;")
add(f"\t\t\tknownRegions = (en, Base);")
add(f"\t\t\tmainGroup = {main_group};")
add(f"\t\t\tproductRefGroup = {products_group} /* Products */;")
add("\t\t\tprojectDirPath = \"\";")
add("\t\t\tprojectRoot = \"\";")
add("\t\t\tpackageReferences = (")
add(f"\t\t\t\t{livekit_package_ref} /* XCRemoteSwiftPackageReference \"client-sdk-swift\" */,")
add("\t\t\t);")
add("\t\t\ttargets = (")
add(f"\t\t\t\t{target_id} /* WorldApp */,")
add("\t\t\t);")
add("\t\t};")
add("/* End PBXProject section */")
add("")
add("/* Begin PBXResourcesBuildPhase section */")
add(f"\t\t{resources_phase} /* Resources */ = {{")
add("\t\t\tisa = PBXResourcesBuildPhase;")
add("\t\t\tbuildActionMask = 2147483647;")
add("\t\t\tfiles = (")
add(f"\t\t\t\t{assets_build} /* Assets.xcassets in Resources */,")
for rel in resource_files:
    add(f"\t\t\t\t{build_files[rel]} /* {os.path.basename(rel)} in Resources */,")
add("\t\t\t);")
add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
add("\t\t};")
add("/* End PBXResourcesBuildPhase section */")
add("")
add("/* Begin PBXSourcesBuildPhase section */")
add(f"\t\t{sources_phase} /* Sources */ = {{")
add("\t\t\tisa = PBXSourcesBuildPhase;")
add("\t\t\tbuildActionMask = 2147483647;")
add("\t\t\tfiles = (")
for rel in swift_files:
    add(f"\t\t\t\t{build_files[rel]} /* {os.path.basename(rel)} in Sources */,")
add("\t\t\t);")
add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
add("\t\t};")
add("/* End PBXSourcesBuildPhase section */")
add("")
add("/* Begin XCRemoteSwiftPackageReference section */")
add(f"\t\t{livekit_package_ref} /* XCRemoteSwiftPackageReference \"client-sdk-swift\" */ = {{")
add("\t\t\tisa = XCRemoteSwiftPackageReference;")
add("\t\t\trepositoryURL = \"https://github.com/livekit/client-sdk-swift\";")
add("\t\t\trequirement = {")
add("\t\t\t\tkind = upToNextMajorVersion;")
add("\t\t\t\tminimumVersion = 2.5.0;")
add("\t\t\t};")
add("\t\t};")
add("/* End XCRemoteSwiftPackageReference section */")
add("")
add("/* Begin XCSwiftPackageProductDependency section */")
add(f"\t\t{livekit_product_dep} /* LiveKit */ = {{")
add("\t\t\tisa = XCSwiftPackageProductDependency;")
add(f"\t\t\tpackage = {livekit_package_ref} /* XCRemoteSwiftPackageReference \"client-sdk-swift\" */;")
add("\t\t\tproductName = LiveKit;")
add("\t\t};")
add("/* End XCSwiftPackageProductDependency section */")
add("")
add("/* Begin XCBuildConfiguration section */")
for config_id, name, is_target in [
    (debug_config, "Debug", False),
    (release_config, "Release", False),
    (debug_target_config, "Debug", True),
    (release_target_config, "Release", True),
]:
    add(f"\t\t{config_id} /* {name} */ = {{")
    add("\t\t\tisa = XCBuildConfiguration;")
    add("\t\t\tbuildSettings = {")
    if is_target:
        add("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
        add("\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
        add("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
        entitlements_for_config = (
            release_entitlements_rel if name == "Release" else debug_entitlements_rel
        )
        if entitlements_for_config:
            add(f"\t\t\t\tCODE_SIGN_ENTITLEMENTS = {entitlements_for_config};")
        add("\t\t\t\tCURRENT_PROJECT_VERSION = 19;")
        add(f'\t\t\t\tDEVELOPMENT_TEAM = {development_team()};')
        add("\t\t\t\tENABLE_PREVIEWS = YES;")
        add("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
        add("\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = Matterya;")
        add("\t\t\t\tINFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;")
        add("\t\t\t\tINFOPLIST_KEY_NSLocationWhenInUseUsageDescription = \"Matterya uses your location to set your country during profile setup.\";")
        add("\t\t\t\tINFOPLIST_KEY_NSCameraUsageDescription = \"Matterya uses your camera for video calls and photos.\";")
        add("\t\t\t\tINFOPLIST_KEY_NSMicrophoneUsageDescription = \"Matterya uses your microphone for voice and video calls.\";")
        add("\t\t\t\tINFOPLIST_KEY_NSAppleMusicUsageDescription = \"Matterya reads what you're playing in Apple Music so you can share live listening status with friends.\";")
        add("\t\t\t\tINFOPLIST_KEY_UIBackgroundModes = \"audio remote-notification voip\";")
        add("\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = \"public.app-category.social-networking\";")
        add("\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;")
        add("\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;")
        add("\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;")
        add("\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;")
        add("\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = \"UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown\";")
        add("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
        add("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
        add("\t\t\t\t\t\"$(inherited)\",")
        add("\t\t\t\t\t\"@executable_path/Frameworks\",")
        add("\t\t\t\t);")
        add("\t\t\t\tMARKETING_VERSION = 1.0.1;")
        add("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.matterya.worldapp;")
        add("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
        add("\t\t\t\tSDKROOT = iphoneos;")
        add("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
        add("\t\t\t\tSWIFT_VERSION = 5.0;")
        add("\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";")
        if name == "Debug":
            add("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
    else:
        add("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
        add("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
        add("\t\t\t\tDEAD_CODE_STRIPPING = YES;")
        add("\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;")
        add("\t\t\t\tCOPY_PHASE_STRIP = NO;")
        add("\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;")
        add("\t\t\t\tENABLE_TESTABILITY = YES;")
        add("\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;")
        add("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
        add("\t\t\t\tONLY_ACTIVE_ARCH = YES;" if name == "Debug" else "\t\t\t\tVALIDATE_PRODUCT = YES;")
        add("\t\t\t\tSDKROOT = iphoneos;")
        add("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG $(inherited)\";" if name == "Debug" else "\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
    add("\t\t\t};")
    add(f"\t\t\tname = {name};")
    add("\t\t};")
add("/* End XCBuildConfiguration section */")
add("")
add("/* Begin XCConfigurationList section */")
add(
    f"\t\t{project_config_list} /* Build configuration list for PBXProject \"WorldApp\" */ = {{"
)
add("\t\t\tisa = XCConfigurationList;")
add("\t\t\tbuildConfigurations = (")
add(f"\t\t\t\t{debug_config} /* Debug */,")
add(f"\t\t\t\t{release_config} /* Release */,")
add("\t\t\t);")
add("\t\t\tdefaultConfigurationIsVisible = 0;")
add("\t\t\tdefaultConfigurationName = Release;")
add("\t\t};")
add(
    f"\t\t{target_config_list} /* Build configuration list for PBXNativeTarget \"WorldApp\" */ = {{"
)
add("\t\t\tisa = XCConfigurationList;")
add("\t\t\tbuildConfigurations = (")
add(f"\t\t\t\t{debug_target_config} /* Debug */,")
add(f"\t\t\t\t{release_target_config} /* Release */,")
add("\t\t\t);")
add("\t\t\tdefaultConfigurationIsVisible = 0;")
add("\t\t\tdefaultConfigurationName = Release;")
add("\t\t};")
add("/* End XCConfigurationList section */")
add("\t};")
add(f"\trootObject = {project_id} /* Project object */;")
add("}")

os.makedirs(XCODEPROJ, exist_ok=True)
with open(PBXPROJ, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

print(f"Wrote {PBXPROJ}")
print(f"Swift files: {len(swift_files)}")