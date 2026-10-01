import CloudKit
import Foundation
import LorvexCore
import LorvexDomain
import LorvexStore
import LorvexWidgetKitSupport
import LorvexCloudSync

@testable import LorvexApple

actor RecordingTaskSearchIndexer: TaskSearchIndexing {
  private var indexedIDs: [LorvexTask.ID] = []

  func replaceIndexedTasks(_ tasks: [LorvexTask]) async throws {
    indexedIDs = tasks.map(\.id)
  }

  func lastIndexedIDs() -> [LorvexTask.ID] {
    indexedIDs
  }
}

actor RecordingTaskReminderScheduler: TaskReminderScheduling {
  private var scheduledIDs: [LorvexTask.ID] = []
  private var scheduledReminderIDs: [TaskReminder.ID] = []
  private var scheduledFireDates: [Date] = []
  var report: TaskReminderScheduleReport?

  func scheduleReminders(_ reminders: [ScheduledTaskReminder]) async -> TaskReminderScheduleReport {
    scheduledIDs = reminders.map(\.taskID)
    scheduledReminderIDs = reminders.map(\.reminderID)
    scheduledFireDates = reminders.map(\.fireDate)
    if let report {
      return report
    }
    return .scheduled(scheduledIDs.count)
  }

  func lastScheduledIDs() -> [LorvexTask.ID] {
    scheduledIDs
  }

  func lastScheduledReminderIDs() -> [TaskReminder.ID] {
    scheduledReminderIDs
  }

  func lastScheduledFireDates() -> [Date] {
    scheduledFireDates
  }
}

actor RecordingBadgeSetter {
  private var counts: [Int] = []

  func set(_ count: Int) {
    counts.append(count)
  }

  func lastCount() -> Int? {
    counts.last
  }
}

@MainActor
final class RecordingWidgetSnapshotPublisher: WidgetSnapshotPublishing {
  private var snapshots: [LorvexWidgetKitSupport.WidgetSnapshot] = []

  func publish(source: WidgetSnapshotSource) async throws -> WidgetSnapshot {
    let snapshot = WidgetSnapshotProjector(
      now: { Date(timeIntervalSince1970: 1_779_465_600) }
    ).snapshot(
      storageGeneration: source.storageGeneration,
      logicalDay: source.logicalDay,
      today: source.today,
      timezone: source.timezone,
      habitCatalog: source.habits,
      listCatalog: source.lists,
      statsSource: source.stats)
    snapshots.append(snapshot)
    return snapshot
  }

  func publishedSnapshots() -> [LorvexWidgetKitSupport.WidgetSnapshot] {
    snapshots
  }
}

/// Fake CloudKit account checker for coordinator tests.
struct StubAccountStatusChecker: CloudKitAccountStatusChecking {
  var availability: CloudKitAccountAvailability = .available
  func checkAccountStatus() async throws -> CloudKitAccountAvailability { availability }
}

/// Fake iCloud account identifier returning a scripted, stable identity string
/// (or `nil` for "signed out / indeterminate / lookup failed" — the fail-closed
/// unknown). Drives the account-switch backfill-guard tests without a real
/// iCloud account, using the single CloudKit-user-record identity format.
struct StubAccountIdentifier: CloudKitAccountIdentifying {
  var identifier: String?
  func currentAccountIdentifier() async -> String? { identifier }
}

/// Account identifier returning scripted values on successive reads (the final
/// value repeats once the script is exhausted), so a test can simulate the
/// signed-in iCloud account FLIPPING mid-cycle — the start gate reads one
/// account and the cycle tail reads another. A `nil` entry models an
/// undeterminable identity that cycle.
actor ScriptedAccountIdentifier: CloudKitAccountIdentifying {
  private let script: [String?]
  private(set) var callCount = 0

  init(_ script: [String?]) { self.script = script }

  func currentAccountIdentifier() async -> String? {
    defer { callCount += 1 }
    return callCount < script.count ? script[callCount] : (script.last ?? nil)
  }
}

/// Mutable account identity for deterministic operation-serialization tests.
actor MutableAccountIdentifier: CloudKitAccountIdentifying {
  private var identifier: String?

  init(_ identifier: String?) { self.identifier = identifier }

  func currentAccountIdentifier() async -> String? { identifier }
  func set(_ identifier: String?) { self.identifier = identifier }
}

