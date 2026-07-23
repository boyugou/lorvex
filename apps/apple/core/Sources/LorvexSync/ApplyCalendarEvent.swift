import Foundation
import GRDB
import LorvexDomain
import LorvexStore

struct CalendarEventDeleteApplyResult {
  let decision: ApplyAggregate.CascadingDeleteDecision
  let repairTargets: [CalendarCleanupRepairTarget]
}

/// Per-entity apply handler for the `calendar_event` aggregate root.
///
/// Occurrence decisions use deterministic ids and whole-row LWW. Base events
/// join two independent registers: metadata follows `content_version`, while
/// timing, timezone, recurrence, and generation follow
/// `recurrence_topology_version`. That split prevents a newer metadata edit from
/// rolling back a separately-newer recurrence topology.
public struct CalendarEventApplier: EntityApplier {
  public init() {}

  public var handledEntityTypes: [String] { [EntityName.calendarEvent] }

  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    try ApplyCalendarEvent.applyCalendarEventUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, tieBreak: tieBreak, applyTs: applyTs,
      payloadSchemaVersion: envelope.payloadSchemaVersion)
    return .applied
  }

  public func applyDelete(_ db: Database, envelope: SyncEnvelope, applyTs: String) throws
    -> EntityApplyOutcome
  {
    let result = try ApplyCalendarEvent.applyCalendarEventDeleteWithRepairs(
      db, entityId: envelope.entityId, version: envelope.version.description, applyTs: applyTs)
    switch result.decision {
    case .applied:
      guard !result.repairTargets.isEmpty else { return .applied }
      // Returning a repair obligation bypasses the generic delete finalizer, so
      // author the triggering event tombstone here before the host re-emits the
      // sanitized focus-schedule roots.
      try Tombstone.createTombstone(
        db, entityType: EntityName.calendarEvent, entityId: envelope.entityId,
        version: envelope.version.description, deletedAt: applyTs)
      return .repairRequired(
        .propagateCalendarCleanup(
          targets: result.repairTargets, additionalFloor: envelope.version))
    case .rejected(let localVersion):
      return .lwwRejected(localVersion: localVersion)
    }
  }
}

extension ApplyCalendarEvent {

  /// LWW-gated parent delete with a cascade pass over synced edges and
  /// canonical focus-schedule references. The latter are aggregate children,
  /// so their parent roots are returned for strict-successor re-emission.
  static func applyCalendarEventDeleteWithRepairs(
    _ db: Database, entityId: String, version: String, applyTs: String
  ) throws -> CalendarEventDeleteApplyResult {
    var repairTargets: [CalendarCleanupRepairTarget] = []
    let decision = try ApplyAggregate.gateThenCascade(
      db, readVersionSQL: "SELECT version FROM calendar_events WHERE id = ?",
      deleteSQL: "DELETE FROM calendar_events WHERE id = :id", entityId: entityId,
      incomingVersion: version, tieBreak: .allowEqual
    ) { db in
      try ApplyAggregate.tombstoneCompositeEdges(
        db,
        selectSQL:
          "SELECT task_id, version FROM task_calendar_event_links WHERE calendar_event_id = ?",
        parentId: entityId, entityType: EdgeName.taskCalendarEventLink,
        composeId: { "\($0):\(entityId)" }, version: version, deletedAt: applyTs)
      repairTargets += try CalendarSeriesCutoverCleanup.removeFocusScheduleReferences(
        db, eventIds: [entityId], barrierVersion: version, deletedAt: applyTs)
    }
    if case .rejected = decision { repairTargets.removeAll() }
    return CalendarEventDeleteApplyResult(
      decision: decision,
      repairTargets: CalendarSeriesCutoverCleanup.normalized(repairTargets))
  }

}

enum ApplyCalendarEvent {

