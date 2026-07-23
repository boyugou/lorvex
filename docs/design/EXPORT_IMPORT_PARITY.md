# Export / Import Format (Apple-native)

Lorvex Apple has one version-1 export contract, with two deliberately different
data representations inside it. Version 5 is the first public backup contract,
not merely the current encoder version: later formats append an explicit decoder
while the committed v1 compatibility fixtures continue to decode unchanged.

- Portable category documents are readable migration projections. For tasks,
  `tasks.json` contains `ExportTask` values and is suitable for AI-assisted or
  best-effort import.
- Apple-native restore members preserve state that a portable projection cannot
  express. When tasks are selected, human JSON/ZIP exports additionally carry a
  typed `NativeTaskGraphSnapshot` (`native_task_graph.json` in ZIP).

This container backs Settings → Data "Export"/"Import". The MCP `export_data`
tool intentionally emits only the portable representation. There is no separate
cross-runtime "interchange" format; cross-platform data movement is AI-reconciled
best-effort (an assistant reads an export and recreates the data through MCP
tools), never a lossless-by-construction contract.

## Export

`apps/apple/Sources/LorvexCore/Support/LorvexDataExporter.swift` emits either one
versioned JSON document or a version-1 `.zip` package for the requested
categories:

- One pretty-printed JSON array per portable category (`tasks.json`,
  `lists.json`, `tags.json`, `habits.json`, `calendar_events.json`,
  `preferences.json`, …). `native_task_graph.json` is the independently
  versioned object member.
- For a human JSON/ZIP task export, `native_task_graph.json` captures every
  canonical task column except generated `priority_effective`, plus recurrence
  EXDATEs, task-tag edges, dependency edges, checklist items, and reminders.
  Register clocks, row HLCs, lineage generations, rollover decisions, and stable
  successor identities remain typed instead of being flattened into the
  portable task projection. The same member also preserves task-domain
  tombstones and opaque payload shadows for tasks, reminders, checklist items,
  tags, dependencies, and calendar links. CloudKit confirmation receipts are
  deliberately excluded. CSV and AI/MCP export omit this member.
- A top-level `manifest.json` carrying `schemaVersion: "1"`, the caller-supplied
  app version and generation time, and exact per-member record counts. Version 5
  is a closed inventory: it emits no attachment/blob members, and an importer
  rejects every unrecognized or duplicate archive path.

Single-file JSON carries `formatVersion: "1"` plus an informational provenance
manifest. That manifest may record the producing Apple app version and device
ID, but the importer never applies that source identity. Its inline entity
counts are an enforced closed-inventory boundary just like the ZIP manifest:
included categories and decoded row counts must match exactly, while internal
task/calendar dependency members remain owned by their parent category.

Reads are full-table, not view-scoped: `exportData` (and the `load*ForDataExport`
requirements on `LorvexDataExportServicing`) draw the complete catalog for each
category, so tasks include archived rows and calendar events span the store's
full history. The bounded in-memory v1 implementation never silently truncates:
if daily-review or per-habit completion history exceeds its explicit safety
window, export fails with the category/count/limit instead of emitting a partial
backup. The portable task projection and the complete native task graph are
captured in one SQLite read transaction, so a concurrent child edit cannot
produce a root/child split snapshot.

Before an archive is emitted, the native graph is rejected unless its primitive
values and graph invariants are valid: IDs and owners are unique; dates,
timestamps, recurrence JSON, reminder anchors, and HLCs are canonical; every
register is at or below its row version; recurrence lineage is acyclic and
matches deterministic successor generations; dependency edges are unique and
acyclic; cancelled tasks are not dependency endpoints; terminal tasks have no
active reminders; and the maximum HLC leaves room for a later local operation.
List and tag foreign-key roots are checked against the same database snapshot.

`LorvexCSVExport.swift` provides the portable multi-section CSV rendering. The
human path is exposed in Settings → Data. MCP `export_data`
(`exportDataForAI(entities:format:)`) is a migration/analysis surface, not a
clock-preserving Apple import artifact.

## Import

`apps/apple/Sources/LorvexCore/Support/LorvexDataImporter*.swift` decodes the
archive and chooses the appropriate path per representation:

- Portable category documents build an apply plan and merge per category and
  per record.
- A valid native task graph is eligible for clock-preserving,
  single-transaction materialization
  only when the local task domain is fresh and its separately exported list/tag
  roots already exist. It restores the complete graph and its clocks, then
  restores task-domain tombstones and forward-compatible payload shadows, and
  creates the local changelog/outbox effects needed for future CloudKit sync.
  A tombstone-only or shadow-only task graph is recoverable even when it has no
  live tasks; a genuinely empty graph remains a no-op.
- If native task materialization is inapplicable because the destination already
  has task state or the selected export omitted list/tag roots, import falls back
  to the portable `tasks.json` path. The archive remains decodable; a task-only
  export is not rejected merely because native materialization needs external
  roots.

Both paths implement the settled non-destructive import contract; neither is an
authoritative rollback of iCloud. Native materialization preserves the exported
register state and original HLCs instead of minting a backup-dominating
rewrite. Portable import is a semantic merge: user-authored records already
present or tombstoned locally are skipped, while an absent record is restored as
a new local write. Preferences are the intentional exception: portable,
non-device-local preference values restore with ordinary LWW semantics.

### CloudKit operation boundary

Shipping Settings surfaces never call `LorvexDataImporter.apply` directly. They
route the confirmed plan through `CloudSyncDataImportBoundary`:

