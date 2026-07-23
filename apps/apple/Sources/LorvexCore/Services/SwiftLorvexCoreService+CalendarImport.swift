import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  public func importCalendarEvent(
    id: CalendarTimelineEvent.ID,
    title: String,
    startDate: String,
    startTime: String?,
    endDate: String?,
    endTime: String?,
    allDay: Bool,
    location: String?,
    notes: String?,
    url: String?,
    color: String?,
    eventType: String?,
    personName: String?,
    attendees: [CalendarEventAttendee]?,
    timezone: String?,
    recurrence: String?,
    seriesId: String?,
    recurrenceInstanceDate: String?,
    occurrenceState: String? = nil,
    recurrenceGeneration: String? = nil,
    seriesCutoverId: String? = nil
  ) async throws -> CalendarTimelineEvent {
    try withWrite { db, hlc, deviceId in
      try self.writeImportedCalendarEventInTx(
        db, hlc: hlc, deviceId: deviceId,
        id: id, title: title,
        startDate: startDate, startTime: startTime,
        endDate: endDate, endTime: endTime, allDay: allDay,
        location: location, notes: notes, url: url, color: color,
        eventType: eventType, personName: personName, attendees: attendees,
        timezone: timezone, recurrence: recurrence,
        seriesId: seriesId, recurrenceInstanceDate: recurrenceInstanceDate,
        occurrenceState: occurrenceState,
        recurrenceGeneration: recurrenceGeneration,
        seriesCutoverId: seriesCutoverId)
    }
  }

  public func importCalendarEventIfAbsent(
    id: CalendarTimelineEvent.ID,
    title: String,
    startDate: String,
    startTime: String?,
    endDate: String?,
    endTime: String?,
    allDay: Bool,
    location: String?,
    notes: String?,
    url: String?,
    color: String?,
    eventType: String?,
    personName: String?,
    attendees: [CalendarEventAttendee]?,
    timezone: String?,
    recurrence: String?,
    seriesId: String?,
    recurrenceInstanceDate: String?,
    occurrenceState: String?,
    recurrenceGeneration: String?,
    seriesCutoverId: String? = nil
  ) async throws -> (CalendarTimelineEvent?, Bool) {
    try withWrite { db, hlc, deviceId in
      // Presence and tombstone checks share the write transaction with the
      // insert, so a non-destructive restore cannot overwrite or resurrect.
      if try Int.fetchOne(
        db, sql: "SELECT 1 FROM calendar_events WHERE id = ?", arguments: [id]) != nil
      {
        return (nil, false)
      }
      if try Tombstone.isTombstoned(
        db, entityType: EntityName.calendarEvent, entityId: id)
      {
        return (nil, false)
      }
      if let seriesCutoverId,
        try CalendarSeriesCutoverRepo.fetch(db, id: seriesCutoverId)?.state == .deleted
      {
        return (nil, false)
      }
      let event = try self.writeImportedCalendarEventInTx(
        db, hlc: hlc, deviceId: deviceId,
        id: id, title: title,
        startDate: startDate, startTime: startTime,
        endDate: endDate, endTime: endTime, allDay: allDay,
        location: location, notes: notes, url: url, color: color,
        eventType: eventType, personName: personName, attendees: attendees,
        timezone: timezone, recurrence: recurrence,
        seriesId: seriesId, recurrenceInstanceDate: recurrenceInstanceDate,
        occurrenceState: occurrenceState,
        recurrenceGeneration: recurrenceGeneration,
        seriesCutoverId: seriesCutoverId)
      return (event, true)
    }
  }

  /// Restore one native calendar row. The backup preserves recurrence generation
  /// because it is part of deterministic decision identity, but carries no sync
  /// register provenance. Base content/topology registers are freshly minted;
  /// a decision remains whole-row LWW. The row high-water version strictly
  /// dominates the imported generation, every prior register on the same id,
  /// and every register minted by this restore.
  func writeImportedCalendarEventInTx(
    _ db: Database,
    hlc: HlcSession,
    deviceId: String,
    id: CalendarTimelineEvent.ID,
    title: String,
    startDate: String,
    startTime: String?,
    endDate: String?,
    endTime: String?,
    allDay: Bool,
    location: String?,
    notes: String?,
    url: String?,
    color: String?,
    eventType: String?,
    personName: String?,
    attendees: [CalendarEventAttendee]?,
    timezone: String?,
    recurrence: String?,
    seriesId: String?,
    recurrenceInstanceDate: String?,
    occurrenceState: String?,
    recurrenceGeneration: String?,
    seriesCutoverId: String?
  ) throws -> CalendarTimelineEvent {
    let normalized = try CalendarNormalization.normalizeCalendarCreate(
      CalendarCreateInput(
        title: title,
        recurrence: recurrence.trimmedNilIfEmpty,
        timezone: timezone.trimmedNilIfEmpty ?? WorkflowTimezone.anchoredTimezoneName(db),
        startDate: startDate,
        startTime: allDay ? nil : startTime.trimmedNilIfEmpty,
        endDate: endDate.trimmedNilIfEmpty,
        endTime: allDay ? nil : endTime.trimmedNilIfEmpty,
        allDay: allDay,
        description: notes.trimmedNilIfEmpty,
        location: location.trimmedNilIfEmpty,
        url: url.trimmedNilIfEmpty,
        color: color.trimmedNilIfEmpty,
        eventType: try Self.calendarEventType(eventType),
        personName: personName.trimmedNilIfEmpty))
    let resolvedSeriesId = seriesId.trimmedNilIfEmpty
    let resolvedSeriesCutoverId = seriesCutoverId.trimmedNilIfEmpty
    let resolvedInstanceDate = recurrenceInstanceDate.trimmedNilIfEmpty
    let resolvedState: CalendarOccurrenceState?
    if let raw = occurrenceState.trimmedNilIfEmpty {
      guard let parsed = CalendarOccurrenceState(rawValue: raw) else {
        throw LorvexCoreError.validation(
          field: "occurrenceState", message: "Unknown occurrence state '\(raw)'.")
      }
      resolvedState = parsed
    } else {
      resolvedState = nil
    }

    let importedGeneration = recurrenceGeneration.trimmedNilIfEmpty
    if let importedGeneration {
      guard let parsed = try? Hlc.parseCanonical(importedGeneration),
        Hlc.isOperationallyAcceptableWire(parsed),
        Hlc.hasOperationalWireSuccessor(after: parsed)
      else {
        throw LorvexCoreError.validation(
          field: "recurrenceGeneration",
          message: "The recurrence generation is not a canonical, editable HLC.")
      }
    }

    let existingClocks = try Row.fetchOne(
      db,
      sql: """
        SELECT version, content_version, recurrence_topology_version,
               recurrence_generation
        FROM calendar_events
        WHERE id = ?
        """,
      arguments: [id])
    let floor = try Self.calendarImportVersionFloor(
      eventID: id,
      candidates: [
        importedGeneration,
        existingClocks?["version"],
        existingClocks?["content_version"],
        existingClocks?["recurrence_topology_version"],
        existingClocks?["recurrence_generation"],
      ])

    let resolvedGeneration: String?
    let resolvedTopology: String?
    let contentVersion: String?
    let version: String
    if resolvedSeriesId != nil {
      resolvedGeneration = importedGeneration
      resolvedTopology = nil
      contentVersion = nil
      version = try VersionFloor.mint(
        hlc: hlc, existingVersion: floor,
        entityType: EntityName.calendarEvent, entityId: id)
    } else {
      let freshContent = try VersionFloor.mint(
        hlc: hlc, existingVersion: floor,
        entityType: EntityName.calendarEvent, entityId: id)
      let freshTopology = try VersionFloor.mint(
        hlc: hlc, existingVersion: freshContent,
        entityType: EntityName.calendarEvent, entityId: id)
      version = try VersionFloor.mint(
        hlc: hlc, existingVersion: freshTopology,
        entityType: EntityName.calendarEvent, entityId: id)
      resolvedGeneration = normalized.recurrence == nil ? nil : (importedGeneration ?? freshContent)
      resolvedTopology = freshTopology
      contentVersion = freshContent
    }
    if case .failure(let error) = CalendarEventOccurrenceInvariant.validate(
      eventId: id,
      recurrence: normalized.recurrence,
      seriesCutoverId: resolvedSeriesCutoverId,
      seriesId: resolvedSeriesId,
      recurrenceInstanceDate: resolvedInstanceDate,
      occurrenceState: resolvedState,
      recurrenceGeneration: resolvedGeneration,
      recurrenceTopologyVersion: resolvedTopology)
    {
      throw LorvexCoreError.validation(field: nil, message: error.description)
    }
    if let resolvedSeriesCutoverId {
      guard
        let cutover = try CalendarSeriesCutoverRepo.fetch(db, id: resolvedSeriesCutoverId),
        cutover.state == .active
      else {
        throw LorvexCoreError.validation(
          field: "seriesCutoverId",
          message: "A restored calendar segment requires its active series boundary first.")
      }
    }
    if let resolvedSeriesId, let resolvedInstanceDate, let resolvedGeneration {
      let expected = CalendarOccurrenceDecisionID.make(
        seriesId: resolvedSeriesId,
        recurrenceGeneration: resolvedGeneration,
        recurrenceInstanceDate: resolvedInstanceDate)
      guard id == expected else {
        throw LorvexCoreError.validation(
          field: "id",
          message: "The occurrence decision id does not match its series, generation, and date.")
      }
    }

    let attendeesJSON: String?
    do {
      attendeesJSON = try CalendarEventAttendees.serialize(Self.attendeeInputs(attendees) ?? [])
    } catch let error as CalendarEventOpError {
      throw error.asCoreError()
    }
    let now = SyncTimestampFormat.syncTimestampNow()
    try db.execute(
      sql: """
        INSERT INTO calendar_events
          (id, title, description, start_date, start_time, end_date, end_time,
           all_day, location, url, color, recurrence, timezone, event_type,
           person_name, attendees, series_cutover_id, series_id, recurrence_instance_date,
           occurrence_state, recurrence_generation, recurrence_topology_version, content_version,
           version, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          title = excluded.title, description = excluded.description,
          start_date = excluded.start_date, start_time = excluded.start_time,
          end_date = excluded.end_date, end_time = excluded.end_time,
          all_day = excluded.all_day, location = excluded.location,
          url = excluded.url, color = excluded.color, recurrence = excluded.recurrence,
          timezone = excluded.timezone, event_type = excluded.event_type,
          person_name = excluded.person_name, attendees = excluded.attendees,
          series_cutover_id = excluded.series_cutover_id,
          series_id = excluded.series_id,
          recurrence_instance_date = excluded.recurrence_instance_date,
          occurrence_state = excluded.occurrence_state,
          recurrence_generation = excluded.recurrence_generation,
          recurrence_topology_version = excluded.recurrence_topology_version,
          content_version = excluded.content_version,
          version = excluded.version, updated_at = excluded.updated_at
        WHERE excluded.version > calendar_events.version
        """,
      arguments: [
        id, normalized.title, normalized.description,
        normalized.startDate, normalized.startTime,
        normalized.endDate, normalized.endTime,
        normalized.allDay ? 1 : 0, normalized.location, normalized.url, normalized.color,
        normalized.recurrence, normalized.timezone, normalized.eventType.rawValue,
        normalized.personName, attendeesJSON,
        resolvedSeriesCutoverId, resolvedSeriesId, resolvedInstanceDate, resolvedState?.rawValue,
        resolvedGeneration, resolvedTopology, contentVersion,
        version, now, now,
      ])
    if db.changesCount == 0 {
      throw StoreError.staleVersion(entity: EntityName.calendarEvent, id: id)
    }
    try self.enqueueUpsert(
      db, hlc: hlc, deviceId: deviceId, kind: .calendarEvent, entityId: id,
      registerIntent: resolvedSeriesId == nil ? .calendar(.all) : EntityRegisterIntent.none)
    let after = try CalendarEventLoad.loadCalendarEventJSON(db, eventId: id)
    try self.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: SyncNaming.opUpsert,
        entityType: EntityName.calendarEvent,
        entityId: id,
        summary: "Imported calendar event '\(normalized.title)'",
        after: after),
      deviceId: deviceId)
    guard let row = try CalendarTimelineQueries.getStoredCalendarEvent(db, id: id) else {
      throw LorvexCoreError.unsupportedOperation(
        "Calendar event '\(id)' missing after import.")
    }
    return SwiftLorvexCalendarDeserializers.event(row)
  }

  private static func calendarImportVersionFloor(
    eventID: String, candidates: [String?]
  ) throws -> String? {
    var maximum: Hlc?
    for candidate in candidates.compactMap({ $0 }) {
      let parsed: Hlc
      do {
        parsed = try Hlc.parseCanonical(candidate)
      } catch {
        throw StoreError.invariant(
          "calendar event '\(eventID)' contains invalid or non-canonical clock '\(candidate)'")
      }
      if let maximumValue = maximum {
        if parsed > maximumValue { maximum = parsed }
      } else {
        maximum = parsed
      }
    }
    return maximum?.description
  }
}

private extension CalendarEventOpError {
  func asCoreError() -> Error {
    switch self {
    case .validation(let message):
      LorvexCoreError.validation(field: "attendees", message: message)
    case .store(let error):
      error
    }
  }
}
