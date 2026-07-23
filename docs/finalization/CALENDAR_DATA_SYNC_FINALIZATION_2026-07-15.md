# Calendar Data and Sync Finalization — 2026-07-15

## Scope

This bounded checkpoint stabilizes the Lorvex-native recurring-calendar
occurrence and register model before the prelaunch schema is frozen. It covers
stored occurrence decisions, grouped CloudKit convergence, native restore,
task-to-event links, ICS export, and the calendar identities exposed to SwiftUI
and MCP. The migration policy remains explicitly prelaunch; this document does
not arm the public-release freeze sentinel.

It does not use simulator or CUA validation. Release UI walkthroughs and a live
production CloudKit-container proof remain separate release activities.

## Implemented model

### Base events

A base `calendar_events` row has two independently ordered registers:

- `content_version` owns title, description, location, URL, color, event type,
  person name, and attendees.
- `recurrence_topology_version` owns timing, timezone, recurrence, and
  `recurrence_generation`.

The row `version` is only the mutation/delete/transport high-water mark. It must
be at least both register versions and the generation. A content-only edit must
not advance topology; a topology-only edit must not advance content. An
all-series reset always advances topology because it changes the active
generation even if no visible timing field changed.

`created_at` is stable record metadata, not part of either mutable register.
`updated_at` follows the deterministic row-version winner.

### Occurrence decisions

A recurring occurrence is addressed by `(series_id, recurrence_generation,
recurrence_instance_date)`. Its stored row ID is the deterministic UUIDv8 derived
from that tuple. A decision is one whole-row LWW register with state
`replacement`, `cancelled`, or `inherit`; it has neither `content_version` nor
`recurrence_topology_version`.

Decision-to-master references remain soft so CloudKit can apply a decision before
its master. Timeline visibility is a presentation rule only: mutation and import
readback always use raw stored rows, including hidden `cancelled` and `inherit`
states.

### Restore

Native backup is final-state data, not a copy of sync provenance. It preserves
the recurrence generation required by deterministic decision IDs, but does not
export content/topology register versions. Restore mints fresh versions that
dominate every imported and locally known HLC. Base restore advances both
registers; decision restore remains whole-row LWW.

### Authoritative snapshots

An authoritative CloudKit snapshot must replace the complete local calendar row,
not merely lower its outer `version`. The authoritative path removes the local
row transactionally and lets the typed envelope rebuild it, so neither grouped
register can leak local data back into the adopted snapshot.

### Task links

`task_calendar_event_links` targets a Lorvex-native base event. A natural or
replacement occurrence is normalized to its recurring-series master. Provider
links remain device-local and privacy-tiered; canonical links remain visible
even when provider AI access is off.

### ICS and surface identity

An exported recurring component is a coherent master/decision group sharing one
UID. A replacement uses its original slot as `RECURRENCE-ID`; a cancellation uses
`EXDATE`. Range filtering must never resurrect a moved natural occurrence or
emit an orphan override.

Every rendered provider occurrence and every MCP recurring occurrence retains a
stable, unique occurrence identity plus the complete scoped-mutation address.

For MCP rows, `id` uniquely identifies the rendered occurrence and `event_id`
always carries the stable source address. Generic canonical update/delete tools
require `event_id`; scoped recurring tools require `event_id` plus the original
occurrence date.

## Remaining freeze blocker

`this_and_following` still represents a split as two independent base records:
an update that truncates the old master and a new tail master under another ID.
A concurrent all-series topology winner can therefore extend the old master
back across the cutover while the new tail survives. This checkpoint is safe to
land as a bounded improvement, but recurring-calendar sync is not declared
fully finalized until a durable convergent lineage/cutover model and its
two-device arrival-order matrix land.

## Required convergence probes

- Concurrent title-only and timing-only writes from a common base converge to
  both new values in either delivery order.
- A generation reset and a concurrent topology edit converge without reviving
  decisions from the prior generation.
- Authoritative snapshot adoption replaces locally newer content and topology
  without a convergence re-emit.
- Replacement, cancelled, and inherit decisions survive raw native round-trip.
- Canonical links round-trip bidirectionally, normalize occurrence targets, and
  do not depend on EventKit privacy access.
- ICS covers replacements moved into and out of the requested range for timed
  and all-day series.

## Verification record

This bounded checkpoint passed the complete code-level gate:

- `swift build` in `apps/apple`.
- `swift test` in `apps/apple`: 428 XCTest cases and 2,435 Swift Testing tests
  passed with zero failures.
- `swift test` in `apps/apple/core`: 2,519 tests passed, with 23 benchmark or
  environment-gated tests skipped by design.
- `LORVEX_VERIFY_SKIP_PACKAGING=1 ./script/verify_all.sh`: passed, including
  schema embedding, the empty pre-launch migration ladder, sync payload
  contract validation, CloudKit readiness for all 19 syncable kinds,
  localization, entitlements, privacy manifests, XcodeGen, release builds,
  local package closure, and both MCP smoke passes.
- `python3 script/mcp_stdio_smoke.py`: passed independently; `tools/list`
  returned all 118 tools and read/write/error-envelope probes succeeded.
- `git diff --check`, schema byte parity, sync payload byte parity, and the MCP
  manifest verifier all passed. The pre-launch schema checksum is
  `1f715fe38f03f1b5993f653cb99f1c4c7a9c45fee7c9bb87610ff29a105cbe27`.

One documented full-suite parallel-load flake,
`appStoreRefreshesLoadedTaskWorkspaceAfterStatusMutations`, appeared during an
intermediate verifier run and passed immediately in isolation; the final
unified verifier run passed without exceptions.

No simulator, CUA, live production CloudKit container, App Store Connect, or
real distribution-signed archive was exercised. Those remain release evidence,
not source-level claims. This checkpoint also deliberately does not close the
`this_and_following` split-lineage blocker above or the separate recurring-task
successor lifecycle blocker recorded in the finalization backlog.
