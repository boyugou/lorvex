# Lorvex Apple — Finalization Findings Archive

Closed record for the finalization loop. Everything here is **settled — do NOT re-open**:
work that landed (with the commit that did it), findings that were verified NOT to be bugs,
and items consciously accepted or deferred. Its companion `FINDINGS_BACKLOG.md` holds only
what is still open.

Kept as a record (not deleted) so a later audit pass doesn't re-flag a solved thing and
waste a cycle re-deriving that it's fine. Git history and PR descriptions are the primary
home for the "how"; this file is the fast index of "already handled, here's why."

This whole `docs/finalization/` tree is DELETED as the last step before the public cut.

---

## Landed — code fixes + refactors (do NOT redo)

- **Terminal CloudKit import boundary + export-format freeze (2026-07-17).**
  macOS and Mobile Settings imports now route through one typed
  `CloudSyncDataImportBoundary` rather than calling the importer directly. Live
  mode continuously holds the retained coordinator's non-reentrant operation
  gate while it drains every visible CloudKit page, re-proves the available
  account and exact ready generation/root/traversal witness, drains ordinary
  dependency deferrals to a bounded local fixed point, and rejects any durable
  pending-inbox or generation-scoped corrupt-record debt before the first import
  decision. Those debt records survive an empty retry and clear only when the
  corresponding record is resolved/deleted or an authoritative snapshot proves
  the generation complete. The gate remains held through the multi-record
  restore, so refresh, cloud deletion, maintenance, and mode transitions cannot
  interleave with its presence/tombstone decisions. Off/record-plan imports do
  no CloudKit I/O but still use the retained maintenance gate when available.
  A failure in unrelated post-terminal outbound/retention/audit work preserves
  the normal sync error and retry-after state without invalidating the proven
  inbound boundary or repeating the import. Both stores publish committed
  changes and await their final coalesced refresh; Mobile first honors a mode
  request queued during the operation. Version 5 is now explicitly the first
  public backup contract for JSON and ZIP, with a retained per-version decoder
  registry and committed golden compatibility fixtures; a future v6 appends a
  decoder instead of reinterpreting v5. The ZIP manifest is required,
  exact-counted, duplicate-free, and a closed member inventory; unknown entries
  and the former unused `blobs/` surface are rejected. Import remains
  non-destructive and atomic per semantic unit, not a destructive or
  whole-archive transaction.
- **Recurring-task grouped-register lifecycle + exact native restore
  (2026-07-15).** The former recurring-task successor P0 is closed. A task
  CloudKit record now carries independent content, schedule, lifecycle, and
  archive registers while row `version` remains the transport/delete high-water
  mark. Completion, reopen, re-completion, stop-series, Someday, permanent
  delete, future-record replay, authoritative snapshots, and post-baseline local
  intent preserve exact register provenance. Recurrence rollover is an explicit
  `none` / `authorized` / `revoked` / `ended` decision with deterministic UUIDv8
  successor identity and parent-generation witness; graph repair covers
  reminders, dependencies, and focus membership without arrival-order forks.
  Future local-intent task upserts replay parent-first and deletes child-first,
  failing closed on duplicate identity or lineage cycles. Apple-native task
  restore v2 preserves the complete live graph plus task-domain tombstones and
  opaque payload shadows, reconstructs outbox work under the current device,
  and never imports CloudKit confirmation/account identity; artifact-only
  backups remain user-restorable. The adversarial completion pass also closed
  equal-HLC shadow promotion, pure-vs-independent list-fallback re-emission, and
  stale Someday successor unwind. Full app/core suites, release verifiers, and
  two MCP stdio smokes are green; `TASK_LIFECYCLE_REGISTER_FINALIZATION.md`
  records the frozen model and evidence.
- **Durable recurring-calendar series cutovers (2026-07-15).** The former
  `this_and_following` split-lineage P0 is closed by a synced, deterministic,
  upsert-only `calendar_series_cutover` remove-wins register. The implicit root
  and every tail now project disjoint original-slot intervals from one durable
  boundary set; predecessor recurrence rows are no longer rewritten with a
  second truncation authority. Active/deleted, equal-HLC, opposite-arrival,
  missing-root, nested-split, late-reference, native restore, full-resync, and
  authoritative-snapshot paths are covered. EventKit and ICS derive bounded
  external recurrence without mutating Lorvex truth. Stable source identities
  now back focus schedules, App Intents, and Spotlight instead of rendered
  occurrence UUIDs, and macOS/Mobile share inclusive/exclusive all-day span
  conversion. The new register is included in HLC bootstrap/retry floors, and
  current-v1 CloudKit conflict/selective-reload fixtures prove the added field
  cannot silently bypass grouped calendar reconciliation or UI reload routing.
  `docs/finalization/CALENDAR_SERIES_CUTOVER_FINALIZATION.md` records the model
  and acceptance evidence.
- **Recurring-calendar occurrence/register checkpoint (2026-07-16).** The former
  cross-aggregate EXDATE/override P0 is closed. Each occurrence now owns one
  deterministic three-state (`replacement` / `cancelled` / `inherit`) LWW
  decision keyed by series, generation, and original occurrence date; timeline,
  ICS, native backup/restore, task links, SwiftUI, Mobile, and MCP all project
  from that model. Base events independently merge descriptive content and
  recurrence topology, including CloudKit `serverRecordChanged` collisions;
  authoritative/future-baseline replay preserves only proven post-baseline
  local register intent and cannot resurrect a remotely absent event from a
  no-op. Complete authoritative snapshots normalize impossible hard-FK child
  orphans into convergent deletes. EventKit future-series replacement is a
  single native `.futureEvents` save and fails closed if the original occurrence
  cannot be proven. `docs/finalization/CALENDAR_DATA_SYNC_FINALIZATION_2026-07-15.md`
  records the model and verification evidence. This checkpoint does not claim
  the independent `this_and_following` segment-lineage problem is closed; that
  subsequently confirmed blocker remains in `FINDINGS_BACKLOG.md`.
