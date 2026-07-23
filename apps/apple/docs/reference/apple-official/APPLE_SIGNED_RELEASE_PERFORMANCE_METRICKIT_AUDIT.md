# Apple Signed-Release Performance and MetricKit Audit

Last verified: 2026-07-10  
Code snapshot: `b9acca441c0a72325f2bcd9764a81e98294fc91e`

This is a static audit of Release archive launch-to-first-usable-data,
foreground refresh, background CloudKit execution, resource fan-out, MetricKit
coverage, performance tests, and exact signed-artifact evidence. It does not
claim that an operation is
slow merely because it performs substantial work. The actual p50/p90 latency,
memory, energy, and disk-write results still need to be measured on Release
archives and physical devices.

## Apple Contract

- Apple's launch metric ends at the first drawn frame, but the user may still be
  waiting for content or controls after that point. Measure both time to first
  frame and the app-defined time to the first locally usable screen.
- Launch behavior varies across cold, warm, prewarmed, partially evicted, device,
  and OS conditions. Organizer exposes typical and 90th-percentile field data;
  Instruments' App Launch template explains where the time went.
- Apple treats main-run-loop stalls over roughly 250 ms as potential hangs.
  Organizer exposes p50/p90 hang rate, while MetricKit can deliver launch,
  resume, responsiveness, memory, CPU, disk, energy, and termination data.
- `OSSignposter` is the current API for attaching product-operation intervals to
  Instruments. The legacy signpost symbols are deprecated.
- Apple recommends `XCTStorageMetric` for disk-write regression tests. XCTest
  also provides launch and resource metrics; a wall-clock microbenchmark is not
  an equivalent artifact-level test.
- iOS background execution is a lease, not an independent worker lifetime.
  Returning the background completion result while work continues does not
  guarantee that the OS lets that work finish. Task-timeout and App-Group file-
  lock terminations are explicitly visible in Apple's termination metrics.
- In the June 2026 SDK, `MetricManager` replaces `MXMetricManager` and its
  subscriber protocol. The new manager uses asynchronous metric and diagnostic
  report sequences. A lower deployment target requires an availability-gated
  new/legacy adapter rather than deleting the legacy path.

Primary sources:

