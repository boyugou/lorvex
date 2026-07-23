# Apple Lifecycle, Restoration, and Time Audit

Last verified: 2026-07-10  
Code snapshot: `cc8c2c925cb30a36091956842b435f59edefe2ae`

This is a static audit of cold/warm launch, normal quit and abrupt termination,
scene/window ownership, database replacement, restoration, midnight, time-zone
change, and memory pressure. It does not substitute for killing and restoring an
exact Release archive on physical hardware.

## Apple Contract

- A SwiftUI scene has a system-managed lifecycle. A `WindowGroup` can have more
  than one window; state created inside the scene hierarchy is independent per
  window. iPadOS multi-window additionally requires
  `UIApplicationSupportsMultipleScenes = true` inside
  `UIApplicationSceneManifest`.
- `SceneStorage` is lightweight per-scene restoration storage. The system makes
  no guarantee about exactly when it persists and destroys it when that scene is
  explicitly destroyed, so it is not a data store or durable draft journal.
- UIKit posts `significantTimeChangeNotification` for events such as midnight,
  carrier time updates, and daylight-saving transitions. Foundation posts
  `NSCalendarDayChangedNotification`; delivery is not guaranteed to be precise,
  and a sleeping device receives one notification on wake.
- `TimeZone.autoupdatingCurrent` and `Calendar.autoupdatingCurrent` track user
  preference changes. A captured `current` value does not become an
  automatically updating value.
- AppKit can delay a normal Quit in `applicationShouldTerminate` while critical
  data finishes, then reply to the termination request. This cannot make force
  quit or process death reliable; durable work must already be on disk.
- iOS memory-pressure termination is expected. Apple asks apps to lower their
  suspension footprint, restore state after relaunch, and react quickly to
  memory warnings. MetricKit exposes exit and memory metrics for shipped builds.

Primary sources:

