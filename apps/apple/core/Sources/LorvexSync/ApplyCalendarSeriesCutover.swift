import GRDB
import LorvexDomain
import LorvexStore

/// Remove-wins inbound applier for durable recurring-series boundaries.
public struct CalendarSeriesCutoverApplier: EntityApplier {
  public init() {}

  public var handledEntityTypes: [String] { [EntityName.calendarSeriesCutover] }

  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak _: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    let incoming = try Self.validatedRow(envelope)
    let merged: CalendarSeriesCutoverRow
    do {
      merged = try CalendarSeriesCutoverRepo.upsert(db, row: incoming)
    } catch let error as StoreError {
      throw ApplyError.invalidPayload(
        "calendar_series_cutover \(envelope.entityId) failed validation: \(error)")
    }
    var repairTargets: [CalendarCleanupRepairTarget] = []
    repairTargets += try CalendarSeriesCutoverCleanup.removeConflictingSegmentIdentity(
      db, cutoverId: merged.id, barrierVersion: merged.version,
      deletedAt: applyTs)
    if merged.state == .deleted {
      repairTargets += try CalendarSeriesCutoverCleanup.removeSegmentData(
        db, cutoverId: merged.id, barrierVersion: merged.version, deletedAt: applyTs)
    }
    repairTargets += try CalendarSeriesCutoverCleanup.removeOutOfOwnershipDecisions(
      db, lineageRootId: merged.lineageRootId,
      barrierVersion: merged.version, deletedAt: applyTs)
    if merged != incoming, !repairTargets.isEmpty {
      // A cleanup outcome bypasses the ordinary post-`.applied` absence/join
      // re-emit hook. Carry the cutover itself in the same typed repair so an
      // older local `deleted` joined with a newer inbound `active` still
      // replaces CloudKit with one strict-successor deleted full snapshot.
      repairTargets.append(
        CalendarCleanupRepairTarget(
          entityType: .calendarSeriesCutover, entityId: merged.id,
          operation: .upsert))
    }
    repairTargets = CalendarSeriesCutoverCleanup.normalized(repairTargets)
    if !repairTargets.isEmpty {
      return .repairRequired(
        .propagateCalendarCleanup(
          targets: repairTargets, additionalFloor: envelope.version))
    }
    return .applied
  }

  public func applyDelete(
    _ db: Database, envelope: SyncEnvelope, applyTs _: String
  ) throws -> EntityApplyOutcome {
    guard try CalendarSeriesCutoverRepo.fetch(db, id: envelope.entityId) != nil else {
      throw ApplyError.invalidPayload(
        "calendar_series_cutover Delete is invalid and no local boundary exists to reassert")
    }
    return .requiredCutoverDeleteRejected
  }

  private static func validatedRow(_ envelope: SyncEnvelope) throws -> CalendarSeriesCutoverRow {
    let object = try ApplyJSON.parseObject(envelope.payload)
    let id = try ApplyJSON.requiredStr(
      object, "id", entity: EntityName.calendarSeriesCutover)
    guard id == envelope.entityId else {
      throw ApplyError.invalidPayload(
        "calendar_series_cutover payload.id must equal envelope entity_id")
    }
    let lineageRootId = try ApplyJSON.requiredStr(
      object, "lineage_root_id", entity: EntityName.calendarSeriesCutover)
    let cutoverDate = try ApplyJSON.requiredStr(
      object, "cutover_date", entity: EntityName.calendarSeriesCutover)
    let stateRaw = try ApplyJSON.requiredStr(
      object, "state", entity: EntityName.calendarSeriesCutover)
    guard let state = CalendarSeriesCutoverState(rawValue: stateRaw) else {
      throw ApplyError.forwardCompatOrInvalid(
        payloadSchemaVersion: envelope.payloadSchemaVersion,
        "calendar_series_cutover state is unknown: '\(stateRaw)'")
    }
    let row = CalendarSeriesCutoverRow(
      id: id, lineageRootId: lineageRootId, cutoverDate: cutoverDate,
      state: state, version: envelope.version.description,
      createdAt: try ApplyJSON.requiredStr(
        object, "created_at", entity: EntityName.calendarSeriesCutover),
      updatedAt: try ApplyJSON.requiredStr(
        object, "updated_at", entity: EntityName.calendarSeriesCutover))
    do {
      try CalendarSeriesCutoverRepo.validate(row)
    } catch let error as StoreError {
      throw ApplyError.invalidPayload(
        "calendar_series_cutover \(envelope.entityId) failed validation: \(error)")
    }
    return row
  }
}

