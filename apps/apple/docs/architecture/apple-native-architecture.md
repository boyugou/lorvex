# Apple-Native Architecture

## Goal

Lorvex Apple is the native Apple-ecosystem edition of Lorvex. It targets macOS
first and expands to iOS, iPadOS, WidgetKit, App Intents, Shortcuts, Spotlight,
CloudKit, and EventKit without carrying Windows, Linux, CLI, or
multi-theme constraints.

## Product Boundary

This repository owns the Apple-native product experience and can
redesign UI, navigation, information architecture, visual hierarchy, and platform
integrations from first principles.

The cross-platform implementation and older design notes remain historical
reference material for:

- canonical SQLite entities and migration history
- task/list/habit/calendar/focus/review/memory workflow semantics
- audit log requirements for assistant-authored writes
- sync outbox/inbox, HLC/version stamping, tombstones, and conflict handling
- MCP tool behavior and error-sanitization expectations
- CloudKit/EventKit integration lessons

## Runtime Shape

### App

The app is a SwiftUI app with AppKit support where SwiftUI is not the best
desktop abstraction. The default macOS scene model is:

- `WindowGroup` for the primary workspace
- `MenuBarExtra` for glanceable status and quick task actions
- `Settings` for preferences and diagnostics
- auxiliary `Window` scenes for detached workspaces, a detached list window, and
  a sticky-task window
- a dedicated Task Detail window reuses the selected task state as the main
  workspace, supporting desktop workflows where list navigation and detail
  editing live in separate windows
- Storage is fixed to the single Lorvex-managed App Group database; every surface
  (app, MCP helper, widgets, App Intents, notifications, mobile) resolves it
  through `DbLocator`. There is no external-database selection — portability is
  export/import through the native file panels, and cross-device sync is
  CloudKit-only. The macOS app entitlements require sandboxing and user-selected
  read/write file access (for the export/import Open/Save panels); metadata and
  signed-bundle verification treat those as part of the product contract. An
  unsandboxed dev/source build additionally honors a launch-time
  `LORVEX_APPLE_DB_PATH` override, resolved directly by the core and never
  persisted.
- `AppIntents` for system-facing actions such as opening Lorvex to a destination
  or specific task, capturing a task, completing a task, deferring a task,
  starting or pausing a task, planning a task for today, and reading,
  suggesting, or saving the day's schedule from
  Shortcuts, Siri, Spotlight, widgets, or controls.
  The shared `LorvexSystemIntents` target owns the `AppIntent`, `AppEntity`,
  `SetFocusFilterIntent`, and `AppShortcutsProvider` types for macOS and
  iOS/iPadOS. Its Shortcuts provider is backed by the tested
  `LorvexShortcutDescriptor` contract in `LorvexCore` so the advertised system
  actions stay complete, ordered, and reusable by Apple targets.
  `LorvexSystemIntentRunner` lives in `LorvexCore`, so capture, complete,
  defer, and day-planning mutations route through the same core service
  boundary from every system surface.
  `LorvexIntentHandoffStore` centralizes the single pending destination/task
  handoff keys consumed by both macOS and mobile navigation.
- `CoreSpotlight` indexing for task search outside the app, fed by the same
  `LorvexCoreServicing` snapshots as the SwiftUI workspace; indexed task
  results carry canonical escaped `lorvex://task/...` links back into task detail
- `lorvex://` deep links for system handoff back into destinations and task
  detail, registered in the packaged macOS app bundle. `LorvexDeepLinkContract`
  in `LorvexCore` owns the canonical scheme, hosts, and task-id path encoding;
  platform routers map that shared URL contract into native navigation state.
- `UserNotifications` scheduling for future task reminders, derived from
  Lorvex task reminder rows and linked back to task deep links; notification
  responses are routed through the same `lorvex://` deep-link parser as
  Spotlight and App Intent handoff
- `EventKit` write-through for newly created Lorvex calendar events is
  **macOS-only**, run after the canonical Lorvex core write succeeds, so Apple
  Calendar integration does not replace or weaken Lorvex database/audit/sync
  semantics. Calendar export reports make permission failures visible in
  Settings and keep the draft available for retry. iPhone/iPad do not
  write to Apple Calendar; they request Calendar access only to read.
