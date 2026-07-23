# Distribution Guide

> Current platform boundary (2026-06): Tauri is the Windows/Linux desktop line.
> Its macOS build is a developer/reference build for contributors who only have
> a Mac. Mac App Store, iOS, iPadOS, watchOS, visionOS, CloudKit/iCloud,
> App Intents, WidgetKit, and other Apple ecosystem distribution/capability work
> belongs to the Swift app under `apps/apple`.

## Distribution Channels

Packaging identity stability only: Tauri package versions identify build
artifacts, release channels, and updater metadata. They are not a current
data-format compatibility guarantee while Lorvex is pre-public-release.

| Channel | Status | Notes |
|---|---|---|
| GitHub Releases (macOS DMG) | Developer/reference | Useful for Mac-only developers; not the future Apple customer channel. |
| GitHub Releases (Windows EXE) | Implemented | Primary future Tauri desktop channel for Windows users. |
| GitHub Releases (Linux AppImage + .deb + .rpm) | Implemented | Primary future Tauri desktop channel for Linux users. |
| Homebrew Cask | Planned | Convenience channel after direct desktop distribution is stable. |
| Mac App Store | Superseded for Tauri | Ship the Swift app from `apps/apple` instead. |
| iOS / iPadOS | Superseded for Tauri | Ship the Swift app from `apps/apple` instead. |
| Android | Future | Separate future runtime; not covered by Apple-specific Tauri code. |

Status vocabulary in this guide: `Implemented`, `Developer/reference`,
`Planned`, `Future`, and `Superseded for Tauri`.

## What Tauri Must Not Own

Tauri should not carry production-facing implementations, docs, or release
workflow expectations for:

- Mac App Store packaging or App Store Connect upload.
- CloudKit/iCloud containers, entitlements, schema deployment, or old iCloud
  container migration.
- iOS/iPadOS Apple ecosystem code paths.
- App Intents, WidgetKit, Swift-only Apple platform integrations.

Historical App Store and CloudKit runbooks are intentionally retired. The old
Tauri CloudKit schema/container can be abandoned; no backward-compatible
migration path is required.

## macOS Developer/Reference Build

The Tauri macOS build remains useful for local development and packaging smoke
tests. It should be signed and notarized before distribution outside the
developer machine, but it is not the App Store path.

Required release credentials for macOS DMG distribution:

| Secret | Purpose |
|---|---|
| `APPLE_CERTIFICATE` | Developer ID application certificate for DMG distribution. |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the Developer ID certificate export. |
| `APPLE_SIGNING_IDENTITY` | Developer ID signing identity. |
| `APPLE_ID` | Apple account used for notarization. |
| `APPLE_PASSWORD` | App-specific password used for notarization. |
| `APPLE_TEAM_ID` | Apple team identifier used for notarization. |
| `TAURI_SIGNING_PRIVATE_KEY` | Tauri updater signing private key. |
| `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` | Required password protecting the updater signing private key. |

Release workflows fail closed unless both `TAURI_SIGNING_PRIVATE_KEY` and `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` are configured.

Signing, notarization, upload, and publishing credentials must live in GitHub
environment secrets, not repository-wide secrets.

Protected GitHub environments used by Tauri release jobs:

- `release-desktop-macos`
- `release-desktop-windows`
- `release-desktop-linux`
- `release-desktop-publish`
- `release-macos-only`
- `release-macos-only-publish`

Local unsigned smoke build:

```bash
scripts/build_dmg.sh
```

Local signed build:

```bash
APPLE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build_dmg.sh
```

Distribution DMGs must be signed with Developer ID and notarized. Unsigned local
smoke-test DMGs may be built without credentials, but must not be distributed.

## Windows And Linux

Windows and Linux are the main Tauri customer surfaces:

- Windows uses the Authenticode-signed NSIS installer (`.exe`) path.
- Linux ships AppImage, `.deb`, and `.rpm` artifacts.
- Tauri updater signing stays relevant for direct desktop distribution.

Current GitHub Releases only prove the repo-visible macOS developer/reference
channel. Windows and Linux packaging is implemented, but should not be described
as externally available stable distribution until matching accessible artifacts
exist.

