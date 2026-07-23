# Lorvex Apple Core Status

This file is the current Apple-core status note. Historical Rust-to-Swift
migration ledgers live in git history; keep this document focused on facts that
are still useful for maintainers.

## Current Shape

`apps/apple/core` is the canonical Swift implementation for the Apple edition.
It owns the pure domain, store, sync, workflow, and runtime primitives used by
the app, MCP host, widgets, watch, mobile, and system-intent surfaces.

The Apple-owned root schema remains this core's storage contract. The Apple core
tracks that schema and language-neutral specs directly, not a Tauri
implementation detail. Tauri can
still be useful as historical context when auditing an old port decision, but it
is not the active oracle for new Apple work.

## Landed Areas

- `LorvexDomain`: IDs, HLCs, timestamps, canonical JSON, validation, naming,
  recurrence/date/time helpers, preference-key registry, and shared value types.
- `LorvexStore`: GRDB-backed schema opening/migration, repositories, task
  reads/writes/search/graph/reminders/calendar links/checklists, calendar event
  storage, task recurrence exceptions, calendar occurrence decisions,
  focus/daily-review/list/tag/memory/provider
  repositories, changelog writes/queries, payload shadow, pending inbox store,
  error-log writes, widget snapshot assembly, and SQL transaction helpers.
- `LorvexSync`: envelope validation, canonicalization, LWW helpers, outbox,
  coalescing, tombstones, conflict logs, payload enqueue, apply dispatch for
  every synced entity kind, pending-inbox drain/enqueue/quarantine/remap, and
  sync retention.
- `LorvexWorkflow`: task create/update/batch/archive/permanent-delete/lifecycle
  orchestration, recurrence config apply, lifecycle successor spawn/cancel,
  task deferral, AI notes, checklist/body/reminder helpers, calendar event
  workflow, overview, weekly review, list reorganize, and small policy ops.
- `LorvexRuntime`: local change counter, sync checkpoints, managed install and
  storage-generation identity, cross-process storage locks, database locator
  logic, and runtime support used by the Swift service layer.

## Platform Boundaries

The remaining boundaries are not core schema or pure-Swift repository gaps:

- ZIP export/import packaging: archive creation/parsing belongs above the pure
  store repositories.
- Calendar subscription ingestion: iCalendar/VTIMEZONE parsing and subscription
  network sync are a calendar-ingestion subsystem, not a generic workflow leaf.
- Transport/runtime I/O: CloudKit or filesystem-bridge transport loops,
  reachability probes, process-global rate limiting, and OS-specific DB locator
  environment implementations live in the app/runtime layer.
- Widget snapshot persistence: App Group resolution, atomic JSON writes, and
  WidgetKit reloads live in `LorvexWidgetKitSupport`, `LorvexApple`, and
  `LorvexMobile`; the core only builds the in-memory snapshot value.

When adding any of these surfaces, keep the pure core boundary intact: the core
should accept explicit inputs, return typed results, and avoid owning process
globals or UI/platform side effects.

## Verification

Use these from `apps/apple` after touching Apple code:

```sh
./script/verify_all.sh
```

For core-only iteration, this is the fast inner loop:

```sh
cd core
swift test
```

Also run the strategy and localization checks when docs, user-facing strings,
tool catalogs, or MCP surfaces move:

```sh
python3 script/verify_apple_strategy.py
python3 script/verify_localization_catalog.py
```

## Maintenance Rules

- Do not add Apple code that depends on Tauri UI, Node packaging, or Rust bridge
  assumptions.
- Do not reintroduce stale port-status language such as active Rust-oracle
  claims, bridge-era placeholders, or historical phase plans.
- Prefer Apple schema/spec references for contracts and focused tests for local
  behavior.
- If a boundary is platform-owned, document the owning Apple package rather than
  describing it as a missing core port.