  /// Terminalize an occurrence decision whose addressed segment is already
  /// known not to own the original recurrence slot. This preflight runs before
  /// generic tombstone/equal/LWW handling so a rejected payload is never copied
  /// into conflict history and a higher-HLC replay cannot rematerialize private
  /// decision content outside the durable partition.
  static func cutoverCleanupRepairIfResolved(
    _ db: Database, envelope: SyncEnvelope, applyTs: String
  ) throws -> ApplyRepairObligation? {
    guard envelope.operation == .upsert, envelope.entityType == .calendarEvent else {
      return nil
    }
    let incoming = try validatedRow(
      entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description,
      payloadSchemaVersion: envelope.payloadSchemaVersion)
    if incoming.isBase {
      let cutover = try cutoverRow(db, id: incoming.seriesCutoverId ?? incoming.id)
      guard let cutover, cutover.state == .deleted else { return nil }
      var targets = try CalendarSeriesCutoverCleanup.removeSegmentData(
        db, cutoverId: cutover.id,
        barrierVersion: envelope.version.description, deletedAt: applyTs)
      targets += try CalendarSeriesCutoverCleanup.removeDecision(
        db, decisionId: incoming.id,
        barrierVersion: envelope.version.description, deletedAt: applyTs)
      targets = CalendarSeriesCutoverCleanup.normalized(targets)
      return .propagateCalendarCleanup(
        targets: targets, additionalFloor: envelope.version)
    }

    guard let ownerId = incoming.seriesId,
      let recurrenceInstanceDate = incoming.recurrenceInstanceDate
    else { return nil }

    if try cutoverRow(db, id: ownerId)?.state == .deleted {
      var targets = try CalendarSeriesCutoverCleanup.removeSegmentData(
        db, cutoverId: ownerId, barrierVersion: envelope.version.description,
        deletedAt: applyTs)
      targets += try CalendarSeriesCutoverCleanup.removeDecision(
        db, decisionId: incoming.id,
        barrierVersion: envelope.version.description, deletedAt: applyTs)
      return .propagateCalendarCleanup(
        targets: CalendarSeriesCutoverCleanup.normalized(targets),
        additionalFloor: envelope.version)
    }
    let ownership = try CalendarTimelineQueries.getCalendarSeriesOwnership(
      db, eventId: ownerId)
      ?? CalendarTimelineQueries.getCalendarSeriesOwnershipForSegmentIdentity(
        db, segmentEventId: ownerId)
    guard let ownership,
      !ownership.owns(recurrenceInstanceDate: recurrenceInstanceDate)
    else { return nil }
    let targets = try CalendarSeriesCutoverCleanup.removeDecision(
      db, decisionId: incoming.id,
      barrierVersion: envelope.version.description, deletedAt: applyTs)
    return .propagateCalendarCleanup(
      targets: CalendarSeriesCutoverCleanup.normalized(targets),
      additionalFloor: envelope.version)
  }

  static func applyCalendarEventUpsert(
    _ db: Database, entityId: String, payload: String, version: String, tieBreak: LwwTieBreak,
    applyTs: String, payloadSchemaVersion: UInt32 = LorvexVersion.payloadSchemaVersion
  ) throws {
    let incoming = try validatedRow(
      entityId: entityId, payload: payload, version: version,
      payloadSchemaVersion: payloadSchemaVersion)
    if incoming.isBase {
      let cutover = try cutoverRow(
        db, id: incoming.seriesCutoverId ?? incoming.id)
      if incoming.seriesCutoverId == nil, cutover != nil {
        throw ApplyError.invalidPayload(
          "calendar_event \(incoming.id) cannot clear immutable series_cutover_id")
      }
      if let cutover, cutover.state == .deleted {
        _ = try CalendarSeriesCutoverCleanup.removeSegmentData(
          db, cutoverId: cutover.id, barrierVersion: version,
          deletedAt: applyTs)
        return
      }
    }
    if let ownerId = incoming.seriesId,
      let recurrenceInstanceDate = incoming.recurrenceInstanceDate
    {
      if try cutoverRow(db, id: ownerId)?.state == .deleted {
        _ = try CalendarSeriesCutoverCleanup.removeSegmentData(
          db, cutoverId: ownerId, barrierVersion: version,
          deletedAt: applyTs)
        _ = try CalendarSeriesCutoverCleanup.removeDecision(
          db, decisionId: incoming.id, barrierVersion: version,
          deletedAt: applyTs)
        return
      }
      // When the owner row and its boundary set have arrived, interval
      // membership is authoritative. A decision outside that interval is a
      // terminal cleanup/no-op, even when its HLC is newer than the boundary;
      // whole-row LWW must never let a predecessor reclaim a partitioned slot.
      let ownership = try CalendarTimelineQueries.getCalendarSeriesOwnership(
        db, eventId: ownerId)
        ?? CalendarTimelineQueries.getCalendarSeriesOwnershipForSegmentIdentity(
          db, segmentEventId: ownerId)
      if let ownership,
        !ownership.owns(recurrenceInstanceDate: recurrenceInstanceDate)
      {
        _ = try CalendarSeriesCutoverCleanup.removeDecision(
          db, decisionId: incoming.id, barrierVersion: version,
          deletedAt: applyTs)
        return
      }
    }
    let local = try CalendarEventSyncRow.load(db, id: entityId)

    if incoming.isBase {
      guard let local else {
        try incoming.writeReplacingSnapshot(db)
        return
      }
      guard local.isBase else {
        throw ApplyError.invalidPayload(
          "calendar_event \(entityId) cannot change between base and occurrence-decision identity")
      }
      let merged = try CalendarEventSyncRow.mergedBase(local: local, incoming: incoming)
      if merged != local {
        try merged.writeReplacingSnapshot(db)
      }
      return
    }

    if let local, local.isBase {
      throw ApplyError.invalidPayload(
        "calendar_event \(entityId) cannot change between base and occurrence-decision identity")
    }
    try incoming.writeWholeRowLww(db, tieBreak: tieBreak)
  }

