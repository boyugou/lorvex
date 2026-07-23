# Lorvex Apple — Surface Design Spec

This document defines what each Apple surface *should be*, the role it plays in
the product, and the bar for "done." Lorvex is an AI-first planner: the MCP host
is the primary **write** interface; the apps are the **read / review / focus /
capture** surfaces with low-friction human actions. Every surface is scoped to
what that device is genuinely good at — not a uniform port of the macOS app.

The right-hand "Status" column reflects the honest audit: ✅ done,
◑ partial, ✗ missing.

---

## macOS — the command center

The full instrument panel. This is where a user reviews everything, plans the
day, works the current focus plan, and drives keyboard-first workflows.

- Sidebar with the active workspaces — Plan group: Today, Calendar, Tasks;
  Reflect group: Habits, Reviews, Memory (⌘6). ✅ Lists have no sidebar row:
  they are managed inline, with the catalog reached via ⌘K. The current focus
  plan and time-blocked schedule live inside Today.
- Multi-window: detached list windows, dedicated workspace windows, and floating
  task "stickies". ✅
- Menu bar extra: a Today HUD — date + due-count, quick-add, next-up task list
  with one-click complete, and Open / Refresh / Quit. ✅
- Full command menus + keyboard shortcuts. ✅
- Command Palette (⌘K): fuzzy command and navigation palette. ✅
- Settings: tabbed (General, Assistant, Calendar, Cloud Sync,
  Diagnostics, Data, Permissions). ✅
- Habit streak metrics + calendar heatmap in the habits workspace. ✅
- Habit milestone waypoints (streak/count auto-ladder + optional user target) with
  a progress bar, a goal picker, and a celebration when a waypoint is crossed on
  both macOS and the iPhone/iPad habit surfaces. ✅
- Eisenhower matrix: urgency/importance quadrant view. ✗ (MCP-data-only; no
  macOS human surface — `WorkspaceView` redirects `.eisenhower` to Today.)
- Dependency-graph workspace: task dependency graph. ✗ (MCP-data-only; no
  macOS human surface — `WorkspaceView` redirects `.dependencies` to Today.)
- List and habit drag reordering with persistence. ✅
- Global transient error toast. ✅
- Calendar week/list navigation with Today/This Week reset. ✅
- Workspace loading states for async panes. ✅
- Weekly-review editable notes, auto-saved locally per review window. ✅

## iPhone — capture, glance, focus

Thumb-first. The phone is for *getting things in* and *staying on the current
focus*, not deep editing. Tab-first with `NavigationStack`.

- Tab bar is Today · Tasks · Calendar · Habits · More — the daily-driver surfaces
  are first-class, not buried. The current focus plan and time-blocked schedule
  live inside Today (interleaved with EventKit). ✅
- Quick capture is a global ＋ (a sheet) raised from the Today / Tasks toolbars,
  the task empty-state, and ⌘N — capture is an action, not a tab. ✅
- Real task detail + edit sheet; create sheets for task/list/habit/event. ✅
- More holds the secondary surfaces: Memory, Review, and Settings; Lists
  live in the Tasks tab home. ✅
- Settings, diagnostics, privacy and acknowledgments, data export/import, and notification toggles. ✅
- A read-only "Recent Diagnostics" list on Settings, backed by the MetricKit
  subscriber that persists crash/hang/CPU/disk diagnostics into `error_logs`. ✅

## iPadOS — the middle instrument

Keyboard- and pointer-aware; closer to macOS than iPhone. Should exploit the
larger canvas, not stretch the phone.

- `NavigationSplitView` for regular width with a full workspace sidebar. ✅
- Detail column routes primary tabs and secondary workspaces independently. ✅
- Tasks workspace uses a query-backed status/search browser; on iPad regular
  width it presents a persistent task list and detail pane instead of stretching
  the phone push flow. ✅
- Calendar uses a regular-width agenda workspace: the 3-day time grid remains
  primary while a pinned agenda inspector exposes visible events and quick
  create/edit affordances. ✅
- Lists uses a regular-width split workspace with the list catalog pinned beside
  the selected list's task/progress detail. ✅
- Habits uses a regular-width split workspace with the active habit catalog
  pinned beside progress metrics and completion/edit/delete controls. ✅
