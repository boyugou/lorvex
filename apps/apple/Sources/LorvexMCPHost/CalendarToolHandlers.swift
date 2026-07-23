import Foundation
import LorvexCore
import MCP

extension ToolRegistry {
  func calendarTimelineResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let from = arguments["from"]?.stringValue, !from.isEmpty else {
      return Self.errorResult(code: "validation", message: "A from date is required.", toolName: "get_calendar_timeline")
    }
    guard let to = arguments["to"]?.stringValue, !to.isEmpty else {
      return Self.errorResult(code: "validation", message: "A to date is required.", toolName: "get_calendar_timeline")
    }
    let outputOptions = try CalendarEventValueOptions.from(
      arguments: arguments, defaultShape: .compact)
    let limit = min(
      max(try StrictScalarArguments.int(arguments["limit"], field: "limit", default: 100), 1),
      500)
    let offset = max(
      try StrictScalarArguments.int(arguments["offset"], field: "offset", default: 0), 0)
    let value = try await calendarTimelinePayload(
      from: from, to: to, outputOptions: outputOptions, limit: limit, offset: offset)
    return fencedReadResult(text: "Loaded calendar timeline.", value: value)
  }

  func createCalendarEventResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard
      let title = arguments["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      !title.isEmpty
    else {
      return Self.errorResult(code: "validation", message: "A non-empty title is required.", toolName: "create_calendar_event")
    }
    guard let startDate = arguments["start_date"]?.stringValue, !startDate.isEmpty else {
      return Self.errorResult(code: "validation", message: "A start_date value is required.", toolName: "create_calendar_event")
    }
    let allDay = try StrictScalarArguments.bool(
      arguments["all_day"], field: "all_day", default: false)
    let startTime = allDay
      ? nil : try StrictScalarArguments.optionalString(arguments["start_time"], field: "start_time")
    let endTime = allDay
      ? nil : try StrictScalarArguments.optionalString(arguments["end_time"], field: "end_time")
    let attendees: [CalendarEventAttendee]?
    let recurrence: TaskRecurrenceRule?
    do {
      attendees = try parseCalendarAttendees(arguments["attendees"])
      recurrence = try wireCalendarRecurrenceRule(arguments["recurrence"])
    } catch let error as CalendarEventToolStoreError {
      return Self.errorResult(code: "validation", message: error.message, toolName: "create_calendar_event")
    }

    let value = try await createCalendarEventPayload(
      title: title,
      startDate: startDate,
      endDate: try StrictScalarArguments.optionalString(arguments["end_date"], field: "end_date"),
      startTime: startTime,
      endTime: endTime,
      allDay: allDay,
      location: try StrictScalarArguments.optionalString(arguments["location"], field: "location"),
      description: try StrictScalarArguments.optionalString(arguments["notes"], field: "notes"),
      recurrence: recurrence,
      timezone: try StrictScalarArguments.optionalString(arguments["timezone"], field: "timezone"),
      url: try StrictScalarArguments.optionalString(arguments["url"], field: "url"),
      color: try StrictScalarArguments.optionalString(arguments["color"], field: "color"),
      eventType: try StrictScalarArguments.optionalString(
        arguments["event_type"], field: "event_type"),
      personName: try StrictScalarArguments.optionalString(
        arguments["person_name"], field: "person_name"),
      attendees: attendees,
      originalID: try CoreBridgeClient.strictImportOriginalID(
        arguments["original_id"], field: "original_id")
    )
    return successResult(text: "Created calendar event: \(title)", value: value)
  }
}

