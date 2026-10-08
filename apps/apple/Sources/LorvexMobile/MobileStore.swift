import Foundation
import LorvexCloudSync
import LorvexCore
import LorvexDomain
import Observation
import UserNotifications

@MainActor
@Observable
public final class MobileStore {
  public internal(set) var snapshot: MobileHomeSnapshot
  public var captureDraft: MobileCaptureDraft
  /// Drives the global quick-capture sheet. Quick capture is a sheet raised by
  /// the tab bar's round ＋ (and ⌘N), not a tab — capture is an action, not a
  /// place.
  public var isPresentingCapture = false
  public internal(set) var isLoading = false
  public internal(set) var isCapturing = false
  public var isMutatingTask: Bool { !mutatingTaskIDs.isEmpty || unscopedTaskMutationCount > 0 }
  public internal(set) var mutatingTaskIDs: Set<LorvexTask.ID> = []
  var unscopedTaskMutationCount = 0
  public internal(set) var dailyReview: DailyReviewEntry?
  public internal(set) var selectedReviewDate: String
  public internal(set) var dayReviewEvidence: DayReviewSummary?
  public internal(set) var weekReviewDigest: [DailyReviewEntry] = []
  public internal(set) var weeklyReviewAnchor: String?
  public var dailyReviewDraft: MobileDailyReviewDraft
  public internal(set) var isLoadingDailyReviewDraft = true
  /// Suggested times for today's tasks while the user decides on them in the
  /// schedule; nothing is stored until they are used.
  public internal(set) var proposedDayTimes: DayTimesProposal?
  public internal(set) var isSuggestingDayTimes = false
  public internal(set) var isSavingDayTimes = false
  public internal(set) var isSavingReview = false
  public internal(set) var memory: MemorySnapshot?
  public internal(set) var selectedMemoryKey: MemoryEntry.ID?
  public internal(set) var lists: ListCatalogSnapshot?
  /// Monotonic guard for `loadDailyReviewDraft`. Bumped only by the loader, so
  /// the latest load owns both the commit and the loading flag even when
  /// `selectedReviewDate` is moved by a background refresh (`loadLocalSurfaces`)
  /// that spawns no load of its own — otherwise the flag could strand `true` and
  /// wedge the Review tab on its skeleton.
  var reviewDraftLoadToken = 0
  public var listDraft: MobileListDraft
  public internal(set) var isCreatingList = false
  public internal(set) var isUpdatingList = false
  public internal(set) var isDeletingList = false
  public internal(set) var habits: HabitCatalogSnapshot?
  public internal(set) var selectedHabitID: LorvexHabit.ID?
  public internal(set) var habitDetailsByID: [LorvexHabit.ID: HabitDetail] = [:]
  /// Archived habits for the Habits screen's restore section, loaded when that
  /// screen appears and refreshed after an archive, restore, or delete.
  public internal(set) var archivedHabits: [LorvexHabit] = []
  /// True once ``loadArchivedHabits()`` has read the archived habits. From then
  /// on the full refresh and the habits reload of an inbound sync re-read them
  /// too, so a change made elsewhere reaches the restore section. Until then the
  /// list stays unread: the Habits screen reads it when it appears.
  @ObservationIgnored var archivedHabitsAreLoaded = false
  /// The milestone a completion just crossed, staged for the floating
  /// celebration overlay. Set by ``stageMilestoneCelebrationIfReached(habitID:)``
  /// on a crossing and cleared when the overlay dismisses (tap / auto-timeout).
  var milestoneCelebration: MobileHabitMilestoneCelebration?
  public internal(set) var calendarTimeline: CalendarTimelineSnapshot?
  /// Tasks completed on the logical today, for Today's facts line.
  var doneTodayCount = 0
  /// The tasks completed on the logical today, newest completion first, for
  /// Today's Done section.
  var doneTodayTasks: [LorvexTask] = []
  /// The working hours in minutes since midnight, for Today's overbooked
  /// decision and the Plan week's load; `nil` until loaded.
  var workdayStartMinutes: Int?
  var workdayEndMinutes: Int?
  /// The loaded calendar window's tasks, planned (or, unplanned, due) in it;
  /// a task with a time is drawn on the time axis of its planned day.
  public internal(set) var calendarScheduledTasks: [LorvexTask] = []
  /// Monotonic guard for `refreshCalendarTimeline`: week navigation, the
  /// DatabaseChangeSignal observer, scene-active refresh, and pull-to-refresh can
  /// all request overlapping windows; a superseded load must not pair its events
  /// with a newer window's scheduled tasks (mirrors the macOS `timelineLoadToken`).
  var calendarTimelineLoadToken = 0
  /// The window the calendar surface last asked `refreshCalendarTimeline` for,
  /// recorded before that load awaits anything. A refresh that starts while
  /// the load is in flight supersedes it, so the refresh reloads this window
  /// rather than a today-anchored one; otherwise the week the surface is
  /// about to show would open with its earlier days empty.
  var calendarRequestedWindow: MobileCalendarWindow?
  /// How the calendar shows time: the width-adaptive 1/2/3-day grid, the
  /// seven days of a week, or a month over the chosen day's agenda. A store
  /// opens in the mode the user last switched to
  /// (``switchCalendarPresentationMode(to:onDayKey:)`` remembers it in
  /// `defaults`), Day before any switch. Setting the property directly shows
  /// a mode without remembering it.
  public var calendarPresentationMode: MobileCalendarPresentationMode
  /// A `yyyy-MM-dd` day the next calendar mode to appear opens on: the day a
  /// mode switch carries over (a week column's header, the day Day mode or
  /// the month grid shows). The mode's view clears it once it has opened
  /// there.
  var calendarPendingDayKey: String?
  public var calendarDraft: MobileCalendarDraft
  public internal(set) var isMutatingCalendarEvent = false
  public internal(set) var isExportingCalendarICS = false
  public internal(set) var isExportingData = false
  public internal(set) var runtimeDiagnostics: RuntimeDiagnosticsSnapshot?
  public internal(set) var isLoadingRuntimeDiagnostics = false
  /// Outbox-derived Cloud Sync queue state, and the single source for every
  /// queue depth the UI shows (the Settings → Cloud Sync activity line and the
  /// Diagnostics row). ``refreshSyncStatus()`` re-reads it narrowly whenever the
  /// queue can have moved — Settings appearing, a refresh, a sync cycle that did
  /// work — and ``loadRuntimeDiagnostics()`` assigns it from the snapshot it
  /// just read, so the cheap and the heavy read can never disagree. `nil` until
  /// the first read lands.
  public internal(set) var syncStatus: SyncStatusSnapshot?
  /// Newest-first `error_logs` feed for the Settings "Recent Diagnostics"
  /// section — MetricKit crash/hang/CPU/disk rows plus any other diagnostic
  /// breadcrumbs. Scoped to the `error_log` source so sync-outbox and changelog
  /// operations don't drown out the crash/hang signal.
  public internal(set) var recentDiagnosticLogs: [RecentLogEntry] = []
  /// Outcome of the last task/habit reminder reschedule, mirroring the macOS
  /// shell. A `.failed`/`.permissionDenied` report here (rather than the reports
  /// being discarded) makes a reminder-arming failure observable instead of
  /// silent; a `.failed` habit report also flags that the occurrence read failed
  /// and its reap was skipped to keep the last-good pending notifications.
  public internal(set) var lastTaskReminderScheduleReport: TaskReminderScheduleReport = .disabled
  public internal(set) var lastHabitReminderScheduleReport: TaskReminderScheduleReport = .disabled
  public var badgeEnabled: Bool
  /// Mirrors the local `setupCompleted` flag `MobileSetupWizard` writes.
  /// `rescheduleReminders` uses it (via `ReminderOnboardingGate`) to withhold
  /// the very first background reminder re-plan's authorization request until
  /// the wizard's own Notifications row has had its chance, or setup
  /// completes. Flipped by `LorvexMobileStoreRootView`'s wizard-completion
  /// handler.
  public var isSetupCompleted: Bool
  /// True while one habit write runs, including the reads that show its result.
  /// Habit controls disable on it, and a write that starts while it is set is
  /// dropped. It is released before the widget snapshot and the reminder plan
  /// that follow the write, so those never hold a tap back.
  public internal(set) var isMutatingHabit = false
  /// Guards the immediate habit-reminder policy mutations (add / retime /
  /// toggle / remove) so overlapping taps in the detail editor serialize.
  public internal(set) var isMutatingHabitReminder = false
  public var habitDraft: MobileHabitDraft
  public internal(set) var isCreatingHabit = false
  public internal(set) var isUpdatingHabit = false
  public internal(set) var isDeletingHabit = false
  public var memoryKeyDraft: String
  public var memoryContentDraft: String
  public internal(set) var memoryEditingKey: MemoryEntry.ID?
  public internal(set) var isSavingMemory = false
  public internal(set) var selectedTaskID: LorvexTask.ID?
  public internal(set) var taskCache: [LorvexTask.ID: LorvexTask] = [:]
  /// Monotonic invalidation keys for query/detail state owned by SwiftUI views
  /// rather than by this store. A Cloud/MCP/full-refresh change bumps the
  /// relevant key so an already-visible page re-reads without navigation churn.
  public internal(set) var taskWorkspaceRevision: UInt64 = 0
  public internal(set) var habitDetailRevision: UInt64 = 0
  public var taskDetailRecurrenceDraft = TaskRecurrenceEditorDraft()
  public var selectedTab: MobileTab
  public var routePath: [MobileRoute]
  /// Navigation path for the Tasks tab's `NavigationStack`, so a programmatic
  /// open (e.g. keyboard-driven) pushes detail here without teleporting to the
  /// Today stack. The Habits and Memory workspaces open on this stack too, with
  /// the habit or memory detail a deep link names pushed above them.
  public var tasksRoutePath: [MobileRoute] = []
  /// Navigation path for the Calendar tab's `NavigationStack`, so tapping a
  /// scheduled task/event pushes its detail onto the Calendar stack in place
  /// instead of switching the user to the Today tab.
  public var calendarRoutePath: [MobileRoute] = []
  /// Navigation path for the Review tab's `NavigationStack`, mirroring the
  /// other primary tabs so a deep link / Handoff route to Review can push a
  /// detail onto its own stack in place.
  public var reviewRoutePath: [MobileRoute] = []
  /// Set when the user asks to cancel a recurring task, driving the
  /// occurrence-vs-series confirmation dialog. `nil` when no choice is pending.
  /// A bare `cancelTask` on a recurring task spawns the next occurrence, so the
  /// user must choose whether to end just this one or the whole series.
  public var pendingRecurringCancelTaskID: LorvexTask.ID?
  public var errorMessage: String?

