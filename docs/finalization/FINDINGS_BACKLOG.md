# Lorvex Apple — Finalization Findings Backlog

The **single source of truth for OPEN finalization work**. Completed fixes, findings verified NOT to be
bugs, and accepted/won't-fix/deferred items live in `FINDINGS_ARCHIVE.md` (settled — do not re-open);
this file tracks only what is actually left, grouped by **what unblocks it**. The gate is `gate.sh` in
this directory.

The completed code batches are landed, gated, and pushed — the log is in
`FINDINGS_ARCHIVE.md` (schema/sync-core passes, the eight Apple-audit passes, the external-DB /
interchange / schema-decoupling pass, the review-findings batch, the 2026-07-12 opus ×3 + fable ×5
convergence audits and the two-wave adversarial audit, the error-taxonomy program, the store-orchestration
refactor, the `*ImportServicing` consolidation, the MCP tool-descriptor unification, the SyncEntityDescriptor
field-mapping unification, the pre-release import-durability hardening, the iOS background reminder-refresh,
and the notification / sync-status / polish fixes — plus the 2026-07-13 wave: the CK-1 permanent
death-ledger, CK-4 import atomicity + native-import protocol merge, CK-5 sync-status honesty, the dead-code
sweeps (core Tier A, structural collapses, Tier C + dead-UI routing residue), and the owner-decided feature
cuts: memory revisions/restore removal, attendee machinery → JSON column, `ai_synthesis` drop).
The 2026-07-15 independent schema/sync pass reopened a bounded set of confirmed
source defects; the final import-operation boundary from that set is now closed
and recorded in `FINDINGS_ARCHIVE.md`. Other remaining work needs human review,
a real device, or is deferred by design.

This whole `docs/finalization/` tree is DELETED as the last step before the public cut (dev-process
state, not public docs). Git history is also reset at the cut.

---

## 2026-07-21 surface-correctness batch — SOURCE-GATED

A cross-surface UX/correctness wave landed after the pre-freeze convergence
batch below, gated by the same credential-free gate:

- Task commands (complete/defer/cancel/reopen, menu and keyboard) route
  through a window-scoped `LorvexTaskCommandContext` focused value, so each
  window acts on its own selection surface and another window's navigation
  state can never redirect a command; shift-click range extension and
  arrow-key navigation are surface-scoped the same way.
- Normal macOS Quit waits for every autosave surface (main inspector, daily
  review, detached task windows, sticky notes) to reach SQLite; an
  unconfirmed write cancels termination instead of acknowledging it.
- The calendar AI privacy tier is an explicit device-local three-state choice
  (Off / Busy Only / Full Details) surfaced in Settings on macOS and iPhone;
  Full Details is never selected implicitly, an explicit selection of the
  current default persists, and the former owner-device full-detail
  migration/observer is removed.
- Glance surfaces (widget timelines + the Control Center focus control)
  invalidate together through one `GlanceSurfaceReloader`, with a shared
  `FocusGlancePresentation` model; watch complication entries carry the same
  presentation.
- Mobile memory gains a detail destination and editor sheet; the mobile
  calendar day view gains agenda presentation modes.
- CloudSync retention maintenance resolves its active-outbox policy only
  after owning the coordinator gate, so a maintenance request queued behind a
  temporary sync-off cutover cannot shed live transport debt from a stale
  pre-gate snapshot.
- The source-hygiene structural pins for the affected views were updated to
  the surface-scoped spellings, and the stale ban on the settings tier
  picker's accessibility identifier flipped to a requirement for the new
  explicit picker.

## 2026-07-21 pre-freeze convergence batch — SOURCE-GATED

This section supersedes older statements below that no code work remained.
The complete credential-free gate is green. The separate schema-freeze decision
remains deliberately unarmed until all payload- and schema-affecting work is
settled and the external production release evidence below can be collected.

Closed in code with focused regressions in the current batch:

- CloudKit push conflicts for current+1 task/calendar/cutover payload-shadow
  clients now retain current unknown fields while routing the current server's
  winning typed registers through Core; initial, bounded-retry, Core, and
  coordinator paths are covered. Future-server/future-future records remain
  held rather than guessed at.
- Permanent redirect targets are excluded transitively from tombstone
  compaction; widget snapshots are projected atomically from one database
  transaction and are ordered by storage generation/workspace/change sequence/
  focus revision/logical day; factory reset now completes canonical erasure
  even when derived widget-barrier publication fails.
- Managed-storage reset removes the persisted install identity before deleting
  the database, so a fresh store cannot reuse a device identity whose HLC
  history was erased.
- Habit streaks use scheduled, target-met dates no later than product-timezone
  today. Weekly-every-day requires seven met dates, pinned weeks require their
  unique scheduled dates, and rhythm/progress UI uses the same quota and
  Monday-based week boundary.
- A non-recurring task can no longer retain recurrence exceptions through sync.
  Current-schema recurrence payloads missing their required companion fields
  fail validation, while future-schema variants defer intact instead of being
  permanently dropped. `add_daily_review`/the canonical replacement API clears
  omitted links explicitly, `amend_daily_review` remains the patch API, and
  scalar-only Apple UI/App Intent drafts preserve transaction-current links so
  a stale draft cannot erase a concurrent MCP/CloudKit edit.
- CloudKit physical deletion of a permanent redirect target now reasserts its
  original-death tombstone when no live/pending provenance remains, while
  ordinary tombstone deletion behavior is unchanged. Corrupt-database
  quarantine advances storage generation and rotates install/HLC identity
  before replacing SQLite, failing closed if identity cleanup cannot complete.
