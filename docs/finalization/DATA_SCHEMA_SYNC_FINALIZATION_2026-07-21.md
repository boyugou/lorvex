# Apple data, schema, sync, and production-DMG closeout — 2026-07-21

This is the evidence record for the final pre-freeze source pass after
`d2be93b0b`. It covers the Swift Apple implementation only. There are no
released users, so the canonical baseline was corrected directly and the
migration ladder intentionally remains empty.

## Product and architecture decisions pinned by this pass

- The configured product timezone is the authority for logical days. macOS,
  iPhone/iPad, Watch, widgets, CarPlay, App Intents, MCP, reminders, reviews,
  habits, focus, and calendar date windows must not independently derive a day
  from the host clock.
- Each device's main app is the only CloudKit coordinator owner. MCP, widgets,
  intents, Watch bridges, and other helpers read/write the managed SQLite store
  and atomically create outbox work; they never pull, push, delete zones, or own
  CloudKit cursors.
- Provider/EventKit rows are device-local mirrors and never enter Lorvex
  CloudKit. Canonical Lorvex calendar rows and their task/focus links do sync.
- Backup format 5 is the first public native restore contract. Import is a
  strict, all-or-nothing restore input, not a loose cross-runtime merge format.
- A DMG used for installation testing is the final production artifact: Release,
  arm64-only, Developer-ID/profile authorized, production CloudKit enabled,
  notarized and stapled. The external release harness may permanently erase all
  prior Lorvex state. It never moves, backs up, or restores that state and there
  is no test-only DMG identity.

## Confirmed defects and contract gaps closed

### Logical day, timezone, and derived surfaces

- One atomic Today snapshot now supplies the product logical day to dependent
  focus, schedule, habit, review, widget, Watch, CarPlay, calendar, and intent
  reads. Product-midnight wake tasks refresh otherwise-idle app surfaces.
- Typed preference values are canonicalized and rejected before local write,
  import, or inbound apply. The required timezone preference cannot disappear
  through a remote delete: a deterministic dominating repair restores it.
- Changing or recovering the product timezone reanchors pending task reminders;
  a late old-zone reminder arriving in the same inbound page is repaired only
  after the page's final state is known. Complete remote-authoritative snapshot
  adoption runs the same final reconciliation inside the snapshot/cursor
  transaction, so a fresh or reseeded device cannot retain an old-zone anchor.
- The required timezone row now survives all three forms of remote absence:
  typed Delete envelopes, incremental CloudKit physical deletion, and omission
  from a complete authoritative inventory. The latter two preserve the current
  canonical value and enqueue a fresh, dominating upsert; ordinary preferences
  remain exact-pruned when CloudKit proves them absent.
- Date formatting, reminder presets, EventKit fetch bounds, DST transitions, and
  Smart Stack relevance now consume the same product-zone contract.

### CloudKit outbound liveness and ownership

- Outbound is a bounded fixed-point cursor walk rather than a single 1,000-row
  page. The cursor advances by the highest raw row scanned, including poisoned
  or future-version rows, so those rows cannot hide healthy successors.
- One drain never retries its own failed row in a tight loop. Retry-wait rows
  behind an advanced cursor remain parked with their durable deadline; the next
  main-app wake starts a fresh drain and can rearm them.
- Reaching the defensive 128-page outbound ceiling is successful bounded
  progress, not a transport failure. The cycle reports a typed outbound
  continuation, preserves committed counts, leaves terminal-inbound proof
  intact, and schedules a prompt follow-up without advancing failure backoff or
  the circuit breaker. A non-advancing cursor remains an explicit failure.
- Deferred outbox and audit-purge deadlines are persisted and exposed to the
  main-app pacing layer. A stable, single app-owned wake prevents idle-app retry
  starvation while respecting exponential backoff, server retry-after, circuit
  breaking, active account, and generation boundaries.
- Audit outbox scans and wake queries share one active-account eligibility
  predicate, so durable work from a retired iCloud account cannot upload into or
  busy-loop the current account's zone.
- macOS CloudSync triggers now use serialized single-flight coalescing with a
  trailing pass; a trigger arriving during a suspended cycle is not silently
  dropped. iPhone/iPad uses the same ownership and wake semantics. After a
  same-account `CKAccountChanged` recovery, both stores immediately re-register
  their subscription and enter the ordinary sync flight; durable work is not
  stranded after an unavailable-account attempt canceled its old wake. The
  recovery path resets failure pacing immediately before that flight, after it
  has acquired the shared coordinator gate, so an older queued failure cannot
  leave the recovered account artificially backed off.
- A fresh database that first observes an iCloud account can clear only the
  exact `.accountChanged` pause snapshot it inherited while account status was
  unavailable. The compare-and-set fails closed on any concurrent pause change;
  a database actually bound to a different account still requires the explicit
  adoption/reset flow.
- A coordinator cycle that returns no report at an account/generation boundary
  no longer loses all future progress. Durable pauses and explicit
  no-account/restricted states remain quiet, while safe boundary or transient
  availability aborts retain the outbox and schedule the ordinary bounded
  retry wake on both macOS and iPhone/iPad.

