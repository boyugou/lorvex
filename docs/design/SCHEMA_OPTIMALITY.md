# Schema & Data-Infrastructure Optimality

This document records the stable strengths of `schema/schema.sql` (the Apple
app's schema authority, realized byte-for-byte by its embedded `LorvexCore`
copy). The 2026-07-16/17 convergence audits closed the two pre-freeze model
blockers that had temporarily superseded the earlier optimality conclusion.
Recurring calendar state now uses one deterministic occurrence-decision row for
replacement/cancellation/inherit while each base event joins independently
versioned content and recurrence-topology registers. Recurring-task completion
and deterministic successor creation now form one grouped lifecycle register,
so offline LWW cannot compose a completed predecessor with a missing successor.
No code-side schema/sync freeze blocker remains; the integrity/performance
evidence below is the baseline that future migrations must preserve.

This document records the audit evidence and the **invariants** that keep the
schema optimal, so future changes preserve them rather than re-deriving them.

## What was audited, and the evidence

All ordinary tables are `STRICT`; the schema also carries targeted indexes,
FTS5 virtual tables, and triggers for derived-key maintenance.

**Type safety.** Every table is `STRICT`, so column affinities are enforced
(no silent coercion). Booleans are `INTEGER` with `CHECK (col IN (0,1))`;
timestamps are canonical RFC-3339 `…Z` `TEXT` (the sync layer asserts the `Z`
suffix at the enqueue boundary so lexical comparison ranks as instants).

**Integrity.** Targeted `CHECK` constraints guard enum-like columns (`status`,
`priority` ∈ 1..3, `operation ∈ ('upsert','delete')`, frequency types, …) and
cross-column rules (`end_time` ≥ `start_time` on calendar events). Every foreign key has an
explicit `ON DELETE` (28 CASCADE / 15 RESTRICT / 0 SET NULL) — no accidental
implicit-RESTRICT. Every natural key is protected: junction tables use composite
primary keys (`task_tags(task_id,tag_id)`, `task_dependencies(task_id,
depends_on_task_id)`, `habit_completions(habit_id,completed_date)` = one
completion per habit per day, …); name uniqueness uses partial unique indexes
that correctly exclude archived rows (`UNIQUE habits(lookup_key) WHERE
archived=0`) with a trigger maintaining the derived `lookup_key`.

The finalized baseline currently contains 65 ordinary `STRICT` tables and three
FTS virtual tables. The FTS-owned shadow tables are SQLite implementation detail,
not separately authored application tables.

**Query performance.** The canonical task ordering
(`priority_effective ASC, due_date ASC NULLS LAST, id ASC`) is served by a
`priority_effective INTEGER GENERATED ALWAYS AS (COALESCE(priority,4)) VIRTUAL`
column plus seven composite covering indexes for the canonical key and its
documented per-view deviations (list-scoped and due-first). Partial indexes
(`WHERE planned_date IS NOT NULL`,
`WHERE status='completed' AND completed_at IS NOT NULL`, …) keep indexes small.
Other generated columns (`recurrence_end_date`, `url_normalized`) precompute hot
predicates. FTS5 uses external-content tables with maintaining triggers.
Archived task rows are retained indefinitely until explicit restore or guarded
permanent delete. They intentionally have no age-based purge or dedicated
archive-time index because production has no archived-catalog or cutoff scan;
active reads use the existing `archived_at IS NULL` partial indexes.

**Sync / outbox.** The active drain is FIFO by the
`INTEGER PRIMARY KEY AUTOINCREMENT` rowid (`ORDER BY id ASC LIMIT`) over a narrow
unsynced partial index. A second partial index on `(next_retry_at, id)` covers
only ordinary `retry_wait` rows, making due recovery bounded without taxing
active/synced history; ordinarily empty partial indexes on
`authoritative_session_token` and `created_at` give intentional adoption fences
bounded session cleanup/FK cascade and defensive retention paths respectively.
`disposition` separates automatically recoverable
push/decode failures from intentional `authoritative_adoption` fences; retention
GC prunes synced history and intentional fences but never deletes retry-wait
work. Every adoption fence is FK-owned by its durable snapshot session and is
deleted, never re-armed, on finalize/cancel; `ON DELETE CASCADE` prevents orphan
fences from permanently occupying the per-entity unsynced slot.
`consecutive_error_count <= retry_count` makes the poison-row acceleration
an explicit per-record streak rather than an inference from unrelated failures.
Tombstones, payload shadows, checkpoints, conflict log, pending inbox, and
quarantine carry the HLC `version`, dedupe keys (`PRIMARY KEY (entity_type,
entity_id[, version])`), and retry/error fields correct last-writer-wins sync
needs.