- The Focus Filter Extension is fully represented in XcodeGen, localized plist
  resources, manifests, and static project verification. The iPhone build path
  also closes the Swift 6 WatchConnectivity logging capture error exposed by
  that integration.
- The production DMG path now has one meaning: an arm64-only Release app with
  real Developer ID profiles, production CloudKit entitlements, notarization
  and stapling. It mounts that final DMG, installs the exact app, verifies bundle
  tree identity/signatures/runtime/LaunchServices/PlugInKit, irreversibly clears
  Lorvex's App Group, defaults, private sync state and derived empty Spotlight
  domains without backup/move/restore, cold-launches the installed app, then
  exercises the sandboxed MCP helper against the real App Group. Normal app
  installs/upgrades never invoke this external destructive harness.
- The final bounded convergence follow-up closes four cross-path holes: archived
  tasks are rejected from day-plan local/import/backup ingress; authoritative
  snapshots run the same product-timezone reminder reanchor as incremental
  inbound; the outbound page ceiling returns a successful typed continuation
  instead of feeding failure pacing; and same-account `CKAccountChanged`
  recovery immediately re-registers and resumes the ordinary sync flight on
  macOS and iPhone/iPad.
- First-account recovery now clears only the exact fresh-database
  `.accountChanged` pause it observed, using compare-and-set and preserving the
  explicit adoption barrier for a truly different bound account. Nil-report
  generation/account-boundary and transient-availability exits keep their
  durable work and schedule bounded retry wakes, while durable pauses and
  explicit unavailable accounts remain quiet. Account-change recovery also
  resets pacing after acquiring the coordinator operation gate so a queued old
  failure cannot reintroduce backoff before the recovery flight.
- Required `timezone` repair now covers typed Delete, incremental CloudKit
  physical deletion, and complete authoritative-snapshot absence. The latter
  two preserve the canonical row and enqueue a fresh dominating upsert, while
  ordinary remotely absent preferences remain exact-pruned. Backup-v5 semantic
  preflight also validates every importable stored-JSON preference through the
  shared typed contract before any category write, so malformed settings cannot
  produce a partial restore.

Gate evidence at this checkpoint:

- `swift test`: 2,664 tests in 143 suites, 0 failures.
- `core/swift test`: 2,649 XCTest cases plus 1 Swift Testing case, 0 failures,
  23 explicitly gated benchmarks.
- Python verifier/unit suite inside `verify_all.sh`: 693 tests, 0 failures.
- Schema embed/migration ladder/payload contract/backup-v5/schema-freeze
  tripwire, repository/source/entitlement hygiene, build matrix, CloudKit
  readiness, localization/privacy/acknowledgments, 118-tool MCP manifest,
  XcodeGen, Mach-O distribution/closure, local package, and disposable-db MCP
  stdio smoke all green.

Still external or intentionally deferred at this checkpoint:

- The final signed/notarized DMG run requires the real Developer ID profiles,
  notary credentials, armed schema freeze, and CloudKit Production promotion on
  real Apple accounts/devices. Source and mocked orchestration checks cannot
  substitute for that evidence.
- The final data/timezone/outbox/provider pass is complete and recorded in
  `DATA_SCHEMA_SYNC_FINALIZATION_2026-07-21.md`.
  `schema/migration_policy.json` deliberately remains unarmed until the exact
  first-public-release commit is selected. Arm it immediately before the real
  credentialed production artifact; do not claim production validation before
  the external release evidence exists.

## 2026-07-19 round-4 independent verification wave (new paradigms) — RECONFIRMED

Four independent checks under paradigms the earlier rounds did not use:

- **Multi-peer convergence simulation (empirical):** 2–4 in-memory peers
  exchanging real envelopes through the production apply pipeline across five
  scenario families (mixed-entity storm, three-way alias chains with a
  worst-case late joiner, delete/edit races, day-scoped churn, recurring
  calendar replace-vs-cancel-vs-reset) in shuffled arrival orders — full-state
  BYTE convergence across 17 entity kinds plus the tombstone/redirect ledgers,
  zero divergence. The delete-beats-edit tombstone-ledger asymmetry is the one
  deliberately non-identical ledger state (live state uniform; heals via
  generation republication).
- **Crash-point durability simulation (empirical):** sentinel aborts inside
  every major mutation funnel and mid-inbound-page, plus reopen-after-commit,
  checked by a 10-rule invariant checker (canonical versions, outbox
  referential integrity, tombstone/live exclusivity, redirect acyclicity,
  dense positions, FK/quick_check, changelog shape, HLC high-water dominance)
  — zero product defects.
- **Zero-context cold contract review:** code and schema judged tightly
  co-designed with no blocker; the review exposed SYNC_APPLY_SEMANTICS.md as
  materially behind the implementation (redirect-eligibility over-claim,
  pre-repair-funnel equal-HLC prose, missing grouped-register LWW /
  repairRequired / convergence re-emit / future_record_hold) plus stale
  docstrings. All reconciled: five doc sections rewritten, two added, five
  docstring sets corrected, the schema tombstone_wins comment now covers both
  paths.
- **Data-lifecycle round-trip (empirical):** maximal-dataset double export
  round-trips byte-identically except the importing device id;
  restore-then-sync converges with no deletion resurrection; double import is
  an exact no-op; factory-reset → restore recovers fully with rotated
  identity. One minor code fix landed from this probe: the default-list
  preference validation now decodes the stored JSON form before the
  list-existence check, so a restored custom default list survives portable
  import (regression-pinned).