- **Lossless recurrence editing and scoped-calendar patch semantics
  (2026-07-16).** macOS and Mobile now edit a shared typed task-recurrence draft
  that preserves every supported advanced rule field, completion-vs-schedule
  anchor, canonical weekday order, and edits made while a save is in flight.
  Same-axis peer changes fail closed; independent peer changes rebase; removing
  recurrence cannot silently erase a newer peer rule. Dirty/fingerprint and
  selective-reload paths include the complete draft, and all user-visible
  validation is localized in every shipped language. Calendar recurrence writes
  now distinguish omission, explicit clear, and replacement through a typed
  patch; opaque future rules survive a no-op editor round trip and can still be
  intentionally cleared. MCP decoding rejects malformed scalar values and an
  explicit empty create rule instead of silently defaulting them. Scoped edits
  validate real occurrences including COUNT/UNTIL, preserve cross-midnight
  duration, honor moved dates, clear optional fields, reuse existing overrides,
  and keep EventKit mirrors intact when replacement write-back fails. This
  closed the former recurrence-editor P1 only. At that checkpoint it
  deliberately did **not** close the then-separate cross-aggregate
  calendar-occurrence or recurring-task successor P0 models; both are closed by
  later entries above.
- **Post-checkpoint schema/sync hardening (2026-07-15).** A fresh independent
  pass found and test-reproduced the remaining composition gaps after
  `c66c2436`: a terminal one-page in-window reseed could clear
  `reseed_required` even when a poisoned tombstone made the full-resync
  backfill partial; macOS delete/re-enable actions could use independently
  gated coordinator graphs while sync was off, and a re-enable requested
  before deletion completed could recreate the just-deleted generation; the
  same off-mode maintenance/mode-transition overlap existed on Mobile.
  Recovery completion is now owned by the transactional backfill/snapshot
  primitives, with the unsafe public marker-clear surface removed. Each macOS
  and Mobile store retains one maintenance coordinator and reuses its operation
  gate/file actors for live sync; mode intent is ordered around deletion and
  cleanup. Request-time epochs also invalidate a mode toggle whose UI Task wakes
  only after a later successful deletion, and the macOS re-enable authorization
  plus durable-pause check run inside the coordinator gate. Deterministic barrier
  and delayed-request tests cover both platforms. Release
  preflight now reruns schema embed parity, semantic migration-ladder checks,
  payload-contract checks, and strict freeze coverage. Frozen migration
  identity includes both filename and normalized SHA in repository gates and
  runtime bookkeeping, while destructive-migration closure validation tracks
  trigger-body writes/reads, qualified/comma-separated sources, and OLD/NEW
  column dependencies. The earlier backlog “retention residual” was also
  re-derived as stale: every macOS and Mobile refresh now runs local retention
  before account/transport gates, including live-but-signed-out operation.
- **Mobile localization semantic-quality + count grammar (2026-07-15).** All 29
  entries whose 12 non-English slots had been copied from English now carry real
  locale-specific translations. A catalog guard rejects any future batch that
  copies source-language prose — including ordinary plural and named plural-
  substitution leaves — into every non-source Mobile locale, while explicitly
  preserving product names such as CloudKit and ignoring pure placeholder
  templates. Four task/focus surfaces now share one bundle-owned compact-minute
  resource, and the superseded focus-specific catalog key is gone. Task
  VoiceOver minutes, custom activity-retention days, and review defer counts
  select native singular/plural forms; the heatmap composes three independently
  pluralized, reorderable semantic phrases; and Today's focus count plus
  date/status accessibility message no longer assume English word order.
  Placeholder verification now preserves integer length modifiers, which also
  removed masked `%d` / `%lld` ABI drift from Widget age labels and the remaining
  macOS duration/review formats. Runtime tests pin English and Russian plural
  selection with explicit locales, German compact output, and Japanese sentence
  punctuation. Selected-locale date formatter injection and user-facing
  CloudKit error mapping remain separate backlog items.
- **L2 native localization Phase 2 SystemIntents + request-locale completion
  (2026-07-15).** All 30 eager `SystemL10n.string` calls across 14 call-site
  files now use deferred, bundle-qualified `LocalizedStringResource`s, and the
  System localization facade no longer owns a custom reader. The five former
  `IntentDialog(stringLiteral:)` exceptions are gone: Siri and Shortcuts now
  resolve every dialog in the invoking request locale. Habit/list/calendar
  entities retain raw counts and schedule fields, while the built-in Focus
  profile maps its stable storage ID to a deferred display name; all construct
  localized display resources only at the App-Intent presentation boundary. Batch
  complete/defer/reopen runners preserve their typed changed/skipped result;
  each intent reports both counts through its own operation-specific plural
  resource instead of forwarding an English snapshot summary. Full-sentence
  resources also replaced independently localized fragments, the recurring
  cancel surface consistently says it cancels one occurrence, and 20 new
  catalog keys cover the newly deferred compositions. Swift source/runtime
  guards and the Python verifier require the exact System table and bundle and
  reject any production `IntentDialog(stringLiteral:)` regression.
- **L2 native localization Phase 2 Watch (2026-07-15).** All 77 eager
  `WatchL10n.string/text` calls across 18 source files now use native
  bundle-qualified `Text` / `String(localized:)`; the facade owns only its
  module bundle and direct catalog URL. The complication's gallery name and
  description are deferred `LocalizedStringResource`s so WidgetKit resolves
  the presentation locale, and the newly cataloged name is complete in all 13
  shipped languages. Source guards forbid the retired helper/custom reader,
  the catalog verifier attributes native String/Text/resource calls to the
  Watch bundle, and runtime coverage proves non-English native resolution. The
  same pass corrected all 12 non-English translations whose cancel action still
  described cancelling an entire task instead of one recurring occurrence.
  Live complication-gallery presentation remains the manual L5 leg.
- **L2 native localization Phase 2 WidgetKitSupport/WidgetExtension
  (2026-07-15).** Native bundle-qualified APIs replaced all 27 support-layer
  and 25 extension-layer eager-helper calls, plus the three Watch complication
  consumers that read WidgetKitSupport copy. `WidgetSupportL10n` now owns only
  its public bundle and direct catalog URL. Each of the four widget definitions
  owns deferred gallery name/description resources, so WidgetKit rather than an
  eager process-locale resolver presents the copy; Focus gallery name and
  description were added in all 13 shipped languages. The redundant
  `WidgetConfigL10n` resolver is deleted, and `LorvexWidgetConfiguration` now
  carries storage identity only instead of localized display copy. Source,
  catalog-ownership, language-completeness, and native-resolution tests pin the
  migration; live Widget Gallery presentation remains the manual L5 leg.
