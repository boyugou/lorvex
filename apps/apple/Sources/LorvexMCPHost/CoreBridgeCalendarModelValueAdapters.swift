import Foundation
import LorvexCore
import MCP

struct CalendarEventValueOptions: Sendable, Equatable {
  enum Shape: String, Sendable {
    case compact
    case full
  }

  var shape: Shape
  var includeNulls: Bool
  var fields: Set<String>?
  var include: Set<String>

  static let full = CalendarEventValueOptions(shape: .full, includeNulls: true)
  static let compact = CalendarEventValueOptions(shape: .compact, includeNulls: false)

  static func from(arguments: [String: Value], defaultShape: Shape = .compact) throws
    -> CalendarEventValueOptions
  {
    let shape = Shape(
      rawValue: try StrictScalarArguments.string(
        arguments["shape"], field: "shape", default: defaultShape.rawValue))
      ?? defaultShape
    let requestedFields = try StrictArgumentArray.optionalStrings(
      arguments["fields"], field: "fields")
    let fields = requestedFields.map { Set($0.map(Self.normalizedKey)) }
    let include = Set(
      (try StrictArgumentArray.optionalStrings(arguments["include"], field: "include") ?? [])
        .map(Self.normalizedKey))
    return CalendarEventValueOptions(
      shape: shape,
      includeNulls: try StrictScalarArguments.bool(
        arguments["include_nulls"], field: "include_nulls", default: shape == .full),
      fields: fields,
      include: include)
  }

  init(
    shape: Shape = .compact,
    includeNulls: Bool = false,
    fields: Set<String>? = nil,
    include: Set<String> = []
  ) {
    self.shape = shape
    self.includeNulls = includeNulls
    self.fields = fields
    self.include = include
  }

  func filtered(_ fields: [String: Value]) -> [String: Value] {
    var out: [String: Value] = [:]
    for key in fields.keys.sorted() {
      guard wants(key), let value = fields[key], !shouldDrop(value, key: key) else { continue }
      out[key] = value
    }
    return out
  }

  private func wants(_ key: String) -> Bool {
    if let requested = fields {
      return key == "id" || requested.contains(key)
    }
    if shape == .full { return true }
    return Self.compactDefaultFields.contains(key)
      || include.contains(Self.group(for: key))
      || include.contains(key)
  }

  private func shouldDrop(_ value: Value, key: String) -> Bool {
    switch value {
    case .null:
      if fields?.contains(key) == true { return false }
      return !includeNulls
    case .array(let values):
      if shape == .full { return false }
      return values.isEmpty
        && !(fields?.contains(key) == true || include.contains(Self.group(for: key)))
    default:
      return false
    }
  }

  private static let compactDefaultFields: Set<String> = [
    "id", "event_id", "title", "source", "editable", "start_date", "start_time", "end_date",
    "end_time", "all_day", "location", "color", "event_type", "person_name", "timezone",
    "is_recurring", "series_id", "recurrence_generation", "occurrence_date", "occurrence_state",
  ]

  private static func group(for key: String) -> String {
    switch key {
    case "notes", "url": return "details"
    case "attendees": return "attendees"
    case "recurrence", "is_recurring": return "recurrence"
    case "start_date", "start_time", "end_date", "end_time", "all_day", "timezone":
      return "time"
    case "location", "color", "event_type", "person_name": return "metadata"
    default: return key
    }
  }

