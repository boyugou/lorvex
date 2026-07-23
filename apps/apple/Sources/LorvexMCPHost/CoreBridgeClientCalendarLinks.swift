import Foundation
import LorvexCore
import MCP

extension CoreBridgeClient {
  func updateCalendarEvent(
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
    let event = try await service.updateCalendarEvent(
      id: id,
      title: title,
      startDate: startDate,
      endDate: endDate,
      startTime: startTime,
      endTime: endTime,
      allDay: allDay,
      location: location,
      notes: description,
      recurrence: recurrence,
      timezone: timezone,
      url: url,
      color: color,
      eventType: eventType,
      personName: personName,
      attendees: attendees
    )
    return Self.calendarEventValue(from: event)
  }

  func deleteCalendarEvent(id: String) async throws -> Value {
    // `deleted` reflects the core's real outcome; deleting a non-existent event
    // is a no-op that returns `deleted:false` with a null `previous`, writing no
    // ai_changelog row. `previous` carries the removed event for undo/confirmation.
    let previous = try await service.deleteCalendarEvent(id: id)
    return .object([
      "deleted": .bool(previous != nil),
      "id": .string(id),
      "previous": previous.map { Self.calendarEventValue(from: $0) } ?? .null,
    ])
  }

  func searchCalendarEvents(
    query: String,
    from: String?,
    to: String?,
    limit: Int,
    offset: Int,
    outputOptions: CalendarEventValueOptions = .full
  ) async throws -> Value {
    // Fetch one extra row so the envelope reports a real `truncated`/`next_offset`
    // without a separate COUNT — the merged canonical+provider result has no
    // cheap total, so `total_matching` stays null.
    let rows = try await service.searchCalendarEvents(
      query: query, from: from, to: to, limit: limit + 1, offset: offset)
    let truncated = rows.count > limit
    let page = Array(rows.prefix(limit))
    return MCPPagination.object(
      domain: [
        "events": .array(page.map { Self.calendarEventValue(from: $0, options: outputOptions) })
      ],
      totalMatching: nil, returned: page.count, limit: limit,
      offset: offset, nextOffset: truncated ? offset + limit : nil, truncated: truncated)
  }

  func linkTaskToProviderEvent(
    taskID: String,
    providerEventID: String,
    providerSource: String
  ) async throws -> Value {
    let link = try await service.linkTaskToProviderEvent(
      taskID: taskID, providerEventID: providerEventID, providerSource: providerSource)
    return .object([
      "task_id": .string(link.taskID),
      "provider_event_id": .string(link.providerEventID ?? providerEventID),
      "provider_source": .string(link.providerSource ?? providerSource),
    ])
  }

  /// Create the canonical (synced) task↔calendar-event link. Routes to the
  /// id-preserving ``importTaskCalendarEventLink`` core entry (the same one bulk
  /// data import uses), reached by conformance downcast because the canonical
  /// link importer is not part of `LorvexCoreServicing`. Idempotent: re-linking
  /// the same pair is a no-op (the existing link is preserved, not re-stamped).
  /// `SwiftLorvexCoreService` always conforms;
  /// the `else` guards only an injected stub service without the conformance.
  func linkTaskToEvent(taskID: String, calendarEventID: String) async throws -> Value {
    let receipt = try await mcpMutations.linkTaskToCalendarEventForMcp(
      taskID: taskID, calendarEventID: calendarEventID)
    return .object([
      "task_id": .string(taskID),
      "calendar_event_id": .string(receipt.calendarEventID),
      "linked": .bool(true),
    ])
  }

  /// Remove the canonical (synced) task↔calendar-event link. Routes to the core
  /// ``SwiftLorvexCoreService/unlinkTaskCalendarEventLink(taskID:calendarEventID:)``
  /// through the same `LorvexNativeImportServicing` conformance
  /// downcast the link path uses. `deleted` reflects the core's real outcome:
  /// unlinking a pair that was never linked is an honest no-op that returns
  /// `deleted:false`, writing no `ai_changelog` row and enqueuing no tombstone.
  /// The `else` guards only an injected stub without the conformance.
  func unlinkTaskFromEvent(taskID: String, calendarEventID: String) async throws -> Value {
    let receipt = try await mcpMutations.unlinkTaskFromCalendarEventForMcp(
      taskID: taskID, calendarEventID: calendarEventID)
    return .object([
      "task_id": .string(taskID),
      "calendar_event_id": .string(receipt.calendarEventID),
      "deleted": .bool(receipt.changed),
    ])
  }

  func unlinkTaskFromProviderEvent(taskID: String, providerEventID: String) async throws -> Value {
    // `deleted` reflects the core's real outcome; unlinking a task that was never
    // linked is a no-op that returns `deleted:false`, writing no ai_changelog row.
    let removed = try await service.unlinkTaskFromProviderEvent(
      taskID: taskID, providerEventID: providerEventID)
    return .object([
      "task_id": .string(taskID),
      "provider_event_id": .string(providerEventID),
      "deleted": .bool(removed),
    ])
  }

  func getLinkedEventsForTask(
    taskID: String,
    outputOptions: CalendarEventValueOptions = .full
  ) async throws -> Value {
    let events = try await service.getLinkedEventsForTask(taskID: taskID)
    return .object([
      "task_id": .string(taskID),
      "count": .int(events.count),
      "events": .array(events.map { Self.calendarEventValue(from: $0, options: outputOptions) }),
    ])
  }

  func getLinkedTasksForEvent(eventID: String) async throws -> Value {
    let tasks = try await service.getLinkedTasksForEvent(eventID: eventID)
    return .object([
      "event_id": .string(eventID),
      "count": .int(tasks.count),
      "tasks": Self.taskValues(from: tasks),
    ])
  }
}