- In `.live` mode, the retained `CloudSyncEngineCoordinator` operation gate is
  held continuously while the engine drains every currently visible CloudKit
  page, re-proves the available account and exact ready generation/root, verifies
  a terminal traversal witness, drains dependency-deferred inbox work to a local
  fixed point, and checks the durable pending/corrupt inbound-debt ledgers. Only
  a complete state may enter the importer; a pause, account/generation change,
  nonterminal traversal, unresolved future/dependency row, or corrupt-record
  fence fails closed with no import writes.
- The same non-reentrant gate remains held across the importer's presence,
  tombstone, and write decisions. Cloud deletion, mode transitions, refresh, and
  other coordinator work therefore cannot interleave with the multi-record
  restore.
- A terminal inbound traversal can commit before unrelated post-inbound work
  such as outbound push, retention, or audit maintenance fails. That failure
  does not invalidate the terminal proof or cause the already-authorized import
  to be repeated; the host completes the import once while retaining the normal
  sync error and retry-after/backoff warning.
- `.off` and `.recordPlan` deliberately perform no CloudKit I/O. When a retained
  maintenance coordinator exists they still use its gate to order the import
  against local maintenance. Their collision decisions are local-only: an
  import performed while sync is off cannot claim that unseen CloudKit state
  participated in the decision.

After the gate is released, the macOS and Mobile stores publish committed
database-change signals and wait for their final coalesced refresh. Mobile also
applies a mode request queued during the import before that refresh can start a
new live cycle.

The import path is defensive against hostile or malformed archives:

- **Portable source-size and decompression bounds.** Public v1 uses one
  platform-independent 64 MiB source/archive/entry envelope for every producer
  and consumer, so a backup emitted on macOS cannot exceed the iPhone/iPad
  restore boundary. `LorvexImportLimits` caps the source file's on-disk byte
  length before it is read into memory; JSON export enforces the same limit;
  `LorvexZipArchive` enforces per-entry uncompressed size, entry count,
  aggregate uncompressed size, and decompression-ratio limits on read.
- **Format and ZIP structural validation.** Import accepts versioned Lorvex JSON
  or ZIP, never a SQLite database. ZIP input is selected by its local-file or
  empty-archive `PK` signature; the reader then validates the end-of-central-
  directory record, central/local headers, offsets, supported compression,
  bounded sizes, and every entry CRC.
- **Retained per-version decoders.** The importer reads only the JSON/ZIP version
  envelope first and dispatches to a decoder explicitly registered for that
  version. Version 5 is the first public JSON and ZIP contract. A future v6 adds
  a decoder and advances the exporter; it does not reinterpret or remove v1.
  A production-shaped all-category golden document (including the native graph
  and calendar cutovers) is SHA-pinned and decoded through both JSON and ZIP
  paths. `script/verify_backup_v1_contract.py` additionally checksum-locks every
  v1 DTO source and adapter; future formats add types rather than mutating v1.
- **Manifest as an enforced compatibility contract.** `manifest.json` must be
  present, declare the supported version-1 schema, and exactly describe the
  archive's closed member set and per-member record counts. Missing, extra,
  duplicate, or count-mismatched members are rejected before apply.
- **Whole-payload semantic preflight.** Before preview, both JSON and ZIP reject
  duplicate aggregate/child identities, impossible natural-key collisions,
  dangling references into another included complete category, malformed focus
  block ownership/positions, contradictory calendar boundary/segment topology,
  task-calendar control state that disagrees with the live edge category, and
  every importable preference's stored JSON plus typed value contract. A
  malformed preference therefore fails before any earlier category can write.
  An intentionally partial category export remains valid: references into a
  category omitted from the artifact are resolved best-effort against the
  destination rather than treated as corruption.
- **Independent native schema.** The payload/container format, ZIP manifest,
  and `NativeTaskGraphSnapshot` each carry their own version. The native graph
  member has a manifest count of exactly one and unknown native graph schema
  versions fail closed.
- **Device-local exclusion.** Device-local preferences (for example
  notification and sync-visibility toggles) are not applied from an import, so a
  restore does not overwrite settings that belong to the local device.
- **Per-semantic-unit atomic apply.** The whole archive is intentionally not one
  transaction: failures are collected and earlier successful units remain
  committed. Exact native task materialization is one transaction; portable
  task and habit aggregates and the calendar event/cutover bundle use their
  corresponding transactional units; other user-authored records pair their
  presence/tombstone decision and write in one transaction. Existing or
  tombstoned identities are skipped rather than duplicated or resurrected.
  Portable preferences restore separately with LWW semantics after device-local
  and control-plane keys are excluded.

## Non-goals

- Changing the on-disk SQLite schema. The archive format is independent of
  `schema.sql`.
- A formal, lossless cross-runtime interchange format. Apple and Tauri are
  directionally aligned through `spec/` concepts, not byte-locked; moving data
  between them is AI-reconciled best-effort, not a structural contract.
- Restoring account- or device-bound sync transport state. The native task graph
  preserves user-data deletion high-waters (tombstones) and opaque future-field
  shadows, but excludes CloudKit confirmation receipts, pending inbox/outbox and
  quarantine rows, corrupt-record fences, cursors, delivery state, and generated
  columns. A JSON provenance header may describe the producing device, but that
  identifier is never installed as the destination's runtime identity.
  Delete/upsert outbox work is reconstructed under the current device identity;
  a backup never imports another account's confirmation state.

## Pre-launch v1 freeze record

On 2026-07-21, before any public Lorvex release or user backup existed, the v1
source lock was intentionally re-frozen after adding the whole-payload semantic
preflight above. This was a first-release contract finalization, not a mutation
of a shipped decoder. From the first production release onward, v1 remains
immutable; any future wire or semantic change adds a new versioned DTO/decoder.
