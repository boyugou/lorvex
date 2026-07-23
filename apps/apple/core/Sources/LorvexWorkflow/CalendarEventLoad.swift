import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Calendar-event row reader.
///
/// Loads a single `calendar_events` row into the JSON object every surface
/// re-exports as the post-mutation `after` snapshot, including the `attendees`
/// column parsed back into a JSON array.
///
/// Serialization note: `JSONValue.object` is an unordered `[String: JSONValue]`,
/// so deterministic string output requires running the assembled value through
/// ``canonicalizeJSON`` (sorted keys, alphabetical UTF-8 byte order) at the
/// surface adapter. The wire-level key set and value shapes are fixed here.
public enum CalendarEventLoad {

  /// Load a calendar event row as a ``JSONValue``. Returns `nil` when the row
  /// is missing.
  public static func loadCalendarEventJSON(
    _ db: Database, eventId: String
  ) throws -> JSONValue? {
    guard let row = try CalendarTimelineQueries.getStoredCalendarEvent(db, id: eventId)
    else { return nil }
    return .object(encodeCalendarEventRow(row))
  }

  // MARK: - Row → JSON

  /// Encode a ``CalendarEventRow`` into the key/value object that becomes the
  /// canonical calendar-event JSON after canonicalization (alphabetical UTF-8
  /// byte sort). Keys mirror the stored columns (with `attendees` and
  /// `recurrence_exceptions` parsed back into JSON arrays) and the flattened
  /// `timing` fields.
  static func encodeCalendarEventRow(_ row: CalendarEventRow) -> [String: JSONValue] {
    var obj: [String: JSONValue] = [:]
    obj["id"] = .string(row.id)
    obj["title"] = .string(row.title)
    obj["description"] = stringOrNull(row.description)
    obj["recurrence"] = stringOrNull(row.recurrence)
    // `recurrence_exceptions` is stored as a JSON array string (or NULL);
    // emit the parsed JSON so the wire shape is an actual array, not a
    // quoted string. Matches the task-response shape.
    if let raw = row.recurrenceExceptions {
      obj["recurrence_exceptions"] = JSONValue.parse(raw) ?? .string(raw)
    } else {
      obj["recurrence_exceptions"] = .null
    }
    obj["timezone"] = stringOrNull(row.timezone)
    obj["start_date"] = .string(row.startDate.asString)
    obj["start_time"] = stringOrNull(row.startTime?.asString)
    obj["end_date"] = stringOrNull(row.endDate?.asString)
    obj["end_time"] = stringOrNull(row.endTime?.asString)
    obj["all_day"] = .bool(row.allDay)
    obj["location"] = stringOrNull(row.location)
    obj["color"] = stringOrNull(row.color)
    obj["event_type"] = .string(row.eventType.rawValue)
    obj["person_name"] = stringOrNull(row.personName)
    obj["url"] = stringOrNull(row.url)
    obj["series_cutover_id"] = stringOrNull(row.seriesCutoverId)
    obj["series_id"] = stringOrNull(row.seriesId)
    obj["recurrence_instance_date"] = stringOrNull(row.recurrenceInstanceDate)
    obj["occurrence_state"] = stringOrNull(row.occurrenceState?.rawValue)
    obj["recurrence_generation"] = stringOrNull(row.recurrenceGeneration)
    obj["recurrence_topology_version"] = stringOrNull(row.recurrenceTopologyVersion)
    obj["content_version"] = stringOrNull(row.contentVersion)
    // `attendees` is stored as a JSON array string (or NULL); emit the parsed
    // JSON so the wire shape is an actual array, not a quoted string.
    if let raw = row.attendees {
      obj["attendees"] = JSONValue.parse(raw) ?? .null
    } else {
      obj["attendees"] = .null
    }
    obj["created_at"] = .string(row.createdAt)
    obj["updated_at"] = .string(row.updatedAt)
    obj["version"] = .string(row.version)
    return obj
  }
}

@inline(__always)
private func stringOrNull(_ s: String?) -> JSONValue {
  s.map { .string($0) } ?? .null
}
