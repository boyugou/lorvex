import Foundation
import LorvexStore

/// A calendar event's recurrence rule in an export, projected as a structured
/// object rather than the raw canonical JSON string stored in
/// `calendar_events.recurrence`.
///
/// Shares the camelCase field vocabulary of the task recurrence rule
/// (`ExportRecurrenceRule`) — `freq`, `interval`, `byDay`, `byMonth`,
/// `byMonthDay`, `bySetPos`, `wkst`, `until`, `count` — with values in the
/// canonical RFC-5545-aligned tokens (uppercase `freq`, `MO`…`SU` weekday codes).
/// It deliberately omits `anchor`: the completion anchor is a task-only concept
/// (the calendar recurrence normalizer rejects `ANCHOR`), so a calendar rule can
/// never carry it. See `spec/RECURRENCE.md` and `spec/EXPORT_FORMAT.md`.
///
/// ``init(canonicalJSON:)`` parses the stored uppercase-keyed canonical string
/// into this structure; ``canonicalRecurrenceJSON()`` renders it back to that
/// string for the importer, which re-normalizes it, so an exported rule
/// round-trips to the same stored canonical recurrence.
public struct ExportCalendarRecurrenceRule: Codable, Equatable, Sendable {
  public var freq: String
  public var interval: Int?
  public var byDay: [String]?
  public var byMonth: [Int]?
  public var byMonthDay: [Int]?
  public var bySetPos: [Int]?
  public var wkst: String?
  public var until: String?
  public var count: Int?

  public init(
    freq: String,
    interval: Int? = nil,
    byDay: [String]? = nil,
    byMonth: [Int]? = nil,
    byMonthDay: [Int]? = nil,
    bySetPos: [Int]? = nil,
    wkst: String? = nil,
    until: String? = nil,
    count: Int? = nil
  ) {
    self.freq = freq
    self.interval = interval
    self.byDay = byDay
    self.byMonth = byMonth
    self.byMonthDay = byMonthDay
    self.bySetPos = bySetPos
    self.wkst = wkst
    self.until = until
    self.count = count
  }

  /// Parse the canonical recurrence JSON stored in `calendar_events.recurrence`
  /// (uppercase RFC-5545-aligned keys, e.g. `{"BYDAY":["MO"],"FREQ":"WEEKLY","INTERVAL":1}`)
  /// into the structured form. Returns `nil` for input that is not a JSON object
  /// carrying a string `FREQ`, so a malformed or empty rule omits the field
  /// rather than exporting a partial object.
  public init?(canonicalJSON: String) {
    guard let data = canonicalJSON.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let freqValue = object["FREQ"] as? String
    else { return nil }
    freq = freqValue
    interval = Self.int(object["INTERVAL"])
    byDay = Self.stringArray(object["BYDAY"])
    byMonth = Self.intArray(object["BYMONTH"])
    byMonthDay = Self.intArray(object["BYMONTHDAY"])
    bySetPos = Self.intArray(object["BYSETPOS"])
    wkst = object["WKST"] as? String
    until = object["UNTIL"] as? String
    count = Self.int(object["COUNT"])
  }

  /// Render back to the uppercase-keyed canonical JSON string the calendar
  /// recurrence normalizer reads on import. Keys are byte-sorted; the normalizer
  /// re-canonicalizes and re-validates, so key order here is not significant.
  /// Returns `nil` only if the rule somehow fails JSON serialization.
  public func canonicalRecurrenceJSON() -> String? {
    var object: [String: Any] = ["FREQ": freq]
    if let interval { object["INTERVAL"] = interval }
    if let byDay, !byDay.isEmpty { object["BYDAY"] = byDay }
    if let byMonth, !byMonth.isEmpty { object["BYMONTH"] = byMonth }
    if let byMonthDay, !byMonthDay.isEmpty { object["BYMONTHDAY"] = byMonthDay }
    if let bySetPos, !bySetPos.isEmpty { object["BYSETPOS"] = bySetPos }
    if let wkst { object["WKST"] = wkst }
    if let until { object["UNTIL"] = until }
    if let count { object["COUNT"] = count }
    guard JSONSerialization.isValidJSONObject(object),
      let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      let string = String(data: data, encoding: .utf8)
    else { return nil }
    return string
  }