- Memory uses a regular-width split workspace with save controls and a complete
  memory catalog pinned beside selected content, metadata, and delete controls. ✅
- Hardware-keyboard shortcuts: ⌘R, ⌘N, ⌘1-⌘5, ⌘8, and mnemonic keys (⌘M/⌘E/⌘,). ✅
- **Bar for done:** keep tuning density, visual hierarchy, and pointer/keyboard
  ergonomics across the shipped iPad workspaces.

## Apple Watch — wrist glance + one-tap focus

Glanceable current focus plan and one-tap actions (complete, defer, capture).
Complications on the face.

- Root view: focus task, queue, capture, complete/defer. ✅
- Complication (circular/rectangular/inline/corner). ✅
- On device, the watch reads the App Group snapshot and forwards mutations to
  the phone through `WCSession`; the phone applies the write and publishes a
  fresh snapshot. ✅ Snapshot-only previews remain read-only by design.
- Phone-pushed snapshots write into the watch App Group and reload WidgetKit
  timelines immediately; complication providers also use periodic refresh
  policies when no push arrives. ✅
- Digital Crown navigates the queued focus tasks so secondary items can be
  completed/deferred without hidden gestures. ✅

## Widgets — multiple kinds, configurable, interactive

A productivity app earns its home screen with more than one widget.

- Focus widget (small/medium/large + accessory), interactive complete on
  medium/large. ✅
- ControlWidget (iOS 18) shows the current focus task and opens the app to
  Today when tapped. ✅
- Today, Habits/streak, and daily-progress widgets, with `accessoryCircular`
  gauges and deep links. ✅ Today widget uses `AppIntentConfiguration` so users
  can choose Today tasks or Focus queue and optionally filter with a native
  list picker; filtered widgets use list-scoped counts. ✅

## Menu bar (macOS) — a Today HUD

- A `.window`-style menu-bar extra: a date header with a due-today/overdue
  count (also appended to the menu-bar glyph), a one-line quick-add (Return
  creates an inbox task), a "Next Up" list of today's open tasks with one-click
  completion, and a footer (Open Lorvex / Refresh / Quit). ✅ Considered done.

## CarPlay — hands-free Today/Focus

Zero text entry. Glanceable list of today's / focus tasks. A row tap opens a
short action sheet — Complete, Defer to Tomorrow, Remove from Focus (focus rows
only), Open on iPhone (Handoff) — so a single tap can never accidentally close a
task. Siri-driven voice intents are a tracked follow-up.

**Status:** Code present, provisioning required. The controller and scene
delegate are implemented and fully tested; the CarPlay scene is silently ignored
at runtime until Apple approves the CarPlay entitlement for the Lorvex App ID.
No further code changes are needed to activate CarPlay once the entitlement
is granted and merged into the iOS app target.

### What is built

- `CarPlayTaskListController` (Sources/LorvexCarPlay/) — platform-independent
  controller (no CarPlay import) that loads Today tasks and the current focus
  plan tasks via `LorvexCoreServicing`. Exposes `refresh()`, `complete(id:)`,
  `deferToTomorrow(id:)` (defers to the local next day, UTC-anchored per
  `PlannedDayBridge`), and `removeFromFocus(id:)` (un-focuses only — the task
  stays open and returns to Today). Fully tested headlessly
  (`CarPlayTaskListControllerTests`).
- `LorvexCarPlaySceneDelegate` (Sources/LorvexCarPlay/) — `CPTemplateApplicationSceneDelegate`
  presenting a `CPListTemplate` with Focus, Today, and retry/error sections as
  needed. A row tap presents a `CPActionSheetTemplate` (Complete / Defer to
  Tomorrow / Remove from Focus / Open on iPhone / Cancel) rather than mutating
  on tap. Rows are capped to `CPListTemplate.maximumItemCount` (Focus first,
  then Today) for the driving-safety limit, and an "All clear" empty-state row
  shows when nothing is due. Failures map to driver-safe retry text and refresh
  the template. Each CarPlay callback hops to the main actor explicitly because
  `CPListItem`/`CPAlertAction` handlers are not `@MainActor`-isolated.
  Guarded by `#if canImport(CarPlay) && os(iOS)`.
