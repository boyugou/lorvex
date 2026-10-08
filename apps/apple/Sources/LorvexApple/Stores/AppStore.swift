import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Observation
import SwiftUI
import UserNotifications
import LorvexCloudSync

@MainActor
@Observable
final class AppStore {
  // MARK: - Per-domain storage structs

  var todayStorage = AppStoreTodayStorage()
  var dailyReviewStorage = AppStoreDailyReviewStorage()
  var listsStorage = AppStoreListsStorage()
  var calendarStorage = AppStoreCalendarStorage()
  var calendarDraftStorage = AppStoreCalendarDraftStorage()
  var taskDetailStorage = AppStoreTaskDetailStorage()
  var taskWorkspaceStorage = AppStoreTaskWorkspaceStorage()
  var habitsStorage = AppStoreHabitsStorage()
  var memoryStorage = AppStoreMemoryStorage()
  var syncReportsStorage = AppStoreSyncReportsStorage()

  // MARK: - Navigation (persisted; kept flat — tied to UserDefaults)

  var selection: SidebarSelection = .today {
    didSet {
      defaults.set(selection.rawValue, forKey: Key.selection)
      // Clear `selectedTaskID` when leaving Tasks-style workspaces — the
      // detail pane is meaningless on Habits / Memory, and a stale ID survives
      // across launches via UserDefaults producing a blank detail pane when the
      // underlying task has been deleted on another device. Workspaces that
      // consume the selection on navigation: today, tasks, lists
      // (see `selectionUsesSelectedTaskID`). Calendar is the
      // exception — it clears on navigation but opens the inspector on an
      // explicit event tap, which `reconcileSelectedTaskAfterRefresh` preserves.
      if !Self.selectionUsesSelectedTaskID(selection) {
        selectedTaskID = nil
      }
      // The habit inspector only belongs in the Habits workspace; drop the
      // selection when navigating away so it can't reopen on an unrelated tab.
      if selection != .habits {
        selectedHabitID = nil
      }
      if selection != oldValue {
        // A query narrows only the workspace it was typed in.
        searchText = ""
        // An event's detail belongs to the workspace it was opened in.
        clearSelectedCalendarEvent()
      }
    }
  }

  /// The habit shown in the trailing inspector (Habits workspace). Enforced
  /// mutually exclusive with ``selectedTaskID`` so the single inspector pane
  /// never has two competing subjects (which stranded a stale selection and
  /// could wedge the pane open on a deleted item).
  var selectedHabitID: LorvexHabit.ID? {
    didSet {
      if selectedHabitID != nil, selectedTaskID != nil {
        selectedTaskID = nil
      }
    }
  }
  var selectedTaskID: LorvexTask.ID? {
    didSet {
      persistSelectedTaskID()
      if selectedTaskID == nil {
        clearSelectedTaskDraft()
      } else {
        if selectedHabitID != nil {
          selectedHabitID = nil
        }
        // Today's inspector shows one subject: a task opened there replaces
        // an open event.
        if selection == .today, selectedCalendarEventID != nil {
          clearSelectedCalendarEvent()
        }
      }
    }
  }

  /// Whether Today's Done section is folded, remembered across launches. The
  /// store owns it rather than the view so arrow keys, shift-click ranges, and
  /// Select All on Today skip exactly the rows the fold hides.
  var isTodayDoneCollapsed = false {
    didSet { defaults.set(isTodayDoneCollapsed, forKey: Key.todayDoneCollapsed) }
  }

  /// Whether the main window's trailing inspector is open: for a selected
  /// task, a selected habit, or an event opened from Today's schedule
  /// (``todayInspectorEvent``).
  var isMainInspectorOpen: Bool {
    selectedTaskID != nil || selectedHabitID != nil || todayInspectorEvent != nil
  }

