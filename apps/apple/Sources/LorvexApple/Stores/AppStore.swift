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

  var focusStorage = AppStoreFocusStorage()
  var dailyReviewStorage = AppStoreDailyReviewStorage()
  var listsStorage = AppStoreListsStorage()
  var calendarStorage = AppStoreCalendarStorage()
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
      // consume the selection on navigation: today, tasks, focus, lists
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
      } else if selectedHabitID != nil {
        selectedHabitID = nil
      }
    }
  }

  /// Collapse whichever right-hand inspector is open (task or habit), the same
  /// effect as its ✕ or re-clicking the open row. Returns whether anything was
  /// dismissed so an Escape handler can let the key fall through when no
  /// inspector is open.
  @discardableResult
  func dismissOpenInspector() -> Bool {
    guard selectedTaskID != nil || selectedHabitID != nil else { return false }
    selectedTaskID = nil
    selectedHabitID = nil
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

  // MARK: - Task capture drafts (small cluster; kept flat)

  var draftTitle = ""
  var draftNotes = ""

  /// Monotonic counter the New Task command (⌘N) and empty-state capture
  /// buttons bump via `requestQuickAddFocus()`. Every `QuickAddRow` observes it
  /// and claims keyboard focus when the value changes, so capture happens inline
  /// in the current surface instead of in a popup window.
  var quickAddFocusToken = 0

  // MARK: - Search (single property; kept flat)

  var searchText = ""

  /// Tasks due today or overdue, computed from the same full task pool and
  /// "today" the app-icon badge uses, so the menu-bar attention chip/glyph and
  /// the dock badge always show the same number. Updated whenever the badge is.
  var menuBarAttentionCount = 0

  // MARK: - Command palette (⌘K overlay; kept flat)

  /// Drives the ⌘K command-palette sheet presented from `ContentView`. Toggled
  /// by the menu command so a `Commands` button can drive a view-owned sheet.
  var showCommandPalette = false

  /// True while a capture/create action is writing through the core. Create
  /// surfaces clear their draft only after the write plus a Spotlight reindex
  /// and sync fan-out, a window in which a second Return would otherwise start a
  /// duplicate create; the action guards on this flag and the buttons disable on
  /// it.
  var isCreating = false

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

  /// One app-owned wake for retry/deferred CloudSync work. It never runs in the
  /// MCP host or extensions; those processes only author the shared outbox.
  @ObservationIgnored var cloudSyncRetryWakeTask: Task<Void, Never>?
  @ObservationIgnored var cloudSyncRetryWakeGeneration: UInt64 = 0

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

  /// Drives the auto-dismissing toast in `ContentView`. Set for transient
  /// action failures that don't require acknowledgement (e.g. export errors,
  /// reorder persistence failures). Cleared automatically after the toast
  /// duration elapses or when the user taps it.
  var toastMessage: String?

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
  let cloudSyncSubscriber: any CloudSyncSubscribing
  /// Drives one invisible sync cycle (outbound `sync_outbox` → CloudKit, inbound
  /// CloudKit → `applyEnvelope`) against the ported engine. It is nil when the
  /// store starts without a live backend. A live-started store may retain this
  /// value after an explicit cloud deletion flips its runtime mode to Off; the
  /// mode gate still halts cycles and the stable value avoids a second actor
  /// graph over the sync-state directory.
  let cloudSyncCoordinator: CloudSyncEngineCoordinator?
  /// The one coordinator instance used by every iCloud-data maintenance action
  /// for this store, including while ordinary sync is off. In live mode this is
  /// the same coordinator value as ``cloudSyncCoordinator`` (and therefore
  /// shares its operation gate and file-backed actors); in off mode it remains
  /// retained so repeated delete/retry/re-enable actions cannot construct
  /// competing actor sets over one sync-state directory.
  @ObservationIgnored let cloudDataMaintenanceCoordinator: CloudSyncEngineCoordinator?
  /// EventKit two-way coordinator (tiered read into the local provider mirror +
  /// isolated write-back into the dedicated Lorvex calendar). Set at startup
  /// once the concrete provider-capable core + real `EventKitAccessing` exist;
  /// nil in previews/tests, where the calendar timeline stays canonical-only.
  var eventKitCoordinator: EventKitCoordinator?
  var eventKitIntegrationEnabled: Bool
  let setBadge: @Sendable (Int) async -> Void
  let now: @Sendable () -> Date
  let cloudSyncRetrySleep: @Sendable (TimeInterval) async throws -> Void
  let defaults: UserDefaults

  var hasRegisteredSubscription = false
  /// True from the user's final restore confirmation through the post-import
  /// refresh. Settings uses this shared store state (rather than per-window
  /// view state) to keep mode changes and destructive maintenance from racing a
  /// multi-record import in another Settings window.
  var isDataImportRunning = false
  /// Prevents a second Settings window from capturing the old core while a
  /// factory reset closes and replaces the managed database.
  var isLocalFactoryResetRunning = false
  /// Coalesces launch/activation cleanup triggers so they do not queue duplicate
  /// maintenance operations on the retained coordinator.
  var isCloudDeletionMaintenanceRunning = false
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
    cloudSyncSubscriber: any CloudSyncSubscribing = NoOpCloudSyncSubscriber(),
    cloudSyncCoordinator: CloudSyncEngineCoordinator? = nil,
    cloudDataMaintenanceCoordinator: CloudSyncEngineCoordinator? = nil,
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
    cloudSyncRetrySleep: @escaping @Sendable (TimeInterval) async throws -> Void = { delay in
      try await Task.sleep(for: .seconds(delay))
    },
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
    self.cloudSyncSubscriber = cloudSyncSubscriber
    self.cloudSyncCoordinator = cloudSyncCoordinator
    self.cloudDataMaintenanceCoordinator = cloudDataMaintenanceCoordinator ?? cloudSyncCoordinator
    self.eventKitCoordinator = eventKitCoordinator
    self.eventKitIntegrationEnabled = eventKitIntegrationEnabled ?? (eventKitCoordinator != nil)
    self.badgeEnabled = badgeEnabled
    self.isSetupCompleted = isSetupCompleted
    self.notificationAuthorizationStatusProvider = notificationAuthorizationStatusProvider
    self.clearDeliveredNotificationsForFactoryReset =
      clearDeliveredNotificationsForFactoryReset
    self.setBadge = setBadge
    self.now = now
    self.cloudSyncRetrySleep = cloudSyncRetrySleep
    self.defaults = defaults
    restorePersistedLaunchState()
  }
}
