# Release

Lorvex Apple has a fail-closed production Developer ID DMG path and a separate
Mac App Store package path. Local app/ZIP packaging remains for development and
CI only. The full verification gate also
builds the `LorvexMobileApp` and `LorvexWatchApp` SwiftUI
entry targets and checks the mobile, watchOS, and Widget metadata
contracts. It also
verifies the XcodeGen project that defines the iOS app, embedded Widget and
Focus Filter extensions, and watchOS app. The repo has simulator packaging
scripts for iOS/iPadOS and watchOS; they preflight the local Xcode
SDK/runtime installation before building, installing, and launching the app on a
simulator.

## Schema freeze — arm before every public archive

The version-1 baseline schema is pinned on real devices and must never be
re-seeded: `schema/migration_policy.json` carries `launched: true`, so the
schema-freeze tripwire is armed. Before archiving each App Store / Developer ID
public build:

- [ ] Run `./script/verify_schema_freeze.py --arm`. This atomically freezes the
  shipped `checksums.lock` entries and sync-payload manifest hashes into the
  policy file's `frozen_baseline`, so every migration and payload-contract
  version the build ships is captured. Review and commit the small
  captured-baseline diff; the archive gate rejects a migration or
  payload-contract version that the release policy has not captured.
- [ ] Never regenerate a released baseline checksum
  (`./script/verify_migration_ladder.py --seed` on an existing entry; the script
  refuses to run while `launched` is `true`). Change the schema only
  by appending a numbered migration to the canonical `schema/migrations/`
  directory (new `NNN_<name>.sql` + a new lock entry + a byte-copy into the Apple
  embed; see `schema/migrations/README.md`). Never
  edit a released `schema/sync_payload/NNN.json`; append the next manifest and
  bump `LorvexVersion.payloadSchemaVersion` for a wire-field change.
- [ ] Treat backup version 1 as a released compatibility contract. The exporter
  may advance later, but `LorvexDataExportPayload.supportedFormatVersions` and
  `ExportManifest.supportedSchemaVersions` must retain `"1"` and route it to its
  explicit decoder. Do not regenerate the committed
  `Tests/Fixtures/BackupFormat/` v1 fixtures; their decode tests are the proof
  that a first-release JSON or ZIP backup remains readable by future builds.

`./script/verify_schema_freeze.py` runs on every gate and fails any mutation of a
released migration identity (filename plus checksum) or sync-payload contract; it
is an advisory no-op only while `launched` is `false`. See
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

On a Mac that holds real Lorvex data, run
`./script/package_dmg.sh --skip-runtime-verification` instead. It builds,
signs, notarizes, staples, and verifies the final DMG exactly as above,
including the read-only checks of the mounted image, then stops: nothing is
installed, launched, quiesced, or reset, so
`LORVEX_ALLOW_DESTRUCTIVE_APP_GROUP_RESET` and the install path are not used.
It writes the `.sha256` beside the DMG and `runtime-verification-skipped.txt`
in the evidence directory in place of `release-evidence.json`, which requires
the runtime proof.

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
  change-token checkpointing are ready; inbound record application is ready
  with conservative field-level remote/local merge. A Lorvex CloudKit remote-change
  push makes `CKSyncEngine` fetch the private record-zone changes, and the
  store commits the decoded records through the Swift sync engine before the
  normal app refresh. Core planning entities
  including tasks, lists, habits, calendar events, memory, and daily briefings
  have outbox export and inbound applier coverage.
- app bundle and nested Widget extension both include
  `PrivacyInfo.xcprivacy`, declaring no tracking, no collected data types, and
  the approved UserDefaults required reason used for local settings/state
- Swift MCP tool catalog contract: the release manifest records the expected
  tool count from `script/expected_mcp_tools.py`, and
  `script/verify_mcp_tool_catalog.py` proves that the typed tool-definition
  registry contains that exact unique set with valid write/idempotency metadata
