# Apple Import, Export, and Archive Safety Audit

This is a read-only audit of the macOS/iPhone native JSON/ZIP restore path, the
cross-app `lorvex-interchange` migration archive, the ZIP reader/writer, preview
semantics, and sync consequences. It does not change product code.

Last verified: 2026-07-10 against repository `HEAD`
`605c8a6231605227334ab0f222a925b7f38a5aa5` and its clean working tree.

> **Historical snapshot — current status (2026-07-17).** The findings below are
> preserved as the audit evidence for that commit, not as the current backlog.
> The cross-app interchange/migration flow was removed. The shipping Apple format
> is now version 1 for JSON and ZIP; ZIP has a required exact-count manifest, a
> closed duplicate-free member inventory, and no blob surface. Source, entry,
> aggregate-uncompressed, entry-count, and compression-ratio limits plus strict
> structural-header and CRC validation close the formerly unbounded read path.
> The writer now preflights the same resource envelope and every classic-ZIP
> 16/32-bit field, failing clearly instead of truncating; ZIP64 is deliberately
> unsupported. A future streaming rewrite and physical-device stress evidence
> remain deferred. Preview copy now describes file contents rather than
> predicted writes; device-local/control-plane
> preferences are excluded; task/habit/calendar and other content restore through
> transactional semantic units with atomic presence/tombstone decisions. The
> archive intentionally remains best-effort across those units rather than one
> rollback transaction. Live Settings import also drains and proves the exact
> CloudKit generation, fixed-point pending inbox, and persistent corrupt-record
> debt while holding the same coordinator gate through apply; off/record-plan
> imports remain local-only. See
> `../../../../../docs/design/EXPORT_IMPORT_PARITY.md` for the current contract.

## Two Different Contracts

| Flow | Intended use | Container | Apply model |
| --- | --- | --- | --- |
| Native Data Import | Restore an Apple JSON/ZIP export | Per-category JSON files plus `manifest.json` | Per-category, per-record service calls |
| Migration / interchange | Tauri ↔ Apple or fresh-install migration | `manifest.json` + `data.jsonl` | One deferred-FK database transaction |

Keeping these contracts separate is reasonable. The migration importer is much
closer to a durable backup/migration boundary; the older native importer behaves
like a batch of ordinary user mutations and needs its UI to say so precisely.

## What Is Already Sound

- macOS and iOS hold security-scoped access while reading document-picker URLs.
- Neither ZIP path extracts entry names to the filesystem. `../`, absolute, or
  symlink-style entry names therefore do not create a Zip Slip write today.
- The reader accepts only store and deflate compression, bounds one declared
  uncompressed entry to 256 MiB, and verifies CRC-32 after decoding.
- The interchange importer verifies `format`, rejects a newer version, checks
  `data_sha256`, validates sync-critical HLC/timestamp values, deny-lists internal
  tables, and applies rows in one transaction with deferred foreign keys.
- Interchange import enqueues only imported rows for sync in the same write
  transaction, avoiding a migration that never reaches CloudKit.
- Standard import preserves IDs/keys and reports per-record failures rather than
  silently swallowing them.
- The UI requires explicit confirmation before either import flow writes.

## Findings

### I1 — HIGH: both import paths permit aggregate memory exhaustion

The macOS native import, iOS native import, and macOS migration UI all call
`Data(contentsOf:)` with no file-size limit. The ZIP reader then copies the
entire archive into `[UInt8]`, retains every decoded entry in an array, and can
inflate each entry into a new `Data`. JSON decoding builds full in-memory object
graphs, and the native preview retains the decoded payload until confirmation.

The 256 MiB per-entry limit prevents one forged size field from requesting a
multi-gigabyte buffer, but there is no bound on:

- compressed archive bytes;
- number of entries;
- total declared or actual uncompressed bytes;
- duplicate/overlapping entries;
- JSON record count;
- individual or aggregate string/blob bytes.

A classic ZIP can advertise up to 65,535 central-directory entries. Only a
small number of highly compressible entries near the current per-entry limit is
enough to terminate an iPhone or Mac process. Unknown entries do not help: the
reader inflates and retains them before the higher-level decoder skips them.