- `EventKit` read-through for Apple Calendar events in the Calendar workspace,
  on every platform, merged after the canonical Lorvex timeline loads; EventKit
  permission or read failures do not block Lorvex core calendar data and are
  recorded in the import report.
- `LorvexWidgetKitSupport` owns the shared WidgetKit snapshot wire format,
  loader, freshness/refresh policies, and the projection from `TodaySnapshot`,
  which carries the assistant's daily briefing, into a widget payload. Widget
  code imports this library instead of duplicating JSON decoding, stale-state
  logic, lead-task projection, placeholder state, fallback handling, status
  text, timeline refresh cadence, family-specific row limits, or render-model
  branching.
  `LorvexWidgetViews` owns reusable SwiftUI views for those render models.
  `LorvexWidgetExtension` owns the WidgetKit adapter layer: `TimelineProvider`,
  `TimelineEntry`, App Group snapshot URL resolution, WidgetFamily mapping,
  `StaticConfiguration`, supported families, and WidgetKit container background.
  The app publishes snapshots through `WidgetSnapshotPublishing`, using an
  explicit file path for local validation or an explicit
  `LORVEX_WIDGET_APP_GROUP_ID` opt-in for the shared App Group container. The
  default local publisher is no-op so rebuilds and archive smoke tests do not
  repeatedly trigger macOS shared-container prompts. The Widget extension also
  leaves App Group resolution disabled by default and only reads the shared
  snapshot when its Info.plist explicitly sets `LorvexWidgetAppGroupID`.
  Product metadata now has
  one shared source for the app bundle id, widget bundle id, widget kind, executable,
  `.appex` name, and App Group id. The main app and widget extension
  entitlements both carry the same App Group id, and the widget extension
  Info.plist declares the WidgetKit extension point from the same metadata
  contract. Local package/archive verification embeds and signs
  `Contents/PlugIns/LorvexWidgets.appex`, checks its nested executable and
  Info.plist, and checks the signed app includes the App Group entitlement.
  XcodeGen also defines the real `LorvexWidgets` app-extension
  target with a `@main` `WidgetBundle` entrypoint in `LorvexWidgetBundle`. The
  generated project embeds that extension into the iOS app target, while the
  SwiftPM build keeps the entrypoint source compiling as part of the normal
  verification gate.
  Widget render models carry `lorvex://` deep links so the whole widget can open
  Today or the inline lead task, while visible task rows can open task detail.
- `CloudSyncController`, an actor in `LorvexCloudSync`, is the CloudKit
  transport for live builds. It wraps Apple's `CKSyncEngine` on the private
  database and is the engine's `CKSyncEngineDelegate`. All records live in one
  custom zone named `Lorvex` as `LorvexEntity` records whose envelope fields
  are encrypted. The engine owns change tokens, the push subscription
  (`lorvex-sync-engine`), push handling, scheduling, and retries; its state
  serialization is persisted as a checkpoint in SQLite. Outbound, the local
  `sync_outbox` is the source of truth: `nextBatch` builds records from
  unsynced outbox rows, and `handleSentRecords` confirms the sent rows in one
  `reconcileOutbound` transaction. A `serverRecordChanged` conflict merges by
  HLC last-writer-wins. Inbound, fetched records are decoded and applied
  through Core's inbound apply: typed HLC LWW gates, tombstones,
  redirect-aware pending inbox draining, conflict logging, and the registered
  entity appliers. `ai_changelog` is device-local: its outbox rows are
  confirmed without upload and inbound copies are ignored. Core planning
  entities including tasks, lists, habits, calendar events, memory, and daily
  briefings have outbox export and inbound applier coverage. Existing task
  records merge conservatively: remote fields that are present win, while
  local values are preserved for absent remote fields.
- Sync has two modes, `off` and `live`. `LORVEX_CLOUD_SYNC=live` forces
  live and any other value forces off; without the variable the persisted
  setting applies, and the default is off. Two durable pause reasons stop
  sync until the user acts: `accountChanged` (a different iCloud account
  signed in, and the user must adopt it) and `userDeletedZone` (Lorvex's
  iCloud data was deleted, on this or another device, and the user must turn
  sync back on). `CloudSyncStatusReport` combines the mode, account
  availability, pause reason, last push and pull, and pending count for
  Settings diagnostics. A provisioned CloudKit entitlement template carries
  CloudKit services and the shared iCloud container id from product metadata,
  while the default local ad-hoc signing entitlement remains App Group-only so
  local package/archive launches keep working. Metadata verification covers
  both templates; signed-entitlement verification covers the launchable local
  app. Real CloudKit network traffic needs a provisioned container and a
  logged-in iCloud account.