- release manifest metadata, artifact paths, archive size, and SHA-256
- release manifest strategy: Apple-only across macOS, iOS, iPadOS,
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
./script/verify_watch_simulator.sh
```

These scripts generate an Xcode project from `Config/XcodeGen/project.yml`,
build `LorvexMobileApp` for iOS Simulator or `LorvexWatchApp` for watchOS
Simulator, check the generated app bundle metadata, install it on the
configured simulator, launch it, and terminate it. The generated iOS project
also contains the embedded `LorvexWidgets` target with the real
`WidgetBundle` entrypoint and the separately signed
`LorvexFocusFilterExtension` App Intents target.
`verify_apple_simulators.sh` runs the two platform-specific simulator
verifiers plus `verify_mobile_release_link.sh`
— an unsigned Release device-graph build (`-configuration Release -destination
'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`, a thin wrapper around the
shared `verify_release_link.sh`) that catches Release-only compile/link
failures invisible to Debug/simulator builds and to SwiftPM's single-unit
link, including API calls gated behind an OS version newer than the
platform's deployment-target floor — as the aggregate local Apple platform
gate, printing a per-check summary before returning. If one or more checks
find their simulator runtime or platform SDK unavailable, it returns 78 after
running every check so the missing-environment list is complete.
`verify_xcodegen_project.sh` also emits and verifies
`dist/lorvex-apple-platform-manifest.json`, which records the iOS,
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
push-entitlement key), then builds the package with `productbuild` and signs
it with `productsign`.

CloudKit production schema promotion and App Store Connect provisioning remain
human-gated release requirements. The release manifest records both the runtime
CloudKit sync readiness and the separate production release readiness gate, so
shipping docs cannot claim production CloudKit is ready before those account-side
steps are complete.

## TestFlight builds

One iOS upload carries the iPhone, iPad, and embedded watch apps; the Mac App
Store package is the second channel. `script/release_testflight.sh` runs both
in parallel and reads every credential and signing identity from
`secrets/apple-developer.env` (see `docs/development/NEW_MACHINE.md` at the
repository root). Release with Xcode 27.x: the Mac staging passes a Swift 6.4
flag, and Xcode 26.3's App Intents metadata processor rejects the `bundle:`
argument of an `AppShortcut`'s `shortTitle`. `script/doctor.sh --release`
checks the toolchain and the credentials before anything builds.

1. Verify the tree: `script/verify_swift.sh` (build, catalog compile, and the
   full suite; add `--core` when `core/` changed) and
   `script/verify_static_gates.sh`. App Store Connect checks nothing beyond the
   signature and metadata, so these local gates are the only gate. On a new
   Mac, `script/doctor.sh --release` first.
2. If a migration or sync payload manifest is new, arm the schema freeze first
   (the section above) and commit it; the archive scripts refuse an unarmed
   ladder.
3. Run `script/bump_build.py` (or `script/bump_build.py <number>`). It edits
   each file that holds the build number with one exact replacement that must
   match once, never PlistBuddy `Set`, which re-sorts the plist and deletes its
   comments, and then runs `script/verify_app_metadata.py`, which names any file
   that disagrees. The marketing version stays unchanged between TestFlight
   builds. Run the AppMetadata tests and commit.
4. `script/release_testflight.sh validate <log-dir>` archives and signs both
   channels and has App Store Connect validate each package, without
   uploading (about 15 minutes). Then `script/release_testflight.sh deliver
   <log-dir>` uploads exactly those packages, refuses an iOS package of another
   build number, and prints the two delivery ids. `upload` does both in one
   run. Each channel stops at its first failing step, and a step that fails
   with a transient network error (a lost connection, a 502, 503, or 504) runs
   once more first. Credentials are masked in every log.
5. `script/release_testflight.sh poll <ios-id> <mac-id> <log-dir>` waits until
   both builds have `"import-status" : "VALID"` and a build status of
   `VALID`, `VALID_BINARY`, or `BETA_INTERNAL_TESTING`. `VALID_BINARY` can sit
   next to an import status of `PROCESSING` for several minutes; wait for the
   import status. Match status values with their quotes, because `VALID` is
   also a substring of `INVALID_BINARY`.
6. Delete the superseded packages in `dist/`.

Failures and what they mean:

- `403 FORBIDDEN_ERROR.CONTRACT_NOT_VALID`: an Apple agreement is waiting for
  the account holder in App Store Connect. After it is accepted, re-run only
  the validate and upload steps.
