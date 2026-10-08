import Foundation
import LorvexCore
import LorvexDomain
import LorvexMobile
import LorvexSync
import Testing

// MARK: - Stub core service

/// A `LorvexCoreServicing` (and `EnvelopeSyncServicing`) stub backed by an
/// injected real in-memory core.
///
/// All `LorvexCoreServicing` methods delegate to the backing core to keep the
/// load/task paths working; the extra call-count fields let tests assert
/// delegation and timing behaviour. Transport-facing outbox calls are recorded;
/// retention maintenance and inbound apply delegate to the real backing core.
final class StubCoreService: @unchecked Sendable, LorvexCoreServicing, EnvelopeSyncServicing,
  LorvexWidgetSnapshotSourceServicing
{

  let preview: SwiftLorvexCoreService

  /// Test seed for the database-quarantine notice the in-memory backing core
  /// never produces (nothing on disk to quarantine). Lets store-wiring tests
  /// drive the surface-once path.
  var databaseRecoveryNotice: DatabaseRecoveryNotice?

  init(preview: SwiftLorvexCoreService) {
    self.preview = preview
  }

  // MARK: Envelope-sync facade
  /// Outbox rows the next cycle should drain. Set by a test before the cycle.
  var outboxPending: [PendingOutboundEnvelope] = []
  private let envelopeLock = NSLock()
  private(set) var markedSyncedIDs: [Int64] = []
  private(set) var failedOutboxIDs: [Int64] = []
  private(set) var appliedInboundBatches: [[SyncEnvelope]] = []
  private(set) var deferredUnknownTypeRaws: [RawEnvelopeFields] = []
  var loadTodayAppliedInboundBatchCounts: [Int] = []

  func pendingOutbound() throws -> [PendingOutboundEnvelope] {
    envelopeLock.withLock { outboxPending }
  }
  func markOutboundSynced(outboxIds: [Int64]) throws {
    envelopeLock.withLock { markedSyncedIDs.append(contentsOf: outboxIds) }
  }
  func recordOutboundFailure(outboxId: Int64, error: String, kind: OutboundFailureKind) throws {
    envelopeLock.withLock { failedOutboxIDs.append(outboxId) }
  }
  func applyInbound(_ envelopes: [SyncEnvelope], undecodable: Int) throws -> InboundApplyReport {
    let report = try preview.applyInbound(envelopes, undecodable: undecodable)
    recordAppliedInboundBatch(envelopes)
    return report
  }
  func deferUnknownTypeRecords(_ raws: [RawEnvelopeFields]) throws {
    envelopeLock.withLock { deferredUnknownTypeRaws.append(contentsOf: raws) }
  }
  func appliedInboundBatchCount() -> Int {
    envelopeLock.withLock { appliedInboundBatches.count }
  }
  func recordAppliedInboundBatch(_ envelopes: [SyncEnvelope]) {
    envelopeLock.withLock { appliedInboundBatches.append(envelopes) }
  }

  var todayOverride: TodaySnapshot?
  var loadTodayError: LorvexCoreError?
  var loadTodayCallCount = 0
  /// Optional async barrier invoked inside `loadToday` AFTER the return value
  /// has been captured, so a test can model an older read that completes after
  /// a newer one (the caller observes the data as of entry, then suspends).
  var loadTodayGate: (@Sendable () async -> Void)?
  /// Optional deterministic task-read seam for detached-window race tests. The
  /// value is captured before the gate suspends, modelling a stale read that
  /// completes after the window closes or changes generation.
  var loadTaskOverride: LorvexTask?
  var loadTaskGate: (@Sendable () async -> Void)?
  var loadWeeklyReviewError: LorvexCoreError?
  var loadOverviewTaskListError: LorvexCoreError?
  var loadListsError: LorvexCoreError?
  var loadRuntimeDiagnosticsError: LorvexCoreError?
  var loadSyncStatusError: LorvexCoreError?
  var listTasksError: LorvexCoreError?
  /// Optional async barrier invoked inside `listTasks` before the delegated
  /// read, so a test can observe store state while a task-list read (a loaded
  /// Tasks workspace reloading after a mutation) is in flight.
  var listTasksGate: (@Sendable () async -> Void)?
  /// Optional async barrier invoked inside `loadWidgetStatsSource` before the
  /// delegated read, so a test can observe store state while the badge's read
  /// in the fan-out after a mutation is in flight.
  var widgetStatsGate: (@Sendable () async -> Void)?
  /// Titles of the tasks created through the single-create entry points, in
  /// the order the core received them.
  var createdTaskTitles: [String] = []
  /// When set, `createTask(_:)` throws this after recording the title,
  /// modelling a failed write.
  var createTaskError: LorvexCoreError?
  /// Optional async barrier invoked inside `createTask(_:)` before the
  /// delegated write, so a test can hold a capture mid-write.
  var createTaskGate: (@Sendable () async -> Void)?
  /// Optional async barrier invoked inside `updateTask(_:)` (the draft form)
  /// before the delegated write, so a test can hold a task write mid-flight.
  var updateTaskGate: (@Sendable () async -> Void)?
  /// Optional async barrier invoked inside `upsertDailyReviewPreservingLinks`
  /// before the delegated write, so a test can hold a daily-review save
  /// mid-write.
  var upsertDailyReviewGate: (@Sendable () async -> Void)?
  /// Optional async barrier invoked inside `loadDailyReview` AFTER the entry has
  /// been read, so a test can model a read that completes after the editor moved
  /// on or the user typed (the caller observes the data as of entry, then
  /// suspends).
  var loadDailyReviewGate: (@Sendable () async -> Void)?
  /// When set, `getDueHabitReminderOccurrences` throws this, modelling a
  /// transient habit occurrence-read failure during a reminder reschedule.
  var dueHabitReminderOccurrencesError: LorvexCoreError?
  /// When set, `getTasksWithUpcomingReminders` throws this, modelling a
  /// transient task-reminder read failure during a reminder reschedule.
  var upcomingReminderTasksError: LorvexCoreError?
  var loadListsCallCount = 0
  var loadHabitsCallCount = 0
  var loadMemoryCallCount = 0
  var loadCalendarTimelineCallCount = 0
  var loadRuntimeDiagnosticsCallCount = 0
  var loadSyncStatusCallCount = 0
  var listTasksCallCount = 0
  var scheduledTasksCallCount = 0
  var upcomingReminderTaskCallCount = 0
  var completeTaskDelayNanoseconds: UInt64 = 0
  var batchCompleteTaskCallCount = 0
  var batchTaskDelayNanoseconds: UInt64 = 0
  var setTaskRecurrenceCallCount = 0
  var removeTaskRecurrenceCallCount = 0

  func deleteTask(id: LorvexTask.ID) async throws { try await preview.deleteTask(id: id) }
  func permanentlyDeleteTask(id: LorvexTask.ID) async throws {
    try await preview.permanentlyDeleteTask(id: id)
  }
  func archiveTask(id: LorvexTask.ID) async throws -> LorvexTask {
    try await preview.archiveTask(id: id)
  }
  func unarchiveTask(id: LorvexTask.ID) async throws -> LorvexTask {
    try await preview.unarchiveTask(id: id)
  }
  func loadWidgetStatsSource() async throws -> WidgetStatsSource {
    await widgetStatsGate?()
    return try await preview.loadWidgetStatsSource()
  }
  func loadSearchIndexTasks() async throws -> [LorvexTask] {
    try await preview.loadSearchIndexTasks()
  }
  func loadWidgetSnapshotSource(date: String?) async throws -> WidgetSnapshotSource {
    try await preview.loadWidgetSnapshotSource(date: date)
  }
  func batchCancelTasksInList(listID: LorvexList.ID, statuses: [String]?, cancelSeries: Bool)
    async throws -> [LorvexTask]
  {
    try await preview.batchCancelTasksInList(
      listID: listID, statuses: statuses, cancelSeries: cancelSeries)
  }
  func deletePreference(key: String) async throws { try await preview.deletePreference(key: key) }
  func addCalendarEventException(eventID: CalendarTimelineEvent.ID, date: String) async throws
    -> CalendarTimelineEvent
  {
    try await preview.addCalendarEventException(eventID: eventID, date: date)
  }

  func removeCalendarEventException(eventID: CalendarTimelineEvent.ID, date: String) async throws
    -> CalendarTimelineEvent
  {
    try await preview.removeCalendarEventException(eventID: eventID, date: date)
  }
  func editScopedCalendarEvent(
    eventID: CalendarTimelineEvent.ID, occurrenceDate: String, scope: String,
    updates: ScopedCalendarEventUpdates
  ) async throws -> ScopedCalendarEventEditResult {
    try await preview.editScopedCalendarEvent(
      eventID: eventID, occurrenceDate: occurrenceDate, scope: scope, updates: updates)
  }
  func deleteScopedCalendarEvent(
    eventID: CalendarTimelineEvent.ID, occurrenceDate: String, scope: String
  ) async throws -> ScopedCalendarEventDeleteResult {
    try await preview.deleteScopedCalendarEvent(
      eventID: eventID, occurrenceDate: occurrenceDate, scope: scope)
  }

}
