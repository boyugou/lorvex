import Foundation
import LorvexCloudSync
import LorvexCore
import LorvexDomain
import Observation
import UserNotifications

public struct MobileCloudSyncServices: Sendable {
  let subscriber: any CloudSyncSubscribing
  let coordinator: CloudSyncEngineCoordinator?

  public init(
    subscriber: any CloudSyncSubscribing,
    coordinator: CloudSyncEngineCoordinator?
  ) {
    self.subscriber = subscriber
    self.coordinator = coordinator
  }
}

@MainActor
@Observable
public final class MobileStore {
  public internal(set) var snapshot: MobileHomeSnapshot {
    didSet { summary = MobileHomeProjector().summary(from: snapshot) }
  }
  /// Today-tab summary derived from ``snapshot``. Cached and recomputed only
  /// when `snapshot` is assigned, so SwiftUI `body` reads don't re-run the
  /// projection on every access.
  public private(set) var summary: MobileHomeSummary
  public var captureDraft: MobileCaptureDraft
  /// Drives the global quick-capture sheet. Quick capture is a sheet raised by the
  /// ＋ on Today / Tasks (and ⌘N), not a tab — capture is an action, not a place.
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
  public internal(set) var focusSchedule: FocusSchedule?
  public internal(set) var proposedFocusSchedule: FocusSchedule?
  public internal(set) var isProposingFocusSchedule = false
  public internal(set) var isSavingFocusSchedule = false
  public internal(set) var isClearingFocusSchedule = false
  public internal(set) var isSavingReview = false
  public internal(set) var memory: MemorySnapshot?
  public internal(set) var selectedMemoryKey: MemoryEntry.ID?
  public internal(set) var lists: ListCatalogSnapshot?
  public internal(set) var selectedListID: LorvexList.ID?
  public internal(set) var selectedListDetail: ListDetailSnapshot?
  public internal(set) var isLoadingListDetail = false
  public internal(set) var failedListDetailID: LorvexList.ID?
  /// Monotonic guard for `loadListDetail`: a load whose token is no longer
  /// current (the user switched lists mid-flight) must not commit its result.
  var listDetailLoadToken = 0
  public var listDraft: MobileListDraft
  public internal(set) var isCreatingList = false
  public internal(set) var isUpdatingList = false
  public internal(set) var isDeletingList = false
  public internal(set) var habits: HabitCatalogSnapshot?
  public internal(set) var selectedHabitID: LorvexHabit.ID?
  public internal(set) var habitDetailsByID: [LorvexHabit.ID: HabitDetail] = [:]
  /// The milestone a completion just crossed, staged for the floating
  /// celebration overlay. Set by ``stageMilestoneCelebrationIfReached(habitID:)``
  /// on a crossing and cleared when the overlay dismisses (tap / auto-timeout).
  var milestoneCelebration: MobileHabitMilestoneCelebration?
  public internal(set) var calendarTimeline: CalendarTimelineSnapshot?
  public internal(set) var calendarScheduledTasks: [LorvexTask] = []
  /// Monotonic guard for `refreshCalendarTimeline`: week navigation, the
  /// DatabaseChangeSignal observer, scene-active refresh, and pull-to-refresh can
  /// all request overlapping windows; a superseded load must not pair its events
  /// with a newer window's scheduled tasks (mirrors the macOS `timelineLoadToken`).
  var calendarTimelineLoadToken = 0
  /// Mobile calendar presentation: the width-adaptive 1/2/3-day time-axis grid
  /// (default) or a seven-day grouped agenda.
  public var calendarPresentationMode: MobileCalendarPresentationMode = .grid
  public var calendarDraft: MobileCalendarDraft
  public internal(set) var isMutatingCalendarEvent = false
  public internal(set) var isExportingCalendarICS = false
  public internal(set) var isExportingData = false
  public internal(set) var runtimeDiagnostics: RuntimeDiagnosticsSnapshot?
  public internal(set) var isLoadingRuntimeDiagnostics = false
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
  public internal(set) var listDetailRevision: UInt64 = 0
  public internal(set) var habitDetailRevision: UInt64 = 0
  public var taskDetailRecurrenceDraft = TaskRecurrenceEditorDraft()
  public var selectedTab: MobileTab
  public var routePath: [MobileRoute]
  /// Navigation path for the Tasks tab's `NavigationStack` on iPhone, so a
  /// programmatic open (e.g. keyboard-driven) pushes detail without teleporting
  /// to the Today stack. The Tasks tab is its own first-class surface now.
  public var tasksRoutePath: [MobileRoute] = []
  /// Navigation path for the Habits tab's compact (iPhone) `NavigationStack`,
  /// so a deep link / Handoff / Spotlight route to a specific habit pushes its
  /// detail instead of only selecting the tab. The iPad/visionOS regular
  /// layout shows habit detail via `selectedHabitID` and never reads this path.
  public var habitsRoutePath: [MobileRoute] = []
  /// Navigation path for the More tab's `NavigationStack` on iPhone.
  /// Deep links and Handoff push `MobileDestination` values here to open specific workspaces.
  public var moreNavigationPath: [MobileDestination]
  /// Detail-column selection for the sidebar shell on iPad / visionOS.
  public var iPadDestination: MobileDestination?
  /// Pending list route queued by Handoff for `MobileStoreListsView` to push on appear.
  public var pendingListRoute: MobileRoute?
  /// Set when the user asks to cancel a recurring task, driving the
  /// occurrence-vs-series confirmation dialog. `nil` when no choice is pending.
  /// A bare `cancelTask` on a recurring task spawns the next occurrence, so the
  /// user must choose whether to end just this one or the whole series.
  public var pendingRecurringCancelTaskID: LorvexTask.ID?
  public var errorMessage: String?

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
  let cloudSyncRetrySleep: @Sendable (TimeInterval) async throws -> Void
  let defaults: UserDefaults
  let cloudSyncServiceFactory: @Sendable (CloudSyncMode) -> MobileCloudSyncServices

