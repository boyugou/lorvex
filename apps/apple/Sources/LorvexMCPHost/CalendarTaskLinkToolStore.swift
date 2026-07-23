import MCP

extension ToolRegistry {
  func linkTaskToProviderEventPayload(
    taskID: String,
    providerEventID: String,
    providerSource: String
  ) async throws -> Value {
    try await coreBridge.linkTaskToProviderEvent(
      taskID: taskID,
      providerEventID: providerEventID,
      providerSource: providerSource
    )
  }

  func unlinkTaskFromProviderEventPayload(taskID: String, providerEventID: String) async throws -> Value {
    try await coreBridge.unlinkTaskFromProviderEvent(
      taskID: taskID,
      providerEventID: providerEventID
    )
  }

  func linkedEventsForTaskPayload(
    taskID: String,
    outputOptions: CalendarEventValueOptions = .full
  ) async throws -> Value {
    try await coreBridge.getLinkedEventsForTask(
      taskID: taskID, outputOptions: outputOptions)
  }

  func linkedTasksForEventPayload(eventID: String) async throws -> Value {
    try await coreBridge.getLinkedTasksForEvent(eventID: eventID)
  }

  func addCalendarEventExceptionPayload(eventID: String, date: String) async throws -> Value {
    let event = try await coreBridge.service.addCalendarEventException(
      eventID: eventID, date: date)
    return CoreBridgeClient.calendarEventValue(from: event)
  }

  func removeCalendarEventExceptionPayload(eventID: String, date: String) async throws -> Value {
    let event = try await coreBridge.service.removeCalendarEventException(
      eventID: eventID, date: date)
    return CoreBridgeClient.calendarEventValue(from: event)
  }
}
