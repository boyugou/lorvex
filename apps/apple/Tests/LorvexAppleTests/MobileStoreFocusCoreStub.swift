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
/// generation, traversal, retention, and inbound apply delegate to the real
/// backing core, letting a test drive `MobileStore`'s CloudSync cycle end to end.
final class StubFocusCoreService: @unchecked Sendable, LorvexCoreServicing, EnvelopeSyncServicing,
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
  private(set) var fullResyncBackfillCallCount = 0
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
  func enqueueFullResyncBackfill() throws -> FullResyncBackfillReport {
    envelopeLock.withLock { fullResyncBackfillCallCount += 1 }
    return FullResyncBackfillReport()
  }
  func enrolledZoneEpoch(forAccountIdentifier accountIdentifier: String) throws -> Int? {
    try preview.enrolledZoneEpoch(forAccountIdentifier: accountIdentifier)
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
  var loadCurrentFocusError: LorvexCoreError?
  var loadCurrentFocusCallCount = 0
  /// Optional async barrier invoked at the top of `loadCurrentFocus`, letting a
  /// test suspend a refresh mid-flight to exercise overlapping-refresh ordering.
  var loadCurrentFocusGate: (@Sendable () async -> Void)?
  /// Optional deterministic task-read seam for detached-window race tests. The
  /// value is captured before the gate suspends, modelling a stale read that
  /// completes after the window closes or changes generation.
  var loadTaskOverride: LorvexTask?
  var loadTaskGate: (@Sendable () async -> Void)?
  var loadWeeklyReviewError: LorvexCoreError?
  var loadListsError: LorvexCoreError?
  var loadRuntimeDiagnosticsError: LorvexCoreError?
  var listTasksError: LorvexCoreError?
  /// When set, `getDueHabitReminderOccurrences` throws this, modelling a
  /// transient habit occurrence-read failure during a reminder reschedule.
  var dueHabitReminderOccurrencesError: LorvexCoreError?
  var loadListsCallCount = 0
  var loadHabitsCallCount = 0
  var loadMemoryCallCount = 0
  var loadCalendarTimelineCallCount = 0
  var loadRuntimeDiagnosticsCallCount = 0
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
    try await preview.loadWidgetStatsSource()
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