  // MARK: - CloudKit sync lifecycle

  /// The effective sync mode for this process (env override + persisted setting).
  public internal(set) var cloudSyncMode: CloudSyncMode
  /// Installs the private-database push subscription. No-op when sync is off.
  var cloudSyncSubscriber: any CloudSyncSubscribing
  /// Drives one invisible sync cycle (outbox → CloudKit, CloudKit →
  /// applyEnvelope). Nil unless sync is `.live` and the backend supports
  /// envelope sync.
  var cloudSyncCoordinator: CloudSyncEngineCoordinator?
  /// The single coordinator actor graph retained for off-mode cloud deletion
  /// maintenance and reused when live sync is enabled. Keeping it stable avoids
  /// independent operation gates and safety-state actors over one CloudSyncState
  /// directory during a maintenance/mode-transition interleaving.
  @ObservationIgnored var cloudDataMaintenanceCoordinator: CloudSyncEngineCoordinator?
  /// Set once the push subscription registers; reset on iCloud account change so
  /// the next refresh re-subscribes under the new identity.
  public internal(set) var hasRegisteredSubscription = false
  /// Failure-aware pacing gating when the best-effort cycle runs.
  @ObservationIgnored var cloudSyncPacing = CloudSyncPacing()
  /// Coalesces overlapping lifecycle triggers into one serialized cycle loop.
  /// A trigger that arrives mid-cycle arms a trailing pass and awaits the
  /// combined result, so a foreground refresh can never mistake an in-flight
  /// background apply for `.noData` and publish pre-apply state indefinitely.
  @ObservationIgnored let cloudSyncCycleFlight =
    RefreshSingleFlight<MobileCloudSyncCycleOutcome>(
      combineResults: MobileCloudSyncCycleOutcome.combine)
  var isCloudSyncCycleRunning: Bool { cloudSyncCycleFlight.isRunning }
  /// Advances only after a Cloud sync pass returns a real, successful report.
  /// Silent-push handoff tokens use it to distinguish a completed no-data drain
  /// from a transport/account/pacing gate that never actually paid the debt.
  @ObservationIgnored var cloudSyncSuccessfulCycleGeneration: UInt64 = 0
  /// One main-app-owned wake for retry/deferred CloudSync work. Extensions and
  /// MCP remain database/outbox writers and never create a CloudKit scheduler.
  @ObservationIgnored var cloudSyncRetryWakeTask: Task<Void, Never>?
  @ObservationIgnored var cloudSyncRetryWakeGeneration: UInt64 = 0
  /// App-lifetime CloudKit observers (remote-change push + account change),
  /// retained so they outlive any single view.
  @ObservationIgnored var lifetimeObserverTasks: [Task<Void, Never>] = []
  /// One main-app-owned wake at midnight in the configured product timezone.
  /// It is intentionally not part of any extension/helper runtime.
  @ObservationIgnored var logicalDayBoundaryWakeTask: Task<Void, Never>?
  public internal(set) var lastCloudSyncCycleReport: CloudSyncCycleReport?
  public internal(set) var lastCloudSyncSubscriptionErrorMessage: String?
  public internal(set) var lastCloudSyncRemoteChangeErrorMessage: String?
  public internal(set) var lastCloudSyncRemoteChangeSucceededAt: Date?
  public internal(set) var cloudKitAccountAvailability: CloudKitAccountAvailability =
    .couldNotDetermine
  public internal(set) var isSettingCloudSyncMode = false
  /// Covers the confirmed restore plus its post-import surface refresh. Mode
  /// changes and destructive cloud maintenance queue or reject while this is
  /// true, so a non-live import cannot become live halfway through its sequence
  /// of record-level decisions.
  public internal(set) var isDataImportRunning = false
  /// True only for the user-initiated remote deletion transaction. Kept
  /// separate from the broader mode-transition flag so a re-enable request can
  /// be rejected while deletion is in flight without blocking the legitimate
  /// Live-mode transition that performs an authorized re-enable afterward.
  public internal(set) var isCloudDataDeletionRunning = false
  /// A sync-mode request queued because it arrived while a mode transition,
  /// sync cycle, or deletion cleanup was active. Latest request wins;
  /// the active work applies it atomically on completion, so an explicit user
  /// intent — especially turning sync OFF — is never silently dropped.
  public internal(set) var pendingCloudSyncMode: CloudSyncMode?
  /// Serializes launch/foreground deletion maintenance on the retained
  /// coordinator and keeps mode transitions queued until cleanup finishes.
  @ObservationIgnored var isCloudDeletionMaintenanceRunning = false
  /// Invalidates mode intents captured by the Settings binding before a later
  /// successful cloud deletion. Without this request-time fence, the binding's
  /// unstructured Task could wake after deletion and silently turn sync back on.
  @ObservationIgnored var cloudDataDeletionEpoch: UInt64 = 0
  /// The mode the Settings picker shows and binds to: the queued target while
  /// a request is pending, otherwise the effective mode — so the picker
  /// reflects the user's latest choice instead of snapping back mid-cycle.
  public var cloudSyncModeTarget: CloudSyncMode { pendingCloudSyncMode ?? cloudSyncMode }
  /// Non-nil when CloudSync is durably paused (iCloud account switch, mandatory
  /// backfill failure, or the user deleted the Lorvex zone). Surfaced so the UI
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
    // factory-level tests). `LorvexMobileApp`/`LorvexVisionApp` wire the real
    // system read via `MobileStoreFactory`.
    notificationAuthorizationStatusProvider: @escaping @Sendable () async -> UNAuthorizationStatus = {
      .authorized
    },
    initialSnapshot: MobileHomeSnapshot = MobileHomeSnapshot(
      today: .empty,
      currentFocus: nil,
      weeklyReview: nil
    ),
    selectedTab: MobileTab = .today,
    todayString: @escaping @Sendable () -> String = MobileStore.defaultTodayString,
    now: @escaping @Sendable () -> Date = { Date() },
    cloudSyncRetrySleep: @escaping @Sendable (TimeInterval) async throws -> Void = { delay in
      try await Task.sleep(for: .seconds(delay))
    },
    defaults: UserDefaults = .standard,
    cloudSyncMode: CloudSyncMode = .off,
    cloudSyncSubscriber: any CloudSyncSubscribing = NoOpCloudSyncSubscriber(),
    cloudSyncCoordinator: CloudSyncEngineCoordinator? = nil,
    cloudDataMaintenanceCoordinator: CloudSyncEngineCoordinator? = nil,
    cloudSyncServiceFactory: @escaping @Sendable (CloudSyncMode) -> MobileCloudSyncServices = { _ in
      MobileCloudSyncServices(subscriber: NoOpCloudSyncSubscriber(), coordinator: nil)
    },
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
    self.summary = MobileHomeProjector().summary(from: initialSnapshot)
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
    self.moreNavigationPath = []
    self.iPadDestination = nil
    self.todayString = todayString
    self.now = now
    self.cloudSyncRetrySleep = cloudSyncRetrySleep
    self.defaults = defaults
    self.cloudSyncServiceFactory = cloudSyncServiceFactory
    self.cloudSyncMode = cloudSyncMode
    self.cloudSyncSubscriber = cloudSyncSubscriber
    self.cloudSyncCoordinator = cloudSyncCoordinator
    self.cloudDataMaintenanceCoordinator = cloudDataMaintenanceCoordinator ?? cloudSyncCoordinator
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