- **WidgetViews native plural grammar and VoiceOver order (2026-07-15).** The
  habits circular status and inline progress now inflect their total-count noun
  through native substitutions. Today footer localizations that inflect their
  completed/open fragments select those two plural axes independently, while
  invariant languages keep the simpler ordinary format entry. The habit-row
  VoiceOver label is one full positional message, so Korean and other languages
  can reorder target/completed counts. Runtime tests cover English singular vs
  plural, Spanish cross-axis combinations, and Korean order. The catalog
  verifier now normalizes locale-specific substitution markers through their
  declared argument number/type and validates their structure.
- **L2 native localization Phase 2 WidgetViews (2026-07-15).** All 25 eager
  `WidgetL10n.string/text` calls across eight view files now use native
  bundle-qualified `Text` / `String(localized:)`. Typed interpolation preserves
  translated argument order without the former `String(format:)` layer, and
  source/runtime regression tests cover the retired facade plus non-English
  multi-argument resolution. `WidgetL10n` now owns only its public bundle and
  direct catalog URL. At that checkpoint its bundle still fed the separate
  `WidgetConfigL10n` resolver; the later WidgetKitSupport/WidgetExtension
  migration recorded above deleted that resolver and moved deferred gallery
  metadata into each widget definition. Catalog keys, translations, widget
  data, and behavior were otherwise unchanged in the WidgetViews step.
- **L2 localization-verifier ownership hardening (2026-07-15).** The key graph
  now recognizes bundle-qualified native `Text` as well as native
  `String(localized:)`, legacy helpers, and deferred resources. Each catalog's
  resource references are attributed by explicit bundle token instead of being
  unioned across every module; every module scan must find at least one real
  reference, so a broken regex cannot pass vacuously. The verifier also
  intersects eager helper references with each catalog's plural-key set. That
  exposed the sole hidden Phase-1 residual (`widget.remaining` routed through
  `WidgetL10n.string` + `String(format:)`), which now uses native integer
  interpolation. Python regression tests pin all four boundaries.
- **L2 native localization Phase 2 CarPlay reference (2026-07-15).** All 12
  CarPlay catalog keys now resolve through explicit
  `String(localized:defaultValue:table:bundle:)` calls. `CarPlayL10n` owns only
  module bundle/resource discovery, so it can no longer eagerly collapse a
  localized value into a process-locale string. The native bundle-token scanner
  enforces catalog ownership and source tests forbid the retired helper while
  retaining the driver-safe no-hardcoded-chrome checks. Catalog contents and
  CarPlay behavior are unchanged. At that checkpoint this became the reference
  shape for the remaining L2 Phase 2 modules.
- **L2 native localization Phase 0/1 (2026-07-15).** Permanent tests first pin
  native per-language bundle resolution and CLDR plural selection against the
  actually compiled catalogs. All 43 production call sites that used a custom
  plural facade now use Apple's interpolated `String(localized:)` or deferred
  `LocalizedStringResource` path; the per-surface plural wrappers and shared
  `pluralString` implementation are gone. Regression coverage includes Russian
  one/few/many categories, multi-placeholder positional reordering, widget
  progress whose second integer is the plural pivot, App-Intent deferred
  resources, and a source guard against reintroducing the custom runtime.
  Catalog keys, translations, and wire/user-visible localized values are
  unchanged; L2 Phases 2–4 remain explicitly tracked.
- **CloudKit/notarization release-tooling hardening (2026-07-15).**
  `cloudkit/deploy-schema.sh` now matches Xcode 26.6's Development-only
  `reset-schema` contract (which has no `--environment` option), rejects every
  CLI shape except no arguments / `--reset` / `--help`, and is pinned by a fully
  mocked exact-argv/no-contact test matrix. `notarize_archive.sh --preflight`
  now extracts and checks the exact ZIP payload against its sibling app, then
  requires Developer ID Application authority, one team, hardened runtime, and
  secure timestamps across the app and nested executable code. Preflight remains
  offline and does not claim Apple-service acceptance; submit reuses it before
  authentication, then preserves the existing staple/rebuild/final-extraction
  proof. The release and Apple-reference docs now match those guarantees, the
  Xcode-26 CI pin, and the pre-sign recursive quarantine gate.
- **CloudKit record-identity privacy contract (2026-07-15).** The deterministic
  `SHA256(entity_type + NUL + entity_id)` identity remains the frozen
  multi-device upsert namespace. Documentation now states the exact boundary:
  it removes raw strings and bounds record names, but an observer of CloudKit
  record metadata can dictionary-test enumerable low-entropy pairs. A keyed
  namespace was rejected because its cross-device secret bootstrap and
  loss/fork/reset recovery contract creates disproportionate availability risk;
  all envelope fields and payload contents remain encrypted.
- **WidgetKit gallery/cadence + actionable-focus completion (2026-07-15).** All
  WidgetKit providers now honor `TimelineProviderContext.isPreview` with a
  representative localized snapshot that does not depend on an App Group file;
  configured-list previews inherit the selected list identity. Timeline reloads
  follow actual freshness/visible-age transitions with WidgetKit's five-minute
  floor and a long missing/stale fallback, while app publication remains the
  primary invalidation path. A downstream exact-`open` filter that removed
  `in_progress` tasks after correct projection was replaced by the shared
  actionable predicate across widget rendering, Smart Stack relevance, Control
  Widget, Watch reader, and complication. Day-relative payloads now carry an
  explicit `logical_day` projection key; one shared validator expires them in
  widgets, Control Center, complications, and the Watch reader, including after
  a device-timezone change. The Watch root revalidates on every active-scene
  transition so a retained view cannot keep yesterday's in-memory focus/habits.
  Focused surface tests pin the matrix, travel boundary, and fallback behavior.
- **Canonical MCP tool-count documentation guard (2026-07-15).** User-doc
  verification now derives the expected count from `EXPECTED_MCP_TOOLS` and
  checks the canonical ROADMAP, feature matrix, and Apple architecture
  statements, preventing another 111/112/118 drift.