  /// The message of the refresh failure already shown in the root alert. A
  /// refresh runs on its own (foreground, sync, push), so the same failure is
  /// shown once and then only logged until a refresh succeeds; see
  /// ``presentRefreshFailure(_:)``.
  @ObservationIgnored var surfacedRefreshFailureMessage: String?

  /// Where a failure goes when `error_logs` cannot hold it (see
  /// ``DiagnosticFallbackLog``). Disabled unless the app installs the live
  /// file, so tests and previews never write outside their stores.
  @ObservationIgnored public var diagnosticFallback = DiagnosticFallbackLog(fileURL: nil)

  /// Drives a one-time, dismissible alert in the mobile shell when the on-disk
  /// database had to be quarantined on open (schema mismatch / corruption) and a
  /// fresh one was created. Composed once from the core's `databaseRecoveryNotice`
  /// on the first refresh so the quarantine is never silent; `nil` otherwise.
  public var databaseRecoveryMessage: String?

  /// Latches `databaseRecoveryMessage` so the quarantine notice surfaces exactly
  /// once — across repeated refreshes and after the user dismisses it.
  @ObservationIgnored var hasSurfacedDatabaseRecoveryNotice = false

  /// Coalescing single-flight for the `refresh()` fan-out. A trigger arriving
  /// mid-refresh (scene-active, CloudKit push, DB-change signal, notification
  /// action) does not start a parallel body; it arms one trailing rerun and
  /// registers as a waiter that is resumed with the final rerun's lifecycle
  /// result. Serializing the bodies is what prevents an older read that completes
  /// last from clobbering the snapshot a newer refresh already committed, and
  /// keeps `isLoading` owned by exactly one body at a time. Resuming coalesced
  /// callers with the final result keeps `await refresh()` honest for the app
  /// delegate's background-fetch completion — it still means "a body that saw my
  /// trigger has finished." Mirrors the macOS `AppStore` single-flight.
  @ObservationIgnored let refreshFlight =
    RefreshSingleFlight<MobileCloudSyncLifecycleResult>(
      combineResults: MobileCloudSyncLifecycleResult.combine)

