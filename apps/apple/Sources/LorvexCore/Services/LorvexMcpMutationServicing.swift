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

/// Current-focus header plus the exact task candidates read before its write
/// transaction commits.
public struct McpCurrentFocusProjection: Sendable {
  public var plan: CurrentFocusPlan?
  public var tasks: [LorvexTask]

  public init(plan: CurrentFocusPlan?, tasks: [LorvexTask]) {
    self.plan = plan
    self.tasks = tasks
  }
}

public struct McpCurrentFocusRemovalReceipt: Sendable {
  public var current: McpCurrentFocusProjection
  public var removed: Bool

  public init(current: McpCurrentFocusProjection, removed: Bool) {
    self.current = current
    self.removed = removed
  }
}

public struct McpCurrentFocusClearReceipt: Sendable {
  public var previous: McpCurrentFocusProjection
  public var cleared: Bool

  public init(previous: McpCurrentFocusProjection, cleared: Bool) {
    self.previous = previous
    self.cleared = cleared
  }
}

public struct McpFocusScheduleSaveReceipt: Sendable {
  public var schedule: FocusSchedule
  public var currentFocus: McpCurrentFocusProjection

  public init(schedule: FocusSchedule, currentFocus: McpCurrentFocusProjection) {
    self.schedule = schedule
    self.currentFocus = currentFocus
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

  func setCurrentFocusForMcp(
    date: String, taskIDs: [LorvexTask.ID], briefing: String?, timezone: String
  ) async throws -> McpCurrentFocusProjection
  func addToCurrentFocusForMcp(
    date: String, taskIDs: [LorvexTask.ID], briefing: String?, timezone: String
  ) async throws -> McpCurrentFocusProjection
  func removeFromCurrentFocusForMcp(
    date: String, taskID: LorvexTask.ID
  ) async throws -> McpCurrentFocusRemovalReceipt
  func clearCurrentFocusForMcp(date: String) async throws -> McpCurrentFocusClearReceipt
  func saveFocusScheduleForMcp(
    date: String, blocks: [FocusScheduleBlock], rationale: String?
  ) async throws -> McpFocusScheduleSaveReceipt

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