/// In-memory account-identity store recording every save, so the account-switch
/// guard tests can assert whether the recorded identity advanced.
actor RecordingAccountIdentityStore: CloudSyncAccountIdentityStoring {
  private var identifier: String?
  private(set) var savedIdentifiers: [String] = []

  init(initial: String? = nil) { self.identifier = initial }

  func loadLastAccountIdentifier() async -> String? { identifier }

  func saveLastAccountIdentifier(_ identifier: String) async {
    self.identifier = identifier
    savedIdentifiers.append(identifier)
  }
}

/// In-memory pause-state store recording every save/clear so the account-guard
/// tests can assert the controller durably paused (or resumed) sync.
actor RecordingCloudSyncPauseStore: CloudSyncPauseStateStoring {
  private(set) var reason: CloudSyncPauseReason?
  private(set) var savedReasons: [CloudSyncPauseReason] = []
  private(set) var clearCount = 0

  init(initial: CloudSyncPauseReason? = nil) {
    reason = initial
  }

  func loadPauseReason() async -> CloudSyncPauseReason? { reason }

  func savePauseReason(_ reason: CloudSyncPauseReason) async {
    self.reason = reason
    savedReasons.append(reason)
  }

  func clearPauseReason() async {
    guard reason != nil else { return }
    reason = nil
    clearCount += 1
  }
}

/// Shared monotonic event log so a test can assert the relative order of steps
/// that happen across two different fakes (for example, a fleet-visible delete
/// barrier versus physical zone cleanup). Lock-backed so a synchronous fake and an
/// actor-isolated fake can both append.
final class OrderRecorderBox: @unchecked Sendable {
  private let lock = NSLock()
  private var events: [String] = []

  func record(_ event: String) {
    lock.lock()
    defer { lock.unlock() }
    events.append(event)
  }

  var snapshot: [String] {
    lock.lock()
    defer { lock.unlock() }
    return events
  }
}

/// Captured arguments for the atomic current-and-future EventKit replacement.
struct FakeEventKitFutureSeriesReplacement: Equatable, Sendable {
  let originalLorvexEventID: String
  let occurrenceDate: Date
  let replacement: CalendarEventExport
  let replacementLorvexEventID: String
  let target: EventKitWriteTarget
}