Add limits before allocation: maximum source file bytes, entry count, total
uncompressed bytes, supported-entry inventory, per-JSON-file bytes, record
count, string size, and total decoded payload. Reject duplicates and overlapping
payload ranges. For large legitimate migrations, stream the file/JSONL and
apply bounded batches or a staged transaction instead of retaining the entire
archive plus decoded model.

### I2 — HIGH: “Import Preview” is a category count, not a conflict preview

`LorvexDataImporter.plan(from:)` is pure and performs no database reads. It can
only say how many records the file contains. The macOS copy nevertheless says
the preview shows “what will be added,” and iOS says re-importing is safe.

Actual collision behavior differs by category:

- an existing task ID is skipped entirely;
- lists, tags, habits, calendar events/subscriptions, daily reviews, focus
  records, links, memory, and preferences can update an existing identity;
- habit/list/calendar import paths explicitly use import-wins behavior;
- memory import overwrites the content of a colliding key (memory is a
  last-write key→value store);
- preference import can change application behavior and device-local privacy
  choices;
- successful mutations mint new versions/outbox entries and can propagate the
  imported winner through CloudKit to other devices.

“No duplicate row” is not equivalent to “no overwrite,” “no sync side effect,”
or “safe to repeat.” A real preview must be database-backed and report inserted,
updated, unchanged, skipped, invalid, and conflicting counts, with key examples
for every overwriting category. The confirmation must state that overwrites can
sync to other devices.

### I3 — HIGH: native import is non-atomic and can leave a partially restored dataset

The native importer invokes asynchronous core methods record by record and
collects errors. Every successful call commits independently. A later validation,
foreign-key, storage, or cancellation failure leaves all earlier changes in the
database and possibly in the CloudKit outbox.

There is also partial mutation inside a logical record. A task can be created
while list membership, checklist, reminder, recurrence, dependency, cancelled
state, or exact metadata restoration fails afterward. A habit can be upserted
before one completion or reminder policy fails.

That model is defensible for a best-effort batch operation, but not for UI copy
that reads like a safe restore. Prefer a staged database-backed import session
with validation before commit and one transaction per declared atomic unit —
ideally the whole file. If best-effort remains intentional, provide a pre-import
snapshot/rollback path and a detailed durable error report.

### I4 — MEDIUM-HIGH: the native ZIP manifest is written but never read

`LorvexDataExporter.renderZip` writes `schemaVersion`, app version, generation
time, and file counts. `LorvexDataImporter.decodeZip` sees `manifest.json` and
unconditionally skips it. It does not require the manifest, validate the schema
version, compare counts, or bind the confirmed preview to a recognized archive
contract.

Consequences:

- an archive with no manifest can import;
- a future/native version using the same filenames can be misread as the current
  shape instead of failing closed;
- truncated category inventory can look intentional;
- documentation claiming the importer requires a string `schemaVersion` is
  inaccurate.

Either make the manifest an enforced compatibility contract now or remove it
before public format freeze. If retained, define a supported-version set,
required/optional files, duplicate policy, counts, and per-file digests. CRC is
useful corruption detection but is not a schema/version contract.

### I5 — MEDIUM-HIGH privacy: device-local preferences are exported and silently restored

The native export maps every row returned by `getAllPreferences()` into
`preferences.json`. Import calls the core's generic `setPreference` for every
entry. It does not filter `PreferenceKeys.localOnlyPreferenceKeys`.

This can transfer device-specific configuration between machines. In
particular, `notification_show_task_notes` is intentionally local-only because
it controls whether task notes appear on this device's lock screen/banner. A
manual import can enable the source device's exposure choice on the destination
without showing the key or value in preview. Other local keys include sync
backend/config and widget-container settings.

Split portable preferences from device state in the export contract. Default
to excluding local-only values; if a full device backup intentionally includes
them, show them as a separate sensitive category with explicit opt-in and typed
validation.