- A third AppStore timing test received the bounded-backoff converge treatment
  (same class as the two round-1 proper fixes).

## 2026-07-18 round-3 finalization wave (fix verification + completeness critic) — CAMPAIGN CONVERGED

The convergence criterion (consecutive clean adversarial rounds) is met:

- **Round-2 fix re-review: no correctness regressions.** Budget placement
  discipline proven by transitive caller trace (every budget site local-only;
  sync paths budget-free; the one shared validator maps inbound to a typed
  per-envelope drop at the loosest writer budget). Strict-decode conversions
  preserve absent/null semantics exactly; the escape corpus covers every
  serializer escape class. Two minors, both resolved: `read_memory`'s strict
  key decode is KEPT and the contract now names entity selectors as strict
  (a silently-ignored wrong-typed selector would return the whole store);
  `last_defer_reason`/defer note gain the short-text cap the budget
  arithmetic already reserved for them.
- **Completeness critic: coverage map closed.** All 66 schema tables and every
  data/sync/infra module trace to at least one adversarial round with
  dedicated suites; the nine residual candidates (provider mirrors, snapshot
  staging, LorvexRuntime, audit retention, snapshot content, error_logs GC,
  export lifecycle, preferences, table orphans) each resolved as
  defended-by-construction or thoroughly tested. No unrun modality found.
- At that checkpoint, remaining work appeared exclusively non-code. The
  2026-07-21 checkpoint above supersedes that historical statement with the
  subsequently reproduced data, sync, UI-projection, and packaging findings.

## 2026-07-18 round-2 finalization wave (domain, import, MCP arguments, fix re-review)

Four fresh adversarial reviews; three came back fully clean and one produced
two MEDIUM findings, both fixed in this wave:

- **CLOSED (was MED, reproduced) — per-field codepoint caps composed past the
  256 KiB payload byte cap.** Two individually-legal fields (emoji body +
  emoji ai_notes) overflowed outbound canonicalization with an untyped error
  blamed on whichever write came second. Every payload-bearing user-text field
  now carries a canonical-escaped-byte budget (`PayloadByteBudget`, with
  per-entity worst-case arithmetic in its docstring proving every entity fits
  the cap), enforced at local write/import time only — sync-shared appliers
  and materializers stay budget-free so a peer payload can never wedge a page
  (the wire cap bounds inbound wholes). Collection counts (attendees, review
  links, focus tasks, schedule blocks, recurrence exceptions) are capped the
  same way, and residual `payloadTooLarge` maps to a typed validation error.
- **CLOSED (was MED, reproduced) — lenient wrong-typed MCP write arguments.**
  ~15 write-path sites silently applied a default/other value than the caller
  sent (fractional target_count → 1, integer date → today, string boolean →
  false, wrong-typed idempotency_key → unkeyed). All write-path scalar
  arguments now decode through `StrictScalarArguments` (present-wrong-type
  rejects with a typed error naming the parameter; absent keys keep documented
  defaults; read-path filters and limit/offset clamps stay deliberately
  lenient), including nested attendee/batch-item/schedule-block fields, plus
  an idempotency_key type guard and 256-byte length cap.
- Clean verdicts (adversarially checked, empirical probes): hostile-archive
  import (ZIP bombs/duplicates/zip-slip/JSON depth/duplicate-key smuggling/
  cross-record identity theft/tombstone injection/numeric hostility/no lenient
  cross-platform branch); domain layer (RRULE month-end anchors and skips,
  DST gap/ambiguity/Lord-Howe, canonical-JSON byte-order and escapes and
  bounds, HLC typed-vs-string order over ~810k boundary pairs and counter
  rollover, lookup_key casefold locale-independence); and an independent
  re-review of every round-1 commit (no regressions).
- CALENDAR_BEHAVIOR.md now records the monthly month-end-anchor vs
  literal-day contract and the DST write/export resolution rules.

## 2026-07-18 round-1 finalization wave (five-domain adversarial hunt)

Five parallel adversarial reviews (schema/store DDL+indices, workflow/idempotency,
CloudKit coordinator crash-resume, sync convergence round 2, cross-process infra)
plus targeted fixes, all landed and test-gated in this wave:

- **CLOSED (was MED-HIGH, reproduced) — multi-disjoint-cycle break.** An inbound
  `task_dependency` edge closing two edge-disjoint cycles left a live cycle: the
  applier evicted one SCC-minimum edge and inserted without re-checking. Now
  break-and-revalidate loops until no path remains (deterministic per edge set;
  a mid-loop `incomingLoses` rolls the whole savepoint back). Regression:
  `ApplyEdgeTests.testTaskDependencyUpsertBreaksEveryDisjointCycleTheIncomingEdgeCloses`.
- **CLOSED (was MED) — keyed no-op focus mutations.** `remove_from_current_focus`
  / `clear_current_focus` short-circuited no-ops before any write transaction, so
  a keyed call surfaced the host's "no durable claim" invariant as an internal
  error and never consumed the key. Keyed calls now always reach the write
  transaction (whose no-op branch emits no changelog/outbox). Regression in
  `MCPIdempotencyEnforcementTests`.
- **CLOSED (was MED) — `batch_create_tasks` (and single `create_task`) claim
  exactness.** Both were multi-transaction keyed writes; a crash mid-way left a
  truncated result behind a consumed key. Now one `withWrite` with a per-row
  savepoint (`batchCreateTaskRecords`), preserving per-item skip semantics and
  the exact response shape; an all-invalid keyed batch also commits its claim.
