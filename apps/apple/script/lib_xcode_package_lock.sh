#!/usr/bin/env bash
# Shared helper: pin SwiftPM resolution for the XcodeGen-generated Xcode
# project so device/simulator builds are reproducible and never rewrite a
# git-tracked Package.resolved.
#
# The generated .xcodeproj references the local `core` package by path, and
# Xcode uses that package's core/Package.resolved as the project's resolution
# store. Left to resolve on its own, every xcodebuild invocation (build,
# archive, -list, -showdestinations) expands core/Package.resolved with the
# project-only pins (swift-markdown, swift-cmark) and leaves the working tree
# dirty. Seeding the committed lock into the generated project's workspace
# shared data and passing XCODE_PINNED_RESOLUTION_FLAGS makes Xcode read pinned
# versions from that seeded copy and skip resolution entirely, so
# core/Package.resolved is never touched.
#
# The committed lock (Config/XcodeGen/Package.resolved) is the project graph's
# full resolution — exactly what xcodebuild writes when it resolves this
# project — regenerate it by letting a build resolve against a fresh generated
# project and copying the resulting project.xcworkspace/xcshareddata/swiftpm/
# Package.resolved.

# xcodebuild flags that make SwiftPM use only the versions already in the
# resolved lock and never re-resolve. Expand as an array into every xcodebuild
# invocation that would otherwise resolve packages.
XCODE_PINNED_RESOLUTION_FLAGS=(
  -onlyUsePackageVersionsFromResolvedFile
  -disableAutomaticPackageResolution
)

# seed_xcode_package_lock <root-dir> <project-path>
# Copies Config/XcodeGen/Package.resolved into the generated project's workspace
# shared data. Run after `xcodegen` writes <project-path> and before the first
# xcodebuild call. Returns 1 with a message on stderr if the committed lock is
# missing.
seed_xcode_package_lock() {
  local root_dir="$1"
  local project_path="$2"
  local lock_src="$root_dir/Config/XcodeGen/Package.resolved"
  local lock_dir="$project_path/project.xcworkspace/xcshareddata/swiftpm"
  if [[ ! -f "$lock_src" ]]; then
    echo "seed_xcode_package_lock: committed lock not found: $lock_src" >&2
    return 1
  fi
  mkdir -p "$lock_dir"
  cp "$lock_src" "$lock_dir/Package.resolved"
}
