# Release

Lorvex Apple has a fail-closed production Developer ID DMG path and a separate
Mac App Store package path. Local app/ZIP packaging remains for development and
CI only. The full verification gate also
builds the `LorvexMobileApp`, `LorvexVisionApp`, and `LorvexWatchApp` SwiftUI
entry targets and checks the mobile, visionOS, watchOS, and Widget metadata
contracts. It also
verifies the XcodeGen project that defines the iOS app, embedded Widget and
Focus Filter extensions, visionOS app, and watchOS app. The repo has simulator packaging
scripts for iOS/iPadOS, visionOS, and watchOS; they preflight the local Xcode
SDK/runtime installation before building, installing, and launching the app on a
simulator.

## First public release — arm the schema-freeze tripwire (one-time)

The moment the first public build reaches real devices, the version-1 baseline
schema is pinned in the wild and must never be re-seeded. As part of the first
App Store / Developer ID public submission:

- [ ] Run `./script/verify_schema_freeze.py --arm`. This flips the `launched`
  sentinel in `schema/migration_policy.json` to `true` and atomically freezes
  the shipped `checksums.lock` entries and sync-payload manifest hashes into the
  policy file. Review the small `launched: true` + captured-baseline diff.
- [ ] From this point, never regenerate a released baseline checksum
  (`./script/verify_migration_ladder.py --seed` on an existing entry). Change the schema only
  by appending a numbered migration to the canonical `schema/migrations/`
  directory (new `NNN_<name>.sql` + a new lock entry + a byte-copy into the Apple
  embed; the Tauri schema is directionally aligned, not byte-locked, and is never
  compared against canonical; see `schema/migrations/README.md`). Re-run and
  commit `./script/verify_schema_freeze.py --arm` before archiving each later
  public release; the archive gate rejects a migration or payload-contract
  version that the release policy has not captured. Never
  edit a released `schema/sync_payload/NNN.json`; append the next manifest and
  bump `LorvexVersion.payloadSchemaVersion` for a wire-field change.
- [ ] Treat backup version 1 as a released compatibility contract. The exporter
  may advance later, but `LorvexDataExportPayload.supportedFormatVersions` and
  `ExportManifest.supportedSchemaVersions` must retain `"1"` and route it to its
  explicit decoder. Do not regenerate the committed
  `Tests/Fixtures/BackupFormat/` v1 fixtures; their decode tests are the proof
  that a first-release JSON or ZIP backup remains readable by future builds.

`./script/verify_schema_freeze.py` runs on every gate: dormant advisory (no-op)
while unlaunched, then it fails any post-launch mutation of a released migration
identity (filename plus checksum) or sync-payload contract. See
`../../../docs/design/SCHEMA_OPTIMALITY.md` → "Migration model".

## Production Developer ID DMG (default direct-distribution artifact)

```bash
./script/package_dmg.sh
```

This command has no ad-hoc or pre-freeze fallback. It requires a Developer ID
Application identity, expected team, notarytool keychain profile, explicit
Developer ID provisioning profiles for the app/helper/widget, and production
CloudKit/App Group portal authorization. It also requires a clean Git worktree
so the evidence names reproducible committed source. It builds Release arm64 binaries,
injects profile-authorized application/team identifiers, uses secure
timestamps, notarizes/staples the app payload and the signed outer DMG, mounts
the final disk image, installs that mounted app at `/Applications/Lorvex.app`,
proves installed content identity, permanently resets the production App Group
plus the app's defaults/private CloudSync state without backup or restoration,
cold-launches the exact installed main executable with saved app/window
restoration disabled, verifies LaunchServices and Widget PlugInKit registration,
and then performs a destructive helper write smoke through the real production
App Group. After the smoke removes its own rows, the pipeline performs the full
destructive reset again and cold-launches/reverifies the same installed app; the
retained runtime evidence therefore describes the final clean state, not the
temporary smoke state. That final probe waits for an empty, post-reset Widget
snapshot at the new storage generation, which is published only after the app's
Spotlight/reminder/badge refresh fan-out completes, and rejects any remaining
MCP smoke content. It also opens the recreated SQLite store read-only and proves
the exact smoke task, habit, and list rows are absent. Set
`LORVEX_PRODUCTION_INSTALL_PATH` only when a
release machine needs a different existing, writable, absolute `Lorvex.app`
destination; the script is noninteractive and never invokes `sudo`.

The artifact is
`dist/Lorvex-macOS-<version>+<build>-arm64.dmg`; its sibling `.sha256` and
`dist/release-evidence/<artifact>/release-evidence.json` are part of the
release record. See `docs/DISTRIBUTION.md` § "macOS — production Developer ID
DMG" for the required environment. Existing local Lorvex data on the release
machine is deliberately erased, and an existing app at the install path is
replaced; no backup/move/restore step exists. The shipped app contains no
automatic install/upgrade reset. Production outputs are immutable: if the exact
version/build DMG, checksum, or evidence path already exists, the command fails
instead of replacing it and `BUILD_VERSION` must advance. Move any differently
named retained `dist/Lorvex-macOS-*.dmg` releases out of `dist` first: an
unexpected Lorvex DMG also makes packaging fail rather than leave an ambiguous
unsigned candidate beside the production image.

