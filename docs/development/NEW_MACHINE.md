# Setting up a development machine

Lorvex is developed in this public repository. Clone it, install the tools
below, and copy in the local files git never carries; then every build, test,
capture, and release command in `apps/apple/CLAUDE.md` works.

## The repository

- `github.com/boyugou/lorvex` is the only working repository. Commit and push
  to `main`.
- Every tracked file is public the moment it is pushed.
  `apps/apple/script/verify_public_safety.py` (part of
  `script/verify_static_gates.sh`) rejects email addresses, a developer
  machine's paths, keys, and credential files; run the static gates before
  each push.
- Commit with the GitHub noreply address, never a personal one:
  `git config user.email "<id>+<user>@users.noreply.github.com"`.
- `.gitignore` keeps every local-only file below out of git. When a new kind
  of local file appears (credentials, captures, tool state), add it there,
  not to `.git/info/exclude`, so every clone ignores it.

## Tools

- Xcode 27.x for release builds (Swift 6.4; Xcode 26.3 or later is enough to
  build and test), with the macOS, iOS, and watchOS platforms installed (a slim
  Xcode download needs `xcodebuild -downloadPlatform iOS` and `watchOS`) and the
  iPhone, iPad, and Apple Watch simulators the capture scripts name. Choose the
  toolchain for a shell with `DEVELOPER_DIR=<Xcode>/Contents/Developer` rather
  than changing `xcode-select`.
- `uv` for every Python command in this repository.
- XcodeGen (`script/archive_ios.sh` generates the Xcode project).

`apps/apple/script/doctor.sh` checks all of this, and with `--release` the
signing and upload credentials below, without printing a secret or changing
anything; it names the fix for each failure. Run it first on a new machine.

## Local files git never carries

| File | Holds | Needed for |
|---|---|---|
| `secrets/apple-developer.env` | `APPLE_ID`, `APPLE_PASSWORD` (app-specific), `APPLE_TEAM_ID`, `MAS_APP_SIGN_IDENTITY`, `MAS_INSTALLER_SIGN_IDENTITY`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`, Developer ID variables | TestFlight and DMG releases |
| `~/.appstoreconnect/private_keys/` | The App Store Connect API key file (`AuthKey_<id>.p8`, mode 600) that `ASC_KEY_PATH` names | Headless provisioning in `script/archive_ios.sh`; read-only API checks |
| `apps/apple/secrets/profiles/` | Provisioning profiles for every target | Store and Developer ID archives |
| Keychain | Apple Distribution, Mac Installer, and Developer ID certificates with their keys | Signing |
| Keychain, created per machine | The notarytool profile and the CloudKit management token (`xcrun cktool save-token --type management`); neither can be copied from another Mac, and TestFlight needs neither. The notarytool profile comes from the App Store Connect API key, with no password: after `source secrets/apple-developer.env`, `xcrun notarytool store-credentials lorvex-notary --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID"` | DMG notarization; `xcrun cktool` |
| `docs/APPLE_DEVELOPER.md` | The signing runbook: team, certificates, renewal dates | Renewing signing material |
| `CLAUDE.local.md` | Rules for this machine only (below) | Agents working here |

A signing identity imported from a `.p12` reads as invalid (`security
find-identity -v` reports "0 valid identities") until Apple's intermediate
certificates are in the keychain: Worldwide Developer Relations G3 for Apple
Distribution and the Mac installer certificate, and Developer ID G2 for the
Developer ID certificates. Xcode ships them, so no download is needed:

```bash
R=<Xcode.app>/Contents/SharedFrameworks/DVTFoundation.framework/Versions/A/Resources
security add-certificates -k ~/Library/Keychains/login.keychain-db "$R/AppleWWDRCA-2030.cer" "$R/DeveloperIDCA-G2.cer"
```

`security verify-cert` can pass anyway, because it fetches a missing issuer from
the network; `find-identity` and `codesign` do not.

## Rules for a machine that holds real data

When the released Lorvex runs on the development machine with real data,
write those rules into `CLAUDE.local.md` so agents keep away from it:

- Never kill, relaunch, open, or reinstall the installed app, and never read
  or write its App Group container. Debug builds and tests use in-memory or
  temporary stores; never set `LORVEX_APPLE_DB_PATH`.
- Never run `script/verify_all.sh` or `script/reset_production_app_group.py`
  there; `script/verify_static_gates.sh` is the safe static tier, and
  `script/package_dmg.sh` takes `--skip-runtime-verification`.
- Do visual checks only through the headless channels (`ui_tour_macos.sh`,
  `ios_sim_screenshots.sh`, `watch_sim_screenshots.sh`,
  `widget_gallery_macos.sh`), and shut simulators down afterward.

## Releasing a TestFlight build

1. Run `script/bump_build.py`, which writes the next build number into every
   file that holds it and runs `script/verify_app_metadata.py`, and commit.
2. `script/release_testflight.sh upload <log-dir>` archives, validates, and
   uploads both store channels in parallel and prints the two delivery ids.
3. `script/release_testflight.sh poll <ios-id> <mac-id> <log-dir>` waits until
   App Store Connect has processed both builds.

Failure modes and their fixes are in `apps/apple/docs/release.md`
("TestFlight builds"). The direct-download Mac build is
`script/package_dmg.sh` (`apps/apple/docs/DISTRIBUTION.md`).

## Probe suites and visual review

The `ZZ…` tests under `apps/apple/Tests/LorvexAppleTests` are randomized
walks, fuzzers, and render probes. The light ones run with the suite; each
heavy one runs only when its environment variable is set. Their variables,
the headless capture options, and the test-suite quirks are in
`apps/apple/docs/development/VERIFICATION.md`; the platform traps are in
`apps/apple/docs/development/ENGINEERING_TRAPS.md`.

Simulator identifiers differ per machine; find them with
`xcrun simctl list devices` and pass `LORVEX_SIM_UDID` when two simulators
share a name.