Current desktop release artifact families:

- macOS developer/reference: `.dmg`
- Windows: `.exe`
- Linux: `.AppImage`, `.deb`, `.rpm`

Local Windows NSIS build:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_windows.ps1 -Bundle nsis
```

Do not introduce Apple-only dependencies, entitlements, or release gates into
these paths.

## Sync Direction

Tauri currently has no active cloud sync transport. The supported backup and
transfer path is export/import. The codebase may keep provider-neutral sync
abstractions for a future backend such as Dropbox, Syncthing, a network share,
or a Lorvex-hosted service, but CloudKit/iCloud-specific transport code and
schema docs are retired.

## Release Trigger Policy

Ordinary branch and `main` pushes are verification-only. They must not package,
sign, notarize, upload, or publish Tauri release artifacts.

Use direct desktop release tags only:

- `v*` for multi-platform desktop releases.
- `mac-v*` for macOS-only developer/reference prereleases.

Manual release runs expose `release_mode=dry-run`, `release_mode=artifacts`,
and `release_mode=publish`. Dry-run mode performs release audit/preflight only,
artifact mode signs/notarizes and uploads workflow artifacts, and publish mode
creates or repairs the GitHub Release.

Manual operator paths:

- Actions -> Release -> Run workflow
- Actions -> Release macOS Only -> Run workflow

Release-triggering tags must be signed annotated tags and pushed explicitly:

```bash
git tag -s v1.0.0 -m "v1.0.0"
git push origin v1.0.0
git tag -s mac-v1.0.0-rc.1 -m "mac-v1.0.0-rc.1"
git push origin mac-v1.0.0-rc.1
```

GitHub repository ruleset `Protect release publishing tags` protects the live
release tag namespace.

Do not add or preserve `appstore-v*` release triggers for Tauri. App Store
release work belongs to `apps/apple`.

## Updater Endpoint And Release Repository

The auto-update client polls one hardcoded endpoint in
`app/src-tauri/tauri.conf.json` (`plugins.updater.endpoints`):

```
https://github.com/<owner>/<repo>/releases/latest/download/latest.json
```

It must resolve to the repository that hosts the published desktop release —
the Release page carrying the signed `.dmg` / `.exe` / `.AppImage` bundles,
their `.sig` files, and the generated `latest.json`. The endpoint is baked into
the shipped binary and cannot be reconciled by CI after the fact.

By contrast, the release-manifest generator
(`scripts/release/create_manifest.mjs`) hardcodes no slug: it builds every
artifact URL from `GITHUB_REPOSITORY`, so the manifest's download URLs track
whichever repository runs the release workflow. Only the updater endpoint and
the app's human-facing repository links are static.

Release hosting currently lives in `boyugou/ai-native-todo` (the standalone
Tauri origin, where the release-tag rulesets and GitHub Releases are
configured), and the endpoint is consistent with it. Migrating to the monorepo
publish target `github.com/boyugou/lorvex` is owner/account-side: the target
repository must first exist and carry its own release-tag rulesets. At that cut,
set the endpoint to

```
https://github.com/boyugou/lorvex/releases/latest/download/latest.json
```

and move it in lockstep with the other static `boyugou/ai-native-todo`
references (enumerate with `grep -rn ai-native-todo` across `apps/tauri`): the
`LORVEX_REPO_URL` fallback, the About / Releases / Help / setup-doc / Issues
links, the calendar-subscription User-Agent, the clone URLs and
security-advisory links in the root Markdown docs, and the fixture slug the
`release_manifest` / `repo_governance` contract tests assert against. The
branch/tag ruleset IDs in `docs/execution/CI_RELEASE_TRIGGER_POLICY.md` are
account-specific and must be recreated on the new repository.

## Artifact Integrity

Release workflows publish `SHA256SUMS` alongside release artifacts. Verify local
downloads with:

```bash
shasum -a 256 -c SHA256SUMS
```

GitHub artifact attestation is also produced for release integrity artifacts.
Verify attestations with `gh attestation verify` against the downloaded
artifact/checksum bundle.