  /// Equal whole-row HLCs must still reach the base-event grouped join when the
  /// two payloads differ. Exact replays remain handled by the ordinary equal-HLC
  /// gate before this predicate is consulted.
  static func isBaseMergePair(_ db: Database, envelope: SyncEnvelope) throws -> Bool {
    guard envelope.operation == .upsert, envelope.entityType == .calendarEvent,
      let local = try CalendarEventSyncRow.load(db, id: envelope.entityId), local.isBase
    else { return false }
    let incoming = try validatedRow(
      entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, payloadSchemaVersion: envelope.payloadSchemaVersion)
    return incoming.isBase
  }

  /// The ordinary row LWW gate may reject a stale envelope only after checking
  /// both independently-versioned base-event registers.
  static func staleBaseRegisterWins(_ db: Database, envelope: SyncEnvelope) throws -> Bool {
    guard envelope.operation == .upsert, envelope.entityType == .calendarEvent,
      let local = try CalendarEventSyncRow.load(db, id: envelope.entityId), local.isBase
    else { return false }
    let incoming = try validatedRow(
      entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, payloadSchemaVersion: envelope.payloadSchemaVersion)
    guard incoming.isBase else { return false }
    return try CalendarEventSyncRow.staleIncomingRegisterWins(local: local, incoming: incoming)
  }