- `Config/LorvexCarPlay.entitlements` — entitlement template; see provisioning
  note below.
- `Config/LorvexMobileApp-Info.plist` — documents the `CPSupportsTemplateApplicationScene`
  and `UIApplicationSceneManifest` keys (in a comment block); uncomment once
  the entitlement is approved.

### Provisioning checklist (Apple approval required)

1. At developer.apple.com → Certificates, Identifiers & Profiles → App ID
   `com.lorvex.apple.mobile` → Additional Capabilities, request CarPlay
   (choose the category Apple approves — Navigation / Maps, or General).
2. Once approved, merge `Config/LorvexCarPlay.entitlements` keys into
   `Config/LorvexMobileApp.entitlements`.
3. Uncomment the `CPSupportsTemplateApplicationScene` block in
   `Config/LorvexMobileApp-Info.plist`.
4. Set `UISceneDelegateClassName` to
   `LorvexCarPlay.LorvexCarPlaySceneDelegate` (module-qualified) or expose
   the class into the app module.
5. Rebuild and re-sign with an approved provisioning profile.

Without step 1 the CarPlay scene is silently ignored. The code compiles and
all tests pass without the entitlement.

### SiriKit voice path (follow-up, not built)

Wire `INCompleteTaskListIntentHandling` in a separate `LorvexSiriIntents` app
extension target. The intent handler delegates to `CarPlayTaskListController`
to resolve tasks by voice-matched title and calls `complete(id:)`. Phrases:
"complete [task name] in Lorvex", "what's next in Lorvex". Tracked here; not
blocked by the CarPlay entitlement.

## Notifications & permissions — clear request, denied fallback, escape hatch

- Reminder scheduling + rich notification actions (complete/defer/snooze) on
  macOS and iOS. ✅ Rich actions route complete/defer/snooze on both app
  shells. ✅
- Onboarding permission steps for Calendar/Notifications. ✅
- Permissions status panel with denied-state Open Settings recovery. ✅
- App-icon badge for overdue/due-today tasks on macOS, iOS, and visionOS app
  entry points. ✅
- `EKEventStoreChanged` observer refreshes external calendar edits without a
  manual refresh. ✅

## EventKit — macOS write-back, read-only ingest elsewhere

- Calendar import (read), Lorvex-native calendar create, and ICS export on every
  platform. ✅
- **Write-back to the system Calendar is macOS-only.** On macOS, Lorvex-
  originated calendar events are written into a dedicated Lorvex EventKit
  calendar and create/update/delete propagate back to the matching `EKEvent`.
  iPhone/iPad/visionOS are read-only: they ingest the system calendar for
  display and planning and create Lorvex-native events only — they never write
  to Apple Calendar. ✅
- External provider-owned EventKit events remain read-only mirrors on every
  platform by design. ✅
- The external EventKit mirror (`provider_calendar_events`) is a device-local,
  rebuildable cache and is never CloudKit-synced — the system Calendar syncs
  itself. ✅
- `EKEventStoreChanged` observer refreshes the local mirror. ✅
- EventKit ingest honors persisted per-calendar include/exclude filters before
  provider events enter the local mirror. ✅
- Calendar settings expose a native calendar picker with all-except
  and only-selected modes for EventKit mirroring. ✅

### Field-fidelity limits (current behavior, not overclaimed)

- **Recurrence:** macOS ingest maps only an event's first recurrence rule, and
  write-back emits a single recurrence rule; iPhone/iPad/visionOS ingest does
  not map recurrence rules at all (recurring external events mirror as their
  individual occurrences).
- **Attendees:** participants without a parseable email address are dropped
  (the attendee projection keys on email).
- **Privacy tier:** each device defaults to Busy Only — provider events
  contribute occupancy for planning without storing or showing event detail.
  Settings exposes Off / Busy Only / Full Details explicitly; Full Details is
  never selected implicitly. The tier applies to Lorvex and connected
  assistants on that device. It is device-local, while the per-calendar filter
  separately chooses which Apple calendars are mirrored.

---

## Build priority (highest user-visible impact first)

1. **Apple Watch polish** — writes and live snapshot push are shipped; continue
   improving glance navigation and on-device ergonomics.
