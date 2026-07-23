import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync

/// Durable recurring-series boundary writes and native restore.
extension SwiftLorvexCoreService {
  /// Create or advance one deterministic boundary. The store join makes
  /// `deleted` absorbing, so callers requesting `active` must inspect the
  /// returned state before creating a segment row.
  @discardableResult
  func upsertCalendarSeriesCutover(
    _ db: Database,
    hlc: HlcSession,
    deviceId: String,
    lineageRootId: String,
    cutoverDate: String,
    state: CalendarSeriesCutoverState,
    operation: String
  ) throws -> CalendarSeriesCutoverRow {
    let id = CalendarSeriesCutoverID.make(
      lineageRootId: lineageRootId, cutoverDate: cutoverDate)
    let existing = try CalendarSeriesCutoverRepo.fetch(db, id: id)
    let before = try PayloadLoaders.loadCalendarSeriesCutoverSyncPayload(db, id: id)
    let version = try VersionFloor.mint(
      hlc: hlc, existingVersion: existing?.version,
      entityType: EntityName.calendarSeriesCutover, entityId: id)
    let now = SyncTimestampFormat.syncTimestampNow()
    let converged = try CalendarSeriesCutoverRepo.upsert(
      db,
      row: CalendarSeriesCutoverRow(
        id: id,
        lineageRootId: lineageRootId,
        cutoverDate: cutoverDate,
        state: state,
        version: version,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now))
    try enqueueUpsert(
      db, deviceId: deviceId, kind: .calendarSeriesCutover,
      entityId: id, version: converged.version)
    let after = try PayloadLoaders.loadCalendarSeriesCutoverSyncPayload(db, id: id)
    try writeChangelogRow(
      db,
      ChangelogEntry(
        operation: operation,
        entityType: EntityName.calendarSeriesCutover,
        entityId: id,
        summary: "Set calendar-series boundary '\(cutoverDate)' to \(converged.state.rawValue)",
        before: before,
        after: after),
      deviceId: deviceId)
    return converged
  }

