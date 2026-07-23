import Foundation
import LorvexCore
import MCP

extension ToolRegistry {
  func calendarTimelinePayload(
    from: String,
    to: String,
    outputOptions: CalendarEventValueOptions,
    limit: Int,
    offset: Int
  ) async throws -> Value {
    let value = try await coreBridge.loadCalendarTimeline(
      from: from, to: to, outputOptions: outputOptions)
    return Self.pageCalendarTimelineValue(value, limit: limit, offset: offset)
  }

  static func pageCalendarTimelineValue(_ value: Value, limit: Int, offset: Int) -> Value {
    guard case .object(var object) = value, let events = object["events"]?.arrayValue else {
      return value
    }
    let total = events.count
    let start = min(max(offset, 0), total)
    let end = min(start + max(limit, 1), total)
    let page = Array(events[start..<end])
    let truncated = end < total || (object["truncated"]?.boolValue ?? false)
    object["events"] = .array(page)
    object = MCPPagination.merged(
      into: object, totalMatching: total, returned: page.count, limit: max(limit, 1),
      offset: start, nextOffset: end < total ? end : nil, truncated: truncated)
    return .object(object)
  }

  func createCalendarEventPayload(
    title: String,
    startDate: String,
    endDate: String?,
    startTime: String?,
    endTime: String?,
    allDay: Bool,
    location: String?,
    description: String?,
    recurrence: TaskRecurrenceRule?,
    timezone: String?,
    url: String?,
    color: String?,
    eventType: String?,
    personName: String?,
    attendees: [CalendarEventAttendee]?,
    originalID: String? = nil
  ) async throws -> Value {
    try await coreBridge.createCalendarEvent(
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
      attendees: attendees,
      originalID: originalID
    )
  }

  func updateCalendarEventPayload(
    id: String,
    title: String?,
    startDate: String?,
    endDate: String?,
    startTime: String?,
    endTime: String?,
    allDay: Bool?,
    location: String?,
    description: String?,
    recurrence: CalendarEventRecurrencePatch,
    timezone: String?,
    url: String?,
    color: String?,
    eventType: String?,
    personName: String?,
    attendees: CalendarEventAttendeesPatch
  ) async throws -> Value {
    try await coreBridge.updateCalendarEvent(
      id: id,
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
  }

  func deleteCalendarEventPayload(id: String) async throws -> Value {
    try await coreBridge.deleteCalendarEvent(id: id)
  }

  func searchCalendarEventsPayload(
    query: String,
    from: String?,
    to: String?,
    limit: Int,
    offset: Int,
    outputOptions: CalendarEventValueOptions
  ) async throws
    -> Value
  {
    try await coreBridge.searchCalendarEvents(
      query: query, from: from, to: to, limit: limit, offset: offset,
      outputOptions: outputOptions)
  }
}