/// Fake `EventKitAccessing`: records ingest fetches + write-back calls and
/// returns a configurable event list, without touching a real `EKEventStore`.
actor FakeEventKitAccess: EventKitAccessing {
  var fetchResult: [EventKitFetchedEvent] = []
  var availableCalendarResult: [EventKitCalendarDescriptor] = []
  var writableCalendarResult: [EventKitCalendarDescriptor] = []
  var lorvexEventCalendarIDResult: String?
  var eventSourceResult: EventKitEventSource?
  var readAccessGranted = true
  nonisolated(unsafe) var readAuthorizationStateOverride: EventKitReadAuthorizationState = .authorized
  private(set) var requestAccessCount = 0
  private(set) var fetchCalendarFilters: [EventKitCalendarFilter] = []
  private(set) var fetchWindowEndDays: [String] = []
  private(set) var writes: [(key: String?, title: String, lorvexID: String)] = []
  private(set) var writeRecurrences: [String?] = []
  private(set) var writeTargets: [EventKitWriteTarget] = []
  private(set) var futureSeriesReplacements: [FakeEventKitFutureSeriesReplacement] = []
  private(set) var calendarIDLookups: [String] = []
  private(set) var eventSourceLookups: [String] = []
  private(set) var deletes: [String] = []
  private(set) var occurrenceRemovals: [(lorvexID: String, occurrenceDate: Date)] = []
  private(set) var futureSeriesRemovals: [(lorvexID: String, occurrenceDate: Date)] = []
  private var upsertError: EventKitAccessError?
  private var futureSeriesReplacementError: EventKitAccessError?
  private var nextKey = 0

  init(fetchResult: [EventKitFetchedEvent] = []) { self.fetchResult = fetchResult }

  func requestAccess() async throws -> Bool {
    requestAccessCount += 1
    return readAccessGranted
  }
  nonisolated func isReadAuthorized() -> Bool { readAuthorizationState().canRead }
  nonisolated func readAuthorizationState() -> EventKitReadAuthorizationState {
    readAuthorizationStateOverride
  }

  func availableCalendars() async throws -> [EventKitCalendarDescriptor] {
    guard readAccessGranted else { throw EventKitAccessError.readAccessDenied }
    return availableCalendarResult
  }

  func writableCalendars() async throws -> [EventKitCalendarDescriptor] {
    guard readAccessGranted else { throw EventKitAccessError.readAccessDenied }
    return writableCalendarResult
  }

  func lorvexEventCalendarID(lorvexEventID: String) async -> String? {
    guard readAccessGranted else { return nil }
    calendarIDLookups.append(lorvexEventID)
    return lorvexEventCalendarIDResult
  }

  func eventSource(forEventKey key: String, dayHint: String?) async -> EventKitEventSource? {
    guard readAccessGranted else { return nil }
    eventSourceLookups.append(key)
    return eventSourceResult
  }

  func setEventSourceResult(_ source: EventKitEventSource?) { eventSourceResult = source }

  func fetchEvents(
    start: Date, end: Date, windowEndDay: String,
    calendarFilter: EventKitCalendarFilter
  ) async throws -> [EventKitFetchedEvent] {
    guard readAccessGranted else { throw EventKitAccessError.readAccessDenied }
    fetchCalendarFilters.append(calendarFilter)
    fetchWindowEndDays.append(windowEndDay)
    return fetchResult
  }

  func upsertLorvexEvent(
    existingKey: String?, title: String, start: Date, end: Date,
    isAllDay: Bool, location: String?, notesPatch: EventKitNotesPatch,
    recurrence: String?, lorvexEventID: String,
    target: EventKitWriteTarget = .lorvexDefault
  ) async throws -> EventKitWriteResult {
    if let upsertError { throw upsertError }
    writes.append((key: existingKey, title: title, lorvexID: lorvexEventID))
    writeRecurrences.append(recurrence)
    writeTargets.append(target)
    let key = existingKey ?? { nextKey += 1; return "ek-key-\(nextKey)" }()
    return EventKitWriteResult(providerEventKey: key)
  }

  func replaceFutureLorvexEventSeries(
    originalLorvexEventID: String,
    occurrenceDate: Date,
    replacement: CalendarEventExport,
    replacementLorvexEventID: String,
    target: EventKitWriteTarget = .lorvexDefault
  ) async throws -> EventKitWriteResult {
    futureSeriesReplacements.append(
      FakeEventKitFutureSeriesReplacement(
        originalLorvexEventID: originalLorvexEventID,
        occurrenceDate: occurrenceDate,
        replacement: replacement,
        replacementLorvexEventID: replacementLorvexEventID,
        target: target))
    if let futureSeriesReplacementError { throw futureSeriesReplacementError }
    nextKey += 1
    return EventKitWriteResult(providerEventKey: "ek-key-\(nextKey)")
  }

  func deleteLorvexEvent(providerEventKey: String) async throws { deletes.append(providerEventKey) }
  func deleteLorvexEvent(lorvexEventID: String) async throws { deletes.append(lorvexEventID) }
  func removeLorvexEventOccurrence(lorvexEventID: String, occurrenceDate: Date) async throws {
    occurrenceRemovals.append((lorvexID: lorvexEventID, occurrenceDate: occurrenceDate))
  }
  func removeFutureLorvexEventSeries(
    lorvexEventID: String, occurrenceDate: Date
  ) async throws {
    futureSeriesRemovals.append((lorvexID: lorvexEventID, occurrenceDate: occurrenceDate))
  }

  func recordedWrites() -> [(key: String?, title: String, lorvexID: String)] { writes }
  func recordedWriteRecurrences() -> [String?] { writeRecurrences }
  func recordedFutureSeriesReplacements() -> [FakeEventKitFutureSeriesReplacement] {
    futureSeriesReplacements
  }
  func recordedCalendarIDLookups() -> [String] { calendarIDLookups }
  func recordedEventSourceLookups() -> [String] { eventSourceLookups }
  func recordedDeletes() -> [String] { deletes }
  func recordedOccurrenceRemovals() -> [(lorvexID: String, occurrenceDate: Date)] {
    occurrenceRemovals
  }
  func recordedFutureSeriesRemovals() -> [(lorvexID: String, occurrenceDate: Date)] {
    futureSeriesRemovals
  }
  func recordedRequestAccessCount() -> Int { requestAccessCount }
  func recordedFetchWindowEndDays() -> [String] { fetchWindowEndDays }
  func setReadAccessGranted(_ granted: Bool) {
    readAccessGranted = granted
    readAuthorizationStateOverride = granted ? .authorized : .unavailable
  }
  func setReadAuthorizationState(_ state: EventKitReadAuthorizationState) {
    readAuthorizationStateOverride = state
    readAccessGranted = state.canRead
  }
  func setAvailableCalendars(_ calendars: [EventKitCalendarDescriptor]) {
    availableCalendarResult = calendars
  }
  func setWritableCalendars(_ calendars: [EventKitCalendarDescriptor]) {
    writableCalendarResult = calendars
  }
  func setLorvexEventCalendarID(_ id: String?) { lorvexEventCalendarIDResult = id }
  func setUpsertError(_ error: EventKitAccessError?) { upsertError = error }
  func setFutureSeriesReplacementError(_ error: EventKitAccessError?) {
    futureSeriesReplacementError = error
  }
  func recordedWriteTargets() -> [EventKitWriteTarget] { writeTargets }
}

