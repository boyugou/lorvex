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

- Xcode with the macOS, iOS, and watchOS SDKs and simulators; the iPhone,
  iPad, and Apple Watch simulators the capture scripts name.
- `uv` for every Python command in this repository.
- XcodeGen (`script/archive_ios.sh` generates the Xcode project).

## Local files git never carries

| File | Holds | Needed for |
|---|---|---|
| `secrets/apple-developer.env` | `APPLE_ID`, `APPLE_PASSWORD` (app-specific), `APPLE_TEAM_ID`, `MAS_APP_SIGN_IDENTITY`, `MAS_INSTALLER_SIGN_IDENTITY`, Developer ID variables | TestFlight and DMG releases |
| `apps/apple/secrets/profiles/` | Provisioning profiles for every target | Store and Developer ID archives |
| Keychain | Apple Distribution, Mac Installer, and Developer ID certificates with their keys; the CloudKit management token | Signing; `xcrun cktool` |
| `docs/APPLE_DEVELOPER.md` | The signing runbook: team, certificates, renewal dates | Renewing signing material |
| `CLAUDE.local.md` | Rules for this machine only (below) | Agents working here |

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

1. Bump the build number in the eight files `script/verify_app_metadata.py`
   cross-checks, run it, and commit.
2. `script/release_testflight.sh upload <log-dir>` archives, validates, and
   uploads both store channels in parallel and prints the two delivery ids.
3. `script/release_testflight.sh poll <ios-id> <mac-id> <log-dir>` waits until
   App Store Connect has processed both builds.

The direct-download Mac build is `script/package_dmg.sh`
(`apps/apple/docs/DISTRIBUTION.md`).

## Probe suites

The `ZZ…Probe…` tests under `apps/apple/Tests/LorvexAppleTests` are
randomized walks, fuzzers, and render probes. The light ones run with the
suite; each heavy one runs only when its environment variable is set (named
at the top of its file), and render probes write their images to
`LORVEX_SCRATCH_DIR`.
