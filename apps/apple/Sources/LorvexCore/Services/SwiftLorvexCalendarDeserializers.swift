import Foundation
import LorvexDomain
import LorvexStore

/// Maps the core's calendar-event shapes onto the app's `CalendarTimelineEvent`
/// model type, preserving the stable MCP/UI field shape.
///
/// Two source shapes feed this layer: post-expansion timeline occurrences
/// (`CalendarTimelineItem`) and the enriched event JSON the create/update
/// workflow orchestrators return (`JSONValue`). Both lower into the same
/// `CalendarTimelineEvent`. `recurrenceSummary` is always nil — the pure-Swift
/// core surfaces canonical events only (no EventKit provider rule summary).
enum SwiftLorvexCalendarDeserializers {

  /// Map a post-expansion timeline occurrence onto a `CalendarTimelineEvent`.
  ///
  /// Canonical occurrences carry the master event's `description` as `notes`;
  /// provider mirror occurrences expose no notes (nil).
  static func event(_ item: CalendarTimelineItem) -> CalendarTimelineEvent {
    CalendarTimelineEvent(
      id: item.id,
      eventID: item.eventId,
      seriesID: item.seriesId,
      recurrenceGeneration: item.recurrenceGeneration,
      occurrenceDate: item.recurrenceInstanceDate,
      occurrenceState: occurrenceState(item.occurrenceState),
      title: item.title,
      source: item.source.rawValue,
      editable: item.editable,
      startDate: item.startDate.asString,
      startTime: item.startTime?.asString,
      endDate: item.endDate?.asString,
      endTime: item.endTime?.asString,
      allDay: item.allDay,
      location: item.location,
      notes: item.description,
      url: item.url,
      color: item.color,
      eventType: item.eventType,
      personName: item.personName,
      attendees: attendees(fromJSONString: item.attendeesJson),
      timezone: item.timezone,
      isRecurring: item.isRecurring,
      recurrenceRule: item.recurrenceRule,
      recurrenceSummary: nil)
  }

  /// Map a stored `calendar_events` row (search / single fetch, no expansion)
  /// onto a `CalendarTimelineEvent`. Canonical events are always editable.
  static func event(_ row: CalendarEventRow) -> CalendarTimelineEvent {
    CalendarTimelineEvent(
      id: row.id,
      eventID: row.seriesId ?? row.id,
      seriesID: row.seriesId,
      recurrenceGeneration: row.recurrenceGeneration,
      occurrenceDate: row.recurrenceInstanceDate,
      occurrenceState: occurrenceState(row.occurrenceState),
      title: row.title,
      source: "canonical",
      editable: true,
      startDate: row.startDate.asString,
      startTime: row.startTime?.asString,
      endDate: row.endDate?.asString,
      endTime: row.endTime?.asString,
      allDay: row.allDay,
      location: row.location,
      notes: row.description,
      url: row.url,
      color: row.color,
      eventType: row.eventType.rawValue,
      personName: row.personName,
      attendees: attendees(fromJSONString: row.attendees),
      timezone: row.timezone,
      isRecurring: row.recurrence != nil,
      recurrenceRule: row.recurrence,
      recurrenceSummary: nil)
  }

  /// Map the enriched event JSON emitted by the create/update orchestrators
  /// (`CalendarEventLoad.loadCalendarEventJSON`) onto a `CalendarTimelineEvent`.
  ///
  /// Fails loud on a schema-contract violation instead of fabricating: a missing
  /// or mistyped required field (`id`, `title`, `start_date`) throws
  /// ``LorvexCoreError/malformedCoreData(path:reason:)``. `source`/`editable`
  /// are not stored columns — the core emits canonical events only, so they are
  /// derived constants (`canonical`, editable) rather than decoded values.
  static func event(_ value: JSONValue) throws -> CalendarTimelineEvent {
    let object = SwiftLorvexTaskDeserializers.lowerObject(value)
    let id = try SwiftLorvexTaskDeserializers.requiredString(
      object, key: "id", path: "calendar_event.id")
    let seriesID = object["series_id"] as? String
    let state = try occurrenceState(object["occurrence_state"])
    return CalendarTimelineEvent(
      id: id,
      eventID: seriesID ?? id,
      seriesID: seriesID,
      recurrenceGeneration: object["recurrence_generation"] as? String,
      occurrenceDate: object["recurrence_instance_date"] as? String,
      occurrenceState: state,
      title: try SwiftLorvexTaskDeserializers.requiredString(
        object, key: "title", path: "calendar_event.title"),
      source: object["source"] as? String ?? "canonical",
      editable: object["editable"] as? Bool ?? true,
      startDate: try SwiftLorvexTaskDeserializers.requiredString(
        object, key: "start_date", path: "calendar_event.start_date"),
      startTime: object["start_time"] as? String,
      endDate: object["end_date"] as? String,
      endTime: object["end_time"] as? String,
      allDay: object["all_day"] as? Bool ?? false,
      location: object["location"] as? String,
      notes: object["description"] as? String ?? object["notes"] as? String,
      url: object["url"] as? String,
      color: object["color"] as? String,
      eventType: object["event_type"] as? String ?? "event",
      personName: object["person_name"] as? String,
      attendees: attendees(from: object["attendees"]),
      timezone: object["timezone"] as? String,
      isRecurring: (object["recurrence"] as? String) != nil,
      recurrenceRule: object["recurrence"] as? String,
      recurrenceSummary: nil)
  }

  private static func occurrenceState(
    _ state: CalendarOccurrenceState?
  ) -> CalendarTimelineOccurrenceState? {
    state.flatMap { CalendarTimelineOccurrenceState(rawValue: $0.rawValue) }
  }

  private static func occurrenceState(_ value: Any?) throws -> CalendarTimelineOccurrenceState? {
    guard let value, !(value is NSNull) else { return nil }
    guard let raw = value as? String else {
      throw LorvexCoreError.malformedCoreData(
        path: "calendar_event.occurrence_state",
        reason: "expected a string or null, got \(SwiftLorvexTaskDeserializers.typeName(value))")
    }
    guard let state = CalendarTimelineOccurrenceState(rawValue: raw) else {
      throw LorvexCoreError.malformedCoreData(
        path: "calendar_event.occurrence_state", reason: "unknown state \"\(raw)\"")
    }
    return state
  }

  static func attendees(fromJSONString value: String?) -> [CalendarEventAttendee]? {
    guard let value, let parsed = JSONValue.parse(value) else { return nil }
    return attendees(from: SwiftLorvexTaskDeserializers.lower(parsed))
  }

  private static func attendees(from value: Any?) -> [CalendarEventAttendee]? {
    guard let rows = value as? [[String: Any]] else {
      return nil
    }
    return rows.compactMap { row in
      let email = row["email"] as? String
      let name = row["name"] as? String
      // At least one of email / name must be present; an entry with neither is
      // not a valid annotation and is dropped rather than surfaced empty.
      guard email != nil || name != nil else { return nil }
      // `status` is present only for EventKit provider attendees; native
      // Lorvex attendees leave it nil.
      return CalendarEventAttendee(
        email: email ?? "", name: name, status: row["status"] as? String)
    }
  }
}
