import Foundation

/// A deletion result captured under the same SQLite writer transaction that
/// removed the row. MCP uses the pre-delete value for its rich response; a
/// post-commit read cannot reconstruct it safely once another process writes.
public struct McpDeletionReceipt<Entity: Sendable>: Sendable {
  public var previous: Entity?

  public init(previous: Entity?) {
    self.previous = previous
  }

  public var deleted: Bool { previous != nil }
}

/// The day's briefing after `set_daily_briefing`, with the text it replaced.
public struct McpDailyBriefingReceipt: Sendable, Equatable {
  public var date: String
  public var briefing: String?
  public var previous: String?

  public init(date: String, briefing: String?, previous: String?) {
    self.date = date
    self.briefing = briefing
    self.previous = previous
  }

  public var changed: Bool { briefing != previous }
}

/// A day's times after `save_daily_schedule`, read in the save's own write
/// transaction.
public struct McpDayTimesSaveReceipt: Sendable {
  /// The day, `yyyy-MM-dd`.
  public var date: String
  /// Every task with a time on the day, finished ones included, in start
  /// order.
  public var timedTasks: [LorvexTask]
  /// The unfinished tasks the save took a time from; they keep their planned
  /// date.
  public var clearedTasks: [LorvexTask]

  public init(date: String, timedTasks: [LorvexTask], clearedTasks: [LorvexTask]) {
    self.date = date
    self.timedTasks = timedTasks
    self.clearedTasks = clearedTasks
  }
}

public struct McpHabitBatchCompletionReceipt: Sendable {
  public var snapshot: HabitCatalogSnapshot
  public var completedIDs: [LorvexHabit.ID]
  public var notFoundIDs: [LorvexHabit.ID]
  public var alreadyCompleteIDs: [LorvexHabit.ID]

  public init(
    snapshot: HabitCatalogSnapshot,
    completedIDs: [LorvexHabit.ID],
    notFoundIDs: [LorvexHabit.ID],
    alreadyCompleteIDs: [LorvexHabit.ID]
  ) {
    self.snapshot = snapshot
    self.completedIDs = completedIDs
    self.notFoundIDs = notFoundIDs
    self.alreadyCompleteIDs = alreadyCompleteIDs
  }
}

/// Per-row outcome of an MCP task-record batch create. Advice is derived from
/// the final batch state before the surrounding writer transaction commits, so
/// a concurrent delete/edit cannot turn a committed mutation into a response
/// failure or make the response describe a later database state.
public enum McpTaskRecordCreateOutcome: Sendable {
  case created(task: LorvexTask, advice: [TaskIntakeAdviceItem])
  case failed(reference: String, error: any Error)
}

/// One row of `batch_create_calendar_events`, parsed before the database call.
/// `reference` is response-only and is never persisted.
public struct McpCalendarEventCreateSpec: Sendable {
  public var reference: String
  public var draft: CalendarEventCreateDraft
  public var originalID: String?

  public init(reference: String, draft: CalendarEventCreateDraft, originalID: String?) {
    self.reference = reference
    self.draft = draft
    self.originalID = originalID
  }
}

public enum McpCalendarEventCreateOutcome: Sendable {
  case created(CalendarTimelineEvent)
  case failed(reference: String, error: any Error)
}

public struct McpTaskCalendarEventLinkReceipt: Sendable {
  public var calendarEventID: String
  public var changed: Bool

  public init(calendarEventID: String, changed: Bool) {
    self.calendarEventID = calendarEventID
    self.changed = changed
  }
}

/// MCP-only rich-return capability. Every method returns values captured under
/// the mutation's own `BEGIN IMMEDIATE`; the general app-facing service remains
/// free of wire-response concerns.
public protocol LorvexMcpMutationServicing: Sendable {
  func createListForMcpIfAbsent(_ list: ExportList) async throws -> LorvexList
  func createHabitForMcpIfAbsent(_ habit: ExportHabit) async throws -> LorvexHabit
  func batchCreateCalendarEventsForMcp(
    _ specs: [McpCalendarEventCreateSpec]
  ) async throws -> [McpCalendarEventCreateOutcome]
  func batchCreateTaskRecordsForMcp(
    _ specs: [TaskRecordCreateSpec], includeAdvice: Bool
  ) async throws -> [McpTaskRecordCreateOutcome]

  func deleteTaskForMcp(id: LorvexTask.ID) async throws -> McpDeletionReceipt<LorvexTask>
  func deleteListForMcp(id: LorvexList.ID) async throws -> McpDeletionReceipt<LorvexList>
  func deleteHabitForMcp(id: LorvexHabit.ID) async throws -> McpDeletionReceipt<LorvexHabit>
  func deleteMemoryForMcp(key: String) async throws -> McpDeletionReceipt<MemoryEntry>
  func deletePreferenceForMcp(key: String) async throws -> McpDeletionReceipt<String>

  /// Set or clear the briefing for `date`: the assistant's short note on what
  /// matters that day. A `nil` or blank briefing clears it.
  func setDailyBriefingForMcp(date: String, briefing: String?) async throws
    -> McpDailyBriefingReceipt
  /// ``LorvexDayPlanningServicing/saveDayTimes(date:times:)`` with the tasks
  /// whose times the save cleared.
  func saveDayTimesForMcp(date: String, times: [LorvexTaskTime]) async throws
    -> McpDayTimesSaveReceipt

  func batchCompleteHabitsForMcp(
    ids: [LorvexHabit.ID], date: String
  ) async throws -> McpHabitBatchCompletionReceipt

  func linkTaskToCalendarEventForMcp(
    taskID: LorvexTask.ID, calendarEventID: CalendarTimelineEvent.ID
  ) async throws -> McpTaskCalendarEventLinkReceipt
  func unlinkTaskFromCalendarEventForMcp(
    taskID: LorvexTask.ID, calendarEventID: CalendarTimelineEvent.ID
  ) async throws -> McpTaskCalendarEventLinkReceipt
}