enum CalendarSeriesCutoverCleanup {
  private struct SegmentInterval {
    let lower: String?
    let upper: String?
    let active: Bool

    func owns(_ date: String) -> Bool {
      active && (lower == nil || date >= lower!) && (upper == nil || date < upper!)
    }
  }

  /// Intercept child/aggregate upserts that reference an already-deleted
  /// segment before generic tombstone, equal-HLC, FK, conflict-log, or payload-
  /// shadow processing. A durable cutover is a permanent semantic fence: a late
  /// edge must become a propagated Delete, while a late focus aggregate must be
  /// sanitized and re-authored (or deleted when no blocks remain).
  static func lateReferenceRepairIfResolved(
    _ db: Database, envelope: SyncEnvelope, applyTs: String
  ) throws -> ApplyRepairObligation? {
    guard envelope.operation == .upsert else { return nil }
    switch envelope.entityType {
    case .taskCalendarEventLink:
      return try lateTaskEventLinkRepairIfResolved(
        db, envelope: envelope, applyTs: applyTs)
    case .focusSchedule:
      return try lateFocusScheduleRepairIfResolved(
        db, envelope: envelope, applyTs: applyTs)
    default:
      return nil
    }
  }

  private static func lateTaskEventLinkRepairIfResolved(
    _ db: Database, envelope: SyncEnvelope, applyTs: String
  ) throws -> ApplyRepairObligation? {
    let pair: (String, String)
    switch CompositeEdge.splitCompositeEdgeId(envelope.entityId) {
    case .success(let value): pair = value
    case .failure(let error): throw ApplyError.invalidPayload(error.description)
    }
    let (taskId, eventId) = pair
    guard try CalendarSeriesCutoverRepo.fetch(db, id: eventId)?.state == .deleted else {
      return nil
    }

    var deathVersion = envelope.version.description
    if let local = try String.fetchOne(
      db,
      sql: """
        SELECT version FROM task_calendar_event_links
        WHERE task_id = ? AND calendar_event_id = ?
        """,
      arguments: [taskId, eventId])
    {
      deathVersion = maximumVersion(deathVersion, local)
    }
    if let tombstone = try Tombstone.getTombstone(
      db, entityType: EdgeName.taskCalendarEventLink, entityId: envelope.entityId)
    {
      deathVersion = maximumVersion(deathVersion, tombstone.version)
    }
    try db.execute(
      sql: """
        DELETE FROM task_calendar_event_links
        WHERE task_id = ? AND calendar_event_id = ?
        """,
      arguments: [taskId, eventId])
    try Tombstone.createTombstone(
      db, entityType: EdgeName.taskCalendarEventLink, entityId: envelope.entityId,
      version: deathVersion, deletedAt: applyTs)
    return .propagateCalendarCleanup(
      targets: [
        CalendarCleanupRepairTarget(
          entityType: .taskCalendarEventLink, entityId: envelope.entityId,
          operation: .delete)
      ],
      additionalFloor: envelope.version)
  }

