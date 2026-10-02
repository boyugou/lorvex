import Foundation

extension LorvexSystemIntentRunner {
  public static func readCalendarTimeline(
    from: String,
    to: String,
    core: any LorvexCoreServicing
  ) async throws -> CalendarTimelineSnapshot {
    try await core.loadCalendarTimeline(
      from: try validatedCalendarDate(from, label: "from date"),
      to: try validatedCalendarDate(to, label: "to date")
    )
  }

  public static func searchCalendarEvents(
    query: String,
    from: String?,
    to: String?,
    limit: Int?,
    core: any LorvexCoreServicing
  ) async throws -> [CalendarTimelineEvent] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else {
      throw LorvexCoreError.validation(
        field: "query", message: "A calendar search query is required.")
    }
    return try await core.searchCalendarEvents(
      query: trimmedQuery,
      from: from.trimmedNilIfEmpty,
      to: to.trimmedNilIfEmpty,
      limit: limit.map { min(max(1, $0), 100) }
    )
  }

  public static func readLinkedEventsForTask(
    taskID: LorvexTask.ID,
    core: any LorvexCoreServicing
  ) async throws -> [CalendarTimelineEvent] {
    try await core.getLinkedEventsForTask(taskID: validatedTaskID(taskID))
  }

  public static func readLinkedTasksForEvent(
    eventID: CalendarTimelineEvent.ID,
    core: any LorvexCoreServicing
  ) async throws -> [LorvexTask] {
    try await core.getLinkedTasksForEvent(eventID: validatedCalendarEventID(eventID))
  }

  private static func validatedCalendarDate(_ value: String, label: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.validation(field: nil, message: "A calendar \(label) is required.")
    }
    return trimmed
  }
}