- **`%d`→`%lld` catalog specifier normalization (`finalize/catalog-and-docs`).** The 86 stragglers that still
  declared a 32-bit `%d` integer slot for a Swift `Int` (64-bit) argument — 1,766 occurrences across the six
  localization catalogs plus 117 in Swift format-string fallbacks — now declare `%lld`, matching the rest of the
  catalog (`%lld` was already the majority). Zero user-visible change: on the shipping arm64-only targets `%d`
  rendered identically (64-bit variadic slots, low-word read, consistent `va_arg` advance); this makes the slot
  width strictly correct rather than arm64-accidental. Values-only (0 keys carry a specifier), so no key/code
  lookup changed; the placeholder-parity verifier is unaffected (`%d`/`%lld` tokenize to the same `d`), and the
  one pinned typography fragment in `verify_source_hygiene.py` was updated in lockstep.

- **Store-orchestration refactor (complete).** NOT a merged store (macOS 9 domain-storages vs iOS
  `MobileHomeSnapshot`; Spotlight/menu-bar/detached-windows vs Watch/scene/bg-push are genuinely different) —
  a shared functional core with two thin platform shells. PLAN:
  `docs/superpowers/plans/2026-07-12-shared-store-orchestration-core.md`.
  - Phase 1 (`365690b5b`): shared `RefreshSingleFlight<Result>` now backs both stores' `refresh()`
    (one coalescing state machine + unit tests, replacing the two hand-duplicated loops;
    concurrency-M3 `requestRerun` + iOS waiter/`afterDrain` preserved; zero regression-test lines
    changed; macOS keeps its fire-and-forget pre-guard, iOS keeps its waiter path).
  - Phase 2 (`9aad53644`): both stores' inbound-reload executors are compile-time exhaustive over
    `InboundReloadDomain` (no `default`), so a new domain can't be silently unhandled on one platform;
    behavior-preserving (macOS unchanged; iOS's `.tasks`/`.diagnostics` filled as documented no-ops —
    mobile has no task-pool, and mobile diagnostics load on-demand in Settings, not the refresh fan-out).
  - Phase 3 (`DraftReconciliation`) deliberately SKIPPED as YAGNI: the "duplicated" draft-clean check is a
    trivial `==` over platform-specific draft types, already a one-liner per store; a forced generic helper
    adds indirection for ~zero drift risk. Revisit only if a third draft surface appears.
  - Phases 4 + 5 (`b04a2ed46`): the inline-duplicated badge predicate is now shared via
    `InboundReloadScope.recomputesBadge(_:)`, so the badge, reminders, and widget are all gated on shared
    `InboundReloadScope` predicates in both executors. A cross-shell source-scan test locks that neither store
    hand-rolls a derived-surface predicate, and `MULTI_STORE_COHERENCE.md` documents the selective-reload
    coherence invariant.
- **Error taxonomy foundation** (`028d02e71`): added `LorvexCoreError.notFound(entity:id:)` (+ `LorvexEntityKind`)
  and `.validation(field:message:)`; migrated the 23 UUID-keyed not-found throw sites (list/habit/calendar-event/
  series) to `.notFound`; UI (`UserFacingError.classify`) + MCP (`ToolRegistryFormatting.errorCode`) now branch
  typed-case-first with string-match fallback. Behavior-preserved (byte-identical messages; `.notFound → tool_error`
  matched the then-current wire code; characterization + parity tests pin it).
- **Error taxonomy — App-Intents validation** (`15c6b33f2`): 46 `LorvexSystemIntentRunner` input-validation throws
  → `.validation(field:message:)`; zero wire-code change (these are NOT MCP-reachable — proven).