### Cross-record convergence

- Deleting or archiving tasks removes invalid current-focus and focus-schedule
  references. Empty aggregate roots become real deletes; nonempty roots receive
  a dominating repaired upsert, so peers converge on the same final aggregate.
- Local authoring, overwrite import, if-absent import, and backup-v5 preflight
  also reject day-plan references to archived tasks. Trash is therefore an
  absorbing unavailable state on every ingress, not just an inbound repair.
- Deleting canonical calendar events and series segments removes synced focus
  schedule references and re-emits the affected schedule roots. Soft references
  are retained for ordinary out-of-order delivery and removed only when a
  durable tombstone proves deletion.
- Deferred equal-HLC repairs re-read the final canonical state and cannot
  overwrite a strictly newer envelope that arrived later in the same page.
- Task list-fallback re-emission claims moved out of the age-reaped diagnostics
  log into a dedicated durable ledger. Account/generation replacement clears
  that ledger because its claims belong to the superseded history.

### Schema and provider data

- Seeded Inbox/default-list timestamps now use the zero-HLC epoch instead of
  nondeterministic wall-clock values.
- `sync_outbox.payload_schema_version` enforces the nonzero UInt32 wire domain at
  the SQLite boundary.
- Redundant provider mirror columns and unused indexes were removed before
  freeze. EventKit's authoritative `source_tzid` is projected back into both
  timeline and search `timezone`, so the simplification does not discard the
  event's zone. Series reconstruction also preserves color, organizer, URL, and
  attendees for masters and detached occurrences.
- The embedded Apple schema and checksum lock remain byte-identical to the root
  Apple authority. Cross-platform/Tauri byte parity is not a product contract.

### Backup/import and production packaging

- Backup-v5 preflight rejects duplicate identities, natural-key collisions,
  dangling aggregate references, invalid focus/calendar topology, and
  task-calendar state contradictions before any apply transaction. It also
  parses every importable preference as stored JSON and runs the shared typed
  preference contract before any category can write, so a malformed setting
  cannot leave a partial restore. Programmatic apply reports the real failing
  category.
- The production DMG command fails closed on missing credentials/profiles,
  unarmed schema freeze, dirty source, non-Release or non-arm64 output, wrong
  entitlements/signatures, failed notarization, content mismatch, ambiguous or
  pre-existing release outputs, and stale release-looking symlinks.
- It installs only the app mounted from the final notarized DMG, proves content
  identity, permanently resets production App Group/defaults/private sync state,
  cold-launches that exact executable, runs the bundled production helper
  against the real App Group, resets again, and seals evidence only from the
  final clean launch. The reset and helper paths are regression-scanned for data
  move/copy/restore operations.

## Credential-free verification evidence

All of the following passed on 2026-07-21:

- Apple package: `swift build`; `swift test` — 2,664 tests in 143 suites, zero
  failures.
- Independent core package: 2,649 XCTest cases plus one Swift Testing case,
  zero failures (23 explicitly gated benchmarks skipped).
- `LORVEX_VERIFY_SKIP_PACKAGING=1 ./script/verify_all.sh` — complete Debug and
  Release product builds, core/app tests, 693 Python tests, XcodeGen/build
  matrix, schema/sync/backup/privacy/localization/hygiene/hotspot verifiers,
  local bundle closure, and MCP stdio smoke all passed.
- MCP registry/manifest: 118 unique tools; stdio create/read/error/habit/list
  smoke passed against a disposable managed database.
- Schema: embedded copy and checksum lock match; pre-launch ladder has zero
  migrations; payload contract versions 1...1 are contiguous; backup v5 freezes
  21 files and the closed 13-member ZIP inventory under the 64 MiB envelope.
- Production-DMG orchestration: 29 Python contract tests, shell syntax, packaging
  verifier, user-document verifier, and diff whitespace checks passed.

## Deliberately external release evidence

The source tree is credential-free green, but the following are not honestly
provable by unit tests and remain mandatory before calling the public artifact
released:

1. Promote the checked-in CloudKit contract to Production and retain console
   evidence; validate real account switching, zone deletion/recreation, offline
   conflict, retry wake, and multi-device convergence with production accounts.
2. On the exact first-public-release commit, arm
   `schema/migration_policy.json` with `verify_schema_freeze.py --arm`. Do not
   arm earlier: there is no released baseline to preserve, and doing so would
   manufacture migration debt while source work is still changing.
3. With the real Developer ID identity, three production provisioning profiles,
   notary credentials, and a clean worktree, run `package_dmg.sh`. Retain the
   versioned DMG, checksum, notarization/profile/signature evidence, destructive
   reset evidence, and final installed-app runtime evidence.
4. Generate Xcode's privacy report from the exact signed archive and reconcile
   every embedded Swift package contribution with App Store Connect answers.

Until those four external steps are complete, the accurate statement is
"source-finalized and credential-free-gated," not "production validated."