extension ToolRegistry {
  func batchCreateCalendarEventsResult(arguments: [String: Value]) async throws -> CallTool.Result {
    guard let items = arguments["events"]?.arrayValue, !items.isEmpty else {
      return Self.errorResult(code: "validation", message: "events array is required and must not be empty.", toolName: "batch_create_calendar_events")
    }
    guard items.count <= MCPBatchLimits.maxItems else {
      return Self.errorResult(
        code: "validation",
        message: "batch_create_calendar_events accepts at most \(MCPBatchLimits.maxItems) events per call; split larger sets across calls.",
        toolName: "batch_create_calendar_events")
    }
    // Validate-and-collect per item: a malformed or unpersistable event (bad
    // attendee, invalid recurrence, duplicate original_id) is reported in
    // `skipped` and the rest still land, so restoring a large exported schedule
    // is not aborted by one stale row. Each item carries the full
    // create_calendar_event surface, including original_id for id-preserving
    // re-create.
    var specs: [McpCalendarEventCreateSpec] = []
    var skipped: [Value] = []
    var seenOriginalIDs = Set<String>()
    specs.reserveCapacity(items.count)
    for (index, item) in items.enumerated() {
      let ref =
        CoreBridgeClient.importOriginalID(item.objectValue?["original_id"])
        ?? item.objectValue?["title"]?.stringValue?.trimmingCharacters(
          in: .whitespacesAndNewlines)
        ?? "events[\(index)]"
      do {
        let draft = try calendarEventDraft(from: item, index: index)
        let originalID = try CoreBridgeClient.strictImportOriginalID(
          item.objectValue?["original_id"], field: "events[\(index)].original_id")
        if let originalID, !seenOriginalIDs.insert(originalID).inserted {
          return Self.errorResult(
            code: "validation",
            message:
              "events[\(index)].original_id duplicates an earlier event; each original_id must appear once.",
            toolName: "batch_create_calendar_events")
        }
        specs.append(
          McpCalendarEventCreateSpec(
            reference: ref, draft: draft, originalID: originalID))
      } catch let error as CalendarEventToolStoreError {
        skipped.append(CoreBridgeClient.batchSkip(id: ref, reason: error.message))
      } catch {
        skipped.append(CoreBridgeClient.batchSkip(id: ref, reason: Self.errorMessage(for: error)))
      }
    }
    var results: [Value] = []
    results.reserveCapacity(specs.count)
    for outcome in try await coreBridge.mcpMutations.batchCreateCalendarEventsForMcp(specs) {
      switch outcome {
      case .created(let event):
        results.append(CoreBridgeClient.calendarEventValue(from: event))
      case .failed(let reference, let error):
        skipped.append(
          CoreBridgeClient.batchSkip(id: reference, reason: Self.errorMessage(for: error)))
      }
    }
    let structured: Value = .object([
      "results": .array(results),
      "count": .int(results.count),
      "skipped": .array(skipped),
    ])
    return CallTool.Result(
      content: [
        .text(
          text: "Created \(results.count) calendar event(s).", annotations: nil, _meta: nil)
      ],
      structuredContent: Optional.some(structured),
      isError: false
    )
  }
}

private func calendarEventDraft(from value: Value, index: Int) throws -> CalendarEventCreateDraft {
  guard let obj = value.objectValue else {
    throw CalendarEventToolStoreError(message: "events[\(index)] must be an object.")
  }
  guard let title = obj["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
    !title.isEmpty
  else {
    throw CalendarEventToolStoreError(message: "events[\(index)].title is required.")
  }
  guard let startDate = obj["start_date"]?.stringValue, !startDate.isEmpty else {
    throw CalendarEventToolStoreError(message: "events[\(index)].start_date is required.")
  }
  func strictString(_ key: String) throws -> String? {
    try StrictScalarArguments.optionalString(obj[key], field: "events[\(index)].\(key)")
  }
  let allDay = try StrictScalarArguments.bool(
    obj["all_day"], field: "events[\(index)].all_day", default: false)
  return CalendarEventCreateDraft(
    title: title,
    startDate: startDate,
    endDate: try strictString("end_date"),
    startTime: allDay ? nil : try strictString("start_time"),
    endTime: allDay ? nil : try strictString("end_time"),
    allDay: allDay,
    location: try strictString("location"),
    notes: try strictString("notes"),
    recurrence: try wireCalendarRecurrenceRule(obj["recurrence"]),
    timezone: try strictString("timezone"),
    url: try strictString("url"),
    color: try strictString("color"),
    eventType: try strictString("event_type"),
    personName: try strictString("person_name"),
    attendees: try parseCalendarAttendees(obj["attendees"])
  )
}
