# CI and Release Trigger Policy

This document records the current repository truth for the Apple Swift app.
Release packaging workflows are not implemented yet; this file must not imply
that a `Release macOS` or `Release App Store` workflow exists until the
corresponding workflow file lands in `.github/workflows`.

## Current Workflows

| Workflow | Trigger | Scope | Release artifacts |
|---|---|---|---|
| `Apple CI` | `workflow_dispatch` only (manual) | Swift package build/tests, Apple static verifiers, schema/migration integrity, MCP stdio smoke | No |

Current CI is verification-only and manual: `Apple CI`
(`.github/workflows/apple-ci.yml`) fires solely on `workflow_dispatch`, and it
is dispatched on the commit a release is cut from:

```bash
gh workflow run apple-ci.yml --ref <branch>
```

It has no `push` or `pull_request` trigger because of how long it takes. One
run on the hosted `xcode-27` runner (three cores) was measured on 2026-11-23:
79 min 42 s in all, 57 min for the verification gate and 22 min for the iOS
Release link, from a cold checkout with no dependency cache. A result that
arrives 80 minutes after a push describes a commit the work has usually moved
past, so the gates before each push are the local ones
(`script/verify_swift.sh` and `script/verify_static_gates.sh` in
`apps/apple`), which take minutes.

The hosted run checks what a developer's Mac cannot: a clean checkout, and a
machine whose clock is UTC. The first passing run needed about fifty tests
fixed that had passed only in the developer's own time zone. Between 00:00 and
08:00 UTC the runner's calendar day is one ahead of the day in
America/Los_Angeles, the time zone many fixtures set; the measured run started
at 10:12 UTC, so those hours are not yet covered by a hosted run.

A dispatched run must not package, sign, notarize, upload, or publish
artifacts.

## Implemented Checks

`Apple CI / Swift package` runs:

- `swift build` in `apps/apple`
- `swift test` in `apps/apple`
- `swift test` in `apps/apple/core`
- Apple static verifiers for metadata, strategy, build matrix, CloudKit
  readiness, MCP catalog, localization, system entrypoints, core service
  coverage, hotspots, repo hygiene, and user docs
- `script/mcp_stdio_smoke.py` — MCP host stdio round-trip against the Swift core

The static set also includes `script/verify_sync_payload_contract.py`, which
pins field-set changes to an explicit Apple payload-schema version.

The Apple gate also runs the schema-integrity checks over the bundled
`LorvexCore` schema resources: `script/verify_schema_embed.sh` asserts they stay
byte-identical to the `schema/` authority, and `script/verify_migration_ladder.py`
plus `script/verify_schema_freeze.py` enforce the Apple-only migration ladder and
freeze. `script/verify_sync_payload_contract.py` separately enforces the
contiguous Apple wire-field manifest ladder and its released hashes. These are
Apple-only integrity checks.

## Planned Release Workflows

The target release shape is:

- macOS direct distribution: Developer ID signed and notarized `.dmg`
- macOS App Store: App Store signed macOS archive/upload
- iOS/iPadOS/watchOS: App Store Connect archive/upload from the Swift
  Apple targets

Planned artifact labels:

- Signed `.ipa` uploaded to workflow artifacts
- Signed `.ipa` uploaded to App Store Connect
- App Store Connect (App Store signed IPA)
- App Store distribution signed `.ipa` submitted to App Store Connect

Those workflows still need to be implemented. When they land, add protected
GitHub environments, documented tag families, dry-run/artifact/publish modes,
and operator commands in the same commit as the workflow files. Until then,
release operators should use the local scripts in `apps/apple/script/` and the
distribution notes in `apps/apple/docs/DISTRIBUTION.md`.

## Non-Goals

- Commit messages and trailers do not select CI or release scope.
- There is no `ci:full` label behavior in the current workflows.
- There are no current `mac-v*` or `appstore-v*` GitHub release triggers for the
  Apple app.