The clean cold launch reconciles the empty database into Spotlight, widgets, and
badges. On the normal successful empty-store refresh, the reminder schedulers
also replace Lorvex-owned pending task/habit requests with empty sets and remove
orphaned snoozes. The external harness cannot inspect that app-owned
`UNUserNotificationCenter` namespace directly, so it does not claim notification
attestation. In particular, notifications macOS had already delivered remain
OS-owned history: the ordinary launch path intentionally does not call the
in-app factory-reset-only delivered-notification eraser. Use a dedicated clean
release account/machine when an empty Notification Center is part of the manual
release evidence; no production launch argument or hidden test hook is provided.

## Local development archive

```bash
./script/archive_local.sh
```

This development/CI command builds `dist/Lorvex.app`, creates
`dist/Lorvex-1.0.0+1.zip`, emits
`dist/lorvex-apple-mcp-client.json`, writes
`dist/lorvex-apple-release-manifest.json`, extracts the archive, and verifies
repository contracts. It is not the public Developer ID artifact because it
does not require the armed freeze, production profiles, final-DMG notarization,
or final mounted-artifact evidence:

- pre-package quality gates for Apple-only strategy, core service coverage,
  and hotspot limits
- app bundle structure
- Mach-O load-path safety for the app binary, helper, and widget
- generated MCP client config points at the bundled helper
- generated MCP client config points at an executable bundled helper
- generated MCP client config carries Apple-only Swift-native MCP metadata and
  explicitly forbids a Rust MCP server fallback
- release manifest records the MCP client config generator, verifier, Python
  test glob, and database environment keys
- release manifest records quality gate verifiers for core service coverage,
  hotspot limits, Apple-only strategy, build matrix coverage, CloudKit sync
  readiness drift checks, system entrypoint drift checks, MCP client config
  validation, MCP stdio smoke coverage, Swift MCP tool catalog drift checks,
  user documentation drift checks, and release manifest self-verification
- release manifest records install-package quality gate verifiers for Mach-O
  distribution load paths and codesign entitlements
- release manifest records WidgetKit integration metadata for the embedded
  Home Screen widget and the Control Widget kind/display contract
- release manifest records CloudKit sync readiness metadata: outbound record
  export, private database subscription, remote-change refresh, and
  atomic SQLite change-token checkpointing are ready; inbound record application is ready
  with conservative field-level remote/local merge. Live CloudKit remote-change
  pushes now fetch private record-zone changes and commit decoded records plus
  the successor token atomically through the Swift sync engine before the normal
  app refresh. Core planning entities
  including tasks, lists, habits, calendar events, memory, and focus plans
  have outbox export and inbound applier coverage.
- app bundle and nested Widget extension both include
  `PrivacyInfo.xcprivacy`, declaring no tracking, no collected data types, and
  the approved UserDefaults required reason used for local settings/state
- Swift MCP tool catalog contract: the release manifest records the expected
  tool count from `script/expected_mcp_tools.py`, and
  `script/verify_mcp_tool_catalog.py` proves that the typed tool-definition
  registry contains that exact unique set with valid write/idempotency metadata
- release manifest metadata, artifact paths, archive size, and SHA-256
- release manifest strategy: Apple-only across macOS, iOS, iPadOS, visionOS,
  watchOS, WidgetKit, and App Intents; Swift-native MCP; no CLI product,
  no Rust at runtime, and system appearance instead of a cross-platform theme
  system
- Mach-O load paths are distribution-safe
- code signature validity
- hardened runtime flag
- absence of AppleDouble `._` sidecar files

## Apple Simulator Packaging

```bash
./script/verify_apple_simulators.sh
./script/verify_mobile_simulator.sh
./script/verify_vision_simulator.sh
./script/verify_watch_simulator.sh
```

These scripts generate an Xcode project from `Config/XcodeGen/project.yml`,
build `LorvexMobileApp` for iOS Simulator, `LorvexVisionApp` for visionOS
Simulator, or `LorvexWatchApp` for watchOS Simulator, check the generated app
bundle metadata, install it on the configured simulator, launch it, and
terminate it. The generated iOS project also contains the embedded
`LorvexFocusWidgetExtension` target with the real `WidgetBundle` entrypoint and
the separately signed `LorvexFocusFilterExtension` App Intents target.
`verify_apple_simulators.sh` runs the three platform-specific simulator
verifiers plus `verify_mobile_release_link.sh` and `verify_vision_release_link.sh`
— unsigned Release device-graph builds (`-configuration Release -destination
'generic/platform=iOS'` / `'generic/platform=visionOS'` `CODE_SIGNING_ALLOWED=NO`,
both thin wrappers around the shared `verify_release_link.sh`) that catch
Release-only compile/link failures invisible to Debug/simulator builds and to
SwiftPM's single-unit link, including API calls gated behind an OS version
newer than a platform's deployment-target floor — as the aggregate local Apple
platform gate, printing a per-check summary before returning. If one or more
checks find their simulator runtime or platform SDK unavailable, it returns 78
after running every check so the missing-environment list is complete.
`verify_xcodegen_project.sh` also emits and verifies
`dist/lorvex-apple-platform-manifest.json`, which records the iOS, visionOS,
watchOS, Watch complication, Widget, Focus Filter, and shared App Intents targets, bundle ids, Info.plists,
entitlements, simulator verifier scripts, the aggregate simulator verifier, App
Group, CloudKit container, URL scheme, XcodeGen drift checks for bundle ids,
Info.plists, entitlements, and product names, and shared quality gate verifiers
for Apple-only strategy, build matrix coverage, system entrypoints, core service
coverage, hotspot limits, MCP client config validation, MCP stdio smoke
coverage, Swift MCP tool catalog drift checks, user documentation drift checks,
Mach-O distribution load paths, codesign entitlement checks, and release
manifest self-verification.