## Invariants to preserve on any future change

1. **All tables `STRICT`.** Never add a non-STRICT table.
2. **Booleans are `INTEGER CHECK (col IN (0,1))`; timestamps are RFC-3339 `…Z`
   `TEXT`.** Do not introduce a second timestamp encoding.
3. **Every FK declares an explicit `ON DELETE`.** Choose CASCADE for owned
   children, SET NULL for optional references, RESTRICT for protected parents.
4. **Every enum-like `TEXT` column gets a `CHECK (… IN (…))`.**
5. **Every natural key is uniquely constrained** (composite PK for junctions,
   partial unique index where archived/soft-deleted rows must not collide).
6. **Honor the canonical sort key**: anything that adds a task-list view either
   reuses an existing composite index or documents a new one in
   `SORT_KEYS.md` alongside its index.
7. **Schema identity is the normalized checksum in `checksums.lock`.** The Apple
   app stamps/verifies it in `schema_migrations` (version 1, name `schema`). Changing
   the schema changes the checksum. How that change is made depends on the
   regime below: pre-launch it is a free baseline edit + lock regen; post-launch
   the released entries are frozen and the change is an appended migration.
8. **AI-derived data is local-only proposal state.** Output from any model
   (on-device Foundation Models, Private Cloud Compute, or an external MCP
   assistant) is untrusted proposal state until the user confirms it. Only a
   confirmed write enters the schema, and it writes ordinary existing domain
   fields through the typed core ops — never a new AI-specific *synced* column
   or a new enum value an iOS 18 / macOS 15 build cannot parse. Raw transcripts,
   prompts, hidden reasoning, embeddings, and provider response objects never
   enter CloudKit or `schema.sql`; provenance, if kept, is a local-only record
   (feature, model family/version, prompt/eval version, timestamp, acceptance),
   never the model's reasoning. A model or prompt update is an evaluation event,
   not a schema migration. This keeps every future intelligence feature additive
   and sync-safe on the frozen baseline without a synced-schema change.

## Vocabulary: deliberately shared words

Several words recur across unrelated subsystems on purpose. Each word has one
meaning per family; a new column or table that reuses one of these words must
match the family's meaning.

- **`*_version` — HLC-shaped LWW registers.** `content_version`,
  `schedule_version`, `lifecycle_version`, `archive_version`, and
  `recurrence_topology_version` each guard a field group and merge field-wise
  by HLC comparison. Bare `version` on a synced row is the transport
  high-water mark (the max of the row's register versions), never a merge
  input of its own.
- **"generation" — an identity epoch, never a register.** Generations are
  minted, matched by equality, and fence eras; they do not merge.
  - `calendar_events.recurrence_generation`: the occurrence-decision era of a
    recurring master. A topology change mints a new generation; only decisions
    carrying the current generation are active.
  - CloudKit sync generation (`sync_cloudkit_generation_descriptor`,
    `sync_generation_snapshot_*`): the rebuild epoch of the account's record
    zone. The `sync_generation_snapshot_*` family is the outbound publish
    pipeline; the `sync_authoritative_snapshot*` family is the inbound
    adoption counterpart.
  - Storage generation (store cutover): the on-disk store-directory epoch the
    cutover lease switches between. Local-only, never synced.
- **Reminder delivery vocabulary — "armed" then "delivered".** `last_armed_at`
  stamps the hand-off to `UNUserNotificationCenter` (request scheduled);
  `last_delivered_at` stamps the observed fire-time passing (the OS has
  presented it). Neither is synced.
- **Outbox "disposition".** `sync_outbox.disposition` classifies a parked
  row's resolution path (`retry_wait`, `authoritative_adoption`,
  `future_record_hold`); `NULL` is the ordinary active/synced state. Only
  `retry_wait` is a failure; the other two are deliberate fences.

## Migration model: two regimes, split at first public release