  /// True while the `refresh()` fan-out loop is in flight. Read by the queued
  /// sync-mode drain to hold a mode change until the refresh finishes.
  var isRefreshing: Bool { refreshFlight.isRunning }

  /// Coalesces the best-effort surfaces a habit write refreshes once it has
  /// committed: the widget snapshot and the reminder plan. A write that lands
  /// while a pass is in flight arms one trailing pass instead of re-planning
  /// the reminders in parallel against the same notification center.
  @ObservationIgnored let habitSurfacesFlight = RefreshSingleFlight<Void>()

  let core: any LorvexCoreServicing
  let feedbackProvider: any LorvexFeedbackProviding
  let taskReminderScheduler: any TaskReminderScheduling
  let habitReminderScheduler: any HabitReminderScheduling
  let widgetSnapshotPublisher: any MobileWidgetSnapshotPublishing
  let setBadge: @Sendable (Int) async -> Void
  /// Live `UNUserNotificationCenter` authorization read, injected so tests can
  /// script the OS decision deterministically instead of depending on the
  /// test host process's real (and unentitled) notification authorization
  /// state.
  let notificationAuthorizationStatusProvider: @Sendable () async -> UNAuthorizationStatus
  let todayString: @Sendable () -> String
  let now: @Sendable () -> Date
  let defaults: UserDefaults