  private static func validatedRow(
    entityId: String, payload: String, version: String, payloadSchemaVersion: UInt32
  ) throws -> CalendarEventSyncRow {
    let val = try ApplyJSON.parseObject(payload)

    let title = ApplyAggregate.scrub(
      try ApplyJSON.requiredStr(val, "title", entity: "calendar_event"))
    let description = ApplyAggregate.scrubOpt(
      ApplyAggregate.nullableStrOrClear(
        try ApplyAggregate.optionalStrPreservingEmpty(val, "description", "calendar_event")))
    let startDate = try ApplyJSON.requiredStr(val, "start_date", entity: "calendar_event")
    let startTime = try ApplyJSON.optionalStr(val, "start_time", entity: "calendar_event")
    let endDate = try ApplyJSON.optionalStr(val, "end_date", entity: "calendar_event")
    let endTime = try ApplyJSON.optionalStr(val, "end_time", entity: "calendar_event")
    let allDay = try ApplyJSON.optionalBoolAsInt64(val, "all_day", entity: "calendar_event") ?? 0

    let typedStartDate = try parseDate(startDate, field: "start_date", eventId: entityId)
    let typedEndDate = try endDate.map {
      try parseDate($0, field: "end_date", eventId: entityId)
    }
    let typedStartTime = try startTime.map {
      try parseTime($0, field: "start_time", eventId: entityId)
    }
    let typedEndTime = try endTime.map {
      try parseTime($0, field: "end_time", eventId: entityId)
    }
    if case .failure(let error) = CalendarEventTiming.fromFlatFields(
      startDate: typedStartDate, startTime: typedStartTime,
      endDate: typedEndDate, endTime: typedEndTime, allDay: allDay != 0)
    {
      throw ApplyError.invalidPayload(
        "calendar_event \(entityId) temporal fields failed validation: \(error.description)")
    }

    let location = ApplyAggregate.scrubOpt(
      ApplyAggregate.nullableStrOrClear(
        try ApplyAggregate.optionalStrPreservingEmpty(val, "location", "calendar_event")))
    let urlRaw = ApplyAggregate.nullableStrOrClear(
      try ApplyAggregate.optionalStrPreservingEmpty(val, "url", "calendar_event"))
    let url: String?
    if let urlRaw {
      switch ValidationFormat.validateCalendarURL(urlRaw) {
      case .success(let canonical): url = canonical
      case .failure(let error):
        throw ApplyError.invalidPayload("calendar_event payload.url: \(error.description)")
      }
    } else {
      url = nil
    }

    let recurrenceRaw = ApplyAggregate.nullableStrOrClear(
      try ApplyAggregate.optionalStrPreservingEmpty(val, "recurrence", "calendar_event"))
    let recurrence: String?
    switch ValidationRecurrence.normalizeCalendarRecurrence(recurrenceRaw) {
    case .success(let canonical): recurrence = canonical
    case .failure(let error):
      throw ApplyError.forwardCompatOrInvalid(
        payloadSchemaVersion: payloadSchemaVersion,
        "calendar_event \(entityId) recurrence: \(error.description)")
    }
    if case .failure(let error) = ValidationRecurrence.validateCalendarRecurrenceBound(
      recurrence, startDate: typedStartDate)
    {
      throw ApplyError.invalidPayload(
        "calendar_event \(entityId) recurrence: \(error.description)")
    }

    let timezoneRaw = ApplyAggregate.nullableStrOrClear(
      try ApplyAggregate.optionalStrPreservingEmpty(val, "timezone", "calendar_event"))
    let timezone: String?
    if let timezoneRaw {
      guard let canonical = Timezone.normalizeTimezoneName(timezoneRaw) else {
        throw ApplyError.invalidPayload(
          "calendar_event \(entityId) timezone is not a valid IANA timezone: '\(timezoneRaw)'")
      }
      timezone = canonical
    } else {
      timezone = nil
    }

    let eventType = try ApplyJSON.requiredStr(val, "event_type", entity: "calendar_event")
    if case .failure(let error) = CanonicalCalendarEventType.validate(eventType) {
      throw ApplyError.forwardCompatOrInvalid(
        payloadSchemaVersion: payloadSchemaVersion, "calendar_event payload: \(error)")
    }
    let personName = ApplyAggregate.scrubOpt(
      try ApplyJSON.optionalStr(val, "person_name", entity: "calendar_event"))
    let seriesCutoverIdPresent = val.keys.contains("series_cutover_id")
    if !seriesCutoverIdPresent {
      throw ApplyError.invalidPayload(
        "calendar_event payload schema v\(payloadSchemaVersion) requires series_cutover_id")
    }
    let seriesCutoverId = try ApplyJSON.optionalStr(
      val, "series_cutover_id", entity: "calendar_event")
    let seriesId = try ApplyJSON.optionalStr(val, "series_id", entity: "calendar_event")
    let recurrenceInstanceDate = try ApplyJSON.optionalStr(
      val, "recurrence_instance_date", entity: "calendar_event")
    let occurrenceStateRaw = try ApplyJSON.optionalStr(
      val, "occurrence_state", entity: "calendar_event")
    let occurrenceState: CalendarOccurrenceState?
    if let occurrenceStateRaw {
      guard let parsed = CalendarOccurrenceState(rawValue: occurrenceStateRaw) else {
        throw ApplyError.forwardCompatOrInvalid(
          payloadSchemaVersion: payloadSchemaVersion,
          "calendar_event occurrence_state is unknown: '\(occurrenceStateRaw)'")
      }
      occurrenceState = parsed
    } else {
      occurrenceState = nil
    }
    let recurrenceGeneration = try ApplyJSON.optionalStr(
      val, "recurrence_generation", entity: "calendar_event")
    let contentVersion = try ApplyJSON.optionalStr(
      val, "content_version", entity: "calendar_event")
    let recurrenceTopologyVersion = try ApplyJSON.optionalStr(
      val, "recurrence_topology_version", entity: "calendar_event")

    if case .failure(let error) = CalendarEventOccurrenceInvariant.validate(
      eventId: entityId, recurrence: recurrence, seriesCutoverId: seriesCutoverId,
      seriesId: seriesId,
      recurrenceInstanceDate: recurrenceInstanceDate, occurrenceState: occurrenceState,
      recurrenceGeneration: recurrenceGeneration,
      recurrenceTopologyVersion: recurrenceTopologyVersion)
    {
      throw ApplyError.invalidPayload(
        "calendar_event \(entityId) payload: \(error.description)")
    }
    try validateRegisterClocks(
      eventId: entityId, rowVersion: version, seriesId: seriesId,
      recurrenceGeneration: recurrenceGeneration, contentVersion: contentVersion,
      topologyVersion: recurrenceTopologyVersion)
    if let seriesId, let recurrenceGeneration, let recurrenceInstanceDate {
      let expectedId = CalendarOccurrenceDecisionID.make(
        seriesId: seriesId, recurrenceGeneration: recurrenceGeneration,
        recurrenceInstanceDate: recurrenceInstanceDate)
      guard entityId == expectedId else {
        throw ApplyError.invalidPayload(
          "calendar_event occurrence decision id does not match its deterministic identity")
      }
    }

    return CalendarEventSyncRow(
      id: entityId, title: title, description: description, startDate: startDate,
      startTime: startTime, endDate: endDate, endTime: endTime, allDay: allDay,
      location: location,
      url: url, color: try ApplyJSON.optionalStr(val, "color", entity: "calendar_event"),
      recurrence: recurrence, timezone: timezone, eventType: eventType, personName: personName,
      seriesCutoverId: seriesCutoverId,
      seriesId: seriesId, recurrenceInstanceDate: recurrenceInstanceDate,
      occurrenceState: occurrenceState?.rawValue, recurrenceGeneration: recurrenceGeneration,
      contentVersion: contentVersion,
      recurrenceTopologyVersion: recurrenceTopologyVersion,
      createdAt: try ApplyJSON.requiredStr(val, "created_at", entity: "calendar_event"),
      updatedAt: try ApplyJSON.requiredStr(val, "updated_at", entity: "calendar_event"),
      attendees: try normalizeAttendeesColumn(val["attendees"]), version: version)
  }

