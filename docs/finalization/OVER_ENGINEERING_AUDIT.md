# Over-Engineering Audit — consolidated findings and resolved decisions

Two independent read-only audits looked for over-complex / low-value design and implementation in the
Apple app — a **structural** pass (code structure, seams, dead code) and a **feature** pass (whole
features and schema surface) — followed by an owner review and an independent external re-review that
corrected several feature-level judgments. This document records the findings **and the resolved
decisions**. The feature verdicts and their implementation queue are complete; this is a historical
design record, not an active backlog.

## The decisive lever: the schema-freeze window

`schema/migration_policy.json` is `launched: false` and `schema/migrations/` is empty. **Today**, dropping
a table or column is a free `schema.sql` edit + checksum re-seed. Once `verify_schema_freeze.py --arm`
fires at first release, the v1 baseline is frozen forever and every later change is an append-only
migration. The schema-touching cuts below (F1, F2, F5) landed before that freeze.

---

# Part 1 — Structural audit (code structure / seams / dead code)

The codebase is lean on the axes that matter: the sync core is multi-master **by design** (HLC + LWW
across the user's own devices) but carries no consensus machinery, no vector clocks, and no multi-user
collaboration system; there is no speculative multi-provider generality and no dead feature flags. The
CloudKit safety machinery that looks like multi-user support is single-user account-change safety. What
remained was dead-in-production surface and single-conformer seams — now largely actioned:

- **Tier A — dead in production: DONE (PR #6).** ~936 lines removed (the outbox bulk-retry/quarantine
  mutator tier, three never-thrown error-enum cases, the unadopted `TaskLifecycleUndo` file, four
  superseded read-bucket queries, a dead JSON helper, test-only wrappers folded into production siblings).
- **Tier B — single-conformer / never-injected seams: DONE (PR #11).** The 8-way `LorvexTaskServicing`
  ISP split collapsed into the umbrella (zero narrow consumers); the never-injected `RuntimeClock` seam
  folded into a direct epoch-ms read; `CloudKitUserRecordNameFetching` collapsed to a stored closure;
  **B2**, the two native-import protocols, merged with CK-4 (#13).
- **Tier C — pre-freeze trims: DONE (#15).** The never-emitted
  `HlcSurface.watch`/`.cli` cases and never-adopted `HabitId`/`ReminderId` typed IDs were deleted.
  (`next_cursor` is reserved-null on the pagination
  envelope; batch `skipped` arrays are genuinely populated by several batch tools — an earlier claim that
  they were constant was wrong — so the MCP wire shape stays as-is.)
- **Tier D — tested-but-uncalled core APIs: low-priority backlog**, reconcile case-by-case, not a launch
  item.
- **Structural KEEPs (do not chase):** the CloudKit account-identity/zone/subscription cluster
  (single-user account-change safety); the intent-security protocol hierarchy (93 conformers → real OS
  auth policies); the watch mutation replay cache (real double-apply race); the `LorvexSync`
  conflict-resolution engine; `CloudSyncReadiness` (parsed textually by a release gate).

---

# Part 2 — Feature audit: RESOLVED owner decisions

Each entry: what was found → the decision → implementation notes (including couplings the removal must
handle). Where the external re-review corrected the original audit, the correction is recorded.

## F1 — Memory revisions/restore → **CUT** (decided)

**Keep:** the `memories` KV store, its CloudKit multi-device sync, and `ai_changelog` auditing of AI
writes. **Cut:** the entire per-version revision/restore system — `memory_revisions` table, the
`memory_revision` synced entity, `get_memory_history` + `restore_memory_revision` MCP tools, the
history/diff/restore UI on both platforms, the two restore/history App Intents, revision retention +
revision import/export, and the `revision_count` wire field. There is no restore-to-old-version need.

**Implementation couplings (must be handled, not skipped):**
- **Ownership is derived state:** `MemoryEntry.ownership` is not a `memories` column — it is derived from
  the latest `memory_revisions.actor` (`SwiftLorvexMemoryDeserializers.swift`). With revisions gone,
  **drop the human/ai ownership state machine entirely** (all memories are AI-managed context; this
  matches the product model) rather than adding an ownership column.
- **`ai_changelog` is audit, not recovery:** it records operation summaries (bounded, 4 KB snapshot cap),
  not full before/after content. That is the intended contract — provenance, not a version store. Do not
  grow it into one.
- The `UNIQUE(key)` min-id merge convergence **stays** (KV sync correctness, independent of revisions);
  only the revision re-pointing lines drop. See also the merge-semantics hardening item below.
- Export/import: the `revisions[]` export field and the revision-replay import path go with the cut.

## F2 — Calendar attendees + attendee-shadow → **CUT the relational machinery** (decided)

**The two-calendar distinction (the load-bearing context):** external **EventKit** events (the user's
real Apple/Google calendar) live in `provider_calendar_events` — a **device-local rebuildable cache,
never CloudKit-synced** (each device mirrors its own EventKit; the provider syncs itself). Lorvex-native
`calendar_events` are Lorvex-owned and CloudKit-synced. F2 concerns only the **native** side's attendee
machinery: `calendar_event_attendees` (relational child table with synthesized attendee identity and a
PARTSTAT status field) + `calendar_event_attendee_shadow` (unknown-key preservation).

**Why cut:** no invite/RSVP infrastructure exists (the status field is a never-updated static
annotation); the UI has no attendee editor (read-only display); real meeting attendees come from the
EventKit provider path, which is untouched. **Shape of the cut:** drop both tables, the identity
synthesis, the PARTSTAT machine, and the `attendee_email_collision` merge; keep the MCP attendees
parameter and the inspector display backed by a **plain attendees JSON column on `calendar_events`**
(name/email pairs) — this preserves the AI-facing value (structured create/query of attendees on native
events) at near-zero structural cost, and unknown-field preservation rides the aggregate's generic
payload shadow. *(Recorded dissent: the external re-review preferred keeping the relational table +
shadow for AI queryability and future evolution; the owner chose the lean shape.)*

**Separate follow-up (not part of the cut):** an EventKit fidelity pass — the mobile surface requests
full access but implements no EventKit writes (while its Info.plist usage description claims write
capability — description drift), mobile does not map recurrence rules, macOS keeps only the first
recurrence rule, attendees without a parseable email are dropped, and the default privacy tier is
busy-only. Define and pin the intended display contract (time/title/location/notes/URL/calendar/
recurrence/organizer/attendees) rather than chasing 100% EKEvent mirroring.

## F3 — Focus-schedule persistence → **KEEP persisted + synced** (decided; original audit corrected)

The three layers: `current_focus` (which tasks today, ordered), `propose_daily_schedule` (an ephemeral
deterministic bin-packer over focus + calendar + working hours), and `focus_schedule`/`_blocks` (the
saved plan). The original audit read the saved layer as a derivable cache of the proposal. **Corrected:**
a saved schedule is the **accepted commitment** — re-running the packer after the calendar or estimates
change would silently rewrite a plan the user/AI already accepted, so it is user intent, not derivable
state; the MCP tool accepts hand-authored blocks; and saving merges task blocks into `current_focus`
(it is already not a pure snapshot). The owner expects an accepted time-blocked plan to sync across
devices. **Decision: keep the persisted, synced layer.** UX backlog (post-launch): a block editor
(edit/drag/resize) and a "schedule may be stale — recompute?" affordance instead of silent overwrite.

## F4 — Import → **KEEP and implement correctly** (decided)

Import stays. **CK-4 is complete (#13):** per-aggregate atomic skip-if-exists
(presence check + write in one transaction), tombstone consultation so restore
does not resurrect deleted entities, the habit overwrite fixed, and the two
native-import protocols merged (B2). Shipped semantics: **non-destructive merge** (no authoritative whole-DB replace —
a settled owner decision). Note: CloudKit sign-in is live-state sync, not a backup (deletions and
corruption propagate); backup/restore is a distinct failure model, which is why import earns a correct
implementation. `docs/design/EXPORT_IMPORT_PARITY.md` now describes the actual
per-record/per-category application with partial-failure collection.

**Export philosophy (owner direction):** export/import carries **final state, not history** — a memory
exports its current content, not its revision trail (consistent with F1). Where an aggregate's "state"
spans children (task + checklist + reminders + recurrence), the record exports whole — children are
current state, not history.

## F5 — Daily reviews → **drop `ai_synthesis` only** (decided; original audit corrected)

The journal (`summary`, `mood`, `energy_level`), the add/amend/get tools, and the weekly navigation +
digest are load-bearing. **Corrected by the re-review and verified:** `wins`/`blockers`/`learnings` are
real human-editable fields read by the Reviews workspace and read-only views — **keep them**;
`get_weekly_brief` not reading `daily_reviews` is intentional (it is the deterministic, token-cheap task
-activity summary; `get_review_history` carries the subjective side) — **keep it**. The one genuine trim:
**drop the `ai_synthesis` column** (AI regenerates its observation on demand; it duplicates the AI-writer
path of `summary`). Freeze-timed single-column drop.

## F6 — Recurring-occurrence convergence → **SUPERSEDED by the finalized model**

The earlier audit described random-ID override rows and the associated
`ApplyCalendarOverrideMerge` collision repair. That design no longer exists.
Each occurrence decision now has a deterministic UUIDv8 derived from
`(series_id, recurrence_generation, recurrence_instance_date)` and is one
whole-row LWW register with `replacement`, `cancelled`, or `inherit` state.
Both devices therefore address the same logical occurrence with the same row
identity; ordinary per-entity LWW converges without a UNIQUE-collision repair,
link re-pointing, or loser tombstone.

The recurrence generation is part of the identity, so an all-series reset
starts a new decision namespace instead of recreating a permanently tombstoned
row. Scoped operations (`this`, `thisAndFollowing`, and `all`) remain supported.
See `CALENDAR_DATA_SYNC_FINALIZATION_2026-07-15.md` for the frozen model.

## F7 — Task dependencies → **KEEP model/sync/tools; the standalone view stays deleted** (decided)

Dependencies are load-bearing and **stay CloudKit-synced**: edges are human-editable on iOS/iPad
(`MobileDependencyField`), MCP-writable (`depends_on`), drive cycle-rejection and unblock cascades, and
`get_dependency_graph` (roots/blocked/leaf-blockers, capped at 500 nodes/1000 edges) stays for the AI.
The cross-device cycle-break in `ApplyEdge` (SCC + deterministic loser tombstone) is required as long as
edges sync — two devices adding `A→B` and `B→A` offline is only detectable at merge. **Human-surface
decision:** no standalone dependency-graph view is wanted — dependencies are seen/edited in task
context and via MCP only. The macOS graph workspace and its remnant routing/view code were removed in
the Tier C cleanup.

## Feature KEEPs (unchanged from the audit)

Habit milestones/waypoints/celebrations (structurally near-zero: one nullable column + presentational
UI); the shared `AggregateMergeEngine` and per-entity merge hooks (each a real UNIQUE-collision hazard);
provider/EventKit mirrors; ai_changelog; current_focus; propose_daily_schedule; checklist; task+habit
reminders; tags; and the user-controlled, cross-device `ai_changelog` retention policy.

---

# Implementation queue (from the resolved decisions)

| Item | Status | Freeze-sensitive |
|---|---|---|
| CK-4 import atomicity + tombstone guard + B2 merge | **DONE** (#13) | no |
| F1 memory revisions/restore removal (incl. ownership drop) | **DONE** (#14) | landed pre-freeze |
| F2 attendee machinery cut → JSON column | **DONE** (#16) | landed pre-freeze |
| F5 `ai_synthesis` column drop | **DONE** (#17) | landed pre-freeze |
| Tier C trims + dead-UI routing residue | **DONE** (#15) | landed pre-freeze |
| EXPORT_IMPORT_PARITY.md atomicity-claim fix | **DONE** (with #14) | no |
| Merge-semantics hardening (min-id identity + max-HLC content) | **DONE** (#19-PR / "Split dedup-merge identity from content") | no |
| `in_progress` lifecycle status (owner-approved ADD) | **DONE** (data #20-PR + full-surface #28-PR) — visual QA still owner-deferred | landed pre-freeze |
| EventKit contract → macOS-only write-back + honest docs/plist | **DONE** (#35-PR) | no |
| due_time removal (owner: delete half-implemented column) | **DONE** (#31-PR) | landed pre-freeze |
| provider-kind CHECK → eventkit only | **DONE** (#30-PR) | landed pre-freeze |

All owner-decided feature work and the codex second-review code findings are landed. Remaining work is
tracked in `FINDINGS_BACKLOG.md` and `RELEASE_ACCOUNT_CHECKLIST.md`.