- **CLOSED (was minor) — dead action-date indexes.** The two partial indexes'
  predicates were never provable for the real query spellings (empirically
  confirmed); collapsed to one `idx_tasks_action_date_actionable` matching
  `status IN ('open','in_progress') AND archived_at IS NULL`, with an
  EXPLAIN-plan CI guard. Also added `PRAGMA optimize` (open + post-apply GC) —
  the planner previously ran on default estimates forever — and the FTS
  rowid/VACUUM invariant comment.
- **CLOSED (was minor) — widget-snapshot cross-process revision race** (app vs
  widget-intent extension could land an older revision last): the stale-check +
  write window holds a cross-process flock and fails closed when the lock cannot
  be created or acquired; it never degrades to an unordered write. Storage-
  generation ordering also fences delayed pre-reset publishers.
- **CLOSED (deferred proper fixes) — the two KNOWN FLAKES below.** Reorder test:
  deterministic HLC physical-time seam
  (`SwiftLorvexCoreService.hlcPhysicalNowMsForTesting`). Focus-navigation test:
  the converge helper uses real bounded backoff instead of bare yields.
- Discoverability copy for the `.userDeletedZone` crash window (pause survives a
  crash between the durable pause and the remote `.deleted` CAS; re-running
  Delete iCloud Data completes it safely — protocol-level auto-complete was
  evaluated and REJECTED as unsafe against a peer-re-enabled fleet).
- Clean verdicts (adversarially checked, no defect): CloudKit coordinator
  token/cursor + CAS + account fencing + import boundary + error taxonomy;
  idempotency core; changelog funnel; HLC discipline; outbox atomicity;
  validation symmetry; redirect chains; tombstone compaction; day-scoped and
  calendar-register convergence; DDL/CHECK alignment; triggers; store fault
  taxonomy; migration machinery; cross-process flock coverage; DbLocator;
  quarantine; HLC floors across reset; termination safety.

## 2026-07-17 bounded source closure

The requested data/schema/sync wrap-up is complete on the source side; this
checkpoint intentionally stops expanding the audit surface:

- Committed canonical mutations are no longer reported as failed merely because
  a derived app/widget reload failed afterward. Random-ID creates therefore do
  not invite a duplicate retry; post-commit projection failures are diagnostic
  and converge through the existing database-change relay.
- Habit creation plus initial reminder policies is one core transaction, with
  changelog and outbox rows committed atomically.
- Public backup v5 has a frozen decoder/DTO source lock, a SHA-pinned
  production-shaped all-category JSON fixture, the equivalent ZIP decode probe,
  and a native-task-graph-v2 constant independent of the mutable current model.
- The v5 resource envelope is platform-independent (64 MiB source/archive/entry,
  128 MiB aggregate uncompressed). Bounded history categories fail explicitly
  instead of silently truncating.

Independent terminal reviews found no additional reproducible schema or sync
state-machine defect under the supported main-app-owned CloudSync topology. The
remaining CloudKit container promotion, signed archive, and real multi-device
kill/resume matrix are external release evidence, not source changes.

## Schema and sync freeze blockers

The recurrence editor, recurring-calendar occurrence-decision/grouped-register
checkpoint, durable calendar split-lineage model, and recurring-task grouped-
register lifecycle model are closed and archived. The terminal CloudKit import
boundary is also closed: live import drains and proves the exact current
generation, persistent pending/corrupt inbound debt, and local fixed point while
holding the same coordinator gate through every import decision. There are no
open code-side schema/sync freeze blockers in this backlog.

## Reviewed-work refactors — real, but not headless-loop changes
These touch proven-sound / working code where the payoff is code-health, not a bug. They warrant human
review of the design or a measured need, not an autonomous landing.

- **Unified `RuntimeHealthSnapshot` (optional polish; headline bug already fixed).** `isOperational` now gates on
  the durable pause reason (`922e3fca7`; see archive), so the concrete "green icon over a Sync-Paused notice" bug
  is closed. Remaining, optional: fold the rest of the health signals into one derived surface — quarantined/stuck
  outbox, stuck-pending age, first-run failure (`lastPullAt == nil` while live), requested-vs-effective mode,
  subscription, reseed, App-Group-resolved. Also make `liveLocalizedSettingsSummary` pause-aware (needs a new
  localized string → batch with L5). A stuck-outbox / never-pulled state briefly showing green is far less
  egregious than the fixed durable-pause case → diminishing returns.

## Localization
- **CLOSED 2026-07-21 — native-localization verifier hardening.** Catalog JSON
  loading now rejects duplicate object keys at every nesting level; all Swift
  reference scans mask line and nested block comments without shifting source
  locations; catalog-shaped bare `Text("typo.key")` and implicit
  `LocalizedStringResource = "…"` initializers fail closed; and every plural
  leaf is checked against the source locale's complete argument-position/type
  ABI rather than trusting only `other`. Focused verifier tests pin each
  failure mode, including strings containing `//` and valid singular leaves
  that intentionally render `1` without a placeholder. Separately, a raw
  `swift run`/SwiftPM host can choose English for the resource
  bundle because its executable host has no application localization metadata;
  the packaged app carries the full 13-language `CFBundleLocalizations` list and
  compiled `.lproj` resources. Keep the SwiftPM behavior documented/test-only;
  do not reintroduce a runtime JSON catalog reader to compensate for a
  development-host limitation.