- packaged app metadata declares the `lorvex://` URL scheme, productivity
  category, and calendar usage descriptions required for the current Apple
  system integrations
- `LorvexMobile` is the first iOS/iPadOS-specific product target. It is a
  SwiftUI library target with one native `TabView` and per-tab `NavigationStack`
  structure for iPhone and iPad alike; regular-width layouts add a second pane
  inside a tab (list and detail in Tasks, Habits, and Memory, a schedule pane
  beside Today, an agenda pane beside the Calendar day grid). It consumes
  `TodaySnapshot` and `WeeklyReviewSnapshot` through a
  mobile projection layer instead of sharing macOS multi-window state. This
  keeps the mobile app free to optimize for fast capture and a glanceable
  Today while preserving the same core service boundary and business semantics.
  `MobileStore` is the mobile root state owner: it refreshes Today/weekly
  review through `LorvexCoreServicing`, tracks loading and capture
  state, and routes mobile capture through the same core `createTask` operation
  used by macOS and MCP paths. It also owns selected tab and navigation-path
  state. Every external entry point (widgets, Shortcuts, Spotlight, Handoff,
  notifications) parses through the shared `LorvexDeepLinkRoute` and lands on
  a `MobileNavigationTarget`: one of the four tabs plus the screens to push on
  its stack. Habits and Memory are workspaces on the Tasks stack rather than
  tabs, so the tab bar never selects a tab it does not show.
  `MobileIntentHandoff` consumes the shared `LorvexIntentHandoffStore`
  from `LorvexCore`, giving system intents a stable route into macOS and mobile
  navigation state without duplicating key ownership. The mobile app entry
  links `LorvexSystemIntents`, so mobile Shortcuts expose the same capture,
  list creation/update/delete, habit creation/update/delete, calendar
  creation/update/delete, habit completion/reset, open, complete, cancel,
  reopen, defer, start, pause, and day-planning actions as macOS.
  `LorvexMobileApp` is the first SwiftUI mobile app entry target. Its
  Info.plist registers the mobile bundle id, product category, calendar
  usage text, minimum iOS version, and `lorvex://` URL scheme; paired
  entitlement templates cover the shared App Group and provisioned CloudKit
  container. `MobileStoreFactory` centralizes the mobile store bootstrap:
  app entry targets supply the core runtime plus platform services such as
  haptics, task and habit reminder scheduling, and clock/date dependencies,
  while tests can inject deterministic factories. App Store privacy manifests
  are part of the same checked platform contract: iOS, watchOS,
  Widget, and the macOS bundle all include `PrivacyInfo.xcprivacy` with no
  tracking, no collected data types, and the approved UserDefaults required
  reason for local settings/state.
  `LorvexWatchApp` is a watchOS companion whose production
  `LorvexWatchStoreFactory` is read-only with respect
  to SQLite. The iPhone projects the bounded Watch subset from its canonical
  widget snapshot, binds it to the physical database's workspace UUID, sends it
  through replaceable `WCSession.updateApplicationContext`, and the Watch
  atomically stores the complete envelope as `watch_replica_v1.json` in its own
  App Group. The lead task remains the primary target; habits
  and briefing share that same workspace-fenced replica. Missing or invalid
  replica state fails closed instead of opening a second writable database.
  Watch mutations use a persist-before-send JSON journal, strict versioned
  command/ACK checksums, FIFO sequence delivery, and a phone-local SQLite ledger
  whose applied receipt commits in the same transaction as the domain write.
  Transport callbacks schedule retries but never prove application. The local
  journal and receipt tables are control-plane state excluded from CloudKit,
  export, and import; only their resulting canonical domain mutations sync.
  `Config/XcodeGen/project.yml` generates iOS app, Widget extension,
  and watchOS app targets, while `verify_mobile_simulator.sh`
  and `verify_watch_simulator.sh`
  build/install/launch when the local Xcode simulator SDK and runtime match.
  `verify_xcodegen_project.sh` also writes and validates
  `dist/lorvex-apple-platform-manifest.json` so the mobile, watchOS,
  and Widget target metadata remains a machine-checked Apple platform contract.