2. **iPhone/iPad full workspace reach** — shipped; continue polishing iPad
   workspace-specific layouts and keyboard ergonomics.
3. **Widgets** — Today + Habits + progress widgets, configurable, interactive
   complete.
4. **CarPlay** — new surface.
5. **UI/UX polish** — loading states, error toast, reordering, calendar date
   nav, habit streaks.
6. **Notifications/permissions** — denied-state recovery, iOS scheduling parity,
   badge.

---

## CloudKit two-way sync — production requirements

The sync layer is implemented and settings-driven (Settings > iCloud Sync Mode).
The following remain as external provisioning or on-device verification tasks
and cannot be tested in the local simulator:

### CloudKit container provisioning (App Store Connect)

- Container `iCloud.com.lorvex.apple` must be registered and associated with
  the App ID before the `.live` mode can write to it.
- Deploy the complete checked-in `cloudkit/schema.ckdb` contract, not only
  `LorvexEntity`. `LorvexEntity` carries encrypted envelope fields
  (`entity_type`, `entity_id`, `operation`, `version`,
  `payload_schema_version`, `payload`, `device_id`); the remaining record types
  are protocol-v3 zone control, protocol-v2 generation-root/seal,
  traversal-witness,
  audit-retention, purge, and wake records.
- Development may learn record types while exercising a provisioned build, but
  an App Store build cannot rely on runtime schema creation. Promote the tested
  Development schema to Production in CloudKit Console before submission and
  retain the exported Production schema as release evidence.
- Domain records live in per-generation custom zones. A fixed
  `LorvexZoneEpoch` control record in the private default zone CAS-selects one
  unique custom zone per generation (`LorvexData-e<epoch>-<generation-id>`).
  The client creates and retires those physical zones; no custom zone is
  provisioned manually.

### Entitlements and capabilities

- Production macOS builds targeting iCloud sync must use
  `LorvexAppleCloudKitAppStore.entitlements` (see `docs/DISTRIBUTION.md`), which
  declares the CloudKit container, `Production` iCloud environment, and
  production APS environment. `LorvexAppleCloudKit.entitlements` is the
  development-only on-device template and must never be used for the final
  Developer ID DMG or Mac App Store candidate.
- The Push Notifications capability is required for silent-push delivery of
  remote-change notifications (APNs). Without it, `CKDatabaseSubscription` is
  registered but no pushes arrive; the app falls back to manual refresh only.

### What the local simulator validates

- `CloudSyncMode` persistence and factory wiring: verified by tests.
- `CloudSyncStatusReport` aggregation: verified by tests.
- HLC comparator correctness: verified by tests.
- Tombstone encoder/decoder/applicator round-trip: verified by tests.
- Account/zone/generation/witness-bound SQLite traversal persistence, including
  atomic inbound page + successor-token commits: verified by tests.
- Settings import linearization: live mode drains every visible page, re-proves
  the exact account/generation/root/traversal witness, drains the pending inbox
  to a bounded local fixed point, and fails closed on persistent pending/corrupt
  inbound debt while one coordinator gate remains held through import. Off and
  record-plan imports do no CloudKit I/O but share the retained maintenance gate:
  verified by macOS/Mobile composition tests.
- Import completion and failure refresh already-committed inbound prefixes;
  post-terminal outbound/retention failures remain visible as ordinary sync
  error/backoff state without causing the user's import to run twice: verified
  by tests.
- Record encoding and decoding: verified by existing tests.

### Entity coverage

The live CloudKit engine drains the Swift sync outbox and applies inbound
envelopes through the same `Apply.applyEnvelope` registry used by the core sync
tests. Core planning entities (`task`, `list`, `habit`, `calendar_event`,
`memory`) have outbound upsert/delete enqueue coverage and registered inbound
appliers; child rows and edges travel either as independent sync entities or as
embedded aggregate payloads. `script/verify_cloudkit_sync_readiness.py` now
checks that this core entity coverage stays wired.

Production live sync remains gated on Apple Developer provisioning: the app ID
must own the `iCloud.com.lorvex.apple` container and the CloudKit schema must be
deployed before real private-database writes can succeed.
