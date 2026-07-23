# CI and Release Trigger Policy

This document is the canonical trigger policy for ordinary pushes, pull
requests, manual verification runs, and Tauri desktop release packaging.

## Policy

Summary:

- normal push: verification only
- release tag push: artifact/release path
- manual dispatch: controlled dry-run/artifacts/publish mode

| Intent | Trigger | Scope | Notes |
|---|---|---|---|
| Fast PR feedback | `pull_request` to `main` | Fast CI gates | Default for PR updates. Does not package, sign, notarize, upload, or publish release artifacts. |
| Full PR verification | `pull_request` to `main` with `ci:full` label, or with risky sync/MCP path changes | Full CI matrix | The resolver escalates PRs touching sync, MCP runtime, MCP tests, or release-adjacent paths. |
| Post-merge verification | `push` to `main` | Full CI matrix | Main pushes are verification-only. They must never package, sign, notarize, upload, or publish release artifacts. |
| Manual CI override | `workflow_dispatch` on `CI` with `full_checks=true/false` | Full or fast CI | Use for explicit reruns, billing recovery checks, and release candidate preflight rehearsal without release artifacts. |
| Cross-platform release dry-run | `workflow_dispatch` on `Release` from a `v*` tag ref with `release_mode=dry-run` | Audit and release preflight only | Default manual release rehearsal. |
| Cross-platform artifact build | `workflow_dispatch` on `Release` from a `v*` tag ref with `release_mode=artifacts` | Signed/notarized artifacts uploaded to workflow artifacts | Validates packaging without creating a GitHub Release. |
| Cross-platform publish | `push` tag `v*`, or `workflow_dispatch` on `Release` from a `v*` tag ref with `release_mode=publish` | Signed/notarized artifacts and GitHub Release publish | Tag push is publish intent. Manual publish is the explicit rerun/repair path. |
| macOS-only dry-run | `workflow_dispatch` on `Release macOS Only` from a `mac-v*` tag ref with `release_mode=dry-run` | Audit and release preflight only | Use before macOS-only developer/reference packaging. |
| macOS-only artifact build | `workflow_dispatch` on `Release macOS Only` from a `mac-v*` tag ref with `release_mode=artifacts` | Signed/notarized macOS artifacts uploaded to workflow artifacts | Use only when the cross-platform runner fleet is not ready. |
| macOS-only publish | `push` tag `mac-v*`, or `workflow_dispatch` on `Release macOS Only` from a `mac-v*` tag ref with `release_mode=publish` | Signed/notarized macOS GitHub prerelease artifacts | Tag push is prerelease publish intent. |

## Non-Goals

- Commit messages and trailers do not select CI or release scope.
- Ordinary branch pushes do not trigger repo workflows.
- Ordinary `main` pushes never run packaging, signing, notarization, release
  upload, or publish jobs.
- Tauri does not own App Store release triggers. Do not add `appstore-v*`
  release tags, App Store Connect upload jobs, or App Store signing
  environments here. Apple App Store release work belongs to `apps/apple`.

## Protected Tags

Release-triggering tags must be signed annotated tags:

- `v*` for multi-platform Tauri desktop releases.
- `mac-v*` for macOS-only developer/reference prereleases.

## Release Tag Repository Policy

Tag pushes to `v*` and `mac-v*` start release workflows. The repository ruleset
`Protect release publishing tags` must protect those namespaces and require
signed annotated tags before any signing, notarization, upload, or publish job
runs.

Audit the live protected tag ruleset with:

```bash
gh api repos/boyugou/ai-native-todo/rulesets/16179200
```

There remains a runner limitation after #3988: macOS packaging can be rehearsed
through the macOS-only workflow when the full cross-platform runner fleet is not
available.

```bash
git tag -s v1.0.0 -m "v1.0.0"
git push origin v1.0.0
```

## Main Branch Repository Policy

The repository ruleset `Protect main branch` protects `main`.

Audit the live main branch ruleset with:

```bash
gh api repos/boyugou/ai-native-todo/rulesets/16179282
```

Required status checks:

- `CI Mode`
- `TypeScript`
- `Rust (ubuntu-latest)`
- `Rust MCP Server (windows-latest)`
- `Security Audit Required`
- `Platform Integration (macos-latest)`
- `Platform Integration (windows-latest)`
- `Rust Workspace (macos-latest)`
- `E2E Visual (Playwright snapshots)`
- `MCP Scale Report`

The branch policy requires one approving review. Maintainers may use the
administrator bypass path only for urgent repository maintenance and must still
leave the CI/release policy intact.

## Protected GitHub Environments

Release jobs that use signing credentials, notarization credentials, upload
credentials, or release write permissions must run behind protected GitHub
environments:

- `release-desktop-macos`
- `release-desktop-windows`
- `release-desktop-linux`
- `release-desktop-publish`
- `release-macos-only`
- `release-macos-only-publish`

## Release Artifacts

The multi-platform release workflow uploads:

- macOS: signed/notarized `.dmg` plus optional updater signature.
- Windows: signed NSIS `.exe` plus optional updater signature.
- Linux: `.AppImage`, `.deb`, `.rpm`, plus optional updater signatures.
- `latest.json` for the updater.
- `SHA256SUMS` and GitHub artifact attestations.

The macOS-only workflow publishes a GitHub prerelease and `latest-macos.json`
so prerelease testing does not disturb the multi-platform updater channel.