The schema evolves under one of two regimes, selected by the `launched` sentinel
in `schema/migration_policy.json`. The migration ladder is the canonical
`schema/migrations/` directory — numbered `NNN_<name>.sql` migrations applied on
top of the version-1 baseline `schema/schema.sql` (version 1 is the baseline
itself; the ladder starts at 002). The Apple app derives its embedded registry
from a byte-identical copy of that directory
(`apps/apple/script/verify_schema_embed.sh` enforces the embed;
`schema/migrations/README.md` is the full contract). This ladder and freeze
govern the **Apple app's own** post-launch schema evolution for Apple↔Apple
multi-device rolling upgrades; the Tauri app is only directionally aligned, not
byte-locked. `apps/apple/script/verify_schema_freeze.py`,
`apps/apple/script/verify_migration_ladder.py`, and
`apps/apple/script/verify_sync_payload_contract.py` enforce the split on every
gate: dormant (advisory) while `launched: false`, armed once `launched: true`.
SQLite and sync-payload versions are independent. While the app is pre-launch,
the sole `schema/sync_payload/001.json` contract is edited in place and
`LorvexVersion.payloadSchemaVersion` remains `1`; there are no installed older
clients to justify manufacturing a compatibility generation. After the first
public release, a wire-contract change requires an explicit payload-schema bump
and the next contiguous `schema/sync_payload/NNN.json`, even when it needs no DDL
migration.

### Pre-launch (`launched: false`) — the current regime

No installed device carries a Lorvex database yet, so the baseline is free to
change. There is one consolidated schema and no incremental migrations:

- `schema/schema.sql` (and the Apple embedded copy) is edited directly.
- `checksums.lock` is regenerated with `apps/apple/script/verify_migration_ladder.py
  --seed` (Apple-owned), which rewrites the canonical lock and the Apple embedded
  copy byte-identically.
- The migration ladder stays empty.
- The single pre-launch sync-payload contract remains `001` and is edited in
  place. Do not append a manifest or bump `payloadSchemaVersion` until a public
  install has shipped.

The Apple app verifies the recorded `schema_migrations` checksum against its
embedded `checksums.lock` on open; on mismatch (or a corrupt / not-a-database
file) it renames the file aside to a timestamped `…incompatible-<stamp>.bak`
(preserved, never deleted) and recreates a fresh database. So a pre-launch schema
change never requires hand-written migration code — only a lock regen.

### Post-launch (`launched: true`) — frozen baseline

The first public install pins the version-1 baseline onto real user devices.
Re-seeding a released checksum then makes shipped installs either fail
verification (they quarantine healthy data) or drift silently, so:

- `schema/schema.sql` and every already-released `checksums.lock` identity
  (filename plus normalized SHA-256) are
  **frozen forever**. Regenerating a released identity is a data-loss bug.
- Schema changes happen **only** by appending a numbered migration.
- Released `schema/sync_payload/NNN.json` manifests are also **frozen forever**;
  wire-field changes append a new manifest and bump `payloadSchemaVersion`.

**Recipe — change the schema after launch (append migration N):**

1. Do **not** edit `schema/schema.sql` and do **not** re-seed an existing
   `checksums.lock` entry.
2. Add the canonical `schema/migrations/NNN_<name>.sql` (N = current max + 1).
   A shipped migration's filename and SQL are frozen — its recorded name and
   checksum are verified on every open — so it is never renamed or re-edited.
3. Record the new migration's normalized checksum as a **new** `NNN` entry in
   `checksums.lock` (append only; never touch `001` or any prior entry).
4. Copy the file and the lock byte-identically into the Apple embed location
   (`apps/apple/Sources/LorvexCore/Resources/`); the Apple app loads its bundled
   copies automatically. `apps/apple/script/verify_schema_embed.sh` and the Apple
   test suite verify the embed.

At first public release, arm the guard once with
`apps/apple/script/verify_schema_freeze.py --arm`: it flips `launched` to `true`
and atomically freezes the shipped `checksums.lock` plus every current
sync-payload manifest hash into `migration_policy.json`. For every later public
release, re-run and commit `--arm` **before archiving** so every migration and
payload contract that build can ship is captured. Ordinary development gates
allow append-only candidates; the distributable archive gate rejects a current
identity that has not yet been re-armed. Frozen entries may never change or be
removed.