  // MARK: - CloudKit sync lifecycle

  /// The effective sync mode for this process (env override + persisted setting).
  public internal(set) var cloudSyncMode: CloudSyncMode
  /// This device's one CloudKit sync owner. Built in every mode, so "Delete
  /// iCloud Data" works with sync off; nil in previews and tests without one.
  @ObservationIgnored let cloudSyncController: CloudSyncController?
  /// Coalesces overlapping lifecycle triggers into one serialized cycle loop.
  /// A trigger that arrives mid-cycle arms a trailing pass and awaits the
  /// combined result, so a foreground refresh can never mistake an in-flight
  /// background apply for `.noData` and publish pre-apply state indefinitely.
  @ObservationIgnored let cloudSyncCycleFlight =
    RefreshSingleFlight<MobileCloudSyncCycleOutcome>(
      combineResults: MobileCloudSyncCycleOutcome.combine)
  var isCloudSyncCycleRunning: Bool { cloudSyncCycleFlight.isRunning }
  /// App-lifetime CloudKit observers (remote-change push + account change),
  /// retained so they outlive any single view.
  @ObservationIgnored var lifetimeObserverTasks: [Task<Void, Never>] = []
  /// One main-app-owned wake at midnight in the configured product timezone.
  /// It is intentionally not part of any extension/helper runtime.
  @ObservationIgnored var logicalDayBoundaryWakeTask: Task<Void, Never>?
  public internal(set) var lastCloudSyncCycleReport: CloudSyncCycleReport?
  public internal(set) var lastCloudSyncRemoteChangeErrorMessage: String?
  public internal(set) var lastCloudSyncRemoteChangeSucceededAt: Date?
  public internal(set) var cloudKitAccountAvailability: CloudKitAccountAvailability =
    .couldNotDetermine
  /// True while turning sync on waits for the controller's first evaluation.
  public internal(set) var isSettingCloudSyncMode = false
  /// Covers the confirmed restore plus its post-import surface refresh.
  /// Destructive data actions reject while this is true.
  public internal(set) var isDataImportRunning = false
  /// True only while the user-initiated iCloud-data deletion runs. A sync-on
  /// request is rejected meanwhile.
  public internal(set) var isCloudDataDeletionRunning = false
  /// True only while this device's local store is being erased. Separate from
  /// the cloud-deletion flag because the two are independent actions on
  /// different data, and every destructive path guards on both so they can
  /// never interleave over the same store.
  public internal(set) var isLocalDataResetRunning = false
  /// Invalidates mode intents captured by the Settings binding before a later
  /// successful cloud deletion. Without this request-time fence, the binding's
  /// unstructured Task could wake after deletion and silently turn sync back on.
  @ObservationIgnored var cloudDataDeletionEpoch: UInt64 = 0
  /// Non-nil when CloudSync is durably paused (an iCloud account switch, or
  /// the user deleted Lorvex's iCloud data). Surfaced so the UI
  /// can show a "sync paused" notice and offer the adopt / re-opt-in action;
  /// resolved via
  /// `adoptCurrentCloudAccountAndResumeSync(request:)`.
  public internal(set) var cloudSyncPauseReason: CloudSyncPauseReason?