The macOS root workspace uses native split navigation, a system sidebar,
toolbars, search, command menus, and semantic system materials; the
iOS/iPadOS root is the system tab bar with one navigation stack per tab. Both
honor the system light/dark appearance and follow the user's Apple accent color
through native SwiftUI `.tint`.

### CloudSync ownership

CloudSync has one owner per device: the running main app. The macOS `AppStore`
and the iOS/iPadOS `MobileStore` each retain one `CloudSyncController` and
reuse that same actor for foreground sync, account adoption, and iCloud data
deletion. The controller owns the one `CKSyncEngine` of the process, so there
is no second production engine that needs cross-process arbitration. The app
calls `noteLocalChanges()` when its database changes, which hands unsynced
outbox rows to the engine.

```text
MCP / widgets / App Intents / watch handoff
  -> LorvexCoreServicing
  -> managed local SQLite transaction + audit + outbox
  -> database-change notification
  -> main app's CloudSyncController (CKSyncEngine)
  -> private CloudKit database
```

Non-owner targets and processes never import CloudKit or `LorvexCloudSync`.
They do not fetch or send records or delete zones. An MCP or extension
mutation is complete once the canonical local transaction commits; its outbox
row is durable work for the main app to upload when it next runs. Read-only
extensions consume bounded snapshots or the managed local store according to
their existing surface contract.

This is a product boundary, not an accidental property of current wiring.
Introducing a background sync helper or daemon would require a separate design
for controller ownership, lifecycle, and handoff before that target could link
`LorvexCloudSync`. `script/verify_apple_strategy.py` rejects CloudSync/CloudKit
dependencies or source usage in non-app production targets.

The stores coordinate three flows with the controller:

- **Settings import.** With sync live, the store runs one best-effort sync
  pass, then imports record by record, then refreshes. SQLite transactions
  serialize the importer's writes against the engine's inbound applies, and
  the imported rows upload through the outbox like any other mutation. Import
  rejects only with `LorvexDataImporter.BusyError`.
- **Factory reset and local reset.** The store stops the controller, wipes the
  database, then calls `forgetCachedRecordState()`.
- **iOS background.** When the app leaves the foreground, `BackgroundSyncFlush`
  runs one sync pass inside a `UIApplication` background task and suspends the
  database when the pass ends or the task expires. The engine handles silent
  pushes; the app delegate only keeps the app awake for them, with a 22-second
  deadline.

### Core

The Swift app talks to a narrow `LorvexCoreServicing` boundary backed by:

1. `SwiftLorvexCoreService` over the pure-Swift `LorvexAppleCore` package
   (`core/`: `LorvexDomain`, `LorvexStore` [GRDB/SQLite], `LorvexWorkflow`,
   `LorvexSync`, `LorvexRuntime`) for real data. This is the default; it opens
   the Lorvex-managed store in the App Group container, which every surface
   on the device shares. Only an unsandboxed development build may point it
   elsewhere, with `LORVEX_APPLE_DB_PATH`.
2. The same `SwiftLorvexCoreService` over an in-memory GRDB store
   (`SwiftLorvexCoreService.inMemory()`, seeded via `LorvexPreviewCoreFactory`)
   for UI previews and tests — real query/write semantics, no on-disk
   database. Product runtime environment never opts into this fixture; tests
   and previews construct it explicitly.

Why the core is pure Swift, and what stays shared as language-neutral
artifacts, is recorded in `../../../../docs/decisions/pure-swift-core-port.md`.

The Swift UI must not hand-roll complex mutation SQL. Writes should go through
the same semantic operations that maintain audit logs, outbox rows,
`local_change_seq`, and version stamps.

### MCP

`LorvexMCPHost` is the shipped MCP stdio server: a Swift command-line executable
built on the official Swift MCP SDK (`modelcontextprotocol/swift-sdk`). Real MCP
clients — Claude, Codex, and other stdio clients — drive it as Lorvex's primary
write interface.

- It exposes 116 tools spanning tasks, day planning, lists, habits, calendar,
  reviews, memory, and system diagnostics. `script/expected_mcp_tools.py` is the
  authoritative tool-name set, and `script/verify_mcp_tool_catalog.py` enforces
  that the typed definition registry matches it. The same definitions drive
  `tools/list`, handler dispatch, idempotency membership, and response fencing.