  /// Restore canonical calendar rows and their internal series boundaries in a
  /// single transaction. The full bundle is semantically preflighted before the
  /// first write. In particular, every active boundary must carry its
  /// deterministic segment row, while a target tombstone or either side's
  /// deleted boundary converts that segment to an absorbing gap.
  public func importCalendarBundle(
    cutovers: [ExportCalendarSeriesCutover], events: [ExportCalendarEvent]
  ) async throws -> NativeCalendarImportResult {
    try withWrite { db, hlc, deviceId in
      var eventsByID: [String: ExportCalendarEvent] = [:]
      for event in events {
        guard eventsByID.updateValue(event, forKey: event.id) == nil else {
          throw LorvexCoreError.validation(
            field: "calendarEvents",
            message: "The calendar backup repeats event id '\(event.id)'.")
        }
      }

      var requestedByID: [String: (ExportCalendarSeriesCutover, CalendarSeriesCutoverState)] = [:]
      for cutover in cutovers {
        let state = try Self.validateNativeCalendarCutover(cutover)
        guard requestedByID.updateValue((cutover, state), forKey: cutover.id) == nil else {
          throw LorvexCoreError.validation(
            field: "calendarSeriesCutovers",
            message: "The calendar backup repeats boundary id '\(cutover.id)'.")
        }
      }

      // Validate the payload's topology before applying even a deletion. This
      // makes malformed active-without-segment archives fail closed instead of
      // appearing to restore successfully only because this target had already
      // deleted the segment.
      for (cutover, state) in requestedByID.values where state == .active {
        guard let segment = eventsByID[cutover.id] else {
          throw LorvexCoreError.validation(
            field: "calendarEvents",
            message: "Active boundary '\(cutover.id)' is missing its segment event.")
        }
        try Self.validateNativeCalendarSegment(segment, for: cutover)
      }

      // A segment marker is meaningful only together with the corresponding
      // boundary carried by this same backup. Deleted boundaries may carry a
      // stale segment row; validate identity but let remove-wins skip content.
      for event in events {
        guard let marker = event.seriesCutoverId else { continue }
        guard requestedByID[marker] != nil else {
          throw LorvexCoreError.validation(
            field: "seriesCutoverId",
            message: "Calendar segment '\(event.id)' references a boundary absent from the backup.")
        }
        guard event.id == marker else {
          throw LorvexCoreError.validation(
            field: "seriesCutoverId",
            message: "A calendar segment id must equal its deterministic boundary id.")
        }
      }

      var effectiveByID: [String: CalendarSeriesCutoverState] = [:]
      for (cutover, requestedState) in requestedByID.values {
        let existing = try CalendarSeriesCutoverRepo.fetch(db, id: cutover.id)
        if let existing,
          existing.lineageRootId != cutover.lineageRootId
            || existing.cutoverDate != cutover.cutoverDate
        {
          throw LorvexCoreError.validation(
            field: "calendarSeriesCutovers",
            message: "Boundary '\(cutover.id)' conflicts with immutable local identity fields.")
        }
        let segmentTombstoned = try Tombstone.isTombstoned(
          db, entityType: EntityName.calendarEvent, entityId: cutover.id)
        let effective: CalendarSeriesCutoverState =
          requestedState == .deleted || existing?.state == .deleted || segmentTombstoned
          ? .deleted : .active
        effectiveByID[cutover.id] = effective

        if effective == .active,
          let local = try Row.fetchOne(
            db,
            sql: """
              SELECT series_cutover_id, series_id
              FROM calendar_events WHERE id = ?
              """,
            arguments: [cutover.id])
        {
          let localMarker: String? = local["series_cutover_id"]
          let localSeriesID: String? = local["series_id"]
          guard localMarker == cutover.id, localSeriesID == nil else {
            throw LorvexCoreError.validation(
              field: "calendarEvents",
              message: "Boundary '\(cutover.id)' conflicts with an unrelated local event.")
          }
        }
      }

      // Boundaries first, but still inside this transaction: if any subsequent
      // event validation/write fails, GRDB rolls these joins and cleanups back.
      for (cutover, _) in requestedByID.values.sorted(by: {
        if $0.0.cutoverDate == $1.0.cutoverDate { return $0.0.id < $1.0.id }
        return $0.0.cutoverDate < $1.0.cutoverDate
      }) {
        try self.applyNativeCalendarCutover(
          cutover, state: effectiveByID[cutover.id]!,
          db: db, hlc: hlc, deviceId: deviceId)
      }

      // Base rows precede occurrence decisions so a valid backup never creates
      // a temporary orphan. Stable id ordering makes repeated restores produce
      // deterministic changelog/outbox order.
      let orderedEvents = events.sorted {
        let lhsDecision = $0.seriesId != nil
        let rhsDecision = $1.seriesId != nil
        if lhsDecision != rhsDecision { return !lhsDecision }
        return $0.id < $1.id
      }
      var imported = 0
      var skipped = 0
      for event in orderedEvents {
        if let marker = event.seriesCutoverId,
          effectiveByID[marker] == .deleted
        {
          skipped += 1
          continue
        }
        if let seriesID = event.seriesId {
          let masterTombstoned = try Tombstone.isTombstoned(
            db, entityType: EntityName.calendarEvent, entityId: seriesID)
          if effectiveByID[seriesID] == .deleted || masterTombstoned {
            skipped += 1
            continue
          }
          let masterExists = try Int.fetchOne(
            db, sql: "SELECT 1 FROM calendar_events WHERE id = ?", arguments: [seriesID]) != nil
          if !masterExists {
            skipped += 1
            continue
          }
        }
        if try Int.fetchOne(
          db, sql: "SELECT 1 FROM calendar_events WHERE id = ?", arguments: [event.id]) != nil
        {
          skipped += 1
          continue
        }
        if try Tombstone.isTombstoned(
          db, entityType: EntityName.calendarEvent, entityId: event.id)
        {
          skipped += 1
          continue
        }
        _ = try self.writeNativeCalendarEvent(
          event, db: db, hlc: hlc, deviceId: deviceId)
        imported += 1
      }
      return NativeCalendarImportResult(importedEvents: imported, skippedEvents: skipped)
    }
  }

