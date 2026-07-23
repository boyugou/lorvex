#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/dist/xcode-project-verify"
PROJECT_PATH="$PROJECT_DIR/LorvexAppleNative.xcodeproj"
PROJECT_FILE="$PROJECT_PATH/project.pbxproj"

source "$ROOT_DIR/script/lib_xcode_package_lock.sh"

cd "$ROOT_DIR"

command -v xcodegen >/dev/null

rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
xcodegen --spec "$ROOT_DIR/Config/XcodeGen/project.yml" \
  --project "$PROJECT_DIR" \
  --project-root "$ROOT_DIR" \
  --quiet

# Seed the committed resolver lock and pin resolution so the `xcodebuild -list`
# below reads only the pinned versions and never rewrites the git-tracked
# core/Package.resolved (see lib_xcode_package_lock.sh).
seed_xcode_package_lock "$ROOT_DIR" "$PROJECT_PATH"
"$ROOT_DIR/script/generate_apple_platform_manifest.py"
"$ROOT_DIR/script/verify_apple_platform_manifest.py" \
  "$ROOT_DIR/dist/lorvex-apple-platform-manifest.json"

PROJECT_LIST="$(xcodebuild -project "$PROJECT_PATH" \
  "${XCODE_PINNED_RESOLUTION_FLAGS[@]}" -list 2>&1)"

for target in \
  LorvexMobileApp \
  LorvexVisionApp \
  LorvexFocusWidgetExtension \
  LorvexFocusFilterExtension \
  LorvexCore \
  LorvexCloudSync \
  LorvexMobile \
  LorvexCoreVision \
  LorvexCloudSyncVision \
  LorvexWidgetKitSupportVision \
  LorvexMobileVision \
  LorvexCoreWatch \
  LorvexWatch \
  LorvexWatchApp \
  LorvexWatchComplication \
  LorvexSystemIntents \
  LorvexSystemIntentsVision \
  LorvexWidgetIntents; do
  grep -q "        $target$" <<<"$PROJECT_LIST"
done

for scheme in LorvexMobileApp LorvexVisionApp LorvexWatchApp LorvexFocusWidgetExtension; do
  grep -q "        $scheme$" <<<"$PROJECT_LIST"
done

grep -q "com.apple.product-type.app-extension" "$PROJECT_FILE"
grep -q "LorvexWidgetBundle.swift" "$PROJECT_FILE"
grep -q "LorvexWidgetExtension-Info.plist" "$PROJECT_FILE"
grep -q "LorvexFocusWidgetExtension.entitlements" "$PROJECT_FILE"
grep -q "LorvexFocusFilterExtension-Info.plist" "$PROJECT_FILE"
grep -q "LorvexFocusFilterExtension.entitlements" "$PROJECT_FILE"
grep -q "LorvexWatchApp-Info.plist" "$PROJECT_FILE"
grep -q "LorvexWatchApp.entitlements" "$PROJECT_FILE"
grep -q "PrivacyInfo.xcprivacy" "$PROJECT_FILE"

python3 - "$PROJECT_FILE" <<'PY'
import re
import sys
from pathlib import Path

project_file = Path(sys.argv[1])
source = project_file.read_text()


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


widget_target_match = re.search(
    r"/\* LorvexFocusWidgetExtension \*/ = \{\n\t\t\tisa = PBXNativeTarget;(?P<body>.*?)\n\t\t\};",
    source,
    re.DOTALL,
)
if not widget_target_match:
    fail("Missing LorvexFocusWidgetExtension target in generated project")

widget_target_body = widget_target_match.group("body")

frameworks_phase_match = re.search(
    r"([A-F0-9]+) /\* Frameworks \*/",
    widget_target_body,
)
if not frameworks_phase_match:
    fail("LorvexFocusWidgetExtension has no Frameworks build phase")

frameworks_phase_id = frameworks_phase_match.group(1)
frameworks_phase = re.search(
    rf"\n\t\t{frameworks_phase_id} /\* Frameworks \*/ = \{{(?P<body>.*?)\n\t\t\}};",
    source,
    re.DOTALL,
)
if not frameworks_phase:
    fail("LorvexFocusWidgetExtension Frameworks build phase is missing")