- Tool bodies route through the `LorvexCoreServicing` boundary rather than
  duplicated SQL, so host writes and app writes share one core data path with
  its audit logs, outbox rows, and version stamps.
- A keyed write claims `(tool_name, idempotency_key)` inside the same
  `BEGIN IMMEDIATE` transaction as its first domain mutation. The checksum gate
  therefore remains correct across concurrent MCP host processes; the actor
  cache only avoids avoidable same-process contention.
- Export tools return exact file bytes as base64 MCP blob resources annotated
  for the user audience. User-authored text never appears as model-facing MCP
  text, while clients can decode the blob into an unchanged JSON, CSV, or ICS
  download.
- Installed helper launches carry no storage injection: the sandboxed helper
  resolves the same Lorvex-managed App Group store the app opens, so host writes
  and app writes always share one database. Only an unsandboxed dev/source build
  honors a `LORVEX_APPLE_DB_PATH` path override, available for fixtures and
  developer smoke tests.
- Client compatibility issues are Swift MCP host bugs. The Apple edition does
  not bundle or supervise a separate Rust MCP server.

### Markdown

`swift-markdown` is used for *rendering* only — read-only display of AI notes and
review summaries via `LorvexMarkdownUI` / `MarkdownNoteView`. Human-edited text
(task notes, daily/weekly reviews, sticky notes, and the capture / list / habit
fields) is plain text through the shared `LorvexPlainTextEditor` (an `NSTextView`
wrapper). A markdown *editing* surface was deliberately dropped: plain text
proved sufficient and avoided the editor's caret/commit bugs.

## Data Flow

```text
SwiftUI/AppKit Views
  -> AppStore / scene state
  -> LorvexCoreServicing
  -> SwiftLorvexCoreService -> LorvexAppleCore (LorvexStore/Workflow/Sync)
  -> canonical SQLite + audit + outbox + sync invariants

Swift MCP Host
  -> MCP tool router
  -> LorvexCoreServicing
  -> same core data path as the app

WidgetKit Extension
  -> LorvexWidgetExtension
  -> LorvexWidgetKitSupport
  -> WidgetTimelineProviderSupport
  -> WidgetRenderModelBuilder
  -> LorvexWidgetViews
  -> lorvex:// Today/task deep links
  -> shared App Group widget snapshot file
  -> same core-derived Today projection published by AppStore
```

The UI observes core state through explicit snapshots and refreshes. All app-
process core writes schedule a coalesced in-process `DatabaseChangeSignal` after
commit, so independent main/detached stores see each other's changes. A
completed sync pass separately posts one origin-tagged in-process signal when
its applied-kind set is non-empty: detached stores converge while the
already-reconciled originating store ignores that notification and does not
start a redundant sync pass. The MCP host and interactive-widget intents write
from separate processes and broadcast the Darwin form after their committed
operation; the app relays it to the same
`DatabaseChangeSignal.didChangeNotification`. The core stamps
`local_change_seq` on every write, so a refreshed snapshot reflects the latest
of either path.

Navigation state is app-owned and persisted through lightweight user defaults:
the primary workspace restores the last selected sidebar destination and task,
while incoming App Intents or `lorvex://` deep links intentionally override that
restored state. App Intent handoff supports both destination and task handoff:
task handoff selects the task and opens the Tasks workspace so system surfaces
can deep-link into task detail without duplicating navigation state.

Mobile navigation starts with value routes:

```text
LorvexMobileStoreRootView
  -> TabView: Today, Calendar, Tasks, Review (+ capture button)
  -> one NavigationStack per tab, a path of MobileRoute values
  -> regular width: a second pane inside the tab
  -> MobileStore
  -> LorvexCore snapshots
```

## Quality Bar

- Native first: system sidebar, toolbar, menu, settings, sheets, focus rings,
  accessibility, keyboard shortcuts, and semantic colors.
- No decorative web-app theme system. System light/dark appearance, the user's
  Apple accent color, and high-quality layout are the baseline.
- Apple-platform affordances are product features, not wrappers around a
  cross-platform implementation.
- Every data mutation must preserve or improve original Lorvex correctness
  guarantees.
- Bundle identifiers, widget identifiers, App Group ids, and signed
  entitlements are treated as verified product contract, not ad hoc per-target
  strings. CloudKit container id and services are part of the same verified
  contract. Widget extension Info.plist values are verified against the same
  contract before packaging.
