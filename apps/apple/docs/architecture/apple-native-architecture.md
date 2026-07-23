# Apple-Native Architecture

## Goal

Lorvex Apple is the native Apple-ecosystem edition of Lorvex. It targets macOS
first and expands to iOS, iPadOS, WidgetKit, App Intents, Shortcuts, Spotlight,
CloudKit, EventKit, and visionOS without carrying Windows, Linux, CLI, Tauri, or
multi-theme constraints.

## Product Boundary

The Rust + Tauri repository remains a separately maintained cross-platform
edition. This repository owns the Apple-native product experience and can
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
  reading or proposing/saving the focus schedule, and adding or removing a task
  to/from the current focus plan from
  Shortcuts, Siri, Spotlight, widgets, or controls.
  The shared `LorvexSystemIntents` target owns the `AppIntent`, `AppEntity`,
  `SetFocusFilterIntent`, and `AppShortcutsProvider` types for macOS,
  iOS/iPadOS, and visionOS. Its Shortcuts provider is backed by the tested
  `LorvexShortcutDescriptor` contract in `LorvexCore` so the advertised system
  actions stay complete, ordered, and reusable by Apple targets.
  `LorvexSystemIntentRunner` lives in `LorvexCore`, so capture, complete,
  defer, and focus mutations route through the same core service boundary from
  every system surface.
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
  Settings and keep the draft available for retry. iPhone/iPad/visionOS do not
  write to Apple Calendar; they request Calendar access only to read.
- `EventKit` read-through for Apple Calendar events in the Calendar workspace,
  on every platform, merged after the canonical Lorvex timeline loads; EventKit
  permission or read failures do not block Lorvex core calendar data and are
  recorded in the import report.
- `LorvexWidgetKitSupport` owns the shared WidgetKit snapshot wire format,
  loader, freshness/refresh policies, and the projection from `TodaySnapshot`
  plus `CurrentFocusPlan` into a widget payload. Widget code imports this
  library instead of duplicating JSON decoding, stale-state logic, focus-task
  projection, placeholder state, fallback handling, status text, timeline
  refresh cadence, family-specific row limits, or render-model branching.
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
  `Contents/PlugIns/LorvexFocusWidget.appex`, checks its nested executable and
  Info.plist, and checks the signed app includes the App Group entitlement.
  XcodeGen also defines the real `LorvexFocusWidgetExtension` app-extension
  target with a `@main` `WidgetBundle` entrypoint in `LorvexWidgetBundle`. The
  generated project embeds that extension into the iOS app target, while the
  SwiftPM build keeps the entrypoint source compiling as part of the normal
  verification gate.
  Widget render models carry `lorvex://` deep links so the whole widget can open
  Today or the inline focus task, while visible task rows can open task detail.
- `CloudSyncExporting` is the local snapshot/export-plan boundary. It projects
  `TodaySnapshot`, `CurrentFocusPlan`, and runtime sync
  diagnostics into a deterministic `CloudSyncExportEnvelope` for diagnostics
  and record-plan verification. Live CloudKit sync is driven by
  `CloudSyncEngineCoordinator`, which drains the Swift sync outbox and applies
  inbound envelopes through `Apply.applyEnvelope`. The projector preserves
  source `localChangeSequence` ordering data and uses the shared iCloud
  container id from product metadata. A
  provisioned CloudKit entitlement template carries CloudKit services and the
  same container id, while the default local ad-hoc signing entitlement remains
  App Group-only so local package/archive launches keep working. Metadata
  verification covers both templates; signed-entitlement verification covers the
  launchable local app. `CloudSyncExportReport` records the latest export mode,
  private database scope, record count, source sequence, and failure text so
  Settings diagnostics can surface record-plan/live state. Real CloudKit network
  writes remain a runtime step that needs a provisioned container and logged-in
  iCloud account.
  `LORVEX_CLOUDKIT_EXPORT=record-plan` exercises `CKRecord` encoding without
  network access; `LORVEX_CLOUDKIT_EXPORT=live` switches to private database
  saves for provisioned builds.
- `CloudSyncEngineCoordinator` is the inbound CloudKit authority for live
  builds. It binds every pull to the current account, generation, ready witness,
  database lineage, and SQLite traversal. `CloudKitRemoteChangeFetcher` fetches
  private record-zone changes from that traversal's cursor, then
  `EnvelopeSyncServicing.applyInboundTraversalPage` commits decoded effects and
  the successor token in one SQLite transaction. `AppStore` runs the draining
  coordinator before its normal refresh when a Lorvex CloudKit push arrives. The
  applicator routes decoded records through the Swift sync engine:
  typed HLC LWW gates, tombstones, redirect-aware pending inbox draining,
  conflict logging, and the registered entity appliers. Core planning entities
  including tasks, lists, habits, calendar events, memory, and focus plans
  have outbox export and inbound applier coverage. Existing
  task records merge conservatively: remote fields that
  are present win, while local values are preserved for absent remote fields.