  private static func lateFocusScheduleRepairIfResolved(
    _ db: Database, envelope: SyncEnvelope, applyTs: String
  ) throws -> ApplyRepairObligation? {
    guard case .object(var object)? = JSONValue.parse(envelope.payload),
      case .array(let blocks)? = object["blocks"]
    else {
      throw ApplyError.invalidPayload("focus_schedule payload: blocks must be an array")
    }

    var invalidEventIds = Set<String>()
    var retainedBlocks: [JSONValue] = []
    retainedBlocks.reserveCapacity(blocks.count)
    for block in blocks {
      guard case .object(let fields) = block,
        fields["block_type"] == .string("event"),
        fields["event_source"] == .string("canonical"),
        case .string(let eventId)? = fields["calendar_event_id"],
        try CalendarSeriesCutoverRepo.fetch(db, id: eventId)?.state == .deleted
      else {
        retainedBlocks.append(block)
        continue
      }
      invalidEventIds.insert(eventId)
    }
    guard !invalidEventIds.isEmpty else { return nil }
    guard envelope.payloadSchemaVersion <= LorvexVersion.payloadSchemaVersion else {
      throw ApplyError.deferForwardCompat(
        .schemaTooNew(
          remoteVersion: envelope.payloadSchemaVersion,
          localVersion: LorvexVersion.payloadSchemaVersion))
    }

    // Sanitize every already-materialized reference to the same permanent
    // barriers first. This also handles the stale/equal-incoming case: a newer
    // local schedule keeps its content but loses the forbidden blocks and is
    // selected for a full-snapshot reassertion.
    var targets = try removeFocusScheduleReferences(
      db, eventIds: Array(invalidEventIds),
      barrierVersion: envelope.version.description, deletedAt: applyTs)

    object["blocks"] = .array(retainedBlocks)
    let sanitizedPayload = try SyncCanonicalize.canonicalizeJSON(.object(object))
    let desired: SyncEnvelope
    if retainedBlocks.isEmpty {
      desired = SyncEnvelope(
        entityType: .focusSchedule, entityId: envelope.entityId,
        operation: .delete, version: envelope.version,
        payloadSchemaVersion: envelope.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object(["version": .string(envelope.version.description)])),
        deviceId: envelope.deviceId)
    } else {
      desired = SyncEnvelope(
        entityType: .focusSchedule, entityId: envelope.entityId,
        operation: .upsert, version: envelope.version,
        payloadSchemaVersion: envelope.payloadSchemaVersion,
        payload: sanitizedPayload, deviceId: envelope.deviceId)
    }

    if try desiredWinsAgainstCurrentFocusSchedule(db, desired: desired) {
      switch desired.operation {
      case .upsert:
        _ = try Tombstone.removeTombstone(
          db, entityType: EntityName.focusSchedule, entityId: desired.entityId)
        try ApplyLww.resetCorruptLocalVersion(
          db, entityType: EntityName.focusSchedule, entityId: desired.entityId)
        try ApplyDayScoped.applyFocusScheduleUpsert(
          db, entityId: desired.entityId, payload: desired.payload,
          version: desired.version.description, tieBreak: .allowEqual,
          payloadSchemaVersion: desired.payloadSchemaVersion)
      case .delete:
        try ApplyDayScoped.applyFocusScheduleDelete(
          db, entityId: desired.entityId, version: desired.version.description)
        try Tombstone.createTombstone(
          db, entityType: EntityName.focusSchedule, entityId: desired.entityId,
          version: desired.version.description, deletedAt: applyTs)
      }
    }