  // MARK: - EventKit calendar mirroring

  var eventKitCoordinator: (any MobileEventKitCoordinating)?
  public var eventKitEnabled: Bool
  public var eventKitCalendarFilterMode: EventKitCalendarFilterMode
  public var eventKitIncludedCalendarIDs: Set<String>
  public var eventKitExcludedCalendarIDs: Set<String>
  public internal(set) var lastEventKitImportErrorMessage: String?
  public internal(set) var eventKitSettingsRecoveryNeeded = false
  public internal(set) var isSettingEventKitEnabled = false
  public internal(set) var isApplyingEventKitSettings = false
  /// Serializes EventKit settings reconciliation. A tier, master-toggle, or
  /// calendar-filter change that lands while an ingest is suspended requests a
  /// trailing pass and awaits that final pass; no privacy downgrade or final
  /// filter selection can be stranded behind an older in-flight projection.
  @ObservationIgnored let eventKitSettingsApplyFlight = RefreshSingleFlight<Void>()
  /// `true` wins while apply requests coalesce, so a caller that genuinely
  /// needs authorization is never weakened by an earlier no-prompt pass.
  @ObservationIgnored var pendingEventKitSettingsRequestAccess = false

  public init(
    core: any LorvexCoreServicing,
    feedbackProvider: any LorvexFeedbackProviding = NoOpFeedbackProvider(),
    taskReminderScheduler: any TaskReminderScheduling = NoopTaskReminderScheduler(),
    habitReminderScheduler: any HabitReminderScheduling = NoopHabitReminderScheduler(),
    widgetSnapshotPublisher: any MobileWidgetSnapshotPublishing =
      NoopMobileWidgetSnapshotPublisher(),
    setBadge: @escaping @Sendable (Int) async -> Void = { _ in },
    badgeEnabled: Bool = true,
    isSetupCompleted: Bool = true,
    // Safe, inert default: previews/tests/any caller that never wires the live
    // read get "already resolved" (never withholds, never touches the real
    // `UNUserNotificationCenter` — unavailable in the SwiftPM test-runner
    // process, and `MobileStoreFactory`'s default is exercised directly by
    // factory-level tests). `LorvexMobileApp` wires the real
    // system read via `MobileStoreFactory`.
    notificationAuthorizationStatusProvider: @escaping @Sendable () async -> UNAuthorizationStatus = {
      .authorized
    },
    initialSnapshot: MobileHomeSnapshot = MobileHomeSnapshot(today: .empty, weeklyReview: nil),
    selectedTab: MobileTab = .today,
    todayString: @escaping @Sendable () -> String = MobileStore.defaultTodayString,
    now: @escaping @Sendable () -> Date = { Date() },
    defaults: UserDefaults = .standard,
    cloudSyncMode: CloudSyncMode = .off,
    cloudSyncController: CloudSyncController? = nil,
    eventKitCoordinator: (any MobileEventKitCoordinating)? = nil,
    eventKitEnabled: Bool = false,
    eventKitCalendarFilterMode: EventKitCalendarFilterMode = .allExcept,
    eventKitIncludedCalendarIDs: Set<String> = [],
    eventKitExcludedCalendarIDs: Set<String> = []
  ) {
    self.core = core
    self.feedbackProvider = feedbackProvider
    self.taskReminderScheduler = taskReminderScheduler
    self.habitReminderScheduler = habitReminderScheduler
    self.widgetSnapshotPublisher = widgetSnapshotPublisher
    self.setBadge = setBadge
    self.badgeEnabled = badgeEnabled
    self.isSetupCompleted = isSetupCompleted
    self.notificationAuthorizationStatusProvider = notificationAuthorizationStatusProvider
    self.snapshot = initialSnapshot
    self.captureDraft = MobileCaptureDraft()
    self.listDraft = MobileListDraft()
    self.habitDraft = MobileHabitDraft()
    self.calendarDraft = MobileCalendarDraft(now: now)
    self.dailyReviewDraft = MobileDailyReviewDraft()
    self.selectedReviewDate = todayString()
    self.memoryKeyDraft = ""
    self.memoryContentDraft = ""
    self.memoryEditingKey = nil
    self.selectedTab = selectedTab
    self.routePath = []
    self.todayString = todayString
    self.now = now
    self.defaults = defaults
    self.calendarPresentationMode = MobileCalendarPresentationMode.remembered(in: defaults)
    self.cloudSyncMode = cloudSyncMode
    self.cloudSyncController = cloudSyncController
    self.eventKitCoordinator = eventKitCoordinator
    self.eventKitEnabled = eventKitEnabled
    self.eventKitCalendarFilterMode = eventKitCalendarFilterMode
    self.eventKitIncludedCalendarIDs = eventKitIncludedCalendarIDs
    self.eventKitExcludedCalendarIDs = eventKitExcludedCalendarIDs
  }

  public nonisolated static func defaultTodayString() -> String {
    LorvexDateFormatters.ymd.string(from: Date())
  }

  /// Product calendar day captured atomically with the Today snapshot. Synced
  /// day-scoped writes must use this instead of the device-local clock.
  public var logicalTodayString: String {
    snapshot.today.logicalDay ?? todayString()
  }

  /// IANA zone that owns ``logicalTodayString``.
  public var logicalTimezoneName: String {
    snapshot.today.timezone ?? TimeZone.current.identifier
  }

  /// Product timezone for wall-clock UI. The device zone is used only before
  /// the first validated Today snapshot has loaded.
  public var logicalTimeZone: TimeZone {
    guard let name = snapshot.today.timezone, let timeZone = TimeZone(identifier: name) else {
      return .autoupdatingCurrent
    }
    return timeZone
  }
}