- packaged app metadata declares the `lorvex://` URL scheme, productivity
  category, and calendar usage descriptions required for the current Apple
  system integrations
- `LorvexMobile` is the first iOS/iPadOS/visionOS-specific product target. It is a
  SwiftUI library target with native `TabView` and per-tab `NavigationStack`
  structure for compact iPhone layouts, plus a `NavigationSplitView` sidebar
  shell for regular-width iPad layouts and visionOS. It consumes
  `TodaySnapshot`, `CurrentFocusPlan`, and `WeeklyReviewSnapshot` through a
  mobile projection layer instead of sharing macOS multi-window state. This
  keeps the mobile app free to optimize for fast capture and glanceable focus
  while preserving the same core service boundary and business semantics.
  `MobileStore` is the mobile root state owner: it refreshes Today/current
  focus/weekly review through `LorvexCoreServicing`, tracks loading and capture
  state, and routes mobile capture through the same core `createTask` operation
  used by macOS and MCP paths. It also owns selected tab and navigation-path
  state, while `MobileDeepLinkRoute` maps the shared `lorvex://` URL contract
  into mobile tabs and task detail routes for widgets, Shortcuts, Spotlight,
  and notifications. It parses shared workspace destinations through the
  `SidebarSelection` contract in `LorvexCore`, then applies mobile-specific tab
  mapping. `MobileIntentHandoff` consumes the shared `LorvexIntentHandoffStore`
  from `LorvexCore`, giving system intents a stable route into macOS and mobile
  navigation state without duplicating key ownership. The mobile app entry
  links `LorvexSystemIntents`, so mobile Shortcuts expose the same capture,
  list creation/update/delete, habit creation/update/delete, calendar
  creation/update/delete, habit completion/reset, open, complete, cancel,
  reopen, defer, and focus actions as macOS.
  `LorvexMobileApp` is the first SwiftUI mobile app entry target. Its
  Info.plist registers the mobile bundle id, product category, calendar
  usage text, minimum iOS version, and `lorvex://` URL scheme; paired
  entitlement templates cover the shared App Group and provisioned CloudKit
  container. `MobileStoreFactory` centralizes the mobile/vision store bootstrap:
  app entry targets supply the core runtime plus platform services such as
  haptics, focus-session notifications, and clock/date dependencies,
  while tests can inject deterministic factories. App Store privacy manifests
  are part of the same checked platform contract: iOS, visionOS, watchOS,
  Widget, and the macOS bundle all include `PrivacyInfo.xcprivacy` with no
  tracking, no collected data types, and the approved UserDefaults required
  reason for local settings/state.
  `LorvexVisionApp` reuses the same native surface for visionOS with a distinct
  bundle id, minimum OS, Info.plist, App Group entitlement template, and
  provisioned CloudKit entitlement template, and it enters the same
  `MobileStoreFactory` path as iOS. `LorvexWatchApp` is a watchOS focus
  companion whose production `LorvexWatchStoreFactory` is read-only with respect
  to SQLite. The iPhone projects the bounded Watch subset from its canonical
  widget snapshot, binds it to the physical database's workspace UUID, sends it
  through replaceable `WCSession.updateApplicationContext`, and the Watch
  atomically stores the complete envelope as `watch_replica_v1.json` in its own
  App Group. The first actionable focus row remains the primary target; habits
  and briefing share that same workspace-fenced replica. Missing or invalid
  replica state fails closed instead of opening a second writable database.
  Watch mutations use a persist-before-send JSON journal, strict versioned
  command/ACK checksums, FIFO sequence delivery, and a phone-local SQLite ledger
  whose applied receipt commits in the same transaction as the domain write.
  Transport callbacks schedule retries but never prove application. The local
  journal and receipt tables are control-plane state excluded from CloudKit,
  export, and import; only their resulting canonical domain mutations sync.
  `Config/XcodeGen/project.yml` generates iOS app, Widget extension, visionOS
  app, and watchOS app targets, while `verify_mobile_simulator.sh`,
  `verify_vision_simulator.sh`, and `verify_watch_simulator.sh`
  build/install/launch when the local Xcode simulator SDK and runtime match.
  `verify_xcodegen_project.sh` also writes and validates
  `dist/lorvex-apple-platform-manifest.json` so the mobile, visionOS, watchOS,
  and Widget target metadata remains a machine-checked Apple platform contract.

