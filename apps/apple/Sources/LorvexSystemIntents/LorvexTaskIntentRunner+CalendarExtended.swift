import LorvexCore

extension LorvexTaskIntentRunner {
  public static func readCalendarTimeline(
    from: String,
    to: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> CalendarTimelineSnapshot {
    try await LorvexSystemIntentRunner.readCalendarTimeline(from: from, to: to, core: core)
  }

  public static func searchCalendarEvents(
    query: String,
    from: String? = nil,
    to: String? = nil,
    limit: Int? = nil,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> [CalendarTimelineEvent] {
    try await LorvexSystemIntentRunner.searchCalendarEvents(
      query: query,
      from: from,
      to: to,
      limit: limit,
      core: core
    )
  }

  public static func linkTaskToProviderEvent(
    taskID: LorvexTask.ID,
    providerEventID: String,
    providerSource: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> TaskCalendarEventLink {
    try await LorvexSystemIntentRunner.linkTaskToProviderEvent(
      taskID: taskID,
      providerEventID: providerEventID,
      providerSource: providerSource,
      core: core
    )
  }

  public static func unlinkTaskFromProviderEvent(
    taskID: LorvexTask.ID,
    providerEventID: String,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws {
    try await LorvexSystemIntentRunner.unlinkTaskFromProviderEvent(
      taskID: taskID,
      providerEventID: providerEventID,
      core: core
    )
  }

  public static func readLinkedEventsForTask(
    taskID: LorvexTask.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> [CalendarTimelineEvent] {
    try await LorvexSystemIntentRunner.readLinkedEventsForTask(taskID: taskID, core: core)
  }

  public static func readLinkedTasksForEvent(
    eventID: CalendarTimelineEvent.ID,
    core: any LorvexCoreServicing = LorvexCoreRuntimeFactory.makeForAppIntent()
  ) async throws -> [LorvexTask] {
    try await LorvexSystemIntentRunner.readLinkedTasksForEvent(eventID: eventID, core: core)
  }
}