Set `LORVEX_IOS_SIMULATOR_NAME` to choose a different simulator name. If Xcode's
installed simulator SDK and CoreSimulator runtimes do not match, the
platform-specific script exits before building and prints the available
destinations, SDKs, and runtimes.
Set `LORVEX_VISION_SIMULATOR_NAME` to choose a different visionOS simulator.
Set `LORVEX_WATCH_SIMULATOR_NAME` to choose a different watchOS simulator.

## Standalone ZIP notarization preflight (diagnostic utility)

```bash
./script/notarize_archive.sh --preflight
```

This utility is useful for diagnosing a manually assembled Developer ID ZIP;
it is not the supported final DMG release command. The preflight checks that the archive exists, the archive is readable, the app
inside the archive byte-matches `dist/Lorvex.app`, its signature verifies,
hardened runtime is enabled, and Xcode's `notarytool` and `stapler` are
available. It also verifies Developer ID Application authority, a common
TeamIdentifier, and a secure timestamp on the top-level app and every nested
executable. Set `APPLE_TEAM_ID` to require an expected team; without it,
preflight derives the team from the app signature and checks the nested code
against it. Preflight performs no notary authentication or network submission,
so it cannot prove the keychain profile or Apple-service acceptance.

Release manifest verification also opens the zip archive and rejects AppleDouble
sidecar files, `__MACOSX` metadata entries, symlink entries, and entries outside
the top-level `Lorvex.app/` bundle. The archive must contain the app
executable, privacy manifest, bundled MCP helper, and Widget extension files.
The core is statically linked Swift, so no dylib is bundled.

## Mac App Store

```bash
./script/archive_mas.sh --preflight
./script/archive_mas.sh --package
```

The Mac App Store path signs `Lorvex.app` with
`Config/LorvexAppleCloudKitAppStore.entitlements`, requires the app and MCP
helper distribution provisioning profiles to be embedded, verifies CloudKit
service, the `iCloud.com.lorvex.apple` container, and
`com.apple.developer.aps-environment=production` (the native macOS
push-entitlement key), then builds an App Store signed package with
`productbuild`.

CloudKit production schema promotion and App Store Connect provisioning remain
human-gated release requirements. The release manifest records both the runtime
CloudKit sync readiness and the separate production release readiness gate, so
shipping docs cannot claim production CloudKit is ready before those account-side
steps are complete.

## Produce the direct-distribution release

The credentials live in a notarytool keychain profile created once, so no
secret is passed on the command line:

```bash
xcrun notarytool store-credentials "lorvex-notary" \
  --apple-id "APPLE_ACCOUNT_ID" --team-id "TEAMID" --password "app-specific-password"

export APPLE_TEAM_ID="TEAMID"
export CODE_SIGN_IDENTITY="Developer ID Application: Example, Inc. (TEAMID)"
export NOTARY_KEYCHAIN_PROFILE="lorvex-notary"
export DEVELOPER_ID_APP_PROVISIONING_PROFILE="$PWD/secrets/profiles/LorvexApple-DeveloperID.provisionprofile"
export DEVELOPER_ID_MCP_HOST_PROVISIONING_PROFILE="$PWD/secrets/profiles/LorvexMCPHost-DeveloperID.provisionprofile"
export DEVELOPER_ID_WIDGET_PROVISIONING_PROFILE="$PWD/secrets/profiles/LorvexFocusWidget-DeveloperID.provisionprofile"
export LORVEX_ALLOW_DESTRUCTIVE_APP_GROUP_RESET=1
./script/package_dmg.sh
```

If duplicate identities share a display name, `CODE_SIGN_IDENTITY` may be the
SHA-1 value from `security find-identity -v -p codesigning`; the script still
proves that it resolves to Developer ID Application and verifies the final team
and authority. In headless automation, unlock the keychain and grant
`/usr/bin/codesign` access to the private key before running. The release path
always uses secure timestamping and never accepts `SIGN_TIMESTAMP=none`.

Publish only the final DMG after its `.sha256` matches and the evidence manifest
contains accepted app and DMG notary logs. Do not upload this DMG to App Store
Connect; use `archive_mas.sh` for that separate channel.
