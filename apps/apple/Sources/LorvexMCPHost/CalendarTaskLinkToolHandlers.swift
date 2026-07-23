import MCP

extension ToolRegistry {
  func linkTaskToProviderEventResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let taskID = try Self.taskScopedID(from: arguments) else {
      return Self.errorResult(
        code: "validation", message: "A task_id is required.",
        toolName: "link_task_to_provider_event")
    }
    guard let providerEventID = arguments["provider_event_id"]?.stringValue,
      !providerEventID.isEmpty
    else {
      return Self.errorResult(
        code: "validation", message: "A provider_event_id is required.",
        toolName: "link_task_to_provider_event")
    }
    guard let providerSource = arguments["provider_source"]?.stringValue, !providerSource.isEmpty
    else {
      return Self.errorResult(
        code: "validation", message: "A provider_source is required.",
        toolName: "link_task_to_provider_event")
    }

    let value = try await linkTaskToProviderEventPayload(
      taskID: taskID,
      providerEventID: providerEventID,
      providerSource: providerSource
    )
    return successResult(text: "Linked task to provider event.", value: value)
  }

  func linkTaskToEventResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let taskID = try Self.taskScopedID(from: arguments) else {
      return Self.errorResult(
        code: "validation", message: "A task_id is required.", toolName: "link_task_to_event")
    }
    guard let eventID = arguments["event_id"]?.stringValue, !eventID.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "An event_id is required.", toolName: "link_task_to_event")
    }
    let value = try await coreBridge.linkTaskToEvent(taskID: taskID, calendarEventID: eventID)
    return successResult(text: "Linked task to calendar event.", value: value)
  }

  func unlinkTaskFromEventResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let taskID = try Self.taskScopedID(from: arguments) else {
      return Self.errorResult(
        code: "validation", message: "A task_id is required.", toolName: "unlink_task_from_event")
    }
    guard let eventID = arguments["event_id"]?.stringValue, !eventID.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "An event_id is required.", toolName: "unlink_task_from_event")
    }
    let value = try await coreBridge.unlinkTaskFromEvent(taskID: taskID, calendarEventID: eventID)
    return successResult(text: "Unlinked task from calendar event.", value: value)
  }

  func unlinkTaskFromProviderEventResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let taskID = try Self.taskScopedID(from: arguments) else {
      return Self.errorResult(
        code: "validation", message: "A task_id is required.",
        toolName: "unlink_task_from_provider_event")
    }
    guard let providerEventID = arguments["provider_event_id"]?.stringValue,
      !providerEventID.isEmpty
    else {
      return Self.errorResult(
        code: "validation", message: "A provider_event_id is required.",
        toolName: "unlink_task_from_provider_event")
    }

    let value = try await unlinkTaskFromProviderEventPayload(
      taskID: taskID,
      providerEventID: providerEventID
    )
    return successResult(text: "Unlinked task from provider event.", value: value)
  }

  func linkedEventsForTaskResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let taskID = try Self.taskScopedID(from: arguments) else {
      return Self.errorResult(
        code: "validation", message: "A task_id is required.",
        toolName: "get_linked_events_for_task")
    }
    let outputOptions = try CalendarEventValueOptions.from(
      arguments: arguments, defaultShape: .compact)
    let value = try await linkedEventsForTaskPayload(
      taskID: taskID, outputOptions: outputOptions)
    return fencedReadResult(text: "Loaded linked events.", value: value)
  }

  func linkedTasksForEventResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let eventID = arguments["event_id"]?.stringValue, !eventID.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "An event_id is required.",
        toolName: "get_linked_tasks_for_event")
    }
    let value = try await linkedTasksForEventPayload(eventID: eventID)
    return fencedReadResult(text: "Loaded linked tasks.", value: value)
  }

  func addCalendarEventExceptionResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let eventID = arguments["event_id"]?.stringValue, !eventID.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "An event_id is required.",
        toolName: "add_calendar_event_exception")
    }
    guard let occurrenceDate = arguments["occurrence_date"]?.stringValue, !occurrenceDate.isEmpty
    else {
      return Self.errorResult(
        code: "validation", message: "An occurrence_date (YYYY-MM-DD) is required.",
        toolName: "add_calendar_event_exception")
    }
    do {
      let value = try await addCalendarEventExceptionPayload(
        eventID: eventID, date: occurrenceDate)
      return successResult(
        text: "Cancelled occurrence '\(occurrenceDate)' for event '\(eventID)'.", value: value)
    } catch {
      return Self.errorResult(
        code: Self.errorCode(for: error), message: Self.errorMessage(for: error),
        toolName: "add_calendar_event_exception")
    }
  }

  func removeCalendarEventExceptionResult(
    arguments: [String: Value]
  ) async throws -> CallTool.Result {
    guard let eventID = arguments["event_id"]?.stringValue, !eventID.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "An event_id is required.",
        toolName: "remove_calendar_event_exception")
    }
    guard let occurrenceDate = arguments["occurrence_date"]?.stringValue, !occurrenceDate.isEmpty
    else {
      return Self.errorResult(
        code: "validation", message: "An occurrence_date (YYYY-MM-DD) is required.",
        toolName: "remove_calendar_event_exception")
    }
    do {
      let value = try await removeCalendarEventExceptionPayload(
        eventID: eventID, date: occurrenceDate)
      return successResult(
        text: "Restored occurrence '\(occurrenceDate)' for event '\(eventID)'.", value: value)
    } catch {
      return Self.errorResult(
        code: Self.errorCode(for: error), message: Self.errorMessage(for: error),
        toolName: "remove_calendar_event_exception")
    }
  }
}
