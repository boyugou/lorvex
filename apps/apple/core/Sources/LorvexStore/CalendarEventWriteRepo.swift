import Foundation
import GRDB
import LorvexDomain

/// Inputs for ``CalendarEventWriteRepo/createCalendarEvent(_:params:)``.
public struct CalendarEventCreateParams: Sendable {
  public let id: String
  public let title: String
  public let description: String?
  public let recurrence: String?
  public let timezone: String?
  public let startDate: String
  public let startTime: String?
  public let endDate: String?
  public let endTime: String?
  public let allDay: Bool
  public let location: String?
  public let url: String?
  public let color: String?
  public let eventType: String
  public let personName: String?
  /// Canonical JSON for the `attendees` column (a JSON array of `{name?, email?}`
  /// objects), or nil for none. The workflow validates + serializes before this.
  public let attendees: String?
  /// Immutable deterministic boundary identity for a recurring tail segment.
  public let seriesCutoverId: String?
  /// Decision linkage to a recurring series master. Both nil for a base event.
  public let seriesId: String?
  public let recurrenceInstanceDate: String?
  public let occurrenceState: CalendarOccurrenceState?
  public let recurrenceGeneration: String?
  public let recurrenceTopologyVersion: String?
  public let contentVersion: String?
  public let version: String
  public let now: String

  public init(
    id: String, title: String,
    description: String? = nil, recurrence: String? = nil,
    timezone: String? = nil,
    startDate: String, startTime: String? = nil,
    endDate: String? = nil, endTime: String? = nil,
    allDay: Bool, location: String? = nil, url: String? = nil,
    color: String? = nil, eventType: String, personName: String? = nil,
    attendees: String? = nil,
    seriesCutoverId: String? = nil,
    seriesId: String?, recurrenceInstanceDate: String?,
    occurrenceState: CalendarOccurrenceState?,
    recurrenceGeneration: String?, recurrenceTopologyVersion: String?,
    contentVersion: String? = nil,
    version: String, now: String
  ) {
    self.id = id
    self.title = title
    self.description = description
    self.recurrence = recurrence
    self.timezone = timezone
    self.startDate = startDate
    self.startTime = startTime
    self.endDate = endDate
    self.endTime = endTime
    self.allDay = allDay
    self.location = location
    self.url = url
    self.color = color
    self.eventType = eventType
    self.personName = personName
    self.attendees = attendees
    self.seriesCutoverId = seriesCutoverId
    self.seriesId = seriesId
    self.recurrenceInstanceDate = recurrenceInstanceDate
    self.occurrenceState = occurrenceState
    self.recurrenceGeneration = recurrenceGeneration
    self.recurrenceTopologyVersion = recurrenceTopologyVersion
    self.contentVersion = contentVersion ?? (seriesId == nil ? version : nil)
    self.version = version
    self.now = now
  }
}

/// Patch struct for ``CalendarEventWriteRepo/applyCalendarEventUpdate(_:patch:)``.
///
/// Nullable columns use ``Patch`` for explicit three-state PATCH
/// semantics (`unset` skip, `clear` SQL NULL, `set` write value). `title`
/// is plain `Optional<String>` because the column is NOT NULL. `allDay`
/// uses ``AllDayPatch`` (typed sum: noChange / setAllDay / setTimed).
public struct CalendarEventUpdatePatch: Sendable {
  public let eventId: String
  public var title: String?
  public var description: Patch<String>
  public var recurrence: Patch<String>
  public var timezone: Patch<String>
  public var startDate: String?
  public var startTime: Patch<String>
  public var endDate: Patch<String>
  public var endTime: Patch<String>
  public var allDay: AllDayPatch
  public var location: Patch<String>
  public var url: Patch<String>
  public var color: Patch<String>
  public var eventType: Patch<String>
  public var personName: Patch<String>
  /// Canonical JSON for the `attendees` column (a JSON array of `{name?, email?}`
  /// objects). `unset` skips, `clear` writes NULL, `set` writes the value. The
  /// workflow validates + serializes (and collapses an empty list to `clear`).
  public var attendees: Patch<String>
  public var occurrenceState: Patch<CalendarOccurrenceState>
  public var recurrenceGeneration: Patch<String>
  public var recurrenceTopologyVersion: Patch<String>
  public var contentVersion: Patch<String>
  public var version: String
  public var now: String