- **Apple numeric/count grammar after L2 — OPEN semantic follow-up.** The L2
  architecture is complete across every Apple module: native bundle-qualified
  lookups are in place, `LorvexLocalizedCatalog` is deleted, diagnostics use
  exhaustive static keys (`apps/apple/Sources/LorvexApple/Support/AppleSurfaceDiagnostics.swift`),
  and recurring-cancel batch/singular copy remains distinct
  (`apps/apple/Sources/LorvexApple/Support/RecurringCancelDialog.swift`). Do not
  reopen the runtime migration. The remaining Apple-specific work is the
  independently audited set of 54 flat numeric-printf calls / 50 unique keys:
  13 require plural variations or split phrases, 16 should become
  count-neutral label-plus-number copy, two compact duration-unit entries need
  an abbreviation-versus-plural policy, 18 are safe mechanical interpolation
  migrations, and one raw import count must migrate with its fixed-plural
  wrapper. The full key inventory and source-path evidence is in
  `apps/apple/docs/plans/L2_NATIVE_LOCALIZATION_MIGRATION.md`; do not claim this
  semantic pass complete until non-English singular/few/many tests land.
- **CLOSED 2026-07-17 — Mobile locale semantics and CloudSync error copy.**
  User-facing mobile date, calendar, recurrence, and relative-time formatters
  now follow the localization selected for the LorvexMobile resource bundle
  instead of the device-wide locale, preventing mixed-language UI under an
  app-specific language override. macOS and mobile CloudSync status surfaces
  now show localized user-safe copy while retaining exact transport detail in
  the local diagnostics ring. Regression coverage pins locale resolution,
  formatter wiring, sanitized subscription failures, and diagnostic origins.
- **L5 — pseudolanguage + artifact-load runtime tests.** Separate test/device
  infrastructure after L2; not translation work. Live Widget Gallery
  presentation of the four deferred localized name/description pairs and the
  Watch complication-gallery name/description remains a manual L5 check.

## Blocked on device visual-QA (owner does these manually — automated CUA/simulator QA is OFF the table per owner)
The owner directed that agent-driven CUA/simulator QA not be attempted (unreliable in this harness); these are
verified by hand when convenient. The underlying CODE landed and is unit-tested; only the visual/device pass remains.
- **`in_progress` UI verification** — the badge, the pinned Today "In Progress" section, and the entry points
  landed code-complete (data + all surfaces, unit-tested via the status×surface matrix) with visual QA deferred.
  Needs a light/dark legibility + spacing pass.
- **macOS task-detail dependency display/editor** — macOS neither shows nor edits task dependencies (the draft
  plumbing exists but no view binds it, while mobile has a picker); a UI add that needs a visual pass.
- **B4 watch bundle-ID install validation** — the companion-prefix topology fix is verifier-pinned; the actual
  watch-simulator install check is outstanding.