  private static func validateNativeCalendarCutover(
    _ cutover: ExportCalendarSeriesCutover
  ) throws -> CalendarSeriesCutoverState {
    guard let state = CalendarSeriesCutoverState(rawValue: cutover.state) else {
      throw LorvexCoreError.validation(
        field: "state", message: "Unknown calendar-series boundary state '\(cutover.state)'.")
    }
    let now = SyncTimestampFormat.syncTimestampNow()
    do {
      try CalendarSeriesCutoverRepo.validate(
        CalendarSeriesCutoverRow(
          id: cutover.id, lineageRootId: cutover.lineageRootId,
          cutoverDate: cutover.cutoverDate, state: state,
          version: Hlc.testVersion, createdAt: now, updatedAt: now))
    } catch {
      throw LorvexCoreError.validation(
        field: "calendarSeriesCutovers", message: error.localizedDescription)
    }
    return state
  }

  private static func validateNativeCalendarSegment(
    _ event: ExportCalendarEvent, for cutover: ExportCalendarSeriesCutover
  ) throws {
    guard event.id == cutover.id, event.seriesCutoverId == cutover.id,
      event.seriesId == nil, event.recurrenceInstanceDate == nil,
      event.occurrenceState == nil
    else {
      throw LorvexCoreError.validation(
        field: "calendarEvents",
        message: "Active boundary '\(cutover.id)' has a malformed segment event.")
    }
  }

  private func applyNativeCalendarCutover(
    _ cutover: ExportCalendarSeriesCutover,
    state: CalendarSeriesCutoverState,
    db: Database,
    hlc: HlcSession,
    deviceId: String
  ) throws {
    let existing = try CalendarSeriesCutoverRepo.fetch(db, id: cutover.id)
    if existing?.state != .deleted, existing?.state != state {
      _ = try upsertCalendarSeriesCutover(
        db, hlc: hlc, deviceId: deviceId,
        lineageRootId: cutover.lineageRootId,
        cutoverDate: cutover.cutoverDate,
        state: state,
        operation: "import_calendar_series_cutover")
    }
    guard state == .deleted else { return }
    _ = try sweepSeriesDecisions(
      db, hlc: hlc, deviceId: deviceId, seriesId: cutover.id, scope: .all)
    _ = try deleteCalendarEventRowInline(
      db, hlc: hlc, deviceId: deviceId, id: cutover.id)
  }

  private func writeNativeCalendarEvent(
    _ event: ExportCalendarEvent,
    db: Database,
    hlc: HlcSession,
    deviceId: String
  ) throws -> CalendarTimelineEvent {
    let recurrence = event.recurrence?.canonicalRecurrenceJSON()
    if event.recurrence != nil, recurrence == nil {
      throw LorvexCoreError.validation(
        field: "recurrence", message: "The calendar recurrence could not be serialized.")
    }
    return try writeImportedCalendarEventInTx(
      db, hlc: hlc, deviceId: deviceId,
      id: event.id, title: event.title,
      startDate: event.startDate,
      startTime: event.startTime.isEmpty ? nil : event.startTime,
      endDate: event.endDate.isEmpty ? nil : event.endDate,
      endTime: event.endTime.isEmpty ? nil : event.endTime,
      allDay: event.allDay,
      location: event.location.flatMap { $0.isEmpty ? nil : $0 },
      notes: event.notes, url: event.url, color: event.color,
      eventType: event.eventType, personName: event.personName,
      attendees: event.attendees, timezone: event.timezone,
      recurrence: recurrence, seriesId: event.seriesId,
      recurrenceInstanceDate: event.recurrenceInstanceDate,
      occurrenceState: event.occurrenceState,
      recurrenceGeneration: event.recurrenceGeneration,
      seriesCutoverId: event.seriesCutoverId)
  }
}