  /// Collapse whichever right-hand inspector is open (task, habit, or Today's
  /// event), the same effect as its ✕ or re-clicking the open row. Returns
  /// whether anything was dismissed so an Escape handler can let the key fall
  /// through when no inspector is open.
  @discardableResult
  func dismissOpenInspector() -> Bool {
    guard isMainInspectorOpen else { return false }
    selectedTaskID = nil
    selectedHabitID = nil
    if todayInspectorEvent != nil {
      clearSelectedCalendarEvent()
    }
    return true
  }

  /// Non-nil while a recurring task's cancel is awaiting the occurrence-vs-series
  /// scope choice, and the explicit task the scope dialog acts on. Set by
  /// ``requestCancel(_:)`` (from any task surface — context menu or detail pane)
  /// and consumed by the shared `.lorvexRecurringCancelDialog(_:)` modifier
  /// mounted at every task-bearing scene root (main window, detached workspace
  /// windows, detached task window), so every surface offers the same choice
  /// instead of silently cancelling just the occurrence. The dialog passes this
  /// id to ``cancelRecurringTask(id:scope:)`` so a selection change in another
  /// window can't redirect the cancel. Always `nil` for non-recurring tasks,
  /// which cancel immediately.
  var pendingRecurringCancelTaskID: LorvexTask.ID?

  /// Non-nil while a batch cancel selection containing at least one recurring
  /// task is awaiting the same occurrence-vs-series scope choice. The selected
  /// task ids are captured with the surface that requested the action, so a
  /// later selection change cannot retarget the batch before the dialog choice
  /// resolves.
  var pendingRecurringBatchCancel: AppStorePendingRecurringBatchCancel?

  /// The task awaiting the irreversible "Delete Permanently…" confirmation. Set
  /// by ``requestPermanentDelete(_:)`` from any task surface (detail pane or
  /// context menu) and consumed by the shared `.lorvexPermanentDeleteDialog(_:)`
  /// modifier mounted at every task-bearing scene root, so the destructive
  /// confirmation appears regardless of which window raised it.
  var pendingPermanentDeleteTask: LorvexTask?

  // MARK: - Task capture

  /// Monotonic counter the New Task command (⌘N) bumps via
  /// `requestQuickAddFocus()`. Every `QuickAddRow` observes it and claims
  /// keyboard focus when the value changes, so capture happens inline in the
  /// current surface instead of in a popup window.
  var quickAddFocusToken = 0

  // MARK: - Search (kept flat)

  /// The query typed into the current workspace's toolbar search field. Only
  /// All Tasks and Memory have one, and the query is cleared whenever the
  /// workspace or the Tasks list scope changes, so it never filters a surface
  /// that shows no field.
  var searchText = ""

  /// Set by Find (⌘F) and cleared by the search field that takes focus. A flag
  /// rather than a counter, so a workspace that appears after the request —
  /// Find from a workspace without search opens All Tasks — still sees it
  /// pending.
  var isSearchFocusRequested = false

  /// Tasks due today or overdue, computed from the same full task pool and
  /// "today" the app-icon badge uses, so the menu-bar attention chip/glyph and
  /// the dock badge always show the same number. Updated whenever the badge is.
  var menuBarAttentionCount = 0

  // MARK: - Settings navigation

  /// A Settings category another surface asked the Settings window to show,
  /// such as the first-run wizard's Connect an Assistant button. The Settings
  /// window selects it when it opens, or at once when it is already open, and
  /// then clears it.
  var requestedSettingsCategory: SettingsCategory?

  // MARK: - Command palette (⌘K overlay; kept flat)

  /// Drives the ⌘K command-palette sheet presented from `ContentView`. Toggled
  /// by the menu command so a `Commands` button can drive a view-owned sheet.
  var showCommandPalette = false

  /// True while a create action is writing through the core and reading the
  /// surfaces that show the new row. The list, habit, and calendar sheets guard
  /// their actions on it and disable their confirm button on it, so a double
  /// Return cannot start a duplicate create. It is released before any
  /// post-commit fan-out (Spotlight, reminders, badge, widget, sync), which can
  /// take as long as a CloudKit cycle. Task capture never raises it: the inline
  /// quick-add rows and the global capture serialize through
  /// `inlineCaptureCommitTail` instead.
  var isCreating = false