## Second independent review (2026-07-13/14) — fully processed on the code side
A second external code+static-gate review (post the first 2026-07-12 audit) surfaced ten items; every code-side
one is landed:
- HIGH — `in_progress` completed only the data layer: the app-layer surfaces (Tasks-workspace status enums, App
  Intents picker, ~21 `.open` filters across widget/watch/CarPlay/badge/reminders, the ≤10 Today cap) were missed,
  so a started task vanished from surfaces and lost its reminder. Closed by two canonical predicates
  (`isActionable`/`isActive`, single source for SQL + Swift) + a status×surface matrix test (#28-PR).
- MED-HIGH — corrupt/incomplete-DB quarantine had a cross-process double-opener race → serialized under an
  exclusive `storage-lock` with a re-check + a deterministic barrier test (#32-PR).
- Freeze-timed schema: dead `sync_device_cursors` removed (#29-PR); half-implemented `due_time` removed (#31-PR);
  provider-kind CHECK trimmed to `eventkit` (#30-PR).
- import "preview" made honest (file-contents count, not a write-outcome promise) (#34-PR); macOS cold start made
  local-first like iPhone (#33-PR); EventKit contract made macOS-only-write-back with honest docs/plist (#35-PR).
- release verifiers hardened (MAS rejects `ProvisionsAllDevices`; iOS IPA post-export recursive audit) (#36-PR);
  reference/release doc drift reconciled (118 tools, arm64-only DMG, widget profile required) (#37-PR).
The follow-on data/sync deep-review wave (schema integrity, sync field mapping,
LWW/merge convergence, storage concurrency, tombstone ledger/backfill) completed
in source checkpoint `c66c2436` (`Finalize Apple data schema and CloudKit sync`).
The independent post-checkpoint hardening pass (one-page partial reseed,
single-owner CloudKit maintenance coordination, migration identity/trigger
closure, and release freeze coverage) is recorded as closed in the archive.
That checkpoint closed the findings known at the time. The fresh independent
review below supersedes the former “no HIGH/MED remains” statement; production
CloudKit and signed-artifact evidence also remains account/device work.

## Fresh schema/sync finalization findings — OPEN (2026-07-15)

These were independently re-derived from `main @ 16c235a09`; they are not
speculative cleanup. Exact evidence and the closed mobile fixes are recorded in
`SCHEMA_SYNC_FINALIZATION_WORKLOG_2026-07-14.md`.

### Sync recovery state machines — CLOSED (2026-07-16)

- **CLOSED (was HIGH) — account adoption was not crash-resumable.** The new external account
  identity is persisted before database rebinding and the full generation
  rebuild. A crash can make the ordinary account gate clear `.accountChanged`
  while the database still belongs to the old account, or unlock ordinary sync
  before the stable canonical inventory was republished. Add a durable
  `adoptionInProgress` phase machine; same-account notifications may not clear
  it or `.backfillFailed`; only exact ready-generation confirmation unlocks
  ordinary sync. Primary evidence:
  `CloudSyncEngineCoordinator+AccountAdopt.swift`,
  `CloudSyncEngineCoordinator+AccountGate.swift` and
  `CloudSyncEngineCoordinator.swift`.
- **CLOSED (was HIGH) — expired/invalid continuation recovery was incomplete in three
  consumers.** A mid-baseline ordinary traversal, candidate-generation readback,
  and predecessor drain can each persist and reuse the same rejected cursor
  forever. Reset the exact operation at the point that consumes the cursor and
  restart a nil-token baseline without destroying an otherwise valid partial
  reseed. Primary evidence:
  `CloudSyncEngineCoordinator.swift`,
  `CloudSyncEngineCoordinator+AuthoritativeSnapshot.swift`,
  `CloudSyncEngineCoordinator+GenerationSnapshot.swift` and
  `CloudSyncEngineCoordinator+ZoneEpoch.swift`.
- **CLOSED (was MED) — per-record CloudKit fetch failure became a tight 64/1,024-request
  retry and is reported as success.** Preserve a typed “retry next trigger”
  outcome instead of collapsing it into `moreComing/reachedTerminal`; stop the
  current drain, feed backoff/retry-after, and do not advance last-sync-success.
  Primary evidence: `CloudSyncRemoteChangeFetcher.swift`,
  `CloudSyncEngineCoordinator+AuthoritativeSnapshot.swift`,
  `CloudSyncEngineCoordinator+Draining.swift` and
  `CloudSyncEngineCoordinator+ZoneEpoch.swift`.

### Schema/payload freeze blockers

- **CLOSED 2026-07-16 (was HIGH) — inbound calendar events could poison the
  store with timing combinations the domain model cannot represent.** Sync now
  parses every flat temporal tuple through `CalendarEventTiming`, normalizes and
  validates IANA timezones, and shares the canonical recurrence-UNTIL bound
  validator with workflow writes. SQLite independently enforces real date/time
  shapes, the three legal temporal variants, chronology and the recurrence
  bound. The workflow/domain/schema contract consistently permits an explicitly
  zero-duration same-day event and rejects only reversed instants. Coverage also
  removed invalid test fixtures and replaced a CHECK-swallowing `INSERT OR
  IGNORE` probe with conflict-targeted insertion. Evidence:
  `core/Sources/LorvexSync/ApplyCalendarEvent.swift`,
  `core/Sources/LorvexWorkflow/CalendarNormalization.swift`,
  `core/Sources/LorvexDomain/Calendar.swift`, and `schema/schema.sql`.
- **CLOSED 2026-07-15 (was HIGH) — N+1 forward compatibility overpromised
  deletion/type changes and did not converge legacy field absence.** Payload
  contract format 3 now freezes recursive field shapes, presence/delete
  semantics, shadow-reserved spellings, typed legacy insert defaults and
  update-preserve history. Historical fixtures execute against current
  appliers/builders; nonfinite JSON is rejected. A higher-schema shadow survives
  a legacy same-ID update and triggers a fresh-HLC full-snapshot re-emit;
  promotion/generation fail closed on provenance or schema-domain mismatch.
  Every cross-ID collision with an opaque participant shadow now defers until an
  upgraded build promotes it; the six collision aggregates are additionally
  release-blocked from known-field evolution until an executable entity-specific
  adapter and convergence probes ship in the same change. Evidence:
  `schema/sync_payload/README.md`,
  `core/Sources/LorvexDomain/SyncPayloadEvolution.swift`,
  `core/Sources/LorvexStore/PayloadShadow*.swift`,
  `core/Sources/LorvexSync/PayloadEvolutionCollisionAdapter.swift`, and the
  payload contract/evolution/convergence suites.
- **CLOSED 2026-07-16 (was MED) — focus schedule event provenance was inferred
  from transient join presence.** Each event block now stores explicit
  canonical/provider/freeform provenance with schema-level identity coupling;
  sync/export normalization is independent of calendar-row arrival order.
  Overlapping occurrences remain distinct display blocks while task packing
  uses a separate occupancy union, and SwiftUI identity follows ordered child
  position rather than a colliding value-derived id. AI/MCP reads and exports
  honor calendar access without deleting human-visible blocks. Evidence:
  `core/Sources/LorvexStore/FocusScheduleSnapshot.swift`,
  `core/Sources/LorvexStore/FocusScheduleProposal.swift`,
  `core/Sources/LorvexSync/ApplyDayScoped.swift`, and
  `Sources/LorvexCore/Services/SwiftLorvexCoreService+Focus.swift`.
- **CLOSED 2026-07-16 (was MED) — the payload manifest was not a runtime
  trust-boundary validator.** `LorvexSync` now loads the numbered manifest as a
  packaged resource and applies the same typed, recursive, fail-closed preflight
  to inbound envelopes and final outbound coalesced payloads before any state
  decision or mutation. Imports canonicalize timestamps; reminder identity,
  anchor-pair, time, and timezone invariants are enforced by service, manifest,
  and SQLite boundaries. Release packaging exact-set and byte-checks the schema,
  checksum, and manifest resources in app/helper/widget surfaces. Evidence:
  `core/Sources/LorvexSync/SyncPayloadContractRegistry.swift`,
  `core/Sources/LorvexSync/Apply.swift`,
  `core/Sources/LorvexSync/OutboxCoalesce.swift`, and
  `script/verify_swiftpm_resource_bundles.py`.

### Multi-surface durability

- **CLOSED (code, 2026-07-16) — durable Watch command application.** The Watch
  now atomically journals before optimistic UI, drains strict FIFO commands only
  while WCSession is activated, retains them through transport completion and
  retryable ACKs, and removes them only after an identity/checksum-bound applied
  ACK. The phone preflights a workspace/sequence ledger before HLC minting and
  commits applied receipts in the same SQLite transaction as the domain write;
  deterministic rejection is terminal-recorded and all receipts are indefinite.
  The bounded latest-state replica is separately workspace-fenced and atomically
  stored on Watch. Evidence: `LorvexWatchCommandJournal.swift`,
  `LorvexWatchCommandDelivery.swift`, `PhoneWatchConnectivityReceiver.swift`,
  `SwiftLorvexCoreService+WatchCommands.swift`, and `WatchCommandLedger.swift`.
  Paired iPhone/Watch interruption and signed-device evidence remains external
  release evidence, not an open source-code design defect.

## Deferred by design / feature-scoped
- **Deferred UX** — I2 (import preview diff against the target DB); F8 (availability-gated `MetricManager` adapter
  at the Xcode-27 migration); R-import-streaming (constant-memory import rewrite; caps bound the peak today);
  R-metrickit residual (per-record detached task can drop on a fast suspend; `error_logs` age+cap GC runs from the
  app-layer maintenance funnel `runLocalRetentionMaintenance` on both surfaces regardless of sync mode, with a
  coordinator-less direct fallback).

## CloudKit hardening residuals (from the 2026-07-12 independent audit; adjudicated code-traced)
The load-bearing fact behind all of these: **deletes are soft** — a peer delete rewrites the entity's existing
CKRecord to a `delete`-op envelope (only whole-zone `deleteZone()` removes records), so a nil-token pull
re-delivers deletes in a STABLE zone and the delete barrier is lost ONLY on a zone rebuild.

**Landed** (details in the merged PRs): CK-1 permanent death-ledger — `gcTombstonesWatermark` retains all
tombstones so the backfill can always re-push the delete barrier into a rebuilt zone, closing the
zombie+future-edit resurrection tail, with two-peer repro/fix tests (#8). CK-4 import atomicity — all
aggregates now do presence+tombstone checks INSIDE the write transaction via `…IfAbsent` entry points; the
habit unconditional overwrite and the link resurrection are fixed; B2 protocol merge included (#13). CK-5
`get_sync_status` honesty — `reseed_required` surfaced, DB-only backend placeholder reports `"unknown"` (#9).
CK-2 zone-epoch fail-closed — a failed epoch fetch/parse now THROWS (three-outcome present/absent/error) and
aborts the cycle instead of folding to nil = fail-open; the pre-push gate, reseed arm, and zoneNotFound arm all
propagate; time arm + enrollment untouched (#26). CK-3 factory-reset race — a commit-time identity equality
check (`sync_checkpoints.device_id` vs the resolved deviceId, bound by `BEGIN IMMEDIATE` to the committing inode)
+ bounded whole-operation retry, on both `withWrite` and `applyInbound`, with a deterministic task-local barrier
test (#23).

**All five CloudKit hardening residuals are closed.**

---

## OWNER DECISIONS — resolved (owner call recorded)
- **Whole-DB restore MODE — NOT building it.** The shipped non-destructive merge-import stays the only restore
  behavior; there is no need for a destructive "replace everything from this backup" snapshot-restore.
- **Memory restore Case C — keep the clean refuse.** No memory-snapshot-restore need; the rare
  delete-then-key-reuse case stays a clean `StoreError.validation`, not an auto-merge. (The owner further flagged
  memory's revision/restore surface as likely over-built — see the over-engineering simplification pass.)
- **L8 WEEKLY series start-date move — keep strict.** Moving a WEEKLY series off its `BYDAY` weekday stays a hard
  reject (create/edit validation parity).

## Notifications residuals (owner-deferred)
- N1's habit-reminder `last_fired_at` no-arming-gate — **consciously deferred** by the owner. Bounded (denied
  permission fires nothing; the same-period debounce self-clears). Revisit only if habit-notification fidelity
  matters. (The `last_notified_at` column it would need is a schema add — feasible only before the freeze is armed.)

---

## Guard rails

### KNOWN FLAKES — proper fixes DELIVERED (2026-07-18 round-1 wave)
Both former parallel-load flakes now have their deferred proper fixes landed:
- **`SwiftLorvexCoreServiceReorderTests.testReorderListsBumpsOnlyMovedRows`** — runs under a deterministic
  HLC physical-time source (`SwiftLorvexCoreService.hlcPhysicalNowMsForTesting` task-local seam feeding both
  clock lanes); every mint gets a distinct millisecond, assertions unchanged.
- **`AppStoreFocusNavigationTests.appStoreRefreshesLoadedTaskWorkspaceAfterStatusMutations`** — the converge
  helper waits with real bounded exponential backoff (~2s budget) instead of bare yields, so a maximally
  contended scheduler can finish the coalesced trailing reload; a genuine regression still exhausts and fails.
If either fails again it is a real detector now, not load noise — investigate, do not re-gate around it.

### BUILD-ARTIFACT (localization catalogs — the gate now compiles them itself)
`verify_all.sh` compiles the String Catalogs itself: after the product builds it runs `swift build --build-tests`
(so every test-dependency bundle exists, including test-only `LorvexCarPlay`) then `script/compile_xcstrings.sh`,
which `xcstringstool compile`s every `.build/*/debug/*.xcstrings` into per-language `.lproj/*.strings` before
`swift test`. A cold worktree passes the `LocalizationTests` on the first run — no manual remedy needed. Do NOT
`rm` the `.build/*/debug/*.bundle` dirs mid-gate. Note that a plain `swift build` / raw `swift test` still does NOT
compile catalogs (only `swift build` copies the raw `.xcstrings`); if you run `swift test` directly instead of the
gate, run `./script/compile_xcstrings.sh` first, or the 11 `LocalizationTests` fail with the catalog-not-loaded
fingerprint (`.lproj`→nil, plurals raw `%lld`, non-English→English).

### GATE / PUSH discipline (learned this effort)
- Gate on `LORVEX_VERIFY_SKIP_PACKAGING=1 ./script/verify_all.sh` (`MAC_GATE=0`). A core/service/macOS-only change
  with no `#if os(iOS)`/`canImport` branch is fully covered by it. ALWAYS read the log for the real exit — a
  trailing `echo` masks `verify_all.sh`'s exit code.
- SERIALIZE gates and cap parallel builds — parallel heavy builds drove machine load to 140 and reaped gates.
  Re-gate at low load rather than pushing on a load-induced flake.
- A worktree agent can silently write into the MAIN tree instead of its worktree. Check `git status` for stray
  code before gating; never `git add -A`.

---

## PROVEN SOUND — do NOT re-litigate
Successive auditors (incl. adversarial verification and multiple full external re-audits, through the 2026-07-12
opus ×3 + fable ×5 convergence) confirmed:
- **Architecture / sync core** — fixed-width canonical HLC + single LWW ordering primitive (byte == logical
  order); S-1 bounded inbound drift vs unbounded local authorship; single generic all-ENCRYPTED CloudKit envelope
  + fixed-width deterministic SHA-256 record name (raw inputs hidden; low-entropy pairs dictionary-testable by
  accepted design); change-token checkpoint-after-apply + fail-closed account/consent gating; STRICT
  Apple-owned SQLite schema (decoupled from Tauri byte-parity, guarded by the freeze/ladder/embed gates);
  forward-compat payload shadows; crash-safe App-Group cutover + storage-generation reset; **the immediate
  multi-master resurrection vectors are closed** — in-window union-backfill resurrection (full-tombstone re-push
  with NO age cap into a recreated zone) and pending-outbox resurrection (quarantine-before-clear on over-window
  adopt), both test-pinned; plus tombstone/redirect chain fidelity, min(id) UNIQUE merges converge, reseed_required
  recovery, wholesale-vs-per-record outbound-failure split, FK preflight, outbox coalesce/quarantine, watermark GC,
  emit-once/id-dedup, keep-last-N can only UNDER-prune; complete dyld closure + runpaths gated on every Release
  artifact. The later CloudKit hardening residuals listed below are all closed.
- **MCP** — catalog↔dispatch parity (now derived from one typed `ToolDefinition` registry); central-dispatch
  fencing on every user-text read; `ai_changelog` on every write; durable idempotency (claim-before-lookup);
  real-store-backed behavioral tests; SQL-injection-free dynamic SQL; pagination LIMIT+1 + id-ASC tiebreak.
- **Platform / quality** — `InboundReloadScope` conservative-superset (EntityKind switch exhaustive, no default);
  `DatabaseChangeSignal` cross-process relay; real-store (not fake) test strategy + DualBackend contract suite;
  EventKit access layer (post whole-series span fix); widget TOCTOU-safe size-capped loader; WatchConnectivity
  durable journal + application ACK + transactional phone receipt protocol;
  zero AppKit in the widget targets; the shipping app/host targets compile warning-clean under
  `-warnings-as-errors` (a matching sweep of the test targets — residual actor-isolation and vacuous-test warnings —
  is a tracked follow-up); date/time proven vs an
  independent model; privacy text matches behavior; licenses/acknowledgments shipped + drift-gated; the shipped
  language catalogs are complete and current localization behavior is test-pinned; the native-runtime migration
  is complete, with the remaining flat numeric grammar work tracked above.
- The two 2026-07-11 "reopened" claims are DELIVERED: device-identity clone/restore detection (cross-process
  mint lock + retired-suffix seed, #6/ACF-01); `ai_changelog` cross-device sync emit + retention propagation
  (#10/#14/ACF-14).

## FINAL STEP
The CloudKit traversal/account recovery state machines, canonical calendar
timing contract, additive payload-evolution/shadow provenance contract,
runtime/import payload preflight, focus-schedule provenance, recurrence models,
recurring-task grouped-register lifecycle, exact native task restore, and the
same-gate terminal CloudKit import boundary are closed. The bounded terminal
code-only convergence reviews have converged with no new reproducible finding;
after the full release gate this source version is ready for the owner's publish cut
(`github.com/boyugou/lorvex`; delete `docs/finalization/` in the cut). All account-side actions that genuinely
need the Apple account / a human — identifiers, certs, provisioning profiles, CloudKit production promotion, App
Privacy answers, age rating, EU DSA trader status, private review contact, screenshots, signed-RC
validation, TestFlight, trademark, the Tauri-updater reconciliation — live in `RELEASE_ACCOUNT_CHECKLIST.md`.