  public init(
    eventId: String,
    title: String? = nil,
    description: Patch<String> = .unset,
    recurrence: Patch<String> = .unset,
    timezone: Patch<String> = .unset,
    startDate: String? = nil,
    startTime: Patch<String> = .unset,
    endDate: Patch<String> = .unset,
    endTime: Patch<String> = .unset,
    allDay: AllDayPatch = .noChange,
    location: Patch<String> = .unset,
    url: Patch<String> = .unset,
    color: Patch<String> = .unset,
    eventType: Patch<String> = .unset,
    personName: Patch<String> = .unset,
    attendees: Patch<String> = .unset,
    occurrenceState: Patch<CalendarOccurrenceState> = .unset,
    recurrenceGeneration: Patch<String> = .unset,
    recurrenceTopologyVersion: Patch<String> = .unset,
    contentVersion: Patch<String> = .unset,
    version: String,
    now: String
  ) {
    self.eventId = eventId
    self.title = title
    self.description = description
    self.recurrence = recurrence
    self.timezone = timezone
    self.startDate = startDate
    self.startTime = startTime
    self.endDate = endDate
    self.endTime = endTime
    self.allDay = allDay
    self.location = location
    self.url = url
    self.color = color
    self.eventType = eventType
    self.personName = personName
    self.attendees = attendees
    self.occurrenceState = occurrenceState
    self.recurrenceGeneration = recurrenceGeneration
    self.recurrenceTopologyVersion = recurrenceTopologyVersion
    self.contentVersion = contentVersion
    self.version = version
    self.now = now
  }
}

/// Shared calendar-event INSERT / UPDATE / DELETE operations for the
/// `calendar_events` table.
///
public enum CalendarEventWriteRepo {

  /// Validate `event_type` at the lowest repo entry so a non-canonical
  /// value surfaces as ``StoreError/validation(_:)`` (matching the sync
  /// apply / import paths) rather than an opaque CHECK violation.
  private static func validateEventType(_ value: String) throws {
    switch CanonicalCalendarEventType.validate(value) {
    case .success: return
    case .failure(let message):
      throw StoreError.validation("calendar event \(message)")
    }
  }

  private static func validateOccurrenceShape(
    eventId: String,
    recurrence: String?,
    seriesCutoverId: String?,
    seriesId: String?,
    recurrenceInstanceDate: String?,
    occurrenceState: CalendarOccurrenceState?,
    recurrenceGeneration: String?,
    recurrenceTopologyVersion: String?,
    contentVersion: String?
  ) throws {
    if case .failure(let error) = CalendarEventOccurrenceInvariant.validate(
      eventId: eventId,
      recurrence: recurrence,
      seriesCutoverId: seriesCutoverId,
      seriesId: seriesId,
      recurrenceInstanceDate: recurrenceInstanceDate,
      occurrenceState: occurrenceState,
      recurrenceGeneration: recurrenceGeneration,
      recurrenceTopologyVersion: recurrenceTopologyVersion)
    {
      throw StoreError.validation(error.description)
    }
    if seriesId == nil, contentVersion == nil {
      throw StoreError.validation("a calendar base event requires content_version")
    }
    if seriesId != nil, contentVersion != nil {
      throw StoreError.validation("a calendar occurrence decision must not carry content_version")
    }
    if let seriesCutoverId {
      guard eventId == seriesCutoverId else {
        throw StoreError.validation("a calendar segment id must equal series_cutover_id")
      }
      guard SyncEntityId.isCanonicalUuid(seriesCutoverId) else {
        throw StoreError.validation("series_cutover_id must be a canonical UUID")
      }
    }
    if let seriesId, let recurrenceInstanceDate, let recurrenceGeneration {
      let expected = CalendarOccurrenceDecisionID.make(
        seriesId: seriesId,
        recurrenceGeneration: recurrenceGeneration,
        recurrenceInstanceDate: recurrenceInstanceDate)
      if eventId != expected {
        throw StoreError.validation(
          "calendar occurrence decision id does not match its series, generation, and date")
      }
    }
  }

  // MARK: - Create