  /// The most recent task-capture commit (`createInlineTask(_:destination:)` or
  /// `captureLine(_:)`). Each commit is a write plus the reads that show the new
  /// row; the next commit awaits this one first, so lines typed back to back
  /// all land, in order, without their reads interleaving.
  @ObservationIgnored var inlineCaptureCommitTail: Task<Void, Never>?

  /// Coalescing single-flight for the fan-out a task create owes the rest of
  /// the system (`publishAfterTaskCreate()`): Spotlight, reminders, badge,
  /// widget snapshot, one sync cycle. A create that lands while a pass is in
  /// flight arms one trailing pass instead of running a second reminder re-plan
  /// against the same notification center.
  @ObservationIgnored let taskCreateFanOutFlight = RefreshSingleFlight<Void>()

  /// Coalescing single-flight for the full `refresh()` fan-out. A trigger
  /// arriving while a refresh is in flight — a database-change signal,
  /// `didBecomeActive`, or a CloudKit push, each from its own stream — does not
  /// start a parallel run; it arms one trailing rerun so a write that
  /// committed after the in-flight refresh began its reads is still picked up
  /// rather than staying invisible until the next unrelated trigger. Any number
  /// of mid-flight triggers collapse into a single rerun.
  @ObservationIgnored let refreshFlight = RefreshSingleFlight<Void>()

  /// Coalescing single-flight for CloudKit cycles. A local mutation, remote
  /// push, or lifecycle trigger that arrives after an in-flight cycle's final
  /// outbound scan must arm one trailing pass instead of being dropped; that
  /// pass is what guarantees newly committed outbox work is not stranded until
  /// an unrelated future activation.
  @ObservationIgnored let cloudSyncCycleFlight = RefreshSingleFlight<Void>()

  var isCloudSyncCycleRunning: Bool { cloudSyncCycleFlight.isRunning }

  /// True while a full `refresh()` fan-out is in flight. Read by the tail sync
  /// cycle to choose between an inline selective reload and a trailing full
  /// rerun.
  var isRefreshing: Bool { refreshFlight.isRunning }

  /// True when the in-flight fan-out has a trailing rerun armed but not yet run;
  /// always false once `refresh()` has settled.
  var refreshPending: Bool { refreshFlight.isPendingRerun }

  /// Advances each time the store has re-read task data after a change: when
  /// a local refresh pass ends, after a local mutation, and after an inbound
  /// sync that touched tasks, lists, Today, or the calendar. A view that reads
  /// tasks outside the published collections, such as the tasks the selected
  /// task waits on, keys a re-read on it. Only those three paths write it.
  var taskDataGeneration: UInt64 = 0

  /// The selected task's ID while a task it waits on is unfinished, so it
  /// cannot start; `nil` while it can, or before it has been read. Only
  /// ``refreshSelectedTaskStartGate()`` writes it.
  var heldUpTaskID: LorvexTask.ID?

  /// App-lifetime change-observer tasks (CloudKit push refresh, EventKit
  /// ingestion, notification-action error toasts), started once via
  /// `startLifetimeObserversIfNeeded`. The store outlives any single window, so
  /// holding them here keeps them running after the main window closes while the
  /// menu-bar extra keeps the app alive.
  @ObservationIgnored var lifetimeObserverTasks: [Task<Void, Never>] = []

  /// One main-app-owned wake at midnight in the configured product timezone.
  /// Device-midnight notifications are insufficient when the Mac and synced
  /// product zones differ.
  @ObservationIgnored var logicalDayBoundaryWakeTask: Task<Void, Never>?

  // MARK: - Diagnostics (single property; kept flat)

  var runtimeDiagnostics: RuntimeDiagnosticsSnapshot?