if "/* LorvexWidgetIntents.framework in Frameworks */" not in frameworks_phase.group("body"):
    fail("LorvexFocusWidgetExtension does not link LorvexWidgetIntents.framework")

dependency_ids = re.findall(
    r"([A-F0-9]+) /\* PBXTargetDependency \*/",
    widget_target_body,
)
if not dependency_ids:
    fail("LorvexFocusWidgetExtension has no generated target dependencies")

for dependency_id in dependency_ids:
    dependency_match = re.search(
        rf"\n\t\t{dependency_id} /\* PBXTargetDependency \*/ = \{{(?P<body>.*?)\n\t\t\}};",
        source,
        re.DOTALL,
    )
    if dependency_match and "/* LorvexWidgetIntents */" in dependency_match.group("body"):
        break
else:
    fail("LorvexFocusWidgetExtension is missing a PBXTargetDependency on LorvexWidgetIntents")


focus_filter_target_match = re.search(
    r"/\* LorvexFocusFilterExtension \*/ = \{\n\t\t\tisa = PBXNativeTarget;(?P<body>.*?)\n\t\t\};",
    source,
    re.DOTALL,
)
if not focus_filter_target_match:
    fail("Missing LorvexFocusFilterExtension target in generated project")

focus_filter_target_body = focus_filter_target_match.group("body")
if 'productType = "com.apple.product-type.extensionkit-extension";' not in focus_filter_target_body:
    fail("LorvexFocusFilterExtension has the wrong generated product type")

frameworks_phase_match = re.search(
    r"([A-F0-9]+) /\* Frameworks \*/",
    focus_filter_target_body,
)
if not frameworks_phase_match:
    fail("LorvexFocusFilterExtension has no Frameworks build phase")

frameworks_phase_id = frameworks_phase_match.group(1)
frameworks_phase = re.search(
    rf"\n\t\t{frameworks_phase_id} /\* Frameworks \*/ = \{{(?P<body>.*?)\n\t\t\}};",
    source,
    re.DOTALL,
)
if not frameworks_phase:
    fail("LorvexFocusFilterExtension Frameworks build phase is missing")

if "/* LorvexSystemIntents.framework in Frameworks */" not in frameworks_phase.group("body"):
    fail("LorvexFocusFilterExtension does not link LorvexSystemIntents.framework")

resources_phase_match = re.search(
    r"([A-F0-9]+) /\* Resources \*/",
    focus_filter_target_body,
)
if not resources_phase_match:
    fail("LorvexFocusFilterExtension has no Resources build phase")

resources_phase_id = resources_phase_match.group(1)
resources_phase = re.search(
    rf"\n\t\t{resources_phase_id} /\* Resources \*/ = \{{(?P<body>.*?)\n\t\t\}};",
    source,
    re.DOTALL,
)
if not resources_phase:
    fail("LorvexFocusFilterExtension Resources build phase is missing")

if "/* InfoPlist.strings in Resources */" not in resources_phase.group("body"):
    fail("LorvexFocusFilterExtension does not package localized InfoPlist.strings")

dependency_ids = re.findall(
    r"([A-F0-9]+) /\* PBXTargetDependency \*/",
    focus_filter_target_body,
)
for dependency_id in dependency_ids:
    dependency_match = re.search(
        rf"\n\t\t{dependency_id} /\* PBXTargetDependency \*/ = \{{(?P<body>.*?)\n\t\t\}};",
        source,
        re.DOTALL,
    )
    if dependency_match and "/* LorvexSystemIntents */" in dependency_match.group("body"):
        break
else:
    fail("LorvexFocusFilterExtension is missing a PBXTargetDependency on LorvexSystemIntents")

if "path = ../../Config/InfoPlist/LorvexFocusFilterExtension;" not in source:
    fail("LorvexFocusFilterExtension localized InfoPlist resource group is missing")
PY

echo "XcodeGen project verification passed: $PROJECT_PATH"
