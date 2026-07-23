# Lorvex Distribution Guide

This document describes the end-to-end packaging and distribution flow for
each Apple platform target. It covers the current working state, what is gated
by `verify_all.sh`, and what requires active Apple Developer provisioning.

Apple Swift is the intended shipping line for every Apple ecosystem target:
macOS App Store, direct macOS builds, iOS, iPadOS, watchOS, visionOS,
WidgetKit, App Intents, EventKit, and CloudKit/iCloud. The Tauri app is not the
future Mac App Store or iCloud distribution path.

---

## Table of contents

1. [Platform targets overview](#1-platform-targets-overview)
2. [macOS — production Developer ID DMG](#2-macos--production-developer-id-dmg)
3. [macOS — local development and CI packages](#3-macos--local-development-and-ci-packages)
4. [macOS - Mac App Store](#4-macos---mac-app-store)
5. [iOS/iPadOS — App Store Connect](#5-iosipados--app-store-connect)
6. [watchOS — embedded in iOS app](#6-watchos--embedded-in-ios-app)
7. [visionOS — App Store Connect](#7-visionos--app-store-connect)
8. [Entitlements reference](#8-entitlements-reference)
9. [Required Apple Developer portal provisioning](#9-required-apple-developer-portal-provisioning)
10. [Distribution gaps and follow-up work](#10-distribution-gaps-and-follow-up-work)

---

## 1. Platform targets overview

| Platform | App target | Extensions embedded | Build system | Archive script |
|---|---|---|---|---|
| macOS 15+ direct distribution | `LorvexApple` | `LorvexFocusWidget.appex` | SwiftPM → Developer ID + notarized DMG | `package_dmg.sh` |
| macOS 15+ local/CI | `LorvexApple` | `LorvexFocusWidget.appex` | SwiftPM → ad-hoc app/ZIP | `package_local.sh` / `archive_local.sh` |
| macOS 15+ Mac App Store | `LorvexApple` | `LorvexFocusWidget.appex` | SwiftPM → App Store signed package | `archive_mas.sh` |
| iOS/iPadOS 18+ | `LorvexMobileApp` | `LorvexFocusWidget.appex`, `LorvexFocusFilterExtension.appex` | XcodeGen → xcodebuild | `archive_ios.sh` |
| watchOS 11+ | `LorvexWatchApp` | `LorvexWatchComplication.appex` | XcodeGen → xcodebuild | `archive_ios.sh --scheme LorvexWatchApp` |
| visionOS 2+ | `LorvexVisionApp` | — | XcodeGen → xcodebuild | `archive_ios.sh --scheme LorvexVisionApp` |

---

## 2. macOS — production Developer ID DMG

`package_dmg.sh` is the only direct-distribution release command. It has no
development fallback: no arguments means a real Release, arm64-only,
Developer-ID-signed, profile-authorized, notarized and stapled DMG, or failure.
The output is
`dist/Lorvex-macOS-<version>+<build>-arm64.dmg` plus a sibling `.sha256` and
`dist/release-evidence/<artifact>/release-evidence.json`.

Before running it, arm the schema freeze and create a notarytool keychain
profile. The app, MCP helper and widget need three explicit **Developer ID**
macOS provisioning profiles for their own bundle IDs; the app profile must
authorize the production CloudKit container and push environment, and all
three must authorize `group.com.lorvex.apple`.

```bash
xcrun notarytool store-credentials LorvexNotary \
  --apple-id "APPLE_ACCOUNT_ID" \
  --team-id "ABCDE12345" \
  --password "xxxx-xxxx-xxxx-xxxx"

export APPLE_TEAM_ID="ABCDE12345"
export CODE_SIGN_IDENTITY="Developer ID Application: Team Name (ABCDE12345)"
export NOTARY_KEYCHAIN_PROFILE="LorvexNotary"
export DEVELOPER_ID_APP_PROVISIONING_PROFILE="$PWD/secrets/profiles/LorvexApple-DeveloperID.provisionprofile"
export DEVELOPER_ID_MCP_HOST_PROVISIONING_PROFILE="$PWD/secrets/profiles/LorvexMCPHost-DeveloperID.provisionprofile"
export DEVELOPER_ID_WIDGET_PROVISIONING_PROFILE="$PWD/secrets/profiles/LorvexFocusWidget-DeveloperID.provisionprofile"
export LORVEX_ALLOW_DESTRUCTIVE_APP_GROUP_RESET=1
./script/package_dmg.sh
```

The final verification installs the app at `/Applications/Lorvex.app`. The
calling user must be able to write `/Applications`; the script is intentionally
noninteractive and never invokes `sudo`. A release-only machine may instead set
`LORVEX_PRODUCTION_INSTALL_PATH` to another existing, writable, absolute path
whose last component is `Lorvex.app`. The existing app at that path is deleted,
not backed up or restored. A version/build output is immutable: if its exact DMG,
checksum, or release-evidence path already exists, packaging refuses to overwrite
it and the build number must advance. Before starting, move previously retained
`dist/Lorvex-macOS-*.dmg` releases out of `dist/`: any differently named Lorvex
DMG also makes the production command fail so an old unsigned image cannot be
mistaken for the new output. A failed attempt that has already reserved its
evidence path likewise consumes that build number.

The command enforces all of the following before reporting success:

- The Apple schema freeze is armed and intact. `LORVEX_ALLOW_UNFROZEN` is
  forbidden on this path, and the Git worktree must be clean so the evidence
  manifest identifies reproducible committed source.
- Every binary is built with SwiftPM's Release configuration and is arm64-only.
- The app uses the production CloudKit/APS entitlement plan. Profile-derived
  `com.apple.application-identifier` and
  `com.apple.developer.team-identifier` values are added before signing, then
  compared against each final signature and decoded embedded profile.
- The app, helper and widget are signed inside-out by the requested Developer
  ID Application identity, with hardened runtime, secure timestamps, the
  expected TeamIdentifier, and explicit Developer ID profiles.
- The app payload is notarized and stapled before it is placed in the DMG. The
  outer DMG is then signed, separately notarized, and stapled. Both notary
  submission results and logs are retained.
- `hdiutil verify`, DMG Gatekeeper assessment, read-only mounting, byte-content
  comparison, and strict signing/entitlement/profile checks run against the
  final artifact—not an earlier sibling bundle. The mounted app is copied to the
  real install path, then a deterministic tree digest proves installed file and
  symlink content equals the mounted source.
- Before the installed main app is launched for the first time, the external
  release harness verifies the installed helper's production signature and App
  Group entitlement, stops every Lorvex process, and proves the App Group and
  main-app private container have no open handles. It clears the main-app and
  shared-defaults domains, removes private CloudSync safety/cache state, and
  permanently resets App Group data under the storage-generation lock. This
  prevents an old `.live` preference or EventKit setting from contaminating the
  clean cold launch. The exact cleared paths, reset generation, and the facts
  that no backup or restoration occurred are retained as machine-readable
  evidence. It never moves, backs up, or restores that data.
- LaunchServices registers that exact installed path; the main app cold-launches
  with saved app/window restoration disabled and remains alive through a bounded
  stability window; its PID is tied to the installed executable; and PlugInKit
  must resolve the embedded widget back to the installed `.appex`. Raw
  registration, runtime, PID/path, Gatekeeper,
  signature, profile and signed-entitlement evidence is retained. When
  `launchctl procinfo` is available to the caller, it must report `entitlements
  validated`; an ordinary non-root run records the explicit unsupported result
  instead of pretending runtime entitlement evidence exists.
- Only after the main-app launch succeeds does the bundled sandboxed MCP helper
  perform a real write round-trip through the production App Group. The helper
  smoke stops processes and resets the App Group again before and after its
  write, so main-app startup artifacts cannot weaken the empty-store assertion
  and no smoke data remains. The full production reset then runs once more to
  clear shared defaults and private sync state as well as the App Group, and the
  same installed app is cold-launched/reverified again. Final runtime evidence
  must postdate that final reset, whose storage generation must exceed the
  initial reset; the evidence generator also requires the helper's post-smoke
  removal proof. The final runtime probe waits for the app to publish an empty
  Widget snapshot at that new generation and rejects any residual MCP smoke row;
  it also queries the recreated SQLite store read-only for the exact smoke task,
  habit, and list. Because snapshot publication follows Spotlight indexing,
  reminder scheduling, and badge reconciliation in the launch refresh, it is
  also the external completion signal for those derived surfaces. Neither reset
  moves, backs up, or restores data. Replacing the installed app likewise never
  preserves the previous bundle. These destructive behaviors live only in the
  external release harness; normal app installation, upgrade and launch contain
  no automatic data reset.
- On a successful empty-store refresh the production schedulers replace
  Lorvex-owned pending task/habit requests with empty sets and remove orphaned
  snoozes. The external harness cannot directly inspect the app-owned
  `UNUserNotificationCenter` namespace, so this remains natural app behavior,
  not release evidence. Already-delivered notifications are different: macOS
  owns that history, and an ordinary launch deliberately does not invoke the
  factory-reset-only `removeAllDeliveredNotifications` path. Attesting either OS
  state without user interaction would require a privileged or hidden production
  hook, so release testing that requires an empty Notification Center must use a
  dedicated clean account/machine.

The Developer ID DMG and the Mac App Store candidate share product code,
bundle IDs, production CloudKit contract and schema, but they are **not the
same signed artifact**. Developer ID uses Developer ID certificates/profiles
plus notarization; MAS uses Apple Distribution profiles, App Store validation,
an installer package and the App Store receipt model. Never upload the DMG to
App Store Connect or repackage the MAS candidate as a DMG.

## 3. macOS — local development and CI packages

```bash
./script/package_local.sh
./script/archive_local.sh
```

These commands assemble and inspect `dist/Lorvex.app` and a ZIP for local
development, CI, manifest generation and offline verifier coverage. Without a
real identity they sign ad hoc, omit restricted entitlements/profiles, and run
the MCP smoke against a disposable database. They do not require an armed
schema freeze and do not notarize the final outer distribution artifact.
Consequently, neither output is a production release candidate.

`notarize_archive.sh` remains a ZIP notarization utility and offline signing
preflight. It is useful for diagnosing Developer ID signing independently, but
the supported public direct-distribution path is `package_dmg.sh`, which adds
the stricter profile-aware production contract and final-DMG verification.

---

## 4. macOS - Mac App Store

Mac App Store builds use the production CloudKit entitlement template and
produce a signed installer package for App Store Connect. This is distinct
from Developer ID notarization: do not submit the notarized zip/DMG to the Mac
App Store.

### Repository-side preflight

```bash
./script/archive_mas.sh --preflight
```

Every `archive_mas.sh` subcommand (`--preflight`, `--package`, `--validate`,
`--upload`) routes through `preflight()`, which first reruns Apple schema-embed
parity, semantic migration-ladder validation, sync-payload validation, and the
strict release freeze check. The freeze must be ARMED and must capture every
current migration/payload identity (`schema/migration_policy.json`
`"launched": true`) — see
`docs/release.md` § "First public release" for arming it. Lorvex is
pre-launch today, so this gate is skippable for a local pre-launch build
only via `LORVEX_ALLOW_UNFROZEN=1`; real release packaging must not set that
variable, since the whole point is to keep a pre-freeze schema from ever
reaching a shipped MAS artifact.

```bash
LORVEX_ALLOW_UNFROZEN=1 ./script/archive_mas.sh --preflight   # pre-launch local build only
```

The preflight then runs `verify_mas_release_readiness.py`, which checks:

- `Config/LorvexAppleCloudKitAppStore.entitlements` includes the App Group,
  sandbox, user-selected-file and calendar access, `iCloud.com.lorvex.apple`, CloudKit
  service, `com.apple.developer.icloud-container-environment=['Production']`,
  and `com.apple.developer.aps-environment=production` — the native macOS
  push-entitlement key (Xcode-managed signing injects both of these
  automatically; the manual codesign flow here needs them on the plist).
- `Config/LorvexApple.entitlements` stays the basic non-CloudKit macOS template.
- `verify_codesign_entitlements.py` has MAS flags for required CloudKit and
  production APS checks.
- `archive_mas.sh` is present and executable.

CloudKit production schema promotion remains a manual release gate. Promote
the development schema for `iCloud.com.lorvex.apple` in CloudKit Console and
verify the matching App ID/provisioning profiles before enabling Live iCloud
Sync in a submitted MAS build.

### Package

```bash
export MAS_APP_SIGN_IDENTITY="Apple Distribution: Team Name (TEAMID)"
export MAS_INSTALLER_SIGN_IDENTITY="3rd Party Mac Developer Installer: Team Name (TEAMID)"
./script/archive_mas.sh --package
```

The package path:

1. Runs `package_local.sh` with
   `ENTITLEMENTS_PATH=Config/LorvexAppleCloudKitAppStore.entitlements`.
2. Verifies the signed `.app` with:

   ```bash
   ./script/verify_codesign_entitlements.py \
     --require-cloudkit \
     --require-production-aps \
     dist/Lorvex.app
   ```

3. Cross-checks any embedded provisioning profile against the signed
   entitlements: `./script/verify_mas_provisioning.py dist/Lorvex.app`.
4. Produces `dist/Lorvex-macOS-MAS-<version>+<build>.pkg` with
   `productbuild --component ... --sign ...`.

### Provisioning profiles

Distribution provisioning profiles are passed to `--package` the same way
signing identities are — environment variables pointing at a local
`.provisionprofile` file downloaded from the Apple Developer portal:

```bash
export MAS_APP_PROVISIONING_PROFILE="secrets/profiles/LorvexApple.provisionprofile"
export MAS_MCP_HOST_PROVISIONING_PROFILE="secrets/profiles/LorvexMCPHost.provisionprofile"
export MAS_WIDGET_PROVISIONING_PROFILE="secrets/profiles/LorvexFocusWidget.provisionprofile"
```

If unset, `sign_app_bundle.sh` falls back to that same `secrets/profiles/`
location by default (see `.gitignore`'s "Secrets & internal ops" block — the
directory is never committed). An explicitly-set path that does not exist is
treated as a misconfiguration and fails the build.

**The app, MCP helper, and Focus-widget profiles are all mandatory for
`--package`.** A MAS package with no distribution provisioning profile is never
accepted by App Store Connect, so `archive_mas.sh --package` hard-fails
immediately after packaging if `Contents/embedded.provisionprofile` is missing
from any of the top-level `.app`, the MCP helper bundle, or the Focus widget
extension — set the corresponding `MAS_*_PROVISIONING_PROFILE` env var or place
each profile at its `secrets/profiles/` default path first. This mandatory check is specific to `--package`;
`sign_app_bundle.sh` itself keeps its soft-skip (silently omit embedding when
no profile is found) for `package_local.sh`/`archive_local.sh`, where building
without portal credentials is normal. `package_dmg.sh` layers its own mandatory
Developer ID profile gate above the generic signer.

When present, each profile is copied to `Contents/embedded.provisionprofile`
before its bundle is signed (embedding after signing would invalidate the
signature) — the top-level `.app`, the MCP helper bundled app
(`Contents/Helpers/LorvexMCPHost.app`), and the Focus widget extension
(`Contents/PlugIns/LorvexFocusWidget.appex`) each carry their own.

`verify_mas_provisioning.py` runs after packaging and, for every embedded
profile it finds, decodes it (`security cms -D -i`, a purely local operation —
no Apple account or network access) and cross-checks its `Entitlements`
against the target's actual signed entitlements and bundle id: application
identifier/bundle id (read from the profile's native macOS
`com.apple.application-identifier` key, falling back to the bare
`application-identifier` key iOS-family profiles use), App Group list, iCloud
container, and `com.apple.developer.aps-environment`. Where the decoded
profile carries the data, it also checks the profile is a macOS distribution
profile (`Platform` includes `OSX`), is not expired, and — across all
embedded profiles in the package — declares a consistent `TeamIdentifier`;
any field absent from a given profile is soft-skipped. Any mismatch is a hard
failure. A target with no embedded profile is logged as a `NOTE` and
skipped — the expected state for a local build without portal credentials
(the app/helper/widget case is instead caught earlier by `archive_mas.sh --package`
itself, per above). Independent of profile presence, it always asserts the
MAS structural invariants that need no Apple credentials at all: the MCP
helper ships as a bundled `.app` with its own `Info.plist` (not a bare
Mach-O), every Mach-O executable in the bundle carries a non-empty
entitlements plan, and none of them lack the app-sandbox entitlement.

### Export compliance

Every shipped Info.plist (macOS, iOS/iPadOS, visionOS, watchOS, the watch
complication, the WidgetKit extension, and the MCP helper) declares
`ITSAppUsesNonExemptEncryption=false`: Lorvex only uses SHA-256 hashing
(idempotency keys, content checksums), which App Store Connect classifies as
exempt. `verify_app_metadata.py` asserts the key on every checked-in Info.plist
and, for the macOS app (whose Info.plist has no checked-in static file — it is
generated by a heredoc in `build_and_run.sh`), asserts the same declaration in
that generator's source text.

### Validate or upload

```bash
APPLE_ID="APPLE_ACCOUNT_ID" \
APPLE_APP_PASSWORD="app-specific-password" \
  ./script/archive_mas.sh --validate

APPLE_ID="APPLE_ACCOUNT_ID" \
APPLE_APP_PASSWORD="app-specific-password" \
  ./script/archive_mas.sh --upload
```

Alternatively, open the generated package in Transporter.app or use Xcode
Organizer after archiving with equivalent App Store provisioning.

---

## 5. iOS/iPadOS — App Store Connect

### Build flow

```bash
# Compile check (no signing required)
./script/archive_ios.sh --scheme LorvexMobileApp --build-only

# Archive + export IPA (requires APPLE_TEAM_ID)
export APPLE_TEAM_ID="ABCDE12345"
./script/archive_ios.sh --scheme LorvexMobileApp --export
```

`--archive` and `--export` (but not `--build-only`, which never produces a
distributable artifact) require the schema-freeze tripwire to be ARMED, the
same gate `archive_mas.sh` enforces — see § 4 above. Skip it for a local
pre-launch build only with `LORVEX_ALLOW_UNFROZEN=1`.

`archive_ios.sh` performs:

1. `xcodegen` — regenerates the Xcode project from `Config/XcodeGen/project.yml`
   into `dist/ios-xcode-project/`.
2. `xcodebuild archive` — builds the Release configuration for the generic iOS
   device destination, producing `dist/ios-archive/LorvexMobileApp.xcarchive`.
3. Substitutes `APPLE_TEAM_ID` into the checked-in ExportOptions template.
4. `xcodebuild -exportArchive` — produces an IPA under
   `dist/ios-archive/LorvexMobileApp-export/`.
5. Unpacks the exact exported IPA and recursively verifies the host, Widget,
   Focus Filter, embedded Watch app, and Watch complication. Every bundle must
   have its own matching signature and embedded profile; App Store Connect
   exports reject wildcard/development profiles, and each profile must authorize
   the restricted capabilities in that bundle's signed entitlements. This keeps
   the Focus Filter's App Group grant independent from the Widget profile.

### Export methods

| File | method | Use |
|---|---|---|
| `Config/ExportOptions/AppStore.plist` | `app-store-connect` | TestFlight + App Store |
| `Config/ExportOptions/Development.plist` | `development` | direct device install |

Select via `EXPORT_METHOD=development ./script/archive_ios.sh --export`.

### App Store Connect upload

```bash
xcrun altool --upload-app \
  -f dist/ios-archive/LorvexMobileApp-export/LorvexMobileApp.ipa \
  --type ios \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_PASSWORD"
```

Alternatively use Xcode Organizer (open the `.xcarchive`) or Transporter.app.

### Companion watch app embed

`LorvexMobileApp` embeds `LorvexWatchApp` through an `embed: true` dependency
in `project.yml`, so `xcodebuild` copies the built watch app into the host
IPA's `Watch/` directory — the only way a watchOS app reaches the App Store (a
watch app cannot be submitted on its own). The watch app is therefore a
**companion**, not a standalone watch-only app: its Info.plist declares
`WKWatchOnly=false` and names the iOS host via `WKCompanionAppBundleIdentifier`
(`com.lorvex.apple`). `script/xcodegen_dependency_check.py
--require-embed` enforces the embed in the full gate.

### Extensions and companion apps embedded in LorvexMobileApp

- `LorvexFocusWidgetExtension` (WidgetKit) — declared as a dependency with
  `embed: true` in `project.yml`.
- `LorvexWatchApp` (watchOS companion) — declared with `embed: true`; the built
  watch app is copied into the IPA's `Watch/` directory.

`LorvexSystemIntents` (App Intents) is linked as a framework, not a separate
extension bundle, so it does not appear as an `.appex` entry in the IPA.

---

## 6. watchOS — embedded in iOS app

### Current state

`LorvexWatchApp` ships embedded inside its iOS companion `LorvexMobileApp`: an
`embed: true` dependency in `project.yml` makes `xcodebuild` copy the built
watch app into the host IPA's `Watch/` directory, which is how a watchOS app
reaches the App Store (a watch app cannot be submitted on its own). Because it
is a companion, its Info.plist declares `WKWatchOnly=false` and names the iOS
host via `WKCompanionAppBundleIdentifier` (`com.lorvex.apple`).

The companion pair is archived through the iOS scheme
(`archive_ios.sh --scheme LorvexMobileApp`); the embedded watch app rides along
in the resulting IPA.

### Complication embed hierarchy (within the watch app)

```
LorvexWatchApp.app
└── PlugIns/
    └── LorvexWatchComplication.appex   (WidgetKit complication)
```

This embed is declared explicitly in `project.yml`: `LorvexWatchComplication`
is a dependency of `LorvexWatchApp` with `embed: true`, so XcodeGen places the
complication `.appex` inside the watch app's `PlugIns/` directory.

---

## 7. visionOS — App Store Connect

The visionOS target (`LorvexVisionApp`) follows the same flow as iOS:

```bash
export APPLE_TEAM_ID="ABCDE12345"
./script/archive_ios.sh --scheme LorvexVisionApp --export
```

`xcodebuild` destination is `generic/platform=iOS` (visionOS shares the same
destination flag in Xcode 15+). The scheme is declared in `project.yml` with
`platform: visionOS`.

---

## 8. Entitlements reference

The table below shows the entitlements declared in each checked-in `.entitlements`
file and the corresponding Apple Developer capability that must be enabled in the
portal for a distribution build.

macOS entitlements are selected by the packaging channel. The production
Developer ID DMG derives its final app entitlements from
`LorvexAppleCloudKitAppStore.entitlements` plus the identifiers in its explicit
Developer ID profile; MAS uses the same production CloudKit values with Apple
Distribution profiles; `package_local.sh` retains the caller-selectable
development behavior (see §2–§4). `LorvexMobileApp` and
`LorvexVisionApp` instead get their Release (App Store archive) entitlements from
a **per-target** `configs: Release:` block in `Config/XcodeGen/project.yml` — each
target names its own `CODE_SIGN_ENTITLEMENTS` override for that configuration
only. This is deliberately not a project-wide `xcodebuild
CODE_SIGN_ENTITLEMENTS=...` override, which would apply to every target in the
archive (widgets, the watch app, the watch complication) and leak one app's
entitlements onto all of them.

| Target | File | App Group | Sandbox | User-Selected Files | Bookmarks | CloudKit | Notes |
|---|---|---|---|---|---|---|---|
| macOS app | `LorvexApple.entitlements` | ✓ | ✓ | ✓ | — | — | basic (no iCloud sync) |
| macOS app + iCloud, development | `LorvexAppleCloudKit.entitlements` | ✓ | ✓ | ✓ | — | ✓ | development `com.apple.developer.aps-environment` — the native macOS push-entitlement key, not iOS's bare `aps-environment` |
| macOS app + iCloud, production | `LorvexAppleCloudKitAppStore.entitlements` | ✓ | ✓ | ✓ | — | ✓ | production `com.apple.developer.aps-environment` + `com.apple.developer.icloud-container-environment=['Production']`; the production value plan used by both Developer ID DMG and MAS signing (the signing identity/profile channel still differs) |
| macOS MCP helper | `LorvexMCPHost.entitlements` | ✓ | ✓ | — | — | — | bundled helper app (`Contents/Helpers/LorvexMCPHost.app`), not a bare Mach-O; no iCloud/aps — serves the Lorvex-managed group-container store only, same file for dev and MAS |
| iOS app, Debug (local run) | `LorvexMobileApp.entitlements` | ✓ | — | — | — | — | basic; `project.yml`'s `base` setting, used for every configuration except Release |
| iOS app + iCloud, App Store (Release archive) | `LorvexMobileAppCloudKitAppStore.entitlements` | ✓ | — | — | — | ✓ | production APS + `com.apple.developer.icloud-container-environment=['Production']`; `project.yml`'s per-target `configs: Release:` override for `LorvexMobileApp` |
| iOS app + iCloud, manual dev template | `LorvexMobileAppCloudKit.entitlements` | ✓ | — | — | — | ✓ | development APS; swap in by hand for on-device Debug iCloud testing — not wired into `project.yml` |
| visionOS app, Debug (local run) | `LorvexVisionApp.entitlements` | ✓ | — | — | — | — | basic; matches mobile; `project.yml`'s `base` setting, used for every configuration except Release |
| visionOS app + iCloud, App Store (Release archive) | `LorvexVisionAppCloudKitAppStore.entitlements` | ✓ | — | — | — | ✓ | `com.apple.developer.icloud-container-environment=['Production']`; **no `aps-environment` key** — visionOS holds a synced on-disk DB like iOS but registers no CloudKit push subscription; it detects remote iCloud changes by foreground/scene-active polling instead. `project.yml`'s per-target `configs: Release:` override for `LorvexVisionApp` |
| visionOS app + iCloud, manual dev template | `LorvexVisionAppCloudKit.entitlements` | ✓ | — | — | — | ✓ | same as the App Store variant — no `aps-environment` key in any visionOS entitlements file, dev or Release |
| watchOS app | `LorvexWatchApp.entitlements` | ✓ | — | — | — | — | one file for every configuration including the App Store archive — watch is a read-only snapshot client (no CloudKit), so it needs no Release override |
| Watch complication | `LorvexWatchComplication.entitlements` | ✓ | — | — | — | — | |
| Widget extension (macOS) | `LorvexWidgetExtension.entitlements` | ✓ | ✓ | — | — | — | sandbox required for macOS extensions |
| Focus widget (iOS) | `LorvexFocusWidgetExtension.entitlements` | ✓ | — | — | — | — | no `app-sandbox` key (invalid on iOS) |
| Focus Filter extension (iOS) | `LorvexFocusFilterExtension.entitlements` | ✓ | — | — | — | — | independent App ID/profile; App Group lets the filter update shared focus state |
| iOS CarPlay approval template | `LorvexCarPlay.entitlements` | — | — | — | — | — | CarPlay communication entitlement template; merge into the iOS app entitlements only after Apple approval |

App Group ID: `group.com.lorvex.apple` (defined in `app_metadata.sh` as `APP_GROUP_ID`).

CloudKit container: `iCloud.com.lorvex.apple` (defined as `CLOUDKIT_CONTAINER_ID`).

### Provisioning-gated entitlement templates

`Config/LorvexCarPlay.entitlements` is checked in because the CarPlay task-list
controller, scene delegate, Info.plist activation block, localization catalog,
and tests are already implemented. The template declares
`com.apple.developer.carplay-communication`; do not merge it into
`LorvexMobileApp.entitlements` until Apple approves the CarPlay capability for
the Lorvex iOS App ID. Presence without the matching portal capability causes
codesign validation failures at App Store review.

### Entitlements not currently in the basic entitlement files

The following entitlements are absent because the corresponding capabilities
are not yet implemented. They must be added to the relevant `.entitlements`
file **and** enabled in the Apple Developer portal if/when the feature is added:

- `aps-environment` (push notifications) — present only in the macOS and iOS
  CloudKit entitlement variants, under each platform's own native key:
  `com.apple.developer.aps-environment` on macOS, bare `aps-environment` on
  iOS. Every visionOS entitlements file (dev and App Store) omits it
  entirely: visionOS detects remote iCloud changes by foreground/scene-active
  polling and registers no CloudKit push subscription. Use the production APS
  variant for Developer ID DMG, MAS, and iOS App Store builds that expose Live
  iCloud Sync.
- `com.apple.developer.healthkit` — required if HealthKit integration is added.

Do not add these entitlements pre-emptively; presence without the matching
portal capability causes codesign validation failures at App Store review.

---

## 9. Required Apple Developer portal provisioning

The following must be configured in the Apple Developer portal before a
distribution build can be submitted:

| Capability | Portal section | Applies to |
|---|---|---|
| App Groups (`group.com.lorvex.apple`) | Identifiers → App ID capabilities | all targets |
| CloudKit (`iCloud.com.lorvex.apple`) | Identifiers → iCloud | app + CloudKit entitlements variant |
| App ID registration | Identifiers | all bundle IDs listed in app_metadata.sh |

Bundle IDs requiring registration (the app/app-extension identifiers defined in
`app_metadata.sh`; embedded frameworks sign under their host app's identity and
need no separate App ID):

```
com.lorvex.apple                                   macOS app (BUNDLE_ID)
com.lorvex.apple                            iOS/iPadOS app (MOBILE_BUNDLE_ID)
com.lorvex.apple.vision                            visionOS app (VISION_BUNDLE_ID)
com.lorvex.apple.watchkitapp                watchOS app (WATCH_BUNDLE_ID)
com.lorvex.apple.watchkitapp.widgets   watchOS complication (WATCH_COMPLICATION_BUNDLE_ID)
com.lorvex.apple.focuswidget               WidgetKit extension — macOS + iOS/iPadOS + watchOS embed, one shared bundle id (WIDGET_BUNDLE_ID)
com.lorvex.apple.focus-filter                iOS/iPadOS Focus Filter App Intents extension (FOCUS_FILTER_BUNDLE_ID)
com.lorvex.apple.mcp-host                          macOS MCP helper, Contents/Helpers/LorvexMCPHost.app (MCP_HOST_BUNDLE_ID)
```

The watch identifiers are nested under the iOS host (`com.lorvex.apple`): Apple's embedded-companion rule (TN3157)
requires an embedded watchOS app's bundle ID to be prefixed by its iOS companion's, and the complication's by the watch app's.

`com.lorvex.apple.widget.focus` (`WIDGET_KIND`) and
`com.lorvex.control.focus` (`CONTROL_WIDGET_KIND`) are WidgetKit *kind*
identifiers used in code to select a widget configuration, not bundle IDs —
they have no Developer Portal entry of their own.

For direct macOS distribution, create three Developer ID provisioning profiles:
the app (`com.lorvex.apple`), helper (`com.lorvex.apple.mcp-host`) and widget
(`com.lorvex.apple.focuswidget`). The app profile must authorize the
production CloudKit container and push environment; all three must authorize
the App Group. `package_dmg.sh` requires the three paths explicitly and rejects
development, device-limited, App Store, wrong-team, wrong-bundle or expired
profiles.

For App Store distribution, provisioning profiles for each bundle ID must
exist and be referenced by `DEVELOPMENT_TEAM` in the XcodeGen project settings.
`archive_ios.sh --export` uses `CODE_SIGN_STYLE=Automatic` and
`-allowProvisioningUpdates`, so Xcode can download/create profiles automatically
when the portal credentials are present. The iOS Focus Filter is a separate App
ID and must receive its own exact profile authorizing `group.com.lorvex.apple`;
the final IPA verifier rejects a missing Focus Filter, a reused wildcard profile
on the App Store path, or an App Group grant absent from its profile. The macOS MCP helper's profile must
additionally authorize `group.com.lorvex.apple` (see the entitlements
reference in §8).

---

## 10. Distribution gaps and follow-up work

The following items are known gaps between the current repository state and
a full App Store distribution flow:

### TestFlight upload automation

There is no script for uploading an IPA to TestFlight. The `archive_ios.sh`
output message describes the `xcrun altool` command. A dedicated
`upload_testflight.sh` could wrap `xcrun altool`, Transporter automation, or
the App Store Connect API for fully automated CI delivery. Do not use
`xcrun notarytool` for IPA uploads; notarization is the Developer ID macOS
distribution path, not the TestFlight/App Store Connect path.

### verify_all.sh integration

`verify_packaging.sh` is part of `script/verify_all.sh`, and
`script/verify_build_matrix.py` now treats that call as a required full-gate
command. If the packaging verifier is removed from the standard gate, the build
matrix verifier fails.

### App-Group-SIP signed-entitlement validation

macOS 15+ SIP-protects the shared App Group container (see
`docs/reference/apple-official/MACOS_APP_GROUP_PROVISIONING.md`).
`verify_packaging.sh` checks, against a local packaged bundle at `dist/Lorvex.app`
when one exists, that the main app, MCP helper, and widget extension each
carry the App Group entitlement in their *signed* entitlements (not just the
checked-in `Config/*.entitlements` source plists), and — where the signed
entitlements happen to carry an `application-identifier` and/or an embedded
distribution profile — that both authorize the same bundle id. This is
structural, offline evidence only for the local/CI path, so absent identifiers
or profiles remain `NOTE`s there. The production DMG does not use those soft
skips: `prepare_profile_entitlements.py` synthesizes the profile identities,
`verify_developer_id_provisioning.py` requires and cross-checks all three final
profiles/signatures. `package_dmg.sh` cold-launches the installed main app,
but only after the external release harness permanently resets the App Group;
it captures the exact PID and executable path, and captures `launchctl procinfo`
when the command is available to the noninteractive release user. The helper's
real App Group write is also captured. A release operator should additionally
retain a privileged
`launchctl procinfo` record when the command required root in the automated run,
plus an on-device widget-process record; see that document's "Required Release
Evidence" section.

### App Store listing metadata and account-only actions

Packaging produces the artifact; the App Store submission also needs listing
copy and a set of Apple-account/human actions this repo cannot perform. Those
live outside the packaging scripts:

- `APP_STORE_METADATA.md` (this directory) — draft App Store listing copy
  (name, subtitle, keywords, description, what's-new, URLs, App Review notes).
- `../../docs/finalization/RELEASE_ACCOUNT_CHECKLIST.md` — the consolidated
  owner runbook for account-only steps (identifiers/certs/profiles, CloudKit
  production promotion, App Privacy answers, age rating, EU DSA trader status,
  the F15 Support-URL policy decision, screenshots, signed-RC validation, and
  TestFlight). This file is dev-process state and is deleted at the public cut.