The root workspace uses native split navigation, system sidebars, toolbars,
search, command menus, and semantic system materials. It honors the system
light/dark appearance and follows the user's Apple accent color through native
SwiftUI `.tint`.

### CloudSync ownership

CloudSync has one owner per device: the running main app. The macOS `AppStore`
and the iOS/iPadOS/visionOS `MobileStore` each retain one
`CloudSyncEngineCoordinator` and reuse that same actor for foreground sync,
remote-change drains, import quiescence, retention, account adoption, and cloud
data maintenance. These operations serialize on the coordinator's in-process
gate; there is no second production coordinator that needs cross-process
arbitration.

```text
MCP / widgets / App Intents / watch handoff / CarPlay
  -> LorvexCoreServicing
  -> managed local SQLite transaction + audit + outbox
  -> database-change notification
  -> main app's CloudSyncEngineCoordinator
  -> private CloudKit database
```

Non-owner targets and processes never import CloudKit or `LorvexCloudSync`.
They do not pull, push, delete zones, mutate traversal cursors, switch
generations, or perform CloudKit maintenance. An MCP or extension mutation is
complete once the canonical local transaction commits; its outbox row is
durable work for the main app to upload when it next runs. Read-only extensions
consume bounded snapshots or the managed local store according to their
existing surface contract.

This is a product boundary, not an accidental property of current wiring.
Introducing a background sync helper or daemon would require a separate design
for coordinator ownership, lifecycle, and handoff before that target could link
`LorvexCloudSync`. `script/verify_apple_strategy.py` rejects CloudSync/CloudKit
dependencies or source usage in non-app production targets.

### Core

The Swift app talks to a narrow `LorvexCoreServicing` boundary backed by:

1. `SwiftLorvexCoreService` over the pure-Swift `LorvexAppleCore` package
   (`core/`: `LorvexDomain`, `LorvexStore` [GRDB/SQLite], `LorvexWorkflow`,
   `LorvexSync`, `LorvexRuntime`) for real data. This is the default; it writes
   to `LORVEX_APPLE_DB_PATH` or the core's default location in Application
   Support.
2. The same `SwiftLorvexCoreService` over an in-memory GRDB store
   (`SwiftLorvexCoreService.inMemory()`, seeded via `LorvexPreviewCoreFactory`)
   for UI previews and tests — real query/write semantics, no on-disk
   database. Product runtime environment never opts into this fixture; tests
   and previews construct it explicitly.

The design and Swift-vs-shared split are in
`../../../../docs/superpowers/specs/pure-swift-core-and-monorepo-design.md`.

The Swift UI must not hand-roll complex mutation SQL. Writes should go through
the same semantic operations that maintain audit logs, outbox rows,
`local_change_seq`, and version stamps.

### MCP

`LorvexMCPHost` is the shipped MCP stdio server: a Swift command-line executable
built on the official Swift MCP SDK (`modelcontextprotocol/swift-sdk`). Real MCP
clients — Claude, Codex, and other stdio clients — drive it as Lorvex's primary
write interface.

- It exposes 118 tools spanning tasks, focus, lists, habits, calendar, reviews,
  memory, and system diagnostics. `script/expected_mcp_tools.py` is the
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
  -> same core-derived Today/current-focus projection published by AppStore
```

The UI observes core state through explicit snapshots and refreshes. All app-
process core writes schedule a coalesced in-process `DatabaseChangeSignal` after
commit, so independent main/detached stores see each other's changes. A
successful CloudKit inbound cycle separately posts one origin-tagged in-process
signal when its applied-kind set is non-empty: detached stores converge while
the already-reconciled originating store ignores that notification and does not
start a redundant sync cycle. The MCP host and interactive-widget intents write
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
LorvexMobileRootView
  -> MobileChromeStyle
  -> compact: TabView
  -> regular/visionOS: NavigationSplitView
  -> Today/Capture/Focus/Review NavigationStacks
  -> MobileStore
  -> LorvexCore snapshots
```

## Quality Bar

- Native first: system sidebar, toolbar, menu, settings, sheets, focus rings,
  accessibility, keyboard shortcuts, and semantic colors.
- No decorative web-app theme system. System light/dark appearance, the user's
  Apple accent color, and high-quality layout are the baseline.
- Apple-platform affordances are product features, not wrappers around the old
  Tauri implementation.
- Every data mutation must preserve or improve original Lorvex correctness
  guarantees.
- Bundle identifiers, widget identifiers, App Group ids, and signed
  entitlements are treated as verified product contract, not ad hoc per-target
  strings. CloudKit container id and services are part of the same verified
  contract. Widget extension Info.plist values are verified against the same
  contract before packaging.
