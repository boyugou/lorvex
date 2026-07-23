import Foundation
import LorvexCore
import MCP

/// Parse a wire recurrence value — the typed ``RecurrenceRuleSchema`` object an
/// MCP client sends — into the ``TaskRecurrenceRule`` the calendar service
/// boundary carries. Omitted (`nil`) or explicit null returns `nil` (no
/// recurrence). A present empty or otherwise undecodable object (e.g. a missing
/// `freq`) throws ``CalendarEventToolStoreError`` so an invalid rule is rejected
/// rather than silently dropped. The service still re-normalizes and re-validates
/// the serialized rule (calendar-specific caps, ANCHOR rejection, BYMONTHDAY
/// injection), so this only decodes the wire shape.
func wireCalendarRecurrenceRule(_ value: Value?) throws -> TaskRecurrenceRule? {
  guard let value else { return nil }
  if case .null = value { return nil }
  guard let object = value.objectValue else {
    throw CalendarEventToolStoreError(
      message: "recurrence must be a recurrence rule object with a freq field.")
  }
  if object.isEmpty {
    throw CalendarEventToolStoreError(
      message: "recurrence must be a non-empty recurrence rule object with a freq field.")
  }
  let payload: [String: Any]
  do {
    payload = try recurrenceRulePayload(from: object)
  } catch let error as RecurrenceRuleWireError {
    throw CalendarEventToolStoreError(message: error.message)
  }
  guard let rule = TaskRecurrenceRule.bridgeRule(from: payload) else {
    throw CalendarEventToolStoreError(
      message: "Invalid recurrence rule: freq is required (DAILY/WEEKLY/MONTHLY/YEARLY).")
  }
  return rule
}

func wireCalendarRecurrencePatch(_ value: Value?, isPresent: Bool) throws
  -> CalendarEventRecurrencePatch
{
  guard isPresent else { return .unset }
  guard let value else { return .unset }
  if case .null = value { return .clear }
  guard let rule = try wireCalendarRecurrenceRule(value) else {
    throw CalendarEventToolStoreError(
      message: "recurrence must be null or a non-empty recurrence rule object with a freq field.")
  }
  return .set(rule)
}

extension CoreBridgeClient {
  func loadCalendarTimeline(
    from: String,
    to: String,
    outputOptions: CalendarEventValueOptions = .full
  ) async throws -> Value {
    Self.calendarTimelineValue(
      from: try await service.loadCalendarTimeline(from: from, to: to),
      options: outputOptions)
  }

  func createCalendarEvent(
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
    let draft = CalendarEventCreateDraft(
      title: title,
      startDate: startDate,
      endDate: (endDate?.isEmpty ?? true) ? nil : endDate,
      startTime: (startTime?.isEmpty ?? true) ? nil : startTime,
      endTime: (endTime?.isEmpty ?? true) ? nil : endTime,
      allDay: allDay,
      location: (location?.isEmpty ?? true) ? nil : location,
      notes: (description?.isEmpty ?? true) ? nil : description,
      recurrence: recurrence,
      timezone: (timezone?.isEmpty ?? true) ? nil : timezone,
      url: (url?.isEmpty ?? true) ? nil : url,
      color: (color?.isEmpty ?? true) ? nil : color,
      eventType: (eventType?.isEmpty ?? true) ? nil : eventType,
      personName: (personName?.isEmpty ?? true) ? nil : personName,
      attendees: attendees)
    return Self.calendarEventValue(
      from: try await createCalendarEventModel(draft: draft, originalID: originalID))
  }

  /// ``createCalendarEventModel(draft:originalID:)`` mapped to the MCP event
  /// `Value` shape — the per-item entry `batch_create_calendar_events` calls
  /// while assembling its `{results, count, skipped}` envelope.
  func createCalendarEventModelValue(
    draft: CalendarEventCreateDraft, originalID: String?
  ) async throws -> Value {
    Self.calendarEventValue(
      from: try await createCalendarEventModel(draft: draft, originalID: originalID))
  }

  /// Create one canonical calendar event from a draft, shared by
  /// `create_calendar_event` and each row of `batch_create_calendar_events`.
  /// With an `original_id` the event is restored id-preserving through the
  /// native importer's atomic skip-if-present/tombstoned transaction so exported
  /// task↔event links resolve to the same event; otherwise a fresh id is minted.
  /// The typed recurrence is serialized to canonical JSON only on the import
  /// path (the ordinary create takes the typed rule directly).
  func createCalendarEventModel(
    draft: CalendarEventCreateDraft, originalID: String?
  ) async throws -> CalendarTimelineEvent {
    if let originalID { try Self.validateImportOriginalID(originalID, kind: .calendarEvent) }
    let outcomes = try await mcpMutations.batchCreateCalendarEventsForMcp([
      McpCalendarEventCreateSpec(
        reference: originalID ?? draft.title, draft: draft, originalID: originalID)
    ])
    guard let outcome = outcomes.first else {
      throw LorvexCoreError.unsupportedOperation(
        "Calendar-event creation returned no transactional outcome.")
    }
    switch outcome {
    case .created(let event): return event
    case .failed(_, let error): throw error
    }
  }
}
