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
(`.github/workflows/apple-ci.yml`) fires solely on `workflow_dispatch`.
Automatic `push` and `pull_request` triggers are intentionally disabled because
hosted macOS minutes are paused at the account level, so an auto-run would only
fail at the queue with a billing error; the local
`apps/apple/script/verify_all.sh` gate is the validation of record while CI is
paused. A dispatched run must not package, sign, notarize, upload, or publish
artifacts. The `push` / `pull_request` blocks (restoring their Apple `paths`
filters) are re-enabled once hosted Actions billing is restored.

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
Apple-only integrity checks; Apple and Tauri are directionally aligned through
`spec/`, not byte-locked, so there is no cross-runtime schema-parity gate.

## Planned Release Workflows

The target release shape is:

- macOS direct distribution: Developer ID signed and notarized `.dmg`
- macOS App Store: App Store signed macOS archive/upload
- iOS/iPadOS/visionOS/watchOS: App Store Connect archive/upload from the Swift
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