/// In-memory `EventKitProviderServicing` recording the provider-mirror calls
/// the coordinator makes (no SQLite).
final class FakeEventKitProvider: EventKitProviderServicing, @unchecked Sendable {
  private let lock = NSLock()
  private(set) var ingestedBatches: [[ProviderEventData]] = []
  private(set) var ingestedBuildModes: [CalendarAiAccessMode] = []
  private(set) var ingestedWindows: [(start: String, end: String)] = []
  private(set) var links: [(taskID: String, key: String)] = []
  private(set) var scopeEnabled: Bool?
  private(set) var clearCount = 0
  var eventKitLinksForTaskError: Error?

  func ingestEventKitEvents(
    _ events: [ProviderEventData], builtAtMode: CalendarAiAccessMode,
    windowStart: String, windowEnd: String
  ) throws -> Int {
    lock.withLock {
      ingestedBatches.append(events)
      ingestedBuildModes.append(builtAtMode)
      ingestedWindows.append((windowStart, windowEnd))
    }
    return events.count
  }
  func setEventKitScopeEnabled(_ enabled: Bool) throws { lock.withLock { scopeEnabled = enabled } }
  func clearEventKitMirror() throws -> Int { lock.withLock { clearCount += 1 }; return 0 }
  func linkTaskToEventKitEvent(taskID: String, providerEventKey: String) throws
    -> TaskProviderEventLink
  {
    lock.withLock { links.append((taskID: taskID, key: providerEventKey)) }
    let now = SyncTimestamp.now()
    return TaskProviderEventLink(
      taskId: taskID, providerKind: ProviderKind.eventkit, providerScope: "device",
      providerEventKey: providerEventKey, createdAt: now, updatedAt: now)
  }
  func unlinkTaskFromEventKitEvent(taskID: String, providerEventKey: String) throws
    -> ProviderEventLinkDeleteResult
  {
    lock.withLock { links.removeAll { $0.taskID == taskID && $0.key == providerEventKey } }
    return ProviderEventLinkDeleteResult(deleted: true, before: nil, remainingLinks: [])
  }
  func eventKitLinksForTask(taskID: String) throws -> [ProviderEventLinkWithResolution] {
    if let eventKitLinksForTaskError {
      throw eventKitLinksForTaskError
    }
    let row = lock.withLock { links.first { $0.taskID == taskID } }
    guard let row else { return [] }
    let now = SyncTimestamp.now()
    return [
      ProviderEventLinkWithResolution(
        taskId: row.taskID, providerKind: ProviderKind.eventkit, providerScope: "device",
        providerEventKey: row.key, createdAt: now, updatedAt: now, eventTitle: nil,
        eventStartDate: nil, eventStartTime: nil, resolutionState: .resolved)
    ]
  }

  func recordedLinks() -> [(taskID: String, key: String)] { lock.withLock { links } }
}
