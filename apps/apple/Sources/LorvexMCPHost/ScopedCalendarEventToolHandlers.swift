import LorvexCore
import MCP

extension ToolRegistry {
  func editScopedCalendarEventResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let eventID = arguments["event_id"]?.stringValue, !eventID.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "event_id is required.",
        toolName: "edit_scoped_calendar_event")
    }
    guard let occurrenceDate = arguments["occurrence_date"]?.stringValue, !occurrenceDate.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "occurrence_date is required.",
        toolName: "edit_scoped_calendar_event")
    }
    guard let scope = arguments["scope"]?.stringValue, !scope.isEmpty else {
      return Self.errorResult(
        code: "validation",
        message: "scope is required (all_in_series, this_only, or this_and_following).",
        toolName: "edit_scoped_calendar_event")
    }
    let service = coreBridge.service

    let recurrencePatch: CalendarEventRecurrencePatch
    do {
      recurrencePatch = try wireCalendarRecurrencePatch(
        arguments["recurrence"], isPresent: arguments.keys.contains("recurrence"))
    } catch let error as CalendarEventToolStoreError {
      return Self.errorResult(
        code: "validation", message: error.message, toolName: "edit_scoped_calendar_event")
    }

    let updates = ScopedCalendarEventUpdates(
      title: try StrictScalarArguments.optionalString(arguments["title"], field: "title"),
      startDate: try StrictScalarArguments.optionalString(
        arguments["start_date"], field: "start_date"),
      endDate: try StrictScalarArguments.optionalString(arguments["end_date"], field: "end_date"),
      startTime: try StrictScalarArguments.optionalString(
        arguments["start_time"], field: "start_time"),
      endTime: try StrictScalarArguments.optionalString(arguments["end_time"], field: "end_time"),
      allDay: try StrictScalarArguments.optionalBool(arguments["all_day"], field: "all_day"),
      location: try StrictScalarArguments.optionalString(arguments["location"], field: "location"),
      notes: try StrictScalarArguments.optionalString(arguments["notes"], field: "notes"),
      recurrence: recurrencePatch,
      timezone: try StrictScalarArguments.optionalString(arguments["timezone"], field: "timezone"),
      url: try StrictScalarArguments.optionalString(arguments["url"], field: "url"),
      color: try StrictScalarArguments.optionalString(arguments["color"], field: "color"),
      eventType: try StrictScalarArguments.optionalString(
        arguments["event_type"], field: "event_type"),
      personName: try StrictScalarArguments.optionalString(
        arguments["person_name"], field: "person_name")
    )

    do {
      let result = try await service.editScopedCalendarEvent(
        eventID: eventID, occurrenceDate: occurrenceDate, scope: scope, updates: updates)
      let raw = Value.object([
        "original_event": result.originalEvent.map { CoreBridgeClient.calendarEventValue(from: $0) } ?? .null,
        "replacement_event": result.replacementEvent.map {
          CoreBridgeClient.calendarEventValue(from: $0)
        } ?? .null,
        "noop": .bool(result.noop),
      ])
      return successResult(text: "Edited calendar event '\(eventID)' (\(scope)).",
        value: SecurityFencing.fenceValue(raw))
    } catch {
      return Self.errorResult(
        code: Self.errorCode(for: error), message: Self.errorMessage(for: error),
        toolName: "edit_scoped_calendar_event")
    }
  }

  func deleteScopedCalendarEventResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let eventID = arguments["event_id"]?.stringValue, !eventID.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "event_id is required.",
        toolName: "delete_scoped_calendar_event")
    }
    guard let occurrenceDate = arguments["occurrence_date"]?.stringValue, !occurrenceDate.isEmpty else {
      return Self.errorResult(
        code: "validation", message: "occurrence_date is required.",
        toolName: "delete_scoped_calendar_event")
    }
    guard let scope = arguments["scope"]?.stringValue, !scope.isEmpty else {
      return Self.errorResult(
        code: "validation",
        message: "scope is required (all_in_series, this_only, or this_and_following).",
        toolName: "delete_scoped_calendar_event")
    }
    let service = coreBridge.service

    do {
      let result = try await service.deleteScopedCalendarEvent(
        eventID: eventID, occurrenceDate: occurrenceDate, scope: scope)
      let raw = Value.object([
        "previous": result.event.map { CoreBridgeClient.calendarEventValue(from: $0) } ?? .null,
        "noop": .bool(result.noop),
      ])
      return successResult(text: "Deleted calendar event '\(eventID)' (\(scope)).",
        value: SecurityFencing.fenceValue(raw))
    } catch {
      return Self.errorResult(
        code: Self.errorCode(for: error), message: Self.errorMessage(for: error),
        toolName: "delete_scoped_calendar_event")
    }
  }
}