- `NSURLError -1005` (a lost connection) or an HTTP 504: a transient network
  failure. The script retries the step once; a second failure means re-running
  the step alone (`script/archive_mas.sh --upload`, for example).
- `iOS 26.5 is not installed` from `xcodebuild`: a slim Xcode download holds
  only the macOS platform. Install the platforms with `xcodebuild
  -downloadPlatform iOS` and `watchOS`.
- `archive_mas.sh: line N failed: <command>`: the script's error trap naming a
  step that failed without a message of its own. Run that command alone to see
  why.
- App Store Connect `90255`, "files that are only readable by the root user":
  a file in the app bundle is owner-only. `sign_app_bundle.sh` sets the
  embedded profiles to mode 644 whatever the source file's mode, and
  `archive_mas.sh --package` stops before building the package when any file
  in the bundle is not world-readable.
- A package step that sits at 0 percent CPU for minutes, with a `SecurityAgent`
  process running, is a keychain dialog asking to let a tool use the installer
  key. `productbuild --sign` raised one; the package is signed with
  `productsign`, which does not. If another tool ever raises it, approve it once
  with Always Allow.
- `altool --build-status` can hang for several minutes on its first call or
  report that `Defaults.properties` could not be opened. Neither is a
  credential failure; stop that process and poll again.
- Never print the secrets file or a process list that shows `altool`'s
  arguments. List variable names only, for example with
  `awk -F= '/^export / {sub(/^export /, "", $1); print $1}' secrets/apple-developer.env`.
  BSD `sed` has no `\s`, so a `sed` substitution meant to strip values can
  match nothing and print the whole line.

## Produce the direct-distribution release

The credentials live in a notarytool keychain profile created once, so no
secret is passed on the command line:

```bash
xcrun notarytool store-credentials "lorvex-notary" \
  --apple-id "APPLE_ACCOUNT_ID" --team-id "TEAMID" --password "app-specific-password"

export APPLE_TEAM_ID="TEAMID"
export CODE_SIGN_IDENTITY="Developer ID Application: Example, Inc. (TEAMID)"
export NOTARY_KEYCHAIN_PROFILE="lorvex-notary"
export DEVELOPER_ID_APP_PROVISIONING_PROFILE="$PWD/secrets/profiles/LorvexApple.devid.provisionprofile"
export DEVELOPER_ID_MCP_HOST_PROVISIONING_PROFILE="$PWD/secrets/profiles/LorvexMCPHost.devid.provisionprofile"
export DEVELOPER_ID_WIDGET_PROVISIONING_PROFILE="$PWD/secrets/profiles/LorvexWidgets.devid.provisionprofile"
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

## GitHub Releases

The releases page is the download channel for people who cannot or will not use
the App Store, including DMG users in mainland China. A DMG never updates
itself, so the page has to answer which file is current and what changed. It
lists public versions only. A TestFlight build is not a release: App Store
Connect and the `Build N` commits already record each one, and a notarized DMG
for every build would bury the versions people choose between.

- One release per marketing version: tag `vMAJOR.MINOR.PATCH`, title
  `Lorvex <version> (<build>)`, never a pre-release, never left as a draft.
  Superseded releases stay; each is the record of what that version shipped.
- The tag marks the commit the DMG was built from and never moves. Code that
  DMG users should get is a new version and a new release; the newest release is
  the one `releases/latest` serves, which is what the README links to.
- Only repackaging the same commit (a failed notarization, a signing mistake)
  replaces a release's DMG in place, with `gh release upload <tag> <dmg>
  <sha256> --clobber`; the notes then say it was repackaged.
- Every release carries the same two asset names, `Lorvex-macOS-arm64.dmg` and
  `Lorvex-macOS-arm64.dmg.sha256`. `package_dmg.sh` writes
  `Lorvex-macOS-<version>+<build>-arm64.dmg`; rename both files when uploading.
- The notes, in English, keep the shape of the existing release: install
  steps, the Mac and macOS requirement, what changed since the previous
  release, the language count, and the SHA-256 the download must print.
- Cut a DMG release at a milestone, not per build: a new set of languages, a
  feature people asked for, or a fix DMG users need. A version number is spent
  once a DMG or the App Store ships it, so the next release is a new version.