- [Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time)
- [Analyzing the performance of your shipping app](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-shipping-app)
- [Analyzing responsiveness issues in your shipping app](https://developer.apple.com/documentation/xcode/analyzing-responsiveness-issues-in-your-shipping-app)
- [Understanding hangs in your app](https://developer.apple.com/documentation/xcode/understanding-hangs-in-your-app)
- [Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes)
- [Reducing terminations in your app](https://developer.apple.com/documentation/xcode/reduce-terminations-in-your-app)
- [MetricKit updates](https://developer.apple.com/documentation/updates/metrickit)
- [MXMetricManagerSubscriber](https://developer.apple.com/documentation/metrickit/mxmetricmanagersubscriber)
- [MXAppLaunchMetric](https://developer.apple.com/documentation/metrickit/mxapplaunchmetric)
- [MXMemoryMetric](https://developer.apple.com/documentation/metrickit/mxmemorymetric)
- [OSSignposter](https://developer.apple.com/documentation/os/ossignposter)
- [Recording performance data](https://developer.apple.com/documentation/os/recording-performance-data)

## Existing Strengths

- Mac and mobile refresh bodies are single-flight and retain one pending rerun,
  avoiding overlapping broad refreshes and stale-last-writer publication.
- SQLite/core service opening is lazy. App construction itself does not
  synchronously open and migrate the production database before SwiftUI can
  create its first frame.
- Independent local reads are frequently expressed with `async let` and the
  Mac refresh reuses one up-to-5000-task corpus across task Spotlight,
  notifications, and badge calculation.
- Background CloudKit push handling durably records unfinished work before
  attempting a bounded drain. A 22-second application deadline leaves margin
  inside Apple's approximate remote-notification budget.
- Cloud sync applies pacing/backoff and drains multiple inbound pages rather
  than requiring one OS wake per page.
- The repository contains useful database/query, widget projection, exporter,
  MCP dispatch, and document-construction microbenchmarks. They are valuable
  developer guardrails even though they are not release acceptance evidence.
- Release scripts perform strong structural checks: Mach-O closure, nested
  bundle layout, signing/entitlement verification, privacy manifests, helper
  stdio smoke, and provisioning checks in the relevant packaging paths.
- Selected crash, hang, CPU-exception, and disk-write-exception MetricKit
  diagnostics are stored locally. No application upload path was identified.

## Findings

### P1 — HIGH — The iPhone's first local data is gated by CloudKit network work

`MobileStore.performRefresh()` first awaits subscription registration and then
an entire CloudKit draining cycle. Only after both complete does it set
`isLoading = true` and read SQLite. The root view starts this refresh when the
initial Today snapshot is empty.

Consequences:

- a local-first product can show no local tasks while waiting for iCloud account
  and network operations;
- the first-load skeleton is keyed by `isLoading`, but that flag remains false
  during the network-preface, so the blank/empty presentation can precede the
  skeleton;
- offline, throttled, slow-account, and large-backlog conditions directly extend
  time to first usable local data even though the database is already present;
- the same order applies to ordinary foreground refresh, so local UI freshness
  waits for remote convergence.

Evidence:

- `Sources/LorvexMobile/MobileStoreRuntimeActions.swift:45-49`
- `Sources/LorvexMobile/LorvexMobileStoreRootView.swift:76-82`
- `Sources/LorvexMobile/LorvexMobileStoreCloudSyncActions.swift:306-325`

The Mac is better but still not local-first: its refresh awaits CloudKit
subscription installation before starting local loads, while its full sync cycle
runs later. Once the per-install subscription marker exists this is usually a
no-op, but first launch, account change, or failed registration still gates local
content.

Release condition: split refresh into a critical local snapshot phase and
secondary convergence/publication phases. The existing local snapshot should
be usable without network; CloudKit may update it immediately afterward. Set
the initial-loading state before any awaited work and measure both first frame
and first local content under offline, throttled, and large-backlog conditions.

### P2 — HIGH — Every broad refresh unconditionally republishes unrelated system surfaces

Mac refresh loads the primary UI, reloads the current calendar window, queries
selected-list and task-workspace state, runs per-habit statistics, reads up to
5000 tasks, replaces task/list/habit/review/calendar Spotlight content,
reschedules task and habit notifications, updates the badge, writes the widget
snapshot, and runs CloudKit. Calendar Spotlight alone reads a 183-day past plus
365-day future window.

Mobile refresh runs CloudKit first, ingests EventKit, reloads local planning
snapshots, writes a widget snapshot, replaces reminder schedules, and updates the
badge. This broad body is triggered from launch, foreground/manual refresh,
database-change signals, CloudKit pushes, and numerous mutations.

There is coalescing, but no domain-dirty or local-change-sequence gate around the
whole publication fan-out. Stable Spotlight identifiers reduce semantic risk;
they do not make repeated full indexing, EventKit ingestion, notification
replacement, App-Group snapshot writes, and CloudKit requests free.

Additional amplification:

- Mac `loadAllHabitStats()` performs one awaited query per active habit;
- Mac Spotlight recreates the full content sets and reads a 548-day calendar
  horizon on refresh;
- refresh can rerun once when any trigger arrives mid-flight, repeating the
  complete fan-out;
- multiple Mac UI stores can retain their own snapshot/cache state even though
  only the app-level store should own process-wide publication.

Evidence:

- `Sources/LorvexApple/Stores/AppStoreRuntimeLifecycle.swift`
- `Sources/LorvexApple/Stores/AppStoreAppleSurfacePublishing.swift`
- `Sources/LorvexApple/Stores/AppStoreHabitActions.swift:146-158`
- `Sources/LorvexMobile/MobileStoreRuntimeActions.swift:45-91`
- `Sources/LorvexMobile/MobileStorePlanningActions.swift:5-30`

This is a confirmed composition problem, not a measured claim about present
latency. Release condition: establish one process-wide refresh planner with
dirty domains and time invalidation. Separate at least UI snapshot, calendar
mirror, Spotlight, reminders, badge, widget, and CloudKit. An activation with an
unchanged `local_change_seq`, no due time boundary, no EventKit notification,
and no push should not rewrite or reindex every surface.

### P3 — HIGH — MetricKit is diagnostic-only despite broader observability claims

`MetricKitDiagnosticsSubscriber.didReceive([MXMetricPayload])` is deliberately
empty. Lorvex therefore discards the daily aggregate payload that carries the
field evidence needed for:

- launch, extended launch, and resume time;
- app responsiveness/hang rate and animation behavior;
- peak and suspension memory;
- foreground/background exits and their termination reasons;
- CPU, disk writes, network transfer, and energy-related metrics.

The selected crash/hang/CPU/disk exception diagnostics are useful, but they do
not answer whether a new release made normal launches slower, memory larger, or
activation refresh more expensive. Xcode Organizer may still expose Apple's
aggregated view when enough users share diagnostics; Lorvex's local diagnostics
screen cannot.

Evidence: `Sources/LorvexCore/Services/MetricKitDiagnosticsSubscriber.swift`.

Release condition: either narrow product/docs claims to “selected local
diagnostics” or retain a bounded, privacy-reviewed summary of the field metrics
that have explicit budgets. Do not write these summaries to CloudKit or make
them part of the user-data schema. Version the local report envelope separately
from synced domain data.

### P4 — HIGH observability gap — No operation signposts connect symptoms to the refresh pipeline

No `OSSignposter`, `XCTOSSignpostMetric`, or equivalent current signpost usage was
found. A hang or disk diagnostic can show a stack sample, but there is no stable
product phase for DB open/migration, local snapshot, CloudKit push/pull/apply,
EventKit ingest, Spotlight replacement, reminder replacement, widget publish,
import/export, or database cutover.

Because the refresh body composes many independently expensive operations,
ordinary logging is insufficient to reconstruct overlap and duration in
Instruments. Adding legacy `os_signpost` calls now would create fresh
deprecation debt; Apple's current API is `OSSignposter`.

Release condition: define a small, privacy-safe interval vocabulary. Include
counts, result classes, and dirty-domain bits, never titles, notes, record IDs,
paths, or calendar contents. Ensure every interval ends on success, error, and
cancellation. Validate the exact Release configuration in Instruments.

### P5 — MEDIUM-HIGH — The 22-second deadline bounds the await, not the CloudKit work

The background push race returns at the deadline and cancels the losing task.
The code explicitly records that detached CloudKit work does not observe that
cancellation and may keep running best-effort after the completion result has
been returned to the OS.

Durable handoff prevents logical data loss and the handler no longer blocks past
the application deadline. Those are strong properties. The remaining problem is
resource/lifecycle truth: once the delegate reports completion, the app cannot
assume the process remains runnable. A still-running cycle can retain runtime
state, touch the App-Group database/checkpoint, or be suspended at an arbitrary
point. Current tests prove prompt return and durable retry; they cannot prove
that work stopped within the lease.

Evidence:

- `Sources/LorvexMobile/MobileStoreCloudSyncActions.swift:193-258`
- background-push deadline tests under `Tests/LorvexAppleTests`

Release condition: propagate an absolute deadline/page budget into the draining
coordinator and stop scheduling new CloudKit pages before returning. Treat
cancellation of in-flight framework calls as best-effort, but await cleanup of
Lorvex-owned tasks/state within the lease. Record deadline cutoffs and verify
that no database/checkpoint lock remains when the completion handler returns.
Use Organizer/MetricKit termination data to monitor task-timeout, memory, and
App-Group file-lock exits.

### P6 — HIGH release-evidence gap — The exact shipping iPhone and MAS artifacts are never launched

The iOS archive/export path validates archive and exported-IPA Mach-O closure,
but does not install and launch the exported signed IPA. The Debug simulator
gate intentionally skips install/launch for `LorvexMobileApp` when its required
Watch companion is embedded, because a standalone iPhone simulator is not a
valid pair. As a result, the primary iPhone app currently has build/bundle
evidence but no aggregate-gate launch smoke.

The MAS script packages, checks signatures/profiles/entitlements, and can submit
validation/upload, but it does not install the produced `.pkg` into a clean test
volume/account and launch the exact installed app. `archive_local.sh` does launch
Developer ID/local archives, but a process appearing in `pgrep` is only a basic
smoke. It does not prove the first locally usable screen, database migration,
post-launch stability, offline behavior, nested helper access, or performance.

Evidence:

- `script/archive_ios.sh:280-380`
- `script/verify_xcode_simulator.sh:76-129`
- `script/archive_mas.sh:67-140`
- `script/archive_local.sh:123-169`

Release condition: install the exact exported development/ad-hoc iPhone artifact
on a physical supported device or a correctly paired simulator workflow, and
install the exact signed Mac package into a clean test account/environment.
Capture a readiness marker after DB open/migration and first local content, not
only process existence. App Store distribution builds may require TestFlight or
Apple's installation path for the final proof; preserve the build/version and
artifact hash with the evidence.

### P7 — MEDIUM-HIGH — Existing benchmarks cannot prevent shipping regressions

The benchmark suites are opt-in through `LORVEX_BENCH`; an ordinary test run
skips them. No CI invocation was found. The Apple-layer suite uses `Date()` wall
clock, drops the cold result, and enforces warm medians only. Most dependencies
are in-memory or fake, and the suite measures projections/rendering rather than
actual system publication.

Examples:

- the AppStore refresh benchmark uses a seeded in-memory database and cannot
  exercise production CloudKit, EventKit, Spotlight, notifications, or file I/O;
- the Spotlight benchmark builds search documents but does not call the actual
  Core Spotlight index;
- export benchmarks render one format from a 1000-task payload but do not include
  data collection, ZIP creation, file coordination, peak memory, or writing;
- no XCTest launch, memory, CPU, storage, or signpost metric was found;
- cold DB open/migration, large on-disk stores, long sync backlogs, exact Release
  binaries, p90/p95 tails, and interruption/background cases are absent.

The core database benchmarks remain useful microbenchmarks and should not be
deleted. Release condition: keep deterministic microbenchmarks as one lane and
add a separate archive/device acceptance lane. Use a monotonic clock for custom
timing and record distribution/tail values; use XCTest metrics where they
measure the intended resource directly.

### P8 — MEDIUM — Memory and disk pressure have no end-to-end budget

The broad Mac refresh can hold Today/list/task/habit/review/calendar snapshots,
up to 5000 surface tasks, and a 548-day Spotlight calendar query while multiple
windows retain UI state. Mobile also combines local snapshots with EventKit,
widget, reminder, and sync work. The separate import/export audit found archive
memory limits that need hostile-input testing.

No source proof shows that current hardware exceeds a memory limit. The release
risk is that neither peak/suspension memory nor logical disk writes are measured
as an acceptance budget, and aggregate MetricKit memory/disk data is discarded.
That makes regressions invisible until Organizer has enough field data or the OS
terminates a process.

Release condition: define dataset tiers and measure peak memory, suspension
memory, App-Group/SQLite writes, widget snapshot writes, sync checkpoint writes,
Spotlight rebuild, import/export, and multi-window usage. Include an oldest-
supported iPhone and a baseline Apple-silicon Mac. Exercise memory warning,
background suspension, and relaunch restoration.

### P9 — MEDIUM deprecation gate — The only MetricKit integration is already deprecated

The 2026 SDK marks `MXMetricManager`, `MXMetricManagerSubscriber`, and legacy
payload types deprecated in favor of `MetricManager`. Lorvex directly conforms
to the deprecated subscriber, so the deprecation is isolated but process-wide.
This is not a reason to raise the deployment target to OS 27 or abandon older
supported systems.

The prior `METRICKIT.md` classified this as low-severity future work. Given that
the deprecated API is Lorvex's only shipped performance/diagnostic receiver and
the user explicitly wants deprecations removed before finalization, it should be
an Xcode 27/toolchain adoption gate: create an availability-gated adapter using
`MetricManager` on OS 27+ and retain the MX subscriber below that floor. Probe
beta warnings and concurrency isolation before the next required submission SDK.

### P10 — LOW-MEDIUM — Local diagnostic persistence loses fidelity silently

Each mapped diagnostic is written from a separate unstructured detached task;
write errors are discarded. The details field is subject to the `error_logs`
ring's size/retention policy. A large diagnostic JSON representation can be
truncated mid-document, losing the useful call-tree tail and ceasing to be valid
JSON, while the compact message contains only a few extracted scalars.

Bounded local retention is the correct privacy/storage direction. The weakness
is not that every raw report must be kept; it is that the current representation
does not guarantee a stable actionable signature before truncation. Extract a
privacy-reviewed summary (binary/version, termination category, dominant call-
stack signature, duration/resource value, report timestamp) before applying a
size cap, record persistence failures as a bounded counter, and avoid one
uncoordinated database task per item.

## Required Measurement Matrix

The numbers should be baselined on real artifacts, then approved and frozen by
the product owner. Apple does not supply one universal latency or memory budget
for this app, so this audit deliberately does not invent pass/fail thresholds.

| Operation | Conditions | Required evidence |
| --- | --- | --- |
| First frame | cold, warm, force-quit, partial eviction | XCTest/Organizer p50 and p90 plus App Launch Instruments trace |
| First locally usable screen | empty DB, normal DB, large DB, migrated DB; online/offline/throttled iCloud | Lorvex readiness signpost and screen assertion |
| Foreground activation | unchanged DB; MCP write; remote change; midnight/time-zone change | phase signposts, p50/p90, network/write/index counts |
| SQLite open/migration | current schema and every supported upgrade fixture | elapsed, peak memory, logical writes, rollback/recovery result |
| Cloud sync | 0, 1, 100, and large multi-page backlogs; failure/retry/account switch | per-phase duration/counts and deadline behavior |
| EventKit | off/denied/authorized; small and large provider calendars | ingest/query duration, changed versus unchanged writes |
| Spotlight | incremental change and full rebuild at dataset tiers | elapsed, peak memory, indexed/deleted count, failure recovery |
| Reminders/badge/widget | unchanged activation, time-bound refill, mutation, inbound sync | duration, system-call/write count, resulting correctness |
| Import/export | small/normal/adversarial archives | wall time, peak memory, disk writes, cancellation, atomicity |
| Multi-window Mac | main plus several task/list windows | peak/resident memory, refresh duplication, DB cutover |
| Background push | small/large/stalled CloudKit and App-Group contention | completion time, post-return work absence, termination metrics |

Use at least the oldest supported iPhone hardware class available to the team and
a baseline Apple-silicon Mac. A fast current flagship alone cannot establish the
tail experienced by the supported install base.

## Minimal Signpost Vocabulary

Keep the vocabulary small enough to remain stable across refactors:

- `app.firstLocalContent`
- `database.open`, `database.migrate`, `database.replace`
- `refresh.total`, `refresh.localSnapshot`, `refresh.secondarySurfaces`
- `cloud.subscription`, `cloud.push`, `cloud.pull`, `cloud.apply`
- `eventkit.ingest`
- `spotlight.replace`
- `notifications.replace`, `widget.publish`, `badge.update`
- `archive.import`, `archive.export`

Metadata may include bounded counts, dirty-domain flags, database-generation
number, and result category. It must not include user-authored text, record IDs,
calendar titles, file paths, or other private content.

## Release Gate

Before App Store finalization:

1. Make local content independent of CloudKit latency and instrument first local
   usability.
2. Split broad refresh into domain-gated work and prove unchanged activation
   does not republish everything.
3. Add current `OSSignposter` intervals and set explicit p50/p90/resource budgets
   after baselining.
4. Turn the useful microbenchmarks into a reliable automated lane, then add
   signed-archive/device acceptance tests with XCTest resource metrics.
5. Make the background-push deadline bound Lorvex-owned work, not only the
   caller's await.
6. Retain the MetricKit data required to evaluate the approved budgets, locally
   and privacy-bounded, or explicitly rely on archived Organizer evidence.
7. Add the OS 27 `MetricManager` path while retaining the legacy path for the
   deployment floor.
8. Install and exercise the exact exported iPhone and Mac artifacts, preserving
   artifact hashes, build versions, traces, and results as release evidence.

None of these performance/observability changes requires a CloudKit record-type
or synced SQLite-domain schema change. Keep measurement envelopes and diagnostic
summaries local and separately versioned so observability work cannot create the
data-schema compatibility debt this finalization effort is trying to avoid.