  private static func cutoverRow(
    _ db: Database, id: String
  ) throws -> CalendarSeriesCutoverRow? {
    do {
      return try CalendarSeriesCutoverRepo.fetch(db, id: id)
    } catch { throw ApplyError.lift(error) }
  }

  private static func validateRegisterClocks(
    eventId: String, rowVersion: String, seriesId: String?, recurrenceGeneration: String?,
    contentVersion: String?, topologyVersion: String?
  ) throws {
    func clock(_ raw: String, field: String) throws -> Hlc {
      do {
        let parsed = try Hlc.parseCanonical(raw)
        guard parsed.description == raw else {
          throw ApplyError.invalidPayload(
            "calendar_event \(eventId) \(field) must be a canonical HLC")
        }
        return parsed
      } catch let error as ApplyError {
        throw error
      } catch {
        throw ApplyError.invalidPayload(
          "calendar_event \(eventId) \(field) must be a canonical HLC")
      }
    }

    let row = try clock(rowVersion, field: "version")
    if seriesId == nil {
      guard let contentVersion, let topologyVersion else {
        throw ApplyError.invalidPayload(
          "calendar_event \(eventId) base event requires content_version and "
            + "recurrence_topology_version")
      }
      let content = try clock(contentVersion, field: "content_version")
      let topology = try clock(topologyVersion, field: "recurrence_topology_version")
      guard content <= row, topology <= row else {
        throw ApplyError.invalidPayload(
          "calendar_event \(eventId) register clocks must not exceed row version")
      }
    } else if contentVersion != nil || topologyVersion != nil {
      throw ApplyError.invalidPayload(
        "calendar_event \(eventId) occurrence decision cannot carry base register clocks")
    }

    if let recurrenceGeneration {
      let generation = try clock(recurrenceGeneration, field: "recurrence_generation")
      guard generation <= row else {
        throw ApplyError.invalidPayload(
          "calendar_event \(eventId) recurrence_generation must not exceed row version")
      }
    }
  }

  private static func parseDate(
    _ value: String, field: String, eventId: String
  ) throws -> LorvexDate {
    switch LorvexDate.parse(value) {
    case .success(let date): return date
    case .failure(let error):
      throw ApplyError.invalidPayload(
        "calendar_event \(eventId) \(field) failed validation: \(error.description)")
    }
  }

  private static func parseTime(
    _ value: String, field: String, eventId: String
  ) throws -> TimeOfDay {
    guard let minutes = Parsing.parseHhmmToMinutes(value) else {
      throw ApplyError.invalidPayload(
        "calendar_event \(eventId) \(field) failed validation: expected HH:MM (00:00-23:59)")
    }
    return TimeOfDay.fromMinutesSaturating(Int(minutes))
  }

  /// Normalize the wire array into canonical JSON-in-TEXT. Unknown object keys
  /// are retained verbatim for attendee-level forward compatibility.
  static func normalizeAttendeesColumn(_ value: JSONValue?) throws -> String? {
    switch value {
    case nil, .some(.null):
      return nil
    case .some(.array(let items)):
      if items.isEmpty { return nil }
      for (index, item) in items.enumerated() where ApplyJSON.object(item) == nil {
        throw ApplyError.invalidPayload(
          "calendar_event payload: attendees[\(index)] must be an object")
      }
      do {
        return try SyncCanonicalize.canonicalizeJSON(.array(items))
      } catch {
        throw ApplyError.invalidPayload(
          "calendar_event payload: attendees failed canonicalization: \(error)")
      }
    case .some:
      throw ApplyError.invalidPayload(
        "calendar_event payload: attendees must be an array of objects or null")
    }
  }

}
