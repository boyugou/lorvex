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

  public static func linkTaskToProviderEvent(
    taskID: LorvexTask.ID,
    providerEventID: String,
    providerSource: String,
    core: any LorvexCoreServicing
  ) async throws -> TaskCalendarEventLink {
    try await core.linkTaskToProviderEvent(
      taskID: validatedTaskID(taskID),
      providerEventID: try validatedProviderEventID(providerEventID),
      providerSource: try validatedProviderSource(providerSource)
    )
  }

  public static func unlinkTaskFromProviderEvent(
    taskID: LorvexTask.ID,
    providerEventID: String,
    core: any LorvexCoreServicing
  ) async throws {
    try await core.unlinkTaskFromProviderEvent(
      taskID: validatedTaskID(taskID),
      providerEventID: try validatedProviderEventID(providerEventID)
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

  private static func validatedProviderEventID(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.validation(
        field: "provider_event_id", message: "A provider event ID is required.")
    }
    return trimmed
  }

  private static func validatedProviderSource(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.validation(
        field: "provider_source", message: "A provider source is required.")
    }
    return trimmed
  }
}