    if try ApplyLww.getLocalVersion(
      db, entityType: EntityName.focusSchedule, entityId: envelope.entityId) != nil
    {
      targets.append(
        CalendarCleanupRepairTarget(
          entityType: .focusSchedule, entityId: envelope.entityId,
          operation: .upsert))
    } else {
      var deathVersion = envelope.version.description
      if let tombstone = try Tombstone.getTombstone(
        db, entityType: EntityName.focusSchedule, entityId: envelope.entityId)
      {
        deathVersion = maximumVersion(deathVersion, tombstone.version)
      }
      try Tombstone.createTombstone(
        db, entityType: EntityName.focusSchedule, entityId: envelope.entityId,
        version: deathVersion, deletedAt: applyTs)
      targets.append(
        CalendarCleanupRepairTarget(
          entityType: .focusSchedule, entityId: envelope.entityId,
          operation: .delete))
    }
    return .propagateCalendarCleanup(
      targets: normalized(targets), additionalFloor: envelope.version)
  }

  private static func desiredWinsAgainstCurrentFocusSchedule(
    _ db: Database, desired: SyncEnvelope
  ) throws -> Bool {
    let liveRaw = try ApplyLww.getLocalVersion(
      db, entityType: EntityName.focusSchedule, entityId: desired.entityId)
    let tombstone = try Tombstone.getTombstone(
      db, entityType: EntityName.focusSchedule, entityId: desired.entityId)
    let live = liveRaw.flatMap { try? Hlc.parseCanonical($0) }
    let death = tombstone.flatMap { try? Hlc.parseCanonical($0.version) }
    let floor = [live, death].compactMap { $0 }.max()
    guard let floor else { return true }
    if desired.version != floor { return desired.version > floor }

    let current: SyncEnvelope
    if death == floor {
      current = SyncEnvelope(
        entityType: .focusSchedule, entityId: desired.entityId,
        operation: .delete, version: floor,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object(["version": .string(floor.description)])),
        deviceId: "local-equal-hlc")
    } else {
      let payload = try SyncCanonicalize.canonicalizeJSON(
        OutboxEnqueue.readEntityPayloadSnapshot(
          db, entityType: EntityName.focusSchedule, entityId: desired.entityId))
      current = SyncEnvelope(
        entityType: .focusSchedule, entityId: desired.entityId,
        operation: .upsert, version: floor,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: "local-equal-hlc")
    }
    let winner = try SyncMutationSemantics.deterministicWinner(current, desired)
    return try SyncMutationSemantics.isExactSemanticReplay(winner, desired)
  }

  /// The deterministic cutover id is reserved for its base segment. A corrupt
  /// row must not keep that identity occupied as an occurrence decision for
  /// another series or as an unmarked base row: remove it through the same
  /// terminal repair funnel used for every out-of-ownership decision. This is
  /// intentionally checked for both active and deleted boundaries.
  static func removeConflictingSegmentIdentity(
    _ db: Database, cutoverId: String, barrierVersion: String, deletedAt: String
  ) throws -> [CalendarCleanupRepairTarget] {
    let conflictingID = try String.fetchOne(
      db,
      sql: """
        SELECT id FROM calendar_events
        WHERE id = ? AND (series_id IS NOT NULL OR series_cutover_id IS NOT ?)
        """,
      arguments: [cutoverId, cutoverId])
    guard conflictingID != nil else { return [] }
    return try removeDecision(
      db, decisionId: cutoverId, barrierVersion: barrierVersion,
      deletedAt: deletedAt)
  }

  /// Re-evaluate every locally-known decision in a lineage against the complete
  /// ordered boundary relation. Recomputing the whole lineage is required for
  /// out-of-order cutovers: when D3 arrives before D2, a D2-addressed decision
  /// can exist before D2's identity becomes classifiable; D2 arrival must then
  /// discover that the decision lies beyond D3 and remove it.
  static func removeOutOfOwnershipDecisions(
    _ db: Database, lineageRootId: String, barrierVersion: String,
    deletedAt: String
  ) throws -> [CalendarCleanupRepairTarget] {
    let boundaries = try Row.fetchAll(
      db,
      sql: """
        SELECT id, cutover_date, state
        FROM calendar_series_cutovers
        WHERE lineage_root_id = ?
        ORDER BY cutover_date ASC, id ASC
        """,
      arguments: [lineageRootId])
    var intervals: [String: SegmentInterval] = [
      lineageRootId: SegmentInterval(
        lower: nil, upper: boundaries.first.map { $0["cutover_date"] as String },
        active: true)
    ]
    for (index, boundary) in boundaries.enumerated() {
      let id: String = boundary["id"]
      let stateRaw: String = boundary["state"]
      guard let state = CalendarSeriesCutoverState(rawValue: stateRaw) else {
        throw ApplyError.invalidPayload(
          "calendar_series_cutover \(id) has unknown state '\(stateRaw)'")
      }
      let upper: String? = index + 1 < boundaries.count
        ? boundaries[index + 1]["cutover_date"] : nil
      intervals[id] = SegmentInterval(
        lower: boundary["cutover_date"], upper: upper, active: state == .active)
    }

    let decisions = try Row.fetchAll(
      db,
      sql: """
        SELECT id, series_id, recurrence_instance_date
        FROM calendar_events
        WHERE series_id = ?
           OR series_id IN (
             SELECT id FROM calendar_series_cutovers WHERE lineage_root_id = ?
           )
        ORDER BY id
        """,
      arguments: [lineageRootId, lineageRootId])
    var targets: [CalendarCleanupRepairTarget] = []
    for decision in decisions {
      let id: String = decision["id"]
      let ownerId: String = decision["series_id"]
      let occurrenceDate: String = decision["recurrence_instance_date"]
      guard let interval = intervals[ownerId], !interval.owns(occurrenceDate) else {
        continue
      }
      targets += try removeDecision(
        db, decisionId: id, barrierVersion: barrierVersion,
        deletedAt: deletedAt)
    }
    return normalized(targets)
  }

  /// Remove one decision that its addressed segment provably does not own.
  /// The row may not exist yet (decision-after-boundary); the tombstone still
  /// records the rejected inbound version so stale replays cannot materialize.
  static func removeDecision(
    _ db: Database, decisionId: String, barrierVersion: String, deletedAt: String
  ) throws -> [CalendarCleanupRepairTarget] {
    let existingVersion = try String.fetchOne(
      db, sql: "SELECT version FROM calendar_events WHERE id = ?",
      arguments: [decisionId])
    let deathVersion = existingVersion.map { maximumVersion(barrierVersion, $0) }
      ?? barrierVersion
    var targets = try removeEventData(
      db, eventId: decisionId, deathVersion: deathVersion, deletedAt: deletedAt)
    targets += try removeFocusScheduleReferences(
      db, eventIds: [decisionId], barrierVersion: deathVersion,
      deletedAt: deletedAt)
    return normalized(targets)
  }

  /// Remove every locally materialized payload owned by a deleted segment. The
  /// permanent cutover row remains the resurrection barrier; ordinary event
  /// tombstones additionally replace stale CloudKit event/decision records on
  /// the next full-state reassertion.
  static func removeSegmentData(
    _ db: Database, cutoverId: String, barrierVersion: String, deletedAt: String
  ) throws -> [CalendarCleanupRepairTarget] {
    let rows = try Row.fetchAll(
      db,
      sql: """
        SELECT id, version
        FROM calendar_events
        WHERE id = ? OR series_id = ?
        ORDER BY id
        """,
      arguments: [cutoverId, cutoverId])
    var targets: [CalendarCleanupRepairTarget] = []
    // The aggregate child is a soft reference and can arrive before its
    // calendar-event row. Always include the deterministic segment identity so
    // a deleted boundary also removes a focus block that references a segment
    // whose base payload has not materialized locally yet.
    var eventIds: [String] = [cutoverId]
    for row in rows {
      let eventId: String = row["id"]
      let eventVersion: String = row["version"]
      let deathVersion = maximumVersion(barrierVersion, eventVersion)
      eventIds.append(eventId)
      targets += try removeEventData(
        db, eventId: eventId, deathVersion: deathVersion, deletedAt: deletedAt)
    }
    targets += try removeFocusScheduleReferences(
      db, eventIds: eventIds, barrierVersion: barrierVersion,
      deletedAt: deletedAt)
    return normalized(targets)
  }

  /// Delete one event plus every synced task edge that SQLite will cascade,
  /// returning the shared records that need strict-successor Delete envelopes.
  private static func removeEventData(
    _ db: Database, eventId: String, deathVersion: String, deletedAt: String
  ) throws -> [CalendarCleanupRepairTarget] {
    let links = try Row.fetchAll(
      db,
      sql: """
        SELECT task_id, version
        FROM task_calendar_event_links
        WHERE calendar_event_id = ?
        ORDER BY task_id
        """,
      arguments: [eventId])
    var targets: [CalendarCleanupRepairTarget] = []
    for link in links {
      let taskId: String = link["task_id"]
      let edgeId = "\(taskId):\(eventId)"
      let edgeVersion: String = link["version"]
      try Tombstone.createTombstone(
        db, entityType: EdgeName.taskCalendarEventLink, entityId: edgeId,
        version: maximumVersion(deathVersion, edgeVersion), deletedAt: deletedAt)
      targets.append(
        CalendarCleanupRepairTarget(
          entityType: .taskCalendarEventLink, entityId: edgeId,
          operation: .delete))
    }
    try db.execute(sql: "DELETE FROM calendar_events WHERE id = ?", arguments: [eventId])
    try Tombstone.createTombstone(
      db, entityType: EntityName.calendarEvent, entityId: eventId,
      version: deathVersion, deletedAt: deletedAt)
    targets.append(
      CalendarCleanupRepairTarget(
        entityType: .calendarEvent, entityId: eventId, operation: .delete))
    return targets
  }

  /// Remove canonical-event blocks owned by cleaned events. `focus_schedule` is
  /// a synced aggregate, not a set of independently-synced blocks: retain and
  /// re-emit the parent when blocks remain; otherwise delete/tombstone the empty
  /// parent and propagate that Delete.
  static func removeFocusScheduleReferences(
    _ db: Database, eventIds: [String], barrierVersion: String, deletedAt: String
  ) throws -> [CalendarCleanupRepairTarget] {
    guard !eventIds.isEmpty else { return [] }
    var dates = Set<String>()
    for eventId in Set(eventIds) {
      dates.formUnion(
        try String.fetchAll(
          db,
          sql: "SELECT DISTINCT date FROM focus_schedule_blocks WHERE calendar_event_id = ?",
          arguments: [eventId]))
    }
    var targets: [CalendarCleanupRepairTarget] = []
    for date in dates.sorted() {
      let headerVersion = try String.fetchOne(
        db, sql: "SELECT version FROM focus_schedule WHERE date = ?",
        arguments: [date])
      for eventId in Set(eventIds) {
        try db.execute(
          sql: "DELETE FROM focus_schedule_blocks WHERE date = ? AND calendar_event_id = ?",
          arguments: [date, eventId])
      }
      let remaining = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE date = ?",
        arguments: [date]) ?? 0
      if remaining == 0 {
        try db.execute(sql: "DELETE FROM focus_schedule WHERE date = ?", arguments: [date])
        let deathVersion = headerVersion.map { maximumVersion(barrierVersion, $0) }
          ?? barrierVersion
        try Tombstone.createTombstone(
          db, entityType: EntityName.focusSchedule, entityId: date,
          version: deathVersion, deletedAt: deletedAt)
        targets.append(
          CalendarCleanupRepairTarget(
            entityType: .focusSchedule, entityId: date, operation: .delete))
      } else {
        targets.append(
          CalendarCleanupRepairTarget(
            entityType: .focusSchedule, entityId: date, operation: .upsert))
      }
    }
    return targets
  }

  /// Canonicalize a cleanup fan-out. Multiple removed events can touch the same
  /// schedule; a Delete dominates an Upsert for the same final identity.
  static func normalized(
    _ targets: [CalendarCleanupRepairTarget]
  ) -> [CalendarCleanupRepairTarget] {
    var byIdentity: [String: CalendarCleanupRepairTarget] = [:]
    for target in targets {
      let key = "\(target.entityType.asString)\u{0}\(target.entityId)"
      if byIdentity[key]?.operation == .delete { continue }
      byIdentity[key] = target
    }
    return byIdentity.values.sorted {
      ($0.entityType.asString, $0.entityId, $0.operation.asString)
        < ($1.entityType.asString, $1.entityId, $1.operation.asString)
    }
  }

  private static func maximumVersion(_ lhs: String, _ rhs: String) -> String {
    canonicalPreferringDominates(incoming: rhs, existing: lhs) ? rhs : lhs
  }
}
