import Foundation
import LorvexCore
import MCP

extension ToolRegistry {
  func updateCalendarEventResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let eventID: String
    switch requiredTrimmedString(
      "event_id", from: arguments, message: "An event_id is required.",
      toolName: "update_calendar_event")
    {
    case .value(let value): eventID = value
    case .error(let result): return result
    }
    let title = try StrictScalarArguments.optionalString(arguments["title"], field: "title")
    let startDate = try StrictScalarArguments.optionalString(
      arguments["start_date"], field: "start_date")
    let endDate = try StrictScalarArguments.optionalString(arguments["end_date"], field: "end_date")
    let startTime = try StrictScalarArguments.optionalString(
      arguments["start_time"], field: "start_time")
    let endTime = try StrictScalarArguments.optionalString(arguments["end_time"], field: "end_time")
    let allDay = try StrictScalarArguments.optionalBool(arguments["all_day"], field: "all_day")
    let timezone = try StrictScalarArguments.optionalString(arguments["timezone"], field: "timezone")
    let location = try StrictScalarArguments.optionalString(arguments["location"], field: "location")
    let description = try StrictScalarArguments.optionalString(arguments["notes"], field: "notes")
    let url = try StrictScalarArguments.optionalString(arguments["url"], field: "url")
    let color = try StrictScalarArguments.optionalString(arguments["color"], field: "color")
    let eventType = try StrictScalarArguments.optionalString(
      arguments["event_type"], field: "event_type")
    let personName = try StrictScalarArguments.optionalString(
      arguments["person_name"], field: "person_name")
    let attendees: CalendarEventAttendeesPatch
    let recurrence: CalendarEventRecurrencePatch
    do {
      attendees = try parseCalendarAttendeesPatch(
        arguments["attendees"], isPresent: arguments.keys.contains("attendees"))
      recurrence = try wireCalendarRecurrencePatch(
        arguments["recurrence"], isPresent: arguments.keys.contains("recurrence"))
    } catch let error as CalendarEventToolStoreError {
      return Self.errorResult(code: "validation", message: error.message, toolName: "update_calendar_event")
    }

    let value: Value
    do {
      value = try await updateCalendarEventPayload(
        id: eventID,
        title: title,
        startDate: startDate,
        endDate: endDate,
        startTime: startTime,
        endTime: endTime,
        allDay: allDay,
        location: location,
        description: description,
        recurrence: recurrence,
        timezone: timezone,
        url: url,
        color: color,
        eventType: eventType,
        personName: personName,
        attendees: attendees
      )
    } catch let error as CalendarEventToolStoreError {
      return notFoundResult(error, toolName: "update_calendar_event")
    }
    return successResult(text: "Updated calendar event \(eventID).", value: value)
  }

  func deleteCalendarEventResult(arguments: [String: Value]) async throws -> CallTool.Result {
    let eventID: String
    switch requiredTrimmedString(
      "event_id", from: arguments, message: "An event_id is required.",
      toolName: "delete_calendar_event")
    {
    case .value(let value): eventID = value
    case .error(let result): return result
    }
    let value = try await deleteCalendarEventPayload(id: eventID)
    return successResult(text: "Deleted calendar event \(eventID).", value: value)
  }

  func searchCalendarEventsResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let query = arguments["query"]?.stringValue else {
      return Self.errorResult(code: "validation", message: "A query is required.", toolName: "search_calendar_events")
    }
    let from = try StrictScalarArguments.optionalString(arguments["from"], field: "from")
    let to = try StrictScalarArguments.optionalString(arguments["to"], field: "to")
    let limit = min(
      max(1, try StrictScalarArguments.int(arguments["limit"], field: "limit", default: 50)),
      500)
    let offset = max(
      0, try StrictScalarArguments.int(arguments["offset"], field: "offset", default: 0))
    let outputOptions = try CalendarEventValueOptions.from(
      arguments: arguments, defaultShape: .compact)
    let value = try await searchCalendarEventsPayload(
      query: query, from: from, to: to, limit: limit, offset: offset, outputOptions: outputOptions)
    return fencedReadResult(text: "Searched calendar events.", value: value)
  }
}

func parseCalendarAttendees(_ value: Value?) throws -> [CalendarEventAttendee]? {
  guard let value else { return nil }
  if case .null = value { return nil }
  guard let rows = value.arrayValue else {
    throw CalendarEventToolStoreError(message: "attendees must be an array of objects.")
  }
  return try rows.enumerated().map { index, value in
    guard let object = value.objectValue else {
      throw CalendarEventToolStoreError(message: "attendees[\(index)] must be an object.")
    }
    // email is optional at the MCP layer: `CalendarEventAttendees.serialize`
    // (the trusted local write surface) accepts a name-only attendee and only
    // rejects a fully-empty attendee (no email AND no name), which it reports
    // as a clean `CalendarEventOpError.validation` surfaced through the
    // top-level tool-call error boundary. Don't duplicate that check here.
    let email = try StrictScalarArguments.string(
      object["email"], field: "attendees[\(index)].email", default: "")
    return CalendarEventAttendee(
      email: email,
      name: try StrictScalarArguments.optionalString(
        object["name"], field: "attendees[\(index)].name"))
  }
}

func parseCalendarAttendeesPatch(_ value: Value?, isPresent: Bool) throws
  -> CalendarEventAttendeesPatch
{
  guard isPresent else { return .unset }
  guard let value else { return .unset }
  if case .null = value { return .clear }
  return .set(try parseCalendarAttendees(value) ?? [])
}