  private static func int(_ value: Any?) -> Int? {
    (value as? NSNumber)?.intValue
  }

  private static func intArray(_ value: Any?) -> [Int]? {
    guard let array = value as? [Any] else { return nil }
    let ints = array.compactMap { ($0 as? NSNumber)?.intValue }
    return ints.isEmpty ? nil : ints
  }

  private static func stringArray(_ value: Any?) -> [String]? {
    guard let array = value as? [String], !array.isEmpty else { return nil }
    return array
  }
}

/// Flat DTO for a calendar event row in an export.
public struct ExportCalendarEvent: Codable, Sendable {
  public var id: String
  public var title: String
  public var startDate: String
  public var startTime: String
  public var endDate: String
  public var endTime: String
  public var allDay: Bool
  /// Event location. Omitted from the export when empty.
  public var location: String?
  public var notes: String?
  public var url: String?
  public var color: String?
  public var eventType: String
  public var personName: String?
  public var attendees: [CalendarEventAttendee]?
  public var timezone: String?
  /// Structured recurrence rule (`ExportCalendarRecurrenceRule`). Omitted when the
  /// event does not recur.
  public var recurrence: ExportCalendarRecurrenceRule?
  public var seriesId: String?
  public var recurrenceInstanceDate: String?
  /// One deterministic occurrence-register value. Base events leave this nil.
  public var occurrenceState: String?
  /// Recurring-master generation, or the generation a decision belongs to.
  public var recurrenceGeneration: String?
  /// Deterministic durable-boundary id for a base tail segment. Roots and
  /// occurrence decisions omit it.
  public var seriesCutoverId: String?

  public init(
    id: String,
    title: String,
    startDate: String,
    startTime: String,
    endDate: String,
    endTime: String,
    allDay: Bool,
    location: String? = nil,
    notes: String? = nil,
    url: String? = nil,
    color: String? = nil,
    eventType: String = "event",
    personName: String? = nil,
    attendees: [CalendarEventAttendee]? = nil,
    timezone: String? = nil,
    recurrence: ExportCalendarRecurrenceRule? = nil,
    seriesId: String? = nil,
    recurrenceInstanceDate: String? = nil,
    occurrenceState: String? = nil,
    recurrenceGeneration: String? = nil,
    seriesCutoverId: String? = nil
  ) {
    self.id = id
    self.title = title
    self.startDate = startDate
    self.startTime = startTime
    self.endDate = endDate
    self.endTime = endTime
    self.allDay = allDay
    self.location = location
    self.notes = notes
    self.url = url
    self.color = color
    self.eventType = eventType
    self.personName = personName
    self.attendees = attendees
    self.timezone = timezone
    self.recurrence = recurrence
    self.seriesId = seriesId
    self.recurrenceInstanceDate = recurrenceInstanceDate
    self.occurrenceState = occurrenceState
    self.recurrenceGeneration = recurrenceGeneration
    self.seriesCutoverId = seriesCutoverId
  }

  public init(from event: CalendarTimelineEvent) {
    id = event.id
    title = event.title
    startDate = event.startDate
    startTime = event.startTime ?? ""
    endDate = event.endDate ?? ""
    endTime = event.endTime ?? ""
    allDay = event.allDay
    location = event.location.flatMap { $0.isEmpty ? nil : $0 }
    notes = event.notes
    url = event.url
    color = event.color
    eventType = event.eventType
    personName = event.personName
    attendees = event.attendees
    timezone = event.timezone
    recurrence = event.recurrenceRule.flatMap(ExportCalendarRecurrenceRule.init(canonicalJSON:))
    seriesId = nil
    recurrenceInstanceDate = nil
    occurrenceState = nil
    recurrenceGeneration = event.recurrenceGeneration
    seriesCutoverId = nil
  }