  /// Mirrors `AppSettingsStore.badgeEnabled`. When true, the app-icon badge
  /// is updated to the overdue/due-today task count after each refresh.
  var badgeEnabled: Bool = true

  /// Mirrors `AppSettingsStore.setupCompleted`: whether this device's local
  /// first-run setup wizard has finished. Read once at launch and flipped to
  /// `true` by `ContentView`'s wizard-dismissal handler. `rescheduleReminders`
  /// uses it (via `ReminderOnboardingGate`) to withhold the very first
  /// background reminder re-plan's authorization request until the wizard's
  /// own "Allow" row has had its chance, or setup completes.
  var isSetupCompleted: Bool = true

  /// Live `UNUserNotificationCenter` authorization read, injected so tests can
  /// script the OS decision deterministically instead of depending on the test
  /// host process's real (and unentitled) notification authorization state.
  let notificationAuthorizationStatusProvider: @Sendable () async -> UNAuthorizationStatus

  /// Reset-only erasure hook for notifications the OS has already delivered.
  /// Ordinary reminder replacement intentionally owns only pending requests;
  /// factory reset has the stronger privacy contract and must also remove
  /// previously delivered Lorvex content from Notification Center. Production
  /// wires `UNUserNotificationCenter`; tests and previews remain inert unless
  /// they inject a recorder.
  let clearDeliveredNotificationsForFactoryReset: @Sendable () async -> Void

  // MARK: - Error surface

  /// Drives the blocking alert in `ContentView`. Set for errors that require
  /// explicit user acknowledgement (e.g. core write failures on mutation).
  var errorMessage: String?

  /// The message of the refresh failure already shown in the blocking alert. A
  /// refresh runs on its own (activation, sync, database change), so the same
  /// failure is shown once and then only logged until a refresh succeeds; see
  /// ``presentRefreshFailure(_:)``.
  @ObservationIgnored var surfacedRefreshFailureMessage: String?

  /// Drives the auto-dismissing toast in `ContentView`. Set for transient
  /// action failures that don't require acknowledgement (e.g. export errors,
  /// reorder persistence failures). Cleared automatically after the toast
  /// duration elapses or when the user taps it. When no window shows the toast
  /// (the main window is closed), the store clears it itself after
  /// ``toastLifetime`` so it does not surface hours later.
  var toastMessage: String? {
    didSet { scheduleToastExpiry() }
  }

  /// How long the store keeps a toast that no window has dismissed. Longer than
  /// the toast view's own timer, so a toast on screen is cleared by the view
  /// first.
  @ObservationIgnored var toastLifetime = Duration.seconds(8)

  /// The pending clear of ``toastMessage``; see ``scheduleToastExpiry()``.
  @ObservationIgnored var toastExpiry: Task<Void, Never>?

  /// Drives the transient milestone-celebration overlay in `ContentView`. Set by
  /// a habit completion that just crossed a milestone waypoint; cleared when the
  /// overlay auto-dismisses or the user taps it. Distinct from `toastMessage` so
  /// a celebration renders as a richer, animated badge rather than a status pill.
  var milestoneCelebration: HabitMilestoneCelebration?

  /// Drives a one-time, dismissible alert in `ContentView` when the on-disk
  /// database had to be quarantined on open (schema mismatch / corruption) and a
  /// fresh one was created. Composed once from the core's `databaseRecoveryNotice`
  /// on the first refresh so the quarantine is never silent; `nil` otherwise.
  var databaseRecoveryMessage: String?

  /// Latches `databaseRecoveryMessage` so the quarantine notice surfaces exactly
  /// once — across repeated refreshes and after the user dismisses it.
  @ObservationIgnored var hasSurfacedDatabaseRecoveryNotice = false

  // MARK: - Services

  var core: any LorvexCoreServicing