### I6 — MEDIUM: duplicate entry names are last-writer-wins and unsupported entries consume resources

The native decoder iterates entries and assigns a category repeatedly, so the
last duplicate `tasks.json`/`preferences.json` wins. Blob entries use the same
last-writer-wins dictionary behavior. Interchange constructs `byPath` the same
way for duplicate `manifest.json` or `data.jsonl` names.

The archive contract should reject duplicate logical paths. Otherwise file
inspection tools, preview/debug output, and the actual importer can disagree
about which entry is authoritative. Higher-level decoders should also reject or
skip unsupported inventory before inflation where the container permits it.

### I7 — MEDIUM future-data risk: the ZIP writer silently truncates classic-ZIP limits

`LorvexZipArchive.archive` converts entry sizes, offsets, and central-directory
sizes with `UInt32(truncatingIfNeeded:)`; filename lengths and the entry count use
truncating/wrapping `UInt16`. It returns `Data` rather than throwing.

A sufficiently large legitimate export can therefore produce an archive whose
headers no longer describe its bytes. Current Lorvex data is unlikely to reach
4 GiB or 65,535 entries, but silent truncation is the wrong failure mode for a
backup/export primitive. Enforce classic-ZIP limits and throw, or implement
ZIP64 deliberately. Add an export-side total-memory/disk budget as well.

### I8 — LOW-MEDIUM: blob support is a latent, nonfunctional contract

The native writer and decoder expose `blobs/<hash>` and `DecodedImport.blobs`,
but production export always passes an empty blob dictionary. The apply function
accepts `blobs` and never uses it. No current schema column requires blobs, so
this does not lose shipping data today.

Before format freeze, remove the unused surface or specify and implement it.
If attachments arrive later, require content-hash verification, reference
closure, aggregate size limits, storage atomicity, and orphan cleanup rather
than inheriting this placeholder behavior as an accidental v1 promise.

### I9 — LOW-MEDIUM: interchange validation is stronger than native import but shares the container limits

The interchange runtime correctly treats `row_counts` as advisory under the
committed spec and tolerates extra entries while writers emit exactly two. Its
remaining container-level gaps are the aggregate resource limits and duplicate
logical names described above. Tests assert exact inventory and row-count parity
for golden fixtures, but those test-only helpers do not constrain a hostile or
malformed runtime archive.

Retain the single-transaction and digest-backed design. Add container limits and
duplicate rejection without weakening tolerant unknown-column/table behavior.

## Recommended Contract Before Public Freeze

1. Declare `lorvex-interchange` the durable cross-version migration format and
   decide whether the older native format is a supported backup contract or an
   internal convenience.
2. If native import remains user-facing, version and enforce its manifest now.
3. Define collision policy per category: skip, merge, overwrite, rename, or ask.
   Do not use one generic “safe/idempotent” claim for different behaviors.
4. Separate portable user data, synced preferences, device-local/privacy state,
   diagnostics, and sync internals.
5. Make every resource budget a named, tested product constant. Test just below
   and above each limit on the oldest supported iPhone and baseline Mac.
6. Decide the atomicity promise and provide rollback/recovery evidence.
7. Keep archive integrity distinct from authenticity. A SHA-256 stored beside
   the data detects accidental/tampered mismatch only when the manifest itself
   is trusted; it is not a signature or caller authorization.

## Required Tests

- compressed file at limit, entry at limit, entry count at limit, total
  uncompressed limit, highly compressible bomb, overlapping offsets, duplicate
  names, unsupported compression, corrupt CRC, truncated central directory;
- huge JSON arrays/strings, invalid UTF-8, repeated keys, missing manifest,
  future manifest version, count/digest mismatch;
- database-backed preview for every collision policy and a CloudKit outbox
  assertion showing exactly what will propagate;
- forced failure after record/category N proving the chosen rollback contract;
- local-only preference import, especially lock-screen note exposure;
- backgrounding, cancellation, memory pressure, and app termination during
  read/preview/apply on iPhone and Mac;
- export beyond classic-ZIP boundaries must fail clearly rather than emit a
  corrupt file.