- **Error taxonomy — MCP wire-code promotion** (`92466e542`): the value-delivering step. Entity not-founds
  (list/habit/calendarEvent/calendarSeries) now emit `"not_found"` (mapper one-liner in
  `ToolRegistryFormatting.errorCode`, joining `taskNotFound`); 25 MCP-reachable core-service caller-input guards
  migrated from `unsupportedOperation` → `.validation(field:message:)` so they emit `"validation"`. Messages
  byte-identical; only the typed case + wire `{code}` change; pinning tests flipped, suite docstrings rewritten to
  current state, a positive `create_calendar_event event_type` test added. Manifest doesn't encode per-error codes
  (verifiers pass unchanged at 118 tools). Deliberate pre-launch MCP-contract correction (no published clients).
  Still on `tool_error` by design: conflicts, internal invariants, reference-integrity misses carrying a raw id,
  serialization/resource failures, and import-path payload validation. (Tag/Memory name-keyed not-founds were
  subsequently promoted to `not_found` in `3a7d139a6`/#3 — see below.)
- **Error taxonomy — `.conflict` category** (`5ecc0b2cf`): added `LorvexCoreError.conflict(message:)` and migrated
  the two uniqueness-collision sites — renaming a tag or memory onto a name/key that already belongs to a
  *different* entity, MCP-reachable via `rename_tag` / `rename_memory` — from `unsupportedOperation` → `.conflict`.
  The dispatch map returns `conflict` for it (the same wire code as `StoreError.staleVersion`), so a client
  distinguishes a name collision from a plain validation or generic failure. Messages byte-identical;
  `UserFacingError.classify` routes `.conflict` to the same verbatim-shown `.validation` bucket the string path
  already produced, so UI presentation is unchanged. Envelope tests pin the `conflict` code for both tools (the
  memory dispatch path fences user text in the error message, so that assertion is a substring check).
- **Retention/GC never runs when sync is off** (`99fe273b1`): `runLocalRetentionMaintenance` (emit-less sweep +
  `Outbox.gcUnsyncedBeyondCap` 50k keep-newest) gated on `cloudSyncMode != .live`, called on refresh in both stores.
  Within-cap installs still deliver the full backlog on a later sign-in. (Residual: `cloudSyncMode == .live` with
  iCloud signed-out device-wide is still uncovered — tracked as an OPEN deferred note in the backlog.)
- **Tauri-coupling meta-test (hard-rule violation)** (`7bf0a62c5`): `UIPolishTests.swift` (4136 lines, 104
  source-scan meta-tests incl. the one Tauri-tree-walking one) → all 104 invariants ported to
  `script/verify_source_hygiene.py` (count-reconciled, Tauri-tolerant), wired into `verify_all.sh`; the 10 genuine
  behavioral tests moved to `AppBehaviorTests.swift`. (Follow-up: rename the other wave-named test files — OPEN LOW.)
- **Apple-platform UX M5/M7/M8** (`84735b28c`): M5 iPad wide-split detail gets its own NavigationStack; M7 read/list/
  capture intents now `ReturnsValue` `LorvexTaskEntity` (Read=singular; added `captureTaskReturningTask` core op) so
  Shortcuts can chain; M8 Lists row select reachable by VoiceOver + keyboard.
- **Search/upcoming/deferred/by-tag intents return `[LorvexTaskEntity]`** (`4f6558a05`): the M7 rich-return posture
  extended to the four remaining read/search system intents (`SearchLorvexTasksIntent`,
  `ReadLorvexUpcomingTasksIntent`, `ReadLorvexDeferredTasksIntent`, `FindLorvexTasksByTagIntent`) — each now returns
  `ReturnsValue<[LorvexTaskEntity]>` alongside its unchanged dialog, so a Shortcut can chain on the matched tasks.
  Source-scan test pins the contract + entity mapping for all four.
- **Stale reference comments refreshed to current behavior** (`9901c3e0d`, `5b2f11b3b`): the calendar-link
  re-link docstring ("upserts in place" → no-op), the changelog retention docstring ("stays local / never over
  the wire" → retention pruning propagates as a marked delete+tombstone, ACF-14), the two `schema.sql` comments
  naming the deleted `calendar_subscription_sync` writer (dropped the name, kept the point; byte-identical in both
  schema copies, checksum unchanged), and the `LOCALIZATION.md` exception list (added `LorvexListEntity`; the
  claimed `LorvexFocusFilterIntent` gap was imprecise — its entity `displayRepresentation` renders a raw id title,
  not localizable text, so not a text-localization exception).
- **MCP tool-descriptor unification** (`76698add9`, offloaded to codex, reviewed + merged): the per-tool wiring —
  catalog schema + handler + read/write & idempotency metadata + response-fencing — is now co-located in one
  typed `ToolDefinition`, collected in a domain-split `ToolDefinitionRegistry` (Task/Content/Focus/Habit/System
  `*ToolDefinitions.swift`). `listTools`, dispatch, the idempotency-required set, and fencing are all DERIVED from
  the registry; the five hand-written domain dispatch switches are deleted. Behavior-preserving: the manifest
  SHA-256 is byte-identical (118 tools), stdio smoke green, and a new contract test pins that the definitions are
  the complete listing/dispatch authority with `isWrite ↔ idempotency ↔ advertised-key` and fencing consistency.
  The Python verifiers were reduced, not removed. Full `verify_all.sh` green on main.
- **SyncEntityDescriptor field-mapping unification** (`3630d5c6c`, #2): the outbound serialization, inbound apply,
  and payload-shadow owned-key set now derive from ONE per-entity `SyncEntityDescriptor` carrying typed seam
  metadata; the registry rejects duplicate registration. This makes the previously three-way-hand-maintained field
  symmetry structural — one place to add a column, all three seams stay in sync by construction — closing the
  "a new column ships outbound but is silently dropped inbound" hazard that `SyncFieldRoundTripProbeTests` only
  caught at test time. `task` and `ai_changelog` are deliberately left on the hand path (documented blocker:
  task's partial-patch inbound apply plus its generated `priority_effective` column need a richer field model
  than the descriptor carries). Behavior-preserving — the convergence layer (LWW upsert, min-id merges,
  tombstone/redirect, FK preflight, outbox coalesce/quarantine) is untouched, and every per-field transform
  (`lookup_key` re-derivation, display scrub, nullable-or-clear, 0/1↔bool) is preserved. Full local gate green.
- **Import restore path uniformly non-destructive + retention-safe** (`3a7d139a6`, #3): daily reviews, current
  focus, and focus schedules imported as a fresh-HLC upsert, so a stale backup silently reverted newer local
  journal/focus content and re-propagated it fleet-wide. They now join the entity importers' skip-if-exists
  presence probe (`ImportPresenceTarget.dailyReview/currentFocus/focusSchedule`, keyed on the singleton `date`
  PK), so an import only fills absent rows. `ai_changelog_retention_policy` is skipped on import (importing a
  short retention window would trigger a fleet-wide changelog purge). Adds `task_checklist_item` sync apply/merge
  coverage (`ApplyChildChecklistItemTests`) and fixes one `APP_STORE_PRIVACY_ANSWERS.md` label. This is the one
  real data-loss bug surfaced by the two-wave adversarial audit; behavior fixes are test-guarded, schema /
  CloudKit / UI untouched.
- **Tag/Memory name-keyed not-found → `not_found` wire code** (`3a7d139a6`, #3): `LorvexEntityKind` gained `tag`
  and `memory` cases, and the name/key-keyed lookups in `rename_tag`, `delete_tag`, `merge_tags` (source),
  `rename_memory`, and the memory-key restore path moved from `unsupportedOperation` (→ `tool_error`) to
  `.notFound` (→ `not_found`), so a client distinguishes "no such tag/memory" from a generic failure. The visible
  message changes (verbatim human name preserved). `merge_tags`'s *target* miss deliberately keeps its guided
  `unsupportedOperation` — its recovery is "use `rename_tag`," not a plain not-found. Settles the backlog's
  former "Tag/Memory not-found presentation" owner decision. Rename/tag/memory tests re-pinned.
- **iOS background reminder-refresh (F2)** (`036cc872c`, #4): `LorvexMobileApp` registers a
  `.backgroundTask(.appRefresh)` handler (`ReminderBackgroundRefresh`) that re-arms the rolling reminder window
  while the app is suspended, with `BGTaskSchedulerPermittedIdentifiers` + the fetch background mode added to
  `LorvexMobileApp-Info.plist`. Best-effort, never the sole delivery path. Closes the F2/N2 residual (reminder
  window not self-replenishing / no `BGTaskScheduler` call site). Compiles on macOS + iOS simulator.
- **iPad regular-width Today first-load skeleton (B4)** (`036cc872c`, #4): the compact path's first-load skeleton
  overlay is now applied to the iPad regular-width Today too (`MobileStoreDetailView`), so the wide layout no
  longer first-loads to bare content.
- **`*ImportServicing` protocols consolidated 7→1** (`e58a5ebc1`): the native per-category import path reached
  `SwiftLorvexCoreService` through 7 one/two-method capability protocols (Tag/Focus/HabitCompletion/TaskChild/
  HabitReminderPolicy/TaskCalendarEventLink/Memory), each conformed by the same sole backend and downcast at its
  own call site. Merged into one `LorvexNativeItemImportServicing` (restore a single exported item preserving its
  id); `LorvexNativeRecordImportServicing` kept separate as the distinct optional atomic-restore capability (whole
  task/habit record in one transaction, with a per-op fallback). Behavior-preserving — one downcast now reaches
  every per-item import, each call site keeps its own if-let/guard-let; DualBackend + import-LWW + round-trip
  suites green.
- **Retention prune DELETE+enqueue isolated in a savepoint** (`75307f4f4`): the changelog and memory-revision
  retention sweeps delete each doomed row and enqueue a delete envelope per row; the enclosing sweep is one
  transaction whose `runStep` swallows a throw, so a failure between the DELETE and the enqueue would commit a
  locally-pruned row with no envelope. Wrapped each pair in `StoreTransactions.withSavepoint` (matching
  `FullResyncBackfill`'s per-row emit isolation) so a mid-pair failure rolls back that row too. Bounded/self-healing
  gap closed; additive isolation, happy path unchanged.
- **LorvexMiniMonth resyncs its visible month to an externally-changed day** (`50dd3de52`): the mini-month grid
  seeded `visibleMonth` from `selectedDay` once at init; a later external change to the bound day left the grid on
  its opening month, hiding the new selection. Added `onChange(of: selectedDay)` to jump to the selection's month
  (guarded on an actual month difference so in-month reselection and chevron browsing are preserved). Verified by
  build + the Desktop view snapshot suite; pure state correction, no layout change.
- **Task-status subtitle localized in Shortcuts entity pickers** (`7d7a882e4`): `LorvexTaskEntity` /
  `LorvexReopenableTaskEntity` rendered `subtitle: "\(status)"` — the raw wire enum ("open"). Added
  `LorvexTaskStatusOption.localizedLabel(forRawStatus:)`, which reuses the existing status-filter case
  representations (`system.option.task_status.*`, no new catalog string), and routed both entity subtitles
  through it; unknown status falls back to the raw value.
- **Reminder notification quality: time-sensitive + Notification-Center trace** (`56dd79222`): task / habit /
  snooze reminders now set `interruptionLevel = .timeSensitive` (break through Focus / DND; downgrades to
  `.active` without the entitlement, so safe + forward-compatible), and all three foreground-presentation
  handlers (macOS / iOS / visionOS) add `.list` to `[.banner, .sound]` so a reminder arriving while the app is
  foregrounded leaves a Notification Center entry instead of only a transient banner.
- **CloudSync `isOperational` gates on the durable pause reason** (`922e3fca7`): the Settings sync icon read
  `mode == .live && account == .available`, blind to a standing pause — so a durably-paused device (account
  changed / zone deleted / backfill failed) showed a green "operational" icon directly above its own "Sync Paused"
  notice. `CloudSyncStatusReport` now carries the durable `pauseReason` (both stores already load it for the
  notice) and `isOperational` requires `pauseReason == nil`, so the icon goes neutral whenever a pause stands. The
  init parameter is required (no default) so a future construction site can't silently reintroduce the blind spot.
  Closes the concrete "green over paused" config-hazard; the broader unified `RuntimeHealthSnapshot` is downgraded
  to optional polish (see backlog).
- **ICS `UNTIL` drops the west-of-UTC final occurrence (sync-core M4)** (`b09879465`): `UNTIL` for a timed recurrence
  is now the end of the local until-day in the event's timezone converted to UTC (correct both directions — west rolls
  to the next UTC day so the final occurrence survives; east stays the same UTC day so no phantom). Verified reachable
  (LA: last occ `20260801T030000Z` vs old cap `20260731T235959Z` → was dropped).
- **Sync-field round-trip parity test** (`5299d7892`): `SyncFieldRoundTripProbeTests` — the guard that let the
  SyncEntityDescriptor unification (landed, `3630d5c6c`/#2) proceed incrementally instead of big-bang.
- **Adherence denominator (completionRate30d)** (`2e07084ef`): the real fix behind the mis-framed sync-core "M5".
- **restoreMemoryRevision key hijack (sync-core M6)** (`91eb43f2f`, Fix-4): `ON CONFLICT(id)` — done in wave 2.

---

## Resolved by disposition (documented decision, not a code fix)

- **Error taxonomy `.invariant` category → deferred (YAGNI), no change.** The `LorvexCoreError` "missing after
  insert/import/upsert/rename/restore" sites are genuine internal invariants that correctly surface as
  `tool_error` / the generic alert bucket, and `StoreError.invariant` already routes the store-layer equivalents
  to `tool_error`. A typed `LorvexCoreError.invariant` would map to `tool_error` too — no wire value, no consumer
  for an internal-vs-caller distinction today. Add only when something needs to branch on "internal bug"
  separately (e.g. dedicated telemetry). The remaining `tool_error` sites (reference-integrity misses carrying a
  raw id, serialization/resource failures, import-path payload validation) are correctly generic.
- **Arch-improvable `Reloadable<T>` → attempted, reverted, not worth it.** The keep-old read pattern is 7 macOS +
  17 mobile sites (the backlog's "62/53" over-counted all `try?` uses). Building the helper revealed the blocker:
  the read properties are optional (`today: TodaySnapshot?`, …) while their loaders return non-optional values
  (and one site is non-optional-both), so a uniform `Reloadable<T>` can't wrap both shapes without ambiguous
  `T`/`T?` overloads or per-site wrapping — not the clean mechanical refactor implied, for only a drop-counter
  with no consumer surface. The `if let x = try? await load() { current = x }` idiom is clear and correct.
  `InboundReloadScope.preference` → full-reload is likewise a correct cheap default (preference syncs are rare); a
  granular hot-preference map is premature. Revisit only if transient-read observability becomes a measured need.
- **Wave-named test files → keep, low-value reorg deferred.** `MCPToolSweepFixTests` (17), `MobileAuditFixTests`
  (23), `AppStoreBugFixTests` (6), `WidgetBugFixTests` (4) are grab-bags of unrelated fix-tests, so "rename by the
  invariant they pin" doesn't apply — a real cleanup is a split-by-concern of ~50 tests. All pass and pin real
  invariants; only the filenames carry historical "wave" framing. Not worth the churn pre-launch.


- **Schema M4 (`tags.lookup_key` UNIQUE + `memory_revisions.memory_key` scan) → no change, both deliberate.**
  - **`UNIQUE(tags.lookup_key)` would break sync convergence — do NOT add.** `ApplyTagMerge.applyTagUpsert`
    upserts the inbound tag by `id` first (transiently creating a *second* row with the same `lookup_key` on a
    different id) and only then runs `mergeDuplicate` (min-id winner, re-point `task_tags`, delete loser). A DB
    UNIQUE constraint would reject that first insert and break multi-master tag convergence. The absence of UNIQUE
    is a documented requirement (`schema.sql` note on the `tags` table), not a gap — unlike `memories.key`, whose
    merge path differs. This is part of the PROVEN-SOUND sync core; a future "add the missing UNIQUE" would be a
    regression.
  - **`memory_revisions.memory_key` full-scan is a negligible rare-path cost.** Only the restore-after-delete
    fallback (`+Memory.swift:54`, `SELECT memory_id … WHERE memory_key = ?`) queries by the un-indexed
    `memory_key`; every other path uses `memory_id` (indexed by `idx_memory_revisions_memory_id_created`). The
    table is bounded by keep-last-N retention, and restore-after-delete is a rare user action, so the scan is
    microseconds. Not worth the schema-freeze / embed-copy / checksum-reseed ceremony pre-launch; revisit only if
    profiling ever shows it matters.
- **Config hazards → both dispositioned, no change.**
  - **Unrecognized `LORVEX_CLOUDKIT_EXPORT` → `.off` with no log.** A dev/CI-only override (never set in a
    production App Store build), so a typo silently disabling sync only affects a developer. `resolveMode`'s
    docstring already documents "any other non-nil value → `.off`," so the behavior is discoverable. Adding a
    diagnostic warning would either pollute the pure, unit-tested resolver with a side effect or duplicate the
    parse at both call sites (`CloudSyncFactory`, `AppCoreFactory`) — not worth it for dev-only value.
  - **Retention `.days` byte-compare (`CHECK(length>0)` only).** Same-account threat only — the "attacker" is one
    of your own trusted devices. Timestamps are minted well-formed ISO by the sync clock (lexically comparable, so
    the byte compare is correct for valid data); a lexically-huge non-ISO value that evades every cutoff requires
    corruption or a self-attacking peer, which is outside the threat model.
- **Data-LOW quartet → all resolved by analysis, no change.**
  - **`HlcClock.maxLocalHlc` `try? parse` masking — bounded, corruption-gated.** The `version LIKE '%\_<suffix>'`
    filter restricts the `MAX()` scan to rows THIS device authored, and this device only ever mints valid
    fixed-width HLCs, so a garbage (unparseable) version there implies corruption. Even then the impact is
    bounded: `generate()` mints at `max(seed, now)` and inbound drift is S-1-clamped, so the physical clock
    dominates the next mint. A full-scan-for-highest-valid would trade the index-friendly `MAX()` for closing a
    corruption-only edge — not worth it.
  - **`sync_tombstones` both-or-neither redirect CHECK — unsafe, would break same-type redirects.** The redirect
    pair is deliberately nullable-independent: a same-type redirect stores `redirect_entity_id` set with
    `redirect_entity_type = NULL`, and both the writer (`Tombstone.swift`, `redirectEntityType ?? entityType`) and
    the chain walker (`ApplyRedirect.swift:74`, `ts.redirectEntityType ?? currentType`) read a null type as "same
    type." A both-or-neither CHECK would reject that valid `(id set, type null)` row. The only genuinely-invalid
    state (type set, id null) is not produced by any write path. No CHECK added.
  - **External-content FTS under `VACUUM` — not actionable.** The fragility is latent only under a future
    `VACUUM`; the codebase runs none today. Revisit only if `VACUUM` is ever introduced.
  - **Canonical task sort not index-served — marginal, not worth the schema ceremony.** Task lists are small
    (dozens–hundreds of rows), so the filesort over `priority_effective, due_date, id` is microseconds. A covering
    index is safe (non-unique) but needs the schema-freeze / embed / checksum ceremony for a perf win no user
    would notice pre-launch; add only if profiling shows it matters.
- **`.zoneBusy` retry-after not honored → deliberate + tested, no change.** `CloudSyncTransientClassifier.serverRetryAfter`
  honors the server `retryAfterSeconds` only for the two account/service throttle codes (`requestRateLimited`,
  `serviceUnavailable`), not `.zoneBusy` — and `transientClassifierExtractsServerRetryAfterOnlyForThrottleCodes`
  constructs a `.zoneBusy` *with* a 20s retry-after and asserts it's ignored, so the authors knew the hint can be
  present and chose to skip it. Rationale: `.zoneBusy` is fast-clearing per-zone write contention adequately gated
  by the local backoff (the effective gate is `max(local, server)`, so no stampede), whereas the two throttle
  codes are server-managed account/service limits. Flipping it would override a tested latency-vs-politeness
  decision and touch the proven-sound sync pacing; a defensible improvement in theory but an owner/empirical call,
  not a headless-loop change.
- **Watch-snapshot receiver return value discarded → benign, no change.** `LorvexWatchSnapshotReceiver.handle(userInfo:)`
  is already `@discardableResult`, and the only call site — the Void `WCSessionDelegate.session(_:didReceiveUserInfo:)`
  — has no return-value-based redelivery hook (`transferUserInfo` is at-most-once at the delegate, unlike a
  `replyHandler`). The `false` cases are all non-actionable there: not-a-snapshot (documented silent-ignore), no
  App-Group container (a deployment/entitlement issue, not a per-message error), or a transient write error that
  self-heals on the next push (a stale-drop returns `true`, not `false`). The `Bool` serves the disk-write tests
  and future multi-payload routing. Discard is intentional and correct.
- **Export lossy fields → documented as intentionally non-portable** (`652ef11ee`): the task export omits
  `due_time` and the recurrence-lineage columns (`spawned_from`, `recurrence_group_id`, `recurrence_instance_key`,
  `canonical_occurrence_date`). Both are structural, not oversights — the Apple core never surfaces `due_time` (a
  peer-only column; the Apple due moment is `dueDate`), and series identity is re-derived from the recurrence rule
  on import. Documented on the `ExportTask` wire contract rather than added, consistent with the best-effort (not
  lossless-by-construction) cross-platform data-movement contract.

## Cleared — verified NOT a bug (do NOT re-open)

- **F1 — habit `timesPerWeek` / weekly-nil reminder cadence "fires more than once per period."** NOT a bug. The
  audit's "one reminder per period" framing was a misread: the reminder engine deliberately fires on each
  scheduled day until the weekly target is met, which is the intended cadence for a `timesPerWeek` habit (a
  weekly-quota habit with no fixed weekday should keep nudging on eligible days until the quota is hit). The
  behavior is test-guarded; no change.
- **H1 — complete→reopen→re-complete of a recurring task orphans the series.** NOT a bug. Traced
  `LifecycleSideEffects.apply` + `LifecycleSpawnSuccessor`: completion spawns a successor behind a `status='open'`
  dedup guard; reopen (`completed→open`) runs `cancelRecurringSuccessors`, which cancels every open successor
  (`spawned_from=P` → `LifecycleStatus.cancelTask`, status→'cancelled'); a re-complete then finds no *open* successor,
  so the guard passes and re-spawns. Symmetric and correct.
- **H2 — transient CloudKit `serverRecordChanged` conflict escalates to quarantine → GC → divergence.** NOT a bug.
  `resolveCloudSyncPushConflict` (`CloudSyncPushConflictDecision.swift`) re-resolves every `serverRecordChanged`
  rejection by HLC LWW and CONFIRMS the outbox row in all three branches (local-wins → re-stamp + re-save; server-wins
  → confirm + apply the server winner locally; equal → confirm). A conflict never calls `recordOutboundFailure`, so it
  never advances `retry_count`. Only genuine per-record rejections escalate; transient outages are classified
  `.transient` (no escalation). `+Outbound.swift:61-66,118-140`.
- **Mobile selective-reload ".tasks/.diagnostics missing".** NOT a defect. Mobile has no persistent task-workspace pool
  (the Tasks tab self-loads via `.task(id:)`); a `.task` inbound reloads every store-published task surface via
  `.today`/`.lists`/`.calendar`. The latent exhaustiveness hazard was folded into the store-orchestration refactor
  (Phase 2, landed).
- **dist/ "committed, not gitignored".** FALSE: `git check-ignore` confirms `dist/Lorvex.app` IS ignored.
- **Mutex availability.** SwiftPM + XcodeGen floors (macOS 15 / iOS 18 / watchOS 11 / visionOS 2) == `Mutex`'s exact
  availability floor; the watch app is safe. No `@available` needed.

### Sync-core auditor HIGH/MED list (a17fab61) — assessed 2026-07-12; only M4 was real (now landed, above)
- **M1 replacement-DB backfill skipped on an identity blip** — COVERED. The instance-id check
  (`+FullResync.swift:91-96`, `+AccountGate.swift:388-393`) is the already-verified-sound SYNC-HIGH-2 fix
  (regression-tested, in PROVEN SOUND). A blip (`databaseInstanceIdentifier()` → nil) is CONSERVATIVE: it excludes
  non-matching checkpoints → treats the state as replaced → backfills; it does not skip.
- **M2 zone-epoch regression** — CLEARED. The current
  `beginZoneRebuild(atLeast:ownerIdentifier:boundaryGuard:)` CAS claim reads the surviving server generation and
  chooses a strictly greater epoch; the local enrollment is only completed after the same lease publishes `ready`.
  The `atLeast:` floor remains an extra guard, so a floor read blipping to 0 cannot regress the server generation.
- **M3 LWW-refused permanent delete → partial destruction** — CLEARED (mis-framed). `permanentDeleteTask` REQUIRES the
  task be pre-archived (`archive_task` is a separate step — no "archive+hard-delete" atomicity here); it does
  child-cleanup + an LWW-gated parent hard-delete in the caller's transaction, and a local delete uses a fresh
  dominating `hlc.nextVersionString()` so the parent always deletes (children never orphaned). The LWW gate is for the
  sync-apply path, not local deletes. `TaskPermanentDelete.swift:82,111-122`.
- **M5 habit streak denominator mismatch** — non-issue. Streaks are consecutive-period counts, no denominator; the
  streak-quota correctness was already landed as H1 (Wave 1). The adherence-denominator bug was the separate
  `completionRate30d` fix (`2e07084ef`, above).
- **M6 memory-restore key hijack** — DONE wave-2 (`91eb43f2f`, above).
- **M7 factory-reset install-identity race** — COVERED. Install-identity resolution is serialized by the #6
  `withMintLock`, and a factory reset holds the exclusive cutover lock (ACF-18 fail-closed), so reset (marker removal)
  and a concurrent open (mint under the shared cutover + mint lock) can't race. `ManagedInstallIdentity.swift:67,136`.

---

## Accepted / WONT-FIX (recorded; no action)

- **P5 22s push-drain cancel** — the inner detached CloudKit work doesn't observe cancellation by design; bounded (one
  utility-priority cycle), self-healing via the durable push handoff + idempotent inbound apply.
- **CloudKit adopt runs backfill / clears checkpoint before the nil-account guard** (LOW-MED) — the pause lifts only
  after the guard, so no leak; it can churn durable markers on a transient nil. Assessed and accepted; revisit only if
  observed in the field.

---

## Deferred — Tauri (not a current release target; NOT superseded)

- Cross-runtime destructive-migration alignment — before any first numbered destructive migration, confirm the Tauri
  runner applies the baseline only to a fresh DB and doesn't refuse a dropped baseline object. Ladder is empty at the
  prelaunch freeze; low urgency.
- 3 pre-existing Tauri frontend test failures (`looksLikeBackendInternal`, quickCapture call-shape) — unrelated to
  Apple; fix when Tauri returns to a release footing.