- [SwiftUI scenes](https://developer.apple.com/documentation/swiftui/scenes)
- [WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup)
- [SceneStorage](https://developer.apple.com/documentation/swiftui/scenestorage)
- [UIApplication significantTimeChangeNotification](https://developer.apple.com/documentation/uikit/uiapplication/significanttimechangenotification)
- [NSCalendarDayChangedNotification](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/nscalendardaychanged)
- [TimeZone.autoupdatingCurrent](https://developer.apple.com/documentation/foundation/timezone/autoupdatingcurrent)
- [Calendar.autoupdatingCurrent](https://developer.apple.com/documentation/foundation/calendar/autoupdatingcurrent)
- [NSApplicationDelegate.applicationShouldTerminate](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate(_:))
- [NSApplicationDelegate.applicationSupportsSecureRestorableState](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationsupportssecurerestorablestate(_:))
- [Reducing terminations in your app](https://developer.apple.com/documentation/xcode/reduce-terminations-in-your-app)
- [Responding to low-memory warnings](https://developer.apple.com/documentation/xcode/responding-to-low-memory-warnings)

## Existing Strengths

Several hard lifecycle problems already have deliberate implementations:

- Mac and mobile refreshes are single-flight with a pending rerun, so activation,
  database-change, push, and notification-action triggers do not run overlapping
  refresh bodies or silently drop a mid-flight trigger.
- A cold iOS CloudKit push received before the SwiftUI store attaches is recorded
  durably and consumed by the next store attachment/foreground refresh.
- The iOS background CloudKit drain has a 22-second application deadline inside
  Apple's approximate 30-second remote-notification budget.
- the main Mac `AppStore` and each detached Mac window have distinct UI stores;
  detached window state does not retarget the main selection;
- `DatabaseChangeSignal`, foreground activation, key-window reload, EventKit
  change observation, and CloudKit pushes cover several otherwise invisible
  writer paths;
- refresh code deliberately preserves dirty task and daily-review drafts instead
  of accepting a remote refresh over in-progress typing;
- task-detail and Mac daily-review editing use debounced autosave plus navigation
  and disappearance flushes;
- SwiftUI value-keyed `WindowGroup` scenes deduplicate a Mac detached list or
  sticky task and persist the presentation value for restoration;
- the main Mac window restores the workspace and selected task, then reconciles
  a stale/deleted selection after loading;
- the Mac app explicitly recovers off-screen window placement and handles Dock
  reopen after the last visible window is closed.

These features materially reduce stale UI and duplicate refresh races. The gaps
below sit at the boundaries those mechanisms do not currently observe.

## Findings

### L1 — HIGH — The process freezes its first local time zone into canonical formatters

`LorvexDateFormatters.ymd` and `hourMinute` are static singleton
`DateFormatter`s. At first access they assign `TimeZone.current`, then are never
mutated. They are used for the canonical local day key and calendar event wall
times across Mac, iPhone, widgets, and service calls.

Apple distinguishes `current` from `autoupdatingCurrent`: the latter tracks a
user preference change. Assigning the first `current` value to a cached formatter
therefore fixes that formatter to the old zone until process restart.

This can become persistent data corruption rather than a cosmetic timestamp.
After travel or a manual time-zone change, habit completion, focus state, daily
review targeting, calendar day queries, reminder planning, badge calculation,
and “today” comparisons can continue using the old local day. `Calendar.current`
calls elsewhere may already use the new setting, producing two local-day frames
inside one process.

Evidence:

- `Sources/LorvexCore/Support/LorvexDateFormatters.swift`
- `Sources/LorvexApple/Stores/AppStoreDateFormatting.swift`
- `Sources/LorvexMobile/MobileStore.swift`

Release condition: choose one explicit policy for local-day and wall-time
formatters. Either use an autoupdating time zone/calendar where live change is
intended, or rebuild all affected cached formatters atomically on time-zone and
locale/calendar change. Test a zone change across the International Date Line
while the process remains alive and verify the exact persisted day keys.

### L2 — HIGH — A foreground app can remain on yesterday indefinitely

Neither Mac nor iOS observes calendar-day or significant-time-change events.
The Mac refreshes on `NSApplication.didBecomeActive`; iOS refreshes only when
`scenePhase` becomes `.active`. If Lorvex remains active across midnight, neither
transition occurs. A minute-based `TimelineView` updates the calendar now-line,
but it does not reload the store's Today, focus, habit, review, reminder, badge,
widget, and menu-bar snapshots.

The failure is compositional: a user action after midnight can calculate a new
day while the visible collection still represents the previous day. With L1,
some paths may calculate the old day and others the new one.

Evidence:

- `Sources/LorvexApple/Stores/AppStoreRuntimeLifecycle.swift`
- `Sources/LorvexMobileApp/LorvexMobileApp.swift`
- `Sources/LorvexApple/Views/CalendarWeekGridView.swift`
- `Sources/LorvexMobile/MobileCalendarDayColumn.swift`

Release condition: make day/time/zone invalidation a first-class lifetime
trigger. On receipt, clear the relevant date-derived caches and run the same
coalesced refresh/replan path as activation. Also compare a stored last-refresh
day/zone on every activation because Apple does not guarantee precise day-change
notification delivery.

### L3 — HIGH — Database replacement is not an atomic cutover for open windows

`AppStore.replaceCore` currently performs this sequence:

1. assign the new core to the main store;
2. reset main runtime state;
3. fully refresh the main store;
4. only then iterate open detached stores and ask them to adopt the new core.

During the main refresh, a sticky or detached list window still points at the old
database and can commit there. The edit appears successful but disappears from
the newly active database. This violates the repository's documented
multi-store invariant.

Adoption also ignores the dirty-draft rule. `adoptReplacedCore` assigns the new
core and calls `loadDetachedTaskWindow`; that calls
`syncSelectedTaskDraft(force: true)`. An unsaved sticky note can therefore be
overwritten by the task loaded from the replacement database. The ordinary
key-window reload explicitly avoids this when `selectedTaskDraftHasChanges` is
true, but the database-swap path bypasses that guard.

Evidence:

- `Sources/LorvexApple/Stores/AppStoreRuntimeLifecycle.swift`
- `Sources/LorvexApple/Stores/AppStoreDetachedWindowState.swift`
- `Sources/LorvexApple/Views/StickyTaskWindow.swift`
- `docs/architecture/MULTI_STORE_COHERENCE.md`

The existing tests verify basic replacement and selection isolation, but do not
hold an unsaved detached draft or an in-flight detached write during cutover.

Release condition: define a cutover barrier shared by every store. Block new
writes, resolve or explicitly discard dirty drafts, atomically publish the new
core generation, invalidate all stores, then resume. Every operation should
verify the generation immediately before commit so a pre-cutover task cannot
write the old database after the barrier. Test failure/rollback of the new core
open as well as success.

### L4 — MEDIUM-HIGH — Draft durability depends on timing and view callbacks

The Mac task inspector and daily review debounce saves by about 1.2 seconds.
`ReviewsWorkspaceView` explicitly notes that quitting within the debounce is not
otherwise flushed. There is no `applicationShouldTerminate` coordination with
the store. Sticky notes save on loss of key status, but normal Quit and process
termination are not a proven loss-of-key sequence, and `.task` / `onDisappear`
work can be cancelled during teardown.

On iOS, daily review has an explicit Save button and only saves from that action
or the final field's submit. Capture, task-edit, list, habit, calendar, memory,
and review drafts are ordinary in-memory state. The app has no background-phase
draft snapshot or `SceneStorage` restoration. Suspension, jetsam, or force quit
therefore loses the current uncommitted form.

No callback can make force quit safe. The product needs an explicit contract:

- either unsaved form text is disposable and the UI must make that clear;
- or recoverable drafts are written incrementally to a local, versioned,
  database-scoped draft journal and removed after commit/cancel.

For normal Mac Quit only, AppKit's terminate-later flow can finish a bounded
critical write, but it is not a replacement for eager durability.

Evidence:

- `Sources/LorvexApple/Views/TaskDetailView.swift`
- `Sources/LorvexApple/Views/ReviewsWorkspaceView.swift`
- `Sources/LorvexApple/Views/StickyTaskWindow.swift`
- `Sources/LorvexMobile/MobileStoreReviewView.swift`
- `Sources/LorvexMobile/MobileStore.swift`

Release condition: write down which drafts survive navigation, background,
normal Quit, crash, jetsam, and force quit. Test the chosen behavior at every
point in the debounce and while a database write is in flight.

### L5 — MEDIUM-HIGH ARCHITECTURE GATE — iPad multi-window is disabled, and the current store is not scene-safe

The iOS Info.plist does not contain
`UIApplicationSupportsMultipleScenes = true` in a scene manifest, so the app is
currently single-window on iPadOS despite declaring a SwiftUI `WindowGroup`.
That is a valid current product decision and prevents a live correctness bug.

However, the `MobileStore` is created as `@State` on the top-level `App`, outside
the `WindowGroup` content. If multi-window is later enabled, every scene would
share selected tab, navigation paths, selected task/list/habit, sheet flags,
drafts, loading flags, and mutation guards. One window's navigation or editor
would change another window. Apple's `WindowGroup` contract says state created
inside the scene hierarchy is independent per window; Lorvex's scene state is
currently above that boundary.

Evidence:

- `Config/LorvexMobileApp-Info.plist`
- `Sources/LorvexMobileApp/LorvexMobileApp.swift`
- `Sources/LorvexMobile/MobileStore.swift`

Freeze decision: keep iPad multi-window explicitly unsupported for 1.0, or split
the architecture before enabling the plist key. A future design should share
only durable services/core and app-lifetime coordinators; each scene must own
navigation, presentations, selection, and drafts. Add a per-scene restoration
identifier and database-generation namespace.

### L6 — MEDIUM — Mac lifetime observers start from one window, not the app lifetime

The store describes its CloudKit, EventKit, account, notification, activation,
and database-signal observers as app-lifetime observers. They are actually
started only by `LorvexMainWindowView.onAppear`. Standalone workspace windows,
detached windows, the menu-bar extra, and Settings refresh or mutate the same
store but do not start the observer set.

Ordinary launch currently tends to present the main window, so the common path
works. A restored/non-main-only launch, a future launch-at-login menu-bar mode,
or a lifecycle change that suppresses the main window can leave the supposedly
app-lifetime store without observers. `presentMainWindowIfNeeded` also returns
when any usable Lorvex window is found, not specifically when the main window
has appeared.

Evidence:

- `Sources/LorvexApple/Views/LorvexMainWindowView.swift`
- `Sources/LorvexApple/App/AppDelegate.swift`
- `Sources/LorvexApple/App/LorvexSystemScenes.swift`
- `Sources/LorvexApple/Views/LorvexWorkspaceWindowView.swift`

Release condition: start application-lifetime services from an application
bootstrap owner with an explicit shutdown path, independently of any window.
Test launch into each restorable/external entrypoint with the main window closed.

### L7 — MEDIUM — Restoration policy is fragmented and not release-tested

Mac main navigation is process-wide `UserDefaults`; detached WindowGroup values
are restored by SwiftUI; much other view state is plain `@State`; and
`applicationSupportsSecureRestorableState` explicitly returns `false`. There is
no consolidated policy explaining which windows, selections, drafts, sheets,
calendar ranges, and scroll positions should return after a normal quit, crash,
or OS restart.

Returning `false` does not by itself prove a vulnerability or disable all
SwiftUI window restoration. It is an explicit opt-out of the delegate's secure
restorable-state capability and needs a reason, especially while value-keyed
windows rely on system restoration. Restored task/list IDs can also belong to a
different database after external storage selection changes.

Release condition: define and test a small restoration schema containing only
non-sensitive identifiers and navigation state; validate every restored ID
against the active database generation; and either justify the secure-state
opt-out or enable and test secure restoration. Never place task content or other
sensitive text into `SceneStorage`.

### L8 — MEDIUM — There is no memory-pressure degradation policy

The mobile store retains task caches, list detail, habit details, calendar
timelines, review digests, memory history, recent diagnostics, navigation paths,
and draft state. No app delegate or observer handles iOS memory warnings, and no
source policy distinguishes reloadable caches from user-authored state.

The static audit does not show that current normal data sets exceed memory
limits. It does show that the app cannot deliberately shed reloadable state as
data sets and multi-surface caches grow. Apple specifically recommends reducing
memory promptly and considering unsaved-data durability during memory pressure.

Release condition: measure first. If the signed-build matrix approaches the
budget, discard bounded reloadable caches/history on warning or background while
retaining navigation identifiers and durably journaling any promised drafts.
Verify the next foreground refresh reconstructs every discarded surface.

### L9 — RELEASE GATE — Unit tests do not exercise process and scene transitions

The suite has valuable tests for refresh coalescing, CloudKit push handoff,
window placement, navigation restoration, detached selection isolation, and
basic core replacement. It does not provide process-level evidence for:

- cold launch versus warm activation;
- normal Quit during debounce, SIGKILL/force quit, crash, or jetsam;
- midnight, daylight-saving transition, clock correction, locale/calendar, or
  live time-zone change;
- automatic Mac window restoration and missing/deleted restored IDs;
- database replacement with dirty/in-flight detached windows;
- memory warning and reconstruction after cache eviction;
- iPad multi-window isolation, if that capability is ever enabled.

These require UI/process tests and physical-device runs; an in-memory unit test
cannot prove OS lifecycle delivery or restoration timing.

## Release Scenario Matrix

| Scenario | macOS | iPhone/iPad current static result | Required evidence |
| --- | --- | --- | --- |
| First install / cold launch | Main presentation and refresh exist | Root refresh plus scene-active refresh coalesce | exact Release archive, empty and migrated DB |
| Relaunch with stale selected ID | Main selection reconciles | navigation is not restored | deleted ID, changed DB, signed-out iCloud |
| Close/reopen last visible window | Dock recovery exists; menu-bar lifetime assumed | not applicable | close main with workspace/sticky open and with none |
| Normal Quit while editing | debounce race / no termination barrier | background has no draft flush | kill at 0, 0.5, 1.2 seconds and during commit |
| Force quit / crash / jetsam | uncommitted drafts lost | uncommitted drafts lost | verify committed SQLite/outbox atomicity and chosen draft policy |
| CloudKit push before UI exists | Mac delegate posts in process | durable mobile handoff exists | terminated/background/foreground device cases |
| Remain foreground over midnight | no store refresh trigger | no store refresh trigger | today/focus/habit/review/widget/badge/reminders |
| Change time zone while alive | cached formatter remains old | cached formatter remains old | west/east Date Line, DST, 12/24-hour change |
| Replace database with open windows | cutover window and dirty-draft clobber | feature is Mac-only | sticky/list write during cutover, failure rollback |
| Restore detached windows | SwiftUI value restoration, no consolidated test | multi-window disabled | valid, missing, deleted, wrong-database IDs |
| Memory warning / background eviction | unmeasured | no cache-shedding policy | simulator warning plus real-device pressure/relaunch |

## State Ownership Recommendation

Freeze this ownership model before adding more windows:

| State class | Owner | Durability |
| --- | --- | --- |
| SQLite data, outbox, sync checkpoints | core/database generation | transactional and crash-safe |
| CloudKit/EventKit/push observers | one application-lifetime coordinator | process lifetime; restartable/idempotent |
| navigation, selection, sheet/popover, scroll | one scene/window store | optional lightweight per-scene restoration |
| user-authored unsaved drafts | one scene, namespaced by database + entity + schema version | explicit product policy; journal locally if promised across termination |
| reloadable snapshots and histories | scene cache | bounded and discardable under pressure |
| database selection and active generation | one application authority | atomic cutover observed by all stores |

This preserves the existing good separation between durable domain data and UI
state while making time, termination, and database generation explicit inputs
instead of incidental callbacks.

## Freeze Recommendation

L1, L2, and L3 should be resolved before calling the Apple data behavior final:
they can place otherwise valid operations on the wrong local day or in the wrong
database. L4 and L5 require explicit product decisions before release, but they
do not require changing the synced schema. Restoration and cache policies should
use versioned local state and stable IDs; they must not become CloudKit fields.