  public init(from row: CalendarEventRow, attendees: [CalendarEventAttendee]?) {
    id = row.id
    title = row.title
    startDate = row.startDate.asString
    startTime = row.startTime?.asString ?? ""
    endDate = row.endDate?.asString ?? ""
    endTime = row.endTime?.asString ?? ""
    allDay = row.allDay
    location = row.location.flatMap { $0.isEmpty ? nil : $0 }
    notes = row.description
    url = row.url
    color = row.color
    eventType = row.eventType.rawValue
    personName = row.personName
    self.attendees = attendees?.isEmpty == true ? nil : attendees
    timezone = row.timezone
    recurrence = row.recurrence.flatMap(ExportCalendarRecurrenceRule.init(canonicalJSON:))
    seriesId = row.seriesId
    recurrenceInstanceDate = row.recurrenceInstanceDate
    occurrenceState = row.occurrenceState?.rawValue
    recurrenceGeneration = row.recurrenceGeneration
    seriesCutoverId = row.seriesCutoverId
  }

  enum CodingKeys: String, CodingKey {
    case id, title, startDate, startTime, endDate, endTime, allDay, location
    case notes, url, color, eventType, personName, attendees, timezone
    case recurrence, seriesId, recurrenceInstanceDate, occurrenceState
    case recurrenceGeneration, seriesCutoverId
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    startDate = try container.decode(String.self, forKey: .startDate)
    startTime = try container.decode(String.self, forKey: .startTime)
    endDate = try container.decode(String.self, forKey: .endDate)
    endTime = try container.decode(String.self, forKey: .endTime)
    allDay = try container.decode(Bool.self, forKey: .allDay)
    location = try container.decodeIfPresent(String.self, forKey: .location)
    notes = try container.decodeIfPresent(String.self, forKey: .notes)
    url = try container.decodeIfPresent(String.self, forKey: .url)
    color = try container.decodeIfPresent(String.self, forKey: .color)
    eventType = try container.decode(String.self, forKey: .eventType)
    personName = try container.decodeIfPresent(String.self, forKey: .personName)
    attendees = try container.decodeIfPresent([CalendarEventAttendee].self, forKey: .attendees)
    timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
    recurrence = try container.decodeIfPresent(ExportCalendarRecurrenceRule.self, forKey: .recurrence)
    seriesId = try container.decodeIfPresent(String.self, forKey: .seriesId)
    recurrenceInstanceDate = try container.decodeIfPresent(
      String.self, forKey: .recurrenceInstanceDate)
    occurrenceState = try container.decodeIfPresent(String.self, forKey: .occurrenceState)
    recurrenceGeneration = try container.decodeIfPresent(
      String.self, forKey: .recurrenceGeneration)
    seriesCutoverId = try container.decodeIfPresent(String.self, forKey: .seriesCutoverId)
  }

  static let columns = [
    "id", "title", "startDate", "startTime", "endDate", "endTime", "allDay", "location",
    "notes", "url", "color", "eventType", "personName", "attendees", "timezone", "recurrence",
    "seriesId", "recurrenceInstanceDate", "occurrenceState",
    "recurrenceGeneration", "seriesCutoverId",
  ]

  var csvRow: [String] {
    [
      id, title, startDate, startTime, endDate, endTime, allDay ? "true" : "false", location ?? "",
      notes ?? "", url ?? "", color ?? "", eventType, personName ?? "", Self.encode(attendees),
      timezone ?? "", recurrence?.canonicalRecurrenceJSON() ?? "",
      seriesId ?? "", recurrenceInstanceDate ?? "", occurrenceState ?? "",
      recurrenceGeneration ?? "", seriesCutoverId ?? "",
    ]
  }

  private static func encode(_ attendees: [CalendarEventAttendee]?) -> String {
    guard let attendees, !attendees.isEmpty,
      let data = try? JSONEncoder().encode(attendees),
      let string = String(data: data, encoding: .utf8)
    else { return "" }
    return string
  }

}