  /// Insert a new `calendar_events` base row or occurrence decision.
  public static func createCalendarEvent(
    _ db: Database, params: CalendarEventCreateParams
  ) throws {
    try validateEventType(params.eventType)
    try validateOccurrenceShape(
      eventId: params.id,
      recurrence: params.recurrence,
      seriesCutoverId: params.seriesCutoverId,
      seriesId: params.seriesId,
      recurrenceInstanceDate: params.recurrenceInstanceDate,
      occurrenceState: params.occurrenceState,
      recurrenceGeneration: params.recurrenceGeneration,
      recurrenceTopologyVersion: params.recurrenceTopologyVersion,
      contentVersion: params.contentVersion)
    if let cutoverId = params.seriesCutoverId {
      guard let cutover = try CalendarSeriesCutoverRepo.fetch(db, id: cutoverId),
        cutover.state == .active
      else {
        throw StoreError.validation(
          "a calendar segment requires its active series cutover to exist first")
      }
    }
    try db.execute(
      sql: """
        INSERT INTO calendar_events \
        (id, title, description, recurrence, timezone, \
         start_date, start_time, end_date, end_time, all_day, location, url, color, \
         event_type, person_name, attendees, series_cutover_id, series_id, recurrence_instance_date, \
         occurrence_state, recurrence_generation, recurrence_topology_version, content_version, \
         version, created_at, updated_at) \
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
      arguments: [
        params.id, params.title, params.description, params.recurrence,
        params.timezone, params.startDate, params.startTime, params.endDate,
        params.endTime, params.allDay ? 1 : 0, params.location, params.url,
        params.color, params.eventType, params.personName, params.attendees,
        params.seriesCutoverId, params.seriesId, params.recurrenceInstanceDate,
        params.occurrenceState?.rawValue, params.recurrenceGeneration,
        params.recurrenceTopologyVersion, params.contentVersion,
        params.version, params.now, params.now,
      ])
  }

  // MARK: - Update

  /// Apply a partial update to a calendar event. Always sets `version`
  /// and `updated_at`; other columns are included only when their patch
  /// field carries a change.
  ///
  /// Uses **named** parameters (`:event_id`, `:version`, `:now`, …) so the
  /// LWW gate binds against the patch's `version` regardless of which
  /// optional SET columns precede it — the positional-bind shape would
  /// silently shift the gate's right-hand side under SET-clause reordering.
  ///
  /// LWW gate: `:version > calendar_events.version`. Throws
  /// ``StoreError/staleVersion(entity:id:)`` when the row exists but the
  /// gate rejected the write (the helper distinguishes missing vs stale
  /// via a post-execute existence probe).
  public static func applyCalendarEventUpdate(
    _ db: Database, patch: CalendarEventUpdatePatch
  ) throws {
    if case .set(let value) = patch.eventType {
      try validateEventType(value)
    }

    guard
      let stored = try Row.fetchOne(
        db,
        sql: """
          SELECT recurrence, series_cutover_id, series_id, recurrence_instance_date, occurrence_state, \
                 recurrence_generation, recurrence_topology_version, content_version \
          FROM calendar_events WHERE id = ?
          """,
        arguments: [patch.eventId])
    else {
      throw StoreError.notFound(entity: EntityName.calendarEvent, id: patch.eventId)
    }
    let storedStateRaw: String? = stored[4]
    let storedState: CalendarOccurrenceState?
    if let storedStateRaw {
      guard let parsed = CalendarOccurrenceState(rawValue: storedStateRaw) else {
        throw StoreError.invariant(
          "calendar event \(patch.eventId) has an invalid occurrence_state")
      }
      storedState = parsed
    } else {
      storedState = nil
    }
    func resolve<T>(_ value: T?, with patch: Patch<T>) -> T? {
      switch patch {
      case .unset: value
      case .clear: nil
      case .set(let newValue): newValue
      }
    }
    let effectiveRecurrence = resolve(stored[0] as String?, with: patch.recurrence)
    let seriesCutoverId: String? = stored[1]
    let seriesId: String? = stored[2]
    let recurrenceInstanceDate: String? = stored[3]
    let effectiveState = resolve(storedState, with: patch.occurrenceState)
    let effectiveGeneration = resolve(stored[5] as String?, with: patch.recurrenceGeneration)
    let effectiveTopology = resolve(
      stored[6] as String?, with: patch.recurrenceTopologyVersion)
    let effectiveContent = resolve(stored[7] as String?, with: patch.contentVersion)
    try validateOccurrenceShape(
      eventId: patch.eventId,
      recurrence: effectiveRecurrence,
      seriesCutoverId: seriesCutoverId,
      seriesId: seriesId,
      recurrenceInstanceDate: recurrenceInstanceDate,
      occurrenceState: effectiveState,
      recurrenceGeneration: effectiveGeneration,
      recurrenceTopologyVersion: effectiveTopology,
      contentVersion: effectiveContent)

    var setParts: [String] = ["version = :version", "updated_at = :now"]
    // GRDB drops `nil`-valued entries from a `[String: DatabaseValueConvertible?]`
    // initializer, so an explicit `.clear` (= bind NULL) needs `DatabaseValue.null`
    // to participate. Use `[String: DatabaseValue]` so every present key reaches
    // the prepared statement.
    var dict: [String: DatabaseValue] = [
      "version": patch.version.databaseValue,
      "now": patch.now.databaseValue,
      "event_id": patch.eventId.databaseValue,
    ]
    func bindPatch(_ key: String, _ p: Patch<String>) {
      if case .set(let v) = p {
        dict[key] = v.databaseValue
      } else {
        dict[key] = .null
      }
    }

    if let title = patch.title {
      setParts.append("title = :title")
      dict["title"] = title.databaseValue
    }
    if patch.description.isSetOrClear {
      setParts.append("description = :description")
      bindPatch("description", patch.description)
    }
    if patch.recurrence.isSetOrClear {
      setParts.append("recurrence = :recurrence")
      bindPatch("recurrence", patch.recurrence)
    }
    if patch.timezone.isSetOrClear {
      setParts.append("timezone = :timezone")
      bindPatch("timezone", patch.timezone)
    }
    if let sd = patch.startDate {
      setParts.append("start_date = :start_date")
      dict["start_date"] = sd.databaseValue
    }
    if patch.startTime.isSetOrClear {
      setParts.append("start_time = :start_time")
      bindPatch("start_time", patch.startTime)
    }
    if patch.endDate.isSetOrClear {
      setParts.append("end_date = :end_date")
      bindPatch("end_date", patch.endDate)
    }
    if patch.endTime.isSetOrClear {
      setParts.append("end_time = :end_time")
      bindPatch("end_time", patch.endTime)
    }
    if let allDayValue = patch.allDay.targetValue {
      setParts.append("all_day = :all_day")
      dict["all_day"] = (allDayValue ? Int64(1) : Int64(0)).databaseValue
    }
    if patch.location.isSetOrClear {
      setParts.append("location = :location")
      bindPatch("location", patch.location)
    }
    if patch.url.isSetOrClear {
      setParts.append("url = :url")
      bindPatch("url", patch.url)
    }
    if patch.color.isSetOrClear {
      setParts.append("color = :color")
      bindPatch("color", patch.color)
    }
    if patch.eventType.isSetOrClear {
      setParts.append("event_type = :event_type")
      bindPatch("event_type", patch.eventType)
    }
    if patch.personName.isSetOrClear {
      setParts.append("person_name = :person_name")
      bindPatch("person_name", patch.personName)
    }
    if patch.attendees.isSetOrClear {
      setParts.append("attendees = :attendees")
      bindPatch("attendees", patch.attendees)
    }
    if patch.occurrenceState.isSetOrClear {
      setParts.append("occurrence_state = :occurrence_state")
      switch patch.occurrenceState {
      case .set(let state): dict["occurrence_state"] = state.rawValue.databaseValue
      case .clear: dict["occurrence_state"] = .null
      case .unset: break
      }
    }
    if patch.recurrenceGeneration.isSetOrClear {
      setParts.append("recurrence_generation = :recurrence_generation")
      bindPatch("recurrence_generation", patch.recurrenceGeneration)
    }
    if patch.recurrenceTopologyVersion.isSetOrClear {
      setParts.append("recurrence_topology_version = :recurrence_topology_version")
      bindPatch("recurrence_topology_version", patch.recurrenceTopologyVersion)
    }
    if patch.contentVersion.isSetOrClear {
      setParts.append("content_version = :content_version")
      bindPatch("content_version", patch.contentVersion)
    }

    let sql = """
      UPDATE calendar_events SET \(setParts.joined(separator: ", ")) \
      WHERE id = :event_id AND :version > version
      """
    try db.execute(sql: sql, arguments: StatementArguments(dict))
    if db.changesCount == 0 {
      // Distinguish missing vs stale: probe the row.
      let exists =
        try Int.fetchOne(
          db, sql: "SELECT 1 FROM calendar_events WHERE id = ?",
          arguments: [patch.eventId]) != nil
      if !exists {
        throw StoreError.notFound(entity: EntityName.calendarEvent, id: patch.eventId)
      }
      throw StoreError.staleVersion(entity: EntityName.calendarEvent, id: patch.eventId)
    }

  }

}