  /// Weak references to the per-window stores spawned by `makeDetachedWindowStore`.
  /// A factory reset rebuilds the managed core; `replaceCore` propagates the fresh
  /// core to these windows so an open detached task / list window doesn't keep
  /// writing to the reset store's stale handle (those edits would look successful
  /// yet appear nowhere else). Weak so closed windows are not retained; pruned on
  /// each spawn and propagation.
  @ObservationIgnored var detachedWindowStores: [WeakAppStoreBox] = []

  /// Convergence observers a detached task/list window runs so it stays current
  /// with out-of-band writes (the MCP host in another process, an edit in the
  /// main window) without its own CloudKit stack. A detached store is built with
  /// `cloudSyncMode == .off` and no coordinator, so it cannot see those writes on
  /// its own; this task relays the unified DB-change signal into a reload
  /// of just the entity the window shows. Started once on window open via
  /// `startDetachedWindowObserversIfNeeded()` and cancelled on window close via
  /// `stopDetachedWindowObservers()`, so nothing leaks per opened window. Empty
  /// on the main store, which converges through `lifetimeObserverTasks` +
  /// `refresh()` instead.
  @ObservationIgnored var detachedWindowObserverTasks: [Task<Void, Never>] = []
  /// Invalidates detached reload work when its window closes, its observer is
  /// restarted, or its core is replaced. Cancelling the notification-sequence
  /// task alone is insufficient: a delivery or direct reload may already be
  /// suspended in an old-core read.
  @ObservationIgnored var detachedWindowObserverEpoch: UInt64 = 0

  /// Single-flight guard for the detached-window entity reload. A change signal
  /// arriving while a reload is in flight sets `detachedWindowReloadPending` so
  /// exactly one rerun follows, instead of stampeding one reload per signal on a
  /// burst. Mirrors the `isRefreshing`/`refreshPending` discipline the main
  /// store's `refresh()` uses.
  @ObservationIgnored var isReloadingDetachedWindowEntity = false
  @ObservationIgnored var detachedWindowReloadPending = false

  /// A peer change arrived while this detached task window had unsaved edits.
  /// The reload is deferred until the draft becomes clean; the sticky-window
  /// view observes that transition and resumes convergence without requiring a
  /// second external write or a focus change.
  @ObservationIgnored var detachedWindowReloadDeferredForDraft = false
  let feedbackProvider: any LorvexFeedbackProviding
  let taskSearchIndexer: any TaskSearchIndexing
  let contentSearchIndexer: any ContentSearchIndexing
  let taskReminderScheduler: any TaskReminderScheduling
  let habitReminderScheduler: any HabitReminderScheduling
  let widgetSnapshotPublisher: any WidgetSnapshotPublishing
  var cloudSyncMode: CloudSyncMode
  /// Optional policy inherited by a coordinator-less detached window. CloudKit
  /// ownership and retention policy are separate concerns: a detached window
  /// must never run sync, but it must still honor the parent app's live-mode
  /// guarantee that active outbox debt is not capped.
  @ObservationIgnored let includeActiveOutboxCapProvider: (@MainActor @Sendable () -> Bool)?

  var shouldIncludeActiveOutboxCap: Bool {
    includeActiveOutboxCapProvider?() ?? (cloudSyncMode != .live)
  }
  /// The CloudKit transport. It exists whenever the app can reach CloudKit,
  /// whether or not sync is on, because deleting iCloud data works with sync
  /// off; it runs an engine only while ``cloudSyncMode`` is `.live` and the
  /// iCloud account allows it. Nil in previews and tests without CloudKit.
  @ObservationIgnored let cloudSyncController: CloudSyncController?
  /// EventKit two-way coordinator (tiered read into the local provider mirror +
  /// isolated write-back into the dedicated Lorvex calendar). Set at startup
  /// once the concrete provider-capable core + real `EventKitAccessing` exist;
  /// nil in previews/tests, where the calendar timeline stays canonical-only.
  var eventKitCoordinator: EventKitCoordinator?
  var eventKitIntegrationEnabled: Bool
  let setBadge: @Sendable (Int) async -> Void
  let now: @Sendable () -> Date
  let defaults: UserDefaults

