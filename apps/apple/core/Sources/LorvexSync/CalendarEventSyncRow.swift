import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Validated storage shape used by the calendar sync applier.
///
/// Base events are a product of two independent registers: ordinary content is
/// ordered by `content_version`, while recurrence topology is ordered by
/// `recurrence_topology_version`. The row `version` is only the transport / delete
/// high-water mark. Occurrence decisions are not decomposed; their deterministic
/// identity makes an ordinary whole-row LWW register sufficient.
struct CalendarEventSyncRow: Equatable {
  var id: String
  var title: String
  var description: String?
  var startDate: String
  var startTime: String?
  var endDate: String?
  var endTime: String?
  var allDay: Int64
  var location: String?
  var url: String?
  var color: String?
  var recurrence: String?
  var timezone: String?
  var eventType: String
  var personName: String?
  var seriesCutoverId: String?
  var seriesId: String?
  var recurrenceInstanceDate: String?
  var occurrenceState: String?
  var recurrenceGeneration: String?
  var contentVersion: String?
  var recurrenceTopologyVersion: String?
  var createdAt: String
  var updatedAt: String
  var attendees: String?
  var version: String

  var isBase: Bool { seriesId == nil }

  static func load(_ db: Database, id: String) throws -> CalendarEventSyncRow? {
    guard
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT id, title, description, start_date, start_time, end_date, end_time,
                 all_day, location, url, color, recurrence, timezone, event_type,
                 person_name, series_cutover_id, series_id, recurrence_instance_date, occurrence_state,
                 recurrence_generation, content_version, recurrence_topology_version, created_at,
                 updated_at, attendees, version
            FROM calendar_events WHERE id = ?
          """,
        arguments: [id])
    else { return nil }
    return CalendarEventSyncRow(
      id: row["id"], title: row["title"], description: row["description"],
      startDate: row["start_date"], startTime: row["start_time"], endDate: row["end_date"],
      endTime: row["end_time"], allDay: row["all_day"], location: row["location"],
      url: row["url"], color: row["color"], recurrence: row["recurrence"],
      timezone: row["timezone"], eventType: row["event_type"], personName: row["person_name"],
      seriesCutoverId: row["series_cutover_id"],
      seriesId: row["series_id"], recurrenceInstanceDate: row["recurrence_instance_date"],
      occurrenceState: row["occurrence_state"], recurrenceGeneration: row["recurrence_generation"],
      contentVersion: row["content_version"],
      recurrenceTopologyVersion: row["recurrence_topology_version"],
      createdAt: row["created_at"], updatedAt: row["updated_at"], attendees: row["attendees"],
      version: row["version"])
  }

  /// Join two snapshots of the same base-event identity. Each register chooses
  /// its greater HLC; an impossible equal-HLC/different-bytes collision chooses
  /// the lexicographically greater canonical group, making arrival order inert.
  static func mergedBase(
    local: CalendarEventSyncRow, incoming: CalendarEventSyncRow
  ) throws -> CalendarEventSyncRow {
    guard local.id == incoming.id, local.isBase, incoming.isBase else {
      throw ApplyError.invalidPayload(
        "calendar_event grouped merge requires two base rows with the same id")
    }
    if incoming.seriesCutoverId != local.seriesCutoverId {
      throw ApplyError.invalidPayload(
        "calendar_event \(local.id) cannot change immutable series_cutover_id")
    }

    guard let localContentVersion = local.contentVersion,
      let incomingContentVersion = incoming.contentVersion
    else {
      throw ApplyError.invalidPayload(
        "calendar_event base grouped merge requires content_version")
    }

    var merged = local
    if try incomingWins(
      localVersion: localContentVersion, incomingVersion: incomingContentVersion,
      localBytes: local.contentBytes(), incomingBytes: incoming.contentBytes())
    {
      merged.copyContent(from: incoming)
    }
    guard let localTopologyVersion = local.recurrenceTopologyVersion,
      let incomingTopologyVersion = incoming.recurrenceTopologyVersion
    else {
      throw ApplyError.invalidPayload(
        "calendar_event base grouped merge requires recurrence_topology_version")
    }
    if try incomingWins(
      localVersion: localTopologyVersion, incomingVersion: incomingTopologyVersion,
      localBytes: local.topologyBytes(), incomingBytes: incoming.topologyBytes())
    {
      merged.copyTopology(from: incoming)
    }

    // Creation time is immutable product history, so a malformed equal-identity
    // collision keeps the earliest canonical timestamp deterministically. Update
    // time describes the whole-row mutation and therefore follows the row-version
    // winner rather than either independent field group.
    merged.createdAt = min(local.createdAt, incoming.createdAt)
    if try incomingWins(
      localVersion: local.version, incomingVersion: incoming.version,
      localBytes: Array(local.updatedAt.utf8), incomingBytes: Array(incoming.updatedAt.utf8))
    {
      merged.updatedAt = incoming.updatedAt
    } else {
      merged.updatedAt = local.updatedAt
    }
    merged.version = try maxCanonicalHlc(local.version, incoming.version)
    return merged
  }

  /// Whether a stale whole-row envelope still carries either independent
  /// register value that the local base row has not joined yet.
  static func staleIncomingRegisterWins(
    local: CalendarEventSyncRow, incoming: CalendarEventSyncRow
  ) throws -> Bool {
    guard local.id == incoming.id, local.isBase, incoming.isBase,
      let localContentVersion = local.contentVersion,
      let incomingContentVersion = incoming.contentVersion,
      let localTopologyVersion = local.recurrenceTopologyVersion,
      let incomingTopologyVersion = incoming.recurrenceTopologyVersion
    else { return false }
    if try incomingWins(
      localVersion: localContentVersion, incomingVersion: incomingContentVersion,
      localBytes: local.contentBytes(), incomingBytes: incoming.contentBytes())
    {
      return true
    }
    return try incomingWins(
      localVersion: localTopologyVersion, incomingVersion: incomingTopologyVersion,
      localBytes: local.topologyBytes(), incomingBytes: incoming.topologyBytes())
  }

  func writeReplacingSnapshot(_ db: Database) throws {
    try db.execute(
      sql: """
        INSERT INTO calendar_events
          (id, title, description, start_date, start_time, end_date, end_time, all_day,
           location, url, color, recurrence, timezone, event_type, person_name, series_cutover_id, series_id,
           recurrence_instance_date, occurrence_state, recurrence_generation,
           content_version, recurrence_topology_version, created_at, updated_at, attendees, version)
        VALUES
          (:id, :title, :description, :start_date, :start_time, :end_date, :end_time, :all_day,
           :location, :url, :color, :recurrence, :timezone, :event_type, :person_name, :series_cutover_id, :series_id,
           :recurrence_instance_date, :occurrence_state, :recurrence_generation,
           :content_version, :recurrence_topology_version, :created_at, :updated_at, :attendees,
           :version)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title, description = excluded.description,
          start_date = excluded.start_date, start_time = excluded.start_time,
          end_date = excluded.end_date, end_time = excluded.end_time,
          all_day = excluded.all_day, location = excluded.location, url = excluded.url,
          color = excluded.color, recurrence = excluded.recurrence,
          timezone = excluded.timezone, event_type = excluded.event_type,
          person_name = excluded.person_name, series_cutover_id = excluded.series_cutover_id,
          series_id = excluded.series_id,
          recurrence_instance_date = excluded.recurrence_instance_date,
          occurrence_state = excluded.occurrence_state,
          recurrence_generation = excluded.recurrence_generation,
          content_version = excluded.content_version,
          recurrence_topology_version = excluded.recurrence_topology_version,
          created_at = excluded.created_at, updated_at = excluded.updated_at,
          attendees = excluded.attendees, version = excluded.version
        """,
      arguments: bindings)
  }

  func writeWholeRowLww(_ db: Database, tieBreak: LwwTieBreak) throws {
    let sql = LwwUpsertSpec(
      table: "calendar_events",
      columns: SyncEntityDescriptor.require(.calendarEvent).plainColumns,
      conflict: ["id"], tieBreak: tieBreak
    ).buildSQL()
    try db.execute(sql: sql, arguments: bindings)
  }

  private var bindings: StatementArguments {
    [
      "id": id, "title": title, "description": description, "start_date": startDate,
      "start_time": startTime, "end_date": endDate, "end_time": endTime, "all_day": allDay,
      "location": location, "url": url, "color": color, "recurrence": recurrence,
      "timezone": timezone, "event_type": eventType, "person_name": personName,
      "series_cutover_id": seriesCutoverId,
      "series_id": seriesId, "recurrence_instance_date": recurrenceInstanceDate,
      "occurrence_state": occurrenceState, "recurrence_generation": recurrenceGeneration,
      "content_version": contentVersion,
      "recurrence_topology_version": recurrenceTopologyVersion, "created_at": createdAt,
      "updated_at": updatedAt, "attendees": attendees, "version": version,
    ]
  }

  private mutating func copyContent(from other: CalendarEventSyncRow) {
    title = other.title
    description = other.description
    location = other.location
    url = other.url
    color = other.color
    eventType = other.eventType
    personName = other.personName
    attendees = other.attendees
    contentVersion = other.contentVersion
  }

  private mutating func copyTopology(from other: CalendarEventSyncRow) {
    startDate = other.startDate
    startTime = other.startTime
    endDate = other.endDate
    endTime = other.endTime
    allDay = other.allDay
    timezone = other.timezone
    recurrence = other.recurrence
    recurrenceGeneration = other.recurrenceGeneration
    recurrenceTopologyVersion = other.recurrenceTopologyVersion
  }

  private func contentBytes() throws -> [UInt8] {
    try canonicalBytes([
      "attendees": attendees.flatMap(JSONValue.parse) ?? .null,
      "color": nullable(color),
      "description": nullable(description), "event_type": .string(eventType),
      "location": nullable(location), "person_name": nullable(personName),
      "title": .string(title), "url": nullable(url),
    ])
  }

  private func topologyBytes() throws -> [UInt8] {
    try canonicalBytes([
      "all_day": .bool(allDay != 0), "end_date": nullable(endDate),
      "end_time": nullable(endTime), "recurrence": nullable(recurrence),
      "recurrence_generation": nullable(recurrenceGeneration),
      "recurrence_topology_version": nullable(recurrenceTopologyVersion),
      "start_date": .string(startDate), "start_time": nullable(startTime),
      "timezone": nullable(timezone),
    ])
  }

  private func nullable(_ value: String?) -> JSONValue {
    value.map(JSONValue.string) ?? .null
  }

  private func canonicalBytes(_ object: [String: JSONValue]) throws -> [UInt8] {
    do {
      return Array(try SyncCanonicalize.canonicalizeJSON(.object(object)).utf8)
    } catch {
      throw ApplyError.invalidPayload("calendar_event group canonicalization failed: \(error)")
    }
  }

  private static func incomingWins(
    localVersion: String, incomingVersion: String,
    localBytes: @autoclosure () throws -> [UInt8],
    incomingBytes: @autoclosure () throws -> [UInt8]
  ) throws -> Bool {
    let local = try Hlc.parseCanonical(localVersion)
    let incoming = try Hlc.parseCanonical(incomingVersion)
    if incoming != local { return incoming > local }
    return try localBytes().lexicographicallyPrecedes(incomingBytes())
  }

  private static func maxCanonicalHlc(_ lhs: String, _ rhs: String) throws -> String {
    let left = try Hlc.parseCanonical(lhs)
    let right = try Hlc.parseCanonical(rhs)
    return max(left, right).description
  }
}