  private static func normalizedKey(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  /// User-selectable event field keys, published as the frozen `fields` schema
  /// enum. Recurrence-address metadata is emitted automatically rather than
  /// added here, so introducing it does not mutate the MCP input contract.
  static let fieldNames: [String] = [
    "id", "title", "source", "editable", "start_date", "start_time", "end_date",
    "end_time", "all_day", "location", "notes", "url", "color", "event_type",
    "person_name", "attendees", "timezone", "is_recurring", "recurrence",
  ]

  /// Every valid `include` value: the field-group names plus the individual field
  /// names, both of which `wants(_:)` honors. Derived from `fieldNames` and
  /// `group(for:)` so it can't drift from the projection logic. Published as the
  /// `include` schema enum.
  static let includeValues: [String] = {
    var values = Set(fieldNames)
    for name in fieldNames { values.insert(group(for: name)) }
    return values.sorted()
  }()
}

/// Maps the `LorvexCore` calendar model types onto the MCP `Value` JSON shapes
/// the calendar tool handlers return. Field names and shapes define the frozen
/// prelaunch wire contract while the implementation stays pure Swift.
extension CoreBridgeClient {
  static func calendarEventValue(
    from event: CalendarTimelineEvent,
    options: CalendarEventValueOptions = .full
  ) -> Value {
    var fields: [String: Value] = [
      // `id` identifies this rendered row. Recurring occurrences therefore stay
      // unique in one timeline; `event_id` below is the mutation/link address.
      "id": .string(event.id),
      "title": .string(event.title),
      "source": .string(event.source),
      "editable": .bool(event.editable),
      "start_date": .string(event.startDate),
      "start_time": event.startTime.map(Value.string) ?? .null,
      "end_date": event.endDate.map(Value.string) ?? .null,
      "end_time": event.endTime.map(Value.string) ?? .null,
      "all_day": .bool(event.allDay),
      "location": event.location.map(Value.string) ?? .null,
      "notes": event.notes.map(Value.string) ?? .null,
      "url": event.url.map(Value.string) ?? .null,
      "color": event.color.map(Value.string) ?? .null,
      "event_type": .string(event.eventType),
      "person_name": event.personName.map(Value.string) ?? .null,
      "attendees": event.attendees.map { .array($0.map(calendarAttendeeValue(from:))) } ?? .null,
      "timezone": event.timezone.map(Value.string) ?? .null,
      "is_recurring": .bool(event.isRecurring),
      "recurrence": recurrencePayloadValue(
        TaskRecurrenceRule.bridgeRule(from: event.recurrenceRule)),
    ]
    // Every row exposes the actionable event address, including one-off events
    // where it intentionally equals `id`. A caller never has to infer whether
    // the row came from recurrence expansion before invoking a write tool.
    fields["event_id"] = .string(event.eventID)
    if event.supportsScopedMutation {
      fields["series_id"] = event.seriesID.map(Value.string) ?? .null
      fields["recurrence_generation"] = event.recurrenceGeneration.map(Value.string) ?? .null
      fields["occurrence_date"] = event.occurrenceDate.map(Value.string) ?? .null
      fields["occurrence_state"] = event.occurrenceState.map { .string($0.rawValue) } ?? .null
    }
    var projected = options.filtered(fields)
    // Every row stays safely addressable even under an explicit narrow
    // projection. `id` is the rendered-row identity; `event_id` is the stable
    // source identity accepted by the appropriate canonical or provider-link
    // tool.
    projected["event_id"] = fields["event_id"]
    if event.supportsScopedMutation {
      for key in [
        "series_id", "recurrence_generation", "occurrence_date", "occurrence_state",
      ] {
        projected[key] = fields[key]
      }
    }
    return .object(projected)
  }

  static func calendarAttendeeValue(from attendee: CalendarEventAttendee) -> Value {
    // `status` is non-nil only for EventKit provider attendees; native Lorvex
    // attendees carry no RSVP state and surface `status: null`.
    .object([
      "email": .string(attendee.email),
      "name": attendee.name.map(Value.string) ?? .null,
      "status": attendee.status.map(Value.string) ?? .null,
    ])
  }

  static func calendarTimelineValue(
    from snapshot: CalendarTimelineSnapshot,
    options: CalendarEventValueOptions = .full
  ) -> Value {
    // `from`/`to`/`events`/`truncated` are the domain payload; the canonical
    // pagination envelope is layered on by `pageCalendarTimelineValue`, which
    // re-pages these events, so no count/offset fields are emitted here.
    .object([
      "from": .string(snapshot.from),
      "to": .string(snapshot.to),
      "events": .array(snapshot.events.map { calendarEventValue(from: $0, options: options) }),
      "truncated": .bool(snapshot.truncated),
    ])
  }
}