  /// True from the user's final restore confirmation through the post-import
  /// refresh. Settings uses this shared store state (rather than per-window
  /// view state) to keep mode changes and destructive maintenance from racing a
  /// multi-record import in another Settings window.
  var isDataImportRunning = false
  /// Prevents a second Settings window from capturing the old core while a
  /// factory reset closes and replaces the managed database.
  var isLocalFactoryResetRunning = false
  /// Suppresses a mode-toggle re-enable requested before an in-flight explicit
  /// cloud deletion reaches its terminal state. Such an early request predates
  /// the deletion result and must not recreate the just-deleted generation.
  var isCloudDataDeletionRunning = false
  /// Request-time fence for re-enable intents. Incremented synchronously when
  /// an explicit deletion is accepted, so a Task created by an earlier mode
  /// toggle cannot wake after deletion and authorize a fresh generation.
  @ObservationIgnored var cloudDataDeletionEpoch: UInt64 = 0

  init(
    core: any LorvexCoreServicing,
    feedbackProvider: any LorvexFeedbackProviding = NoOpFeedbackProvider(),
    taskSearchIndexer: any TaskSearchIndexing = NoopTaskSearchIndexer(),
    contentSearchIndexer: any ContentSearchIndexing = NoopContentSearchIndexer(),
    taskReminderScheduler: any TaskReminderScheduling = NoopTaskReminderScheduler(),
    habitReminderScheduler: any HabitReminderScheduling = NoopHabitReminderScheduler(),
    widgetSnapshotPublisher: any WidgetSnapshotPublishing = NoopWidgetSnapshotPublisher(),
    cloudSyncMode: CloudSyncMode = .off,
    includeActiveOutboxCapProvider: (@MainActor @Sendable () -> Bool)? = nil,
    cloudSyncController: CloudSyncController? = nil,
    eventKitCoordinator: EventKitCoordinator? = nil,
    eventKitIntegrationEnabled: Bool? = nil,
    badgeEnabled: Bool = true,
    isSetupCompleted: Bool = true,
    // Safe, inert default: previews/tests/any caller that never wires the live
    // read get "already resolved" (never withholds, never touches the real
    // `UNUserNotificationCenter` — unavailable in the SwiftPM test-runner
    // process). `LorvexAppleBootstrap` wires the real system read.
    notificationAuthorizationStatusProvider: @escaping @Sendable () async -> UNAuthorizationStatus = {
      .authorized
    },
    clearDeliveredNotificationsForFactoryReset: @escaping @Sendable () async -> Void = {},
    setBadge: @escaping @Sendable (Int) async -> Void = { _ in },
    now: @escaping @Sendable () -> Date = Date.init,
    defaults: UserDefaults = .standard
  ) {
    self.core = core
    self.feedbackProvider = feedbackProvider
    self.taskSearchIndexer = taskSearchIndexer
    self.contentSearchIndexer = contentSearchIndexer
    self.taskReminderScheduler = taskReminderScheduler
    self.habitReminderScheduler = habitReminderScheduler
    self.widgetSnapshotPublisher = widgetSnapshotPublisher
    self.cloudSyncMode = cloudSyncMode
    self.includeActiveOutboxCapProvider = includeActiveOutboxCapProvider
    self.cloudSyncController = cloudSyncController
    self.eventKitCoordinator = eventKitCoordinator
    self.eventKitIntegrationEnabled = eventKitIntegrationEnabled ?? (eventKitCoordinator != nil)
    self.badgeEnabled = badgeEnabled
    self.isSetupCompleted = isSetupCompleted
    self.notificationAuthorizationStatusProvider = notificationAuthorizationStatusProvider
    self.clearDeliveredNotificationsForFactoryReset =
      clearDeliveredNotificationsForFactoryReset
    self.setBadge = setBadge
    self.now = now
    self.defaults = defaults
    self.isTodayDoneCollapsed = defaults.bool(forKey: Key.todayDoneCollapsed)
  }
}
