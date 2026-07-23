import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// End-to-end convergence coverage for the durable recurring-series partition.
/// These tests deliberately use the production payload registry, apply flow,
/// cleanup repair, and outbox funnel rather than calling the repository join in
/// isolation: the safety property spans all four layers.
final class CalendarSeriesCutoverSyncTests: XCTestCase {
  private let rootID = "11111111-1111-4111-8111-111111111111"
  private let otherRootID = "22222222-2222-4222-8222-222222222222"
  private let taskID = "33333333-3333-4333-8333-333333333333"
  private let deviceID = "calendar-cutover-test-device"
  private let timestamp = "2026-07-17T00:00:00.000Z"
  private let v1 = "1760000000000_0001_1111111111111111"
  private let v2 = "1760000000100_0001_2222222222222222"
  private let v3 = "1760000000200_0001_3333333333333333"
  private let v4 = "1760000000300_0001_4444444444444444"
  private let v5 = "1760000000400_0001_5555555555555555"

  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  private final class LockedHlcHandle: HlcDominatingStateHandle, @unchecked Sendable {
    private let lock = NSLock()
    private let state: HlcState

    init() throws {
      state = try HlcState(deviceSuffix: "cccccccccccccccc")
    }

    func generate() -> Hlc { generate(dominating: nil) }

    func generate(dominating floor: Hlc?) -> Hlc {
      lock.lock()
      defer { lock.unlock() }
      if let floor {
        state.updateOnReceive(remote: floor, physicalMs: 2_000_000_000_000)
      }
      return state.generate(withPhysicalMs: 2_000_000_000_000)
    }
  }

  private func parsed(_ raw: String) throws -> Hlc {
    try Hlc.parseCanonical(raw)
  }

  private func cutoverID(_ date: String, rootID: String? = nil) -> String {
    CalendarSeriesCutoverID.make(
      lineageRootId: rootID ?? self.rootID, cutoverDate: date)
  }

  private func cutoverEnvelope(
    date: String, state: CalendarSeriesCutoverState, version: String,
    rootID: String? = nil, createdAt: String? = nil, updatedAt: String? = nil
  ) throws -> SyncEnvelope {
    let lineageRootID = rootID ?? self.rootID
    let id = cutoverID(date, rootID: lineageRootID)
    let payload = try SyncCanonicalize.canonicalizeJSON(.object([
      "id": .string(id),
      "lineage_root_id": .string(lineageRootID),
      "cutover_date": .string(date),
      "state": .string(state.rawValue),
      "version": .string(version),
      "created_at": .string(createdAt ?? timestamp),
      "updated_at": .string(updatedAt ?? timestamp),
    ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .calendarSeriesCutover, entityId: id, operation: .upsert,
      version: parsed(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: deviceID)
  }

  private func cutoverDelete(date: String, version: String) throws -> SyncEnvelope {
    let id = cutoverID(date)
    return try SyncTestSupport.completeEnvelope(
      entityType: .calendarSeriesCutover, entityId: id, operation: .delete,
      version: parsed(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(
        .object(["version": .string(version)])),
      deviceId: deviceID)
  }

  private func baseEventEnvelope(
    id: String, startDate: String, version: String,
    marker: String? = nil, includeMarker: Bool = true,
    recurring: Bool = true, title: String = "Segment"
  ) throws -> SyncEnvelope {
    var object: [String: JSONValue] = [
      "title": .string(title),
      "start_date": .string(startDate),
      "start_time": .string("09:00"),
      "end_date": .string(startDate),
      "end_time": .string("10:00"),
      "all_day": .bool(false),
      "timezone": .string("UTC"),
      "event_type": .string("event"),
      "series_id": .null,
      "recurrence_instance_date": .null,
      "occurrence_state": .null,
      "recurrence": recurring ? .string(#"{"FREQ":"DAILY"}"#) : .null,
      "recurrence_generation": recurring ? .string(version) : .null,
      "recurrence_topology_version": .string(version),
      "content_version": .string(version),
      "created_at": .string(timestamp),
      "updated_at": .string(timestamp),
    ]
    if includeMarker {
      object["series_cutover_id"] = marker.map(JSONValue.string) ?? .null
    }
    let completed = try SyncTestSupport.completeEnvelope(
      entityType: .calendarEvent, entityId: id, operation: .upsert,
      version: parsed(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(object)),
      deviceId: deviceID)
    if includeMarker { return completed }
    return try removingPayloadKey("series_cutover_id", from: completed)
  }

  private func decisionEnvelope(
    ownerID: String, occurrenceDate: String, generation: String,
    version: String, title: String = "Decision"
  ) throws -> SyncEnvelope {
    let id = CalendarOccurrenceDecisionID.make(
      seriesId: ownerID, recurrenceGeneration: generation,
      recurrenceInstanceDate: occurrenceDate)
    let payload = try SyncCanonicalize.canonicalizeJSON(.object([
      "title": .string(title),
      "start_date": .string(occurrenceDate),
      "start_time": .string("11:00"),
      "end_date": .string(occurrenceDate),
      "end_time": .string("12:00"),
      "all_day": .bool(false),
      "timezone": .string("UTC"),
      "event_type": .string("event"),
      "series_cutover_id": .null,
      "series_id": .string(ownerID),
      "recurrence_instance_date": .string(occurrenceDate),
      "occurrence_state": .string(CalendarOccurrenceState.replacement.rawValue),
      "recurrence": .null,
      "recurrence_generation": .string(generation),
      "recurrence_topology_version": .null,
      "content_version": .null,
      "created_at": .string(timestamp),
      "updated_at": .string(timestamp),
    ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .calendarEvent, entityId: id, operation: .upsert,
      version: parsed(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: deviceID)
  }

  private func removingPayloadKey(
    _ key: String, from envelope: SyncEnvelope
  ) throws -> SyncEnvelope {
    guard case .object(var object)? = JSONValue.parse(envelope.payload) else {
      XCTFail("fixture payload must be an object")
      return envelope
    }
    object[key] = nil
    return SyncEnvelope(
      entityType: envelope.entityType, entityId: envelope.entityId,
      operation: envelope.operation, version: envelope.version,
      payloadSchemaVersion: envelope.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(object)),
      deviceId: envelope.deviceId)
  }

  private func replacingPayloadField(
    _ key: String, with value: JSONValue, in envelope: SyncEnvelope
  ) throws -> SyncEnvelope {
    guard case .object(var object)? = JSONValue.parse(envelope.payload) else {
      XCTFail("fixture payload must be an object")
      return envelope
    }
    object[key] = value
    return SyncEnvelope(
      entityType: envelope.entityType, entityId: envelope.entityId,
      operation: envelope.operation, version: envelope.version,
      payloadSchemaVersion: envelope.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(object)),
      deviceId: envelope.deviceId)
  }

  @discardableResult
  private func apply(_ db: Database, _ envelope: SyncEnvelope) throws -> ApplyResult {
    try Apply.applyEnvelope(db, registry: registry, envelope: envelope)
  }

  private func cleanupObligation(_ result: ApplyResult) throws
    -> (targets: [CalendarCleanupRepairTarget], floor: Hlc)
  {
    guard case .repairRequired(
      .propagateCalendarCleanup(let targets, let floor)) = result
    else {
      throw NSError(
        domain: "CalendarSeriesCutoverSyncTests", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "expected calendar cleanup repair, got \(result)"])
    }
    return (targets, floor)
  }

  private func fulfill(
    _ db: Database, result: ApplyResult, successor: String = "1760000000900_0001_9999999999999999"
  ) throws {
    guard case .repairRequired(let obligation) = result else {
      return XCTFail("expected repair obligation, got \(result)")
    }
    try ApplyRepair.fulfill(
      db, obligation: obligation, mintVersion: { _ in successor },
      deviceId: deviceID)
  }

  private func localCutover(_ db: Database, date: String) throws -> CalendarSeriesCutoverRow {
    try XCTUnwrap(CalendarSeriesCutoverRepo.fetch(db, id: cutoverID(date)))
  }

  private func pendingEnvelope(
    _ db: Database, entityType: EntityKind, entityID: String
  ) throws -> SyncEnvelope? {
    try Outbox.getPending(db).first {
      $0.envelope.entityType == entityType && $0.envelope.entityId == entityID
    }?.envelope
  }

  func testDerivedUuidV8CannotRootNestedLineage() throws {
    let derivedRoot = cutoverID("2026-08-01")
    let nested = try cutoverEnvelope(
      date: "2026-08-02", state: .active, version: v1,
      rootID: derivedRoot)
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertThrowsError(try apply(db, nested)) { error in
        guard case ApplyError.invalidPayload(let message) = error else {
          return XCTFail("nested cutover must be invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("UUIDv8"), "unexpected rejection: \(message)")
      }
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM calendar_series_cutovers"), 0)

      // Defense in depth: even a future writer that bypasses the repository
      // cannot persist a deterministic derived id as a lineage root.
      XCTAssertThrowsError(
        try db.execute(
          sql: """
            INSERT INTO calendar_series_cutovers
              (id, lineage_root_id, cutover_date, state, version, created_at, updated_at)
            VALUES (?, ?, '2026-08-02', 'active', ?, ?, ?)
            """,
          arguments: [nested.entityId, derivedRoot, v1, timestamp, timestamp]))
    }
  }

  func testDeletedStateAbsorbsStaleNewerAndEqualActiveSnapshotsAndReemitsJoin() throws {
    for (first, second) in [
      (
        try cutoverEnvelope(date: "2026-08-10", state: .active, version: v3),
        try cutoverEnvelope(date: "2026-08-10", state: .deleted, version: v1)
      ),
      (
        try cutoverEnvelope(date: "2026-08-10", state: .deleted, version: v1),
        try cutoverEnvelope(date: "2026-08-10", state: .active, version: v3)
      ),
      (
        try cutoverEnvelope(date: "2026-08-10", state: .deleted, version: v2),
        try cutoverEnvelope(date: "2026-08-10", state: .active, version: v2)
      ),
    ] {
      let store = try SyncTestSupport.freshStore()
      try store.writer.write { db in
        XCTAssertEqual(try apply(db, first), .applied)
        let result = try apply(db, second)
        XCTAssertEqual(result, .applied)
        let row = try localCutover(db, date: "2026-08-10")
        XCTAssertEqual(row.state, .deleted)
        XCTAssertEqual(row.version, max(first.version, second.version).description)

        let target = try XCTUnwrap(
          AbsencePreserveReemit.convergenceReemitTarget(db, envelope: second))
        XCTAssertEqual(target.entityType, EntityName.calendarSeriesCutover)
        XCTAssertEqual(target.entityId, row.id)
        XCTAssertEqual(
          try ConvergenceEmitter.enqueueCurrentSnapshot(
            db, entityType: target.entityType, entityId: target.entityId,
            mintVersion: { _ in self.v4 }, deviceId: self.deviceID),
          .enqueued)
        let reemit = try XCTUnwrap(
          pendingEnvelope(db, entityType: .calendarSeriesCutover, entityID: row.id))
        XCTAssertEqual(reemit.version.description, v4)
        XCTAssertTrue(reemit.payload.contains(#""state":"deleted""#))
      }
    }
  }

  func testInvalidPeerDeleteReassertsExistingCutoverAndRejectsAbsentIdentity() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(
        try apply(db, cutoverEnvelope(date: "2026-08-11", state: .active, version: v1)),
        .applied)
      let result = try apply(db, cutoverDelete(date: "2026-08-11", version: v3))
      guard case .repairRequired(
        .reassertCalendarSeriesCutover(let id, let floor)) = result
      else { return XCTFail("existing boundary must surface typed reassert repair") }
      XCTAssertEqual(id, cutoverID("2026-08-11"))
      XCTAssertEqual(floor.description, v3)
      try fulfill(db, result: result, successor: v4)

      XCTAssertNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.calendarSeriesCutover, entityId: id))
      XCTAssertEqual(try localCutover(db, date: "2026-08-11").version, v4)
      let reassert = try XCTUnwrap(
        pendingEnvelope(db, entityType: .calendarSeriesCutover, entityID: id))
      XCTAssertEqual(reassert.operation, .upsert)
      XCTAssertEqual(reassert.version.description, v4)
    }

    let absentStore = try SyncTestSupport.freshStore()
    try absentStore.writer.write { db in
      XCTAssertThrowsError(
        try apply(db, cutoverDelete(date: "2026-08-11", version: v3))) { error in
          guard case ApplyError.invalidPayload = error else {
            return XCTFail("absent invalid Delete must be invalidPayload, got \(error)")
          }
        }
    }
  }

  func testCurrentSchemaRequiresMarkerKeyAndCannotClearActiveSegmentMarker() throws {
    let date = "2026-08-12"
    let id = cutoverID(date)
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(
        try apply(db, cutoverEnvelope(date: date, state: .active, version: v1)), .applied)
      let segment = try baseEventEnvelope(
        id: id, startDate: date, version: v2, marker: id)
      XCTAssertEqual(try apply(db, segment), .applied)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT series_cutover_id FROM calendar_events WHERE id = ?",
          arguments: [id]),
        id)

      let missing = try baseEventEnvelope(
        id: id, startDate: date, version: v3,
        includeMarker: false)
      XCTAssertThrowsError(try apply(db, missing)) { error in
        guard case ApplyError.invalidPayload(let message) = error else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("series_cutover_id"))
      }

      let explicitNull = try baseEventEnvelope(
        id: id, startDate: date, version: v3,
        marker: nil, includeMarker: true)
      XCTAssertThrowsError(try apply(db, explicitNull)) { error in
        guard case ApplyError.invalidPayload(let message) = error else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("cannot clear immutable series_cutover_id"))
      }
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT series_cutover_id FROM calendar_events WHERE id = ?",
          arguments: [id]),
        id)
    }
  }

  func testMarkedSegmentCanArriveBeforeBoundaryAndDeletedBoundaryStillRemovesIt() throws {
    let date = "2026-08-13"
    let id = cutoverID(date)
    let activeStore = try SyncTestSupport.freshStore()
    try activeStore.writer.write { db in
      let segment = try baseEventEnvelope(
        id: id, startDate: date, version: v1,
        marker: id, recurring: false)
      guard case .deferred(.missingDependency(let kind, let dependencyID)) =
        try apply(db, segment)
      else { return XCTFail("segment must wait for its durable cutover") }
      XCTAssertEqual(kind, .calendarSeriesCutover)
      XCTAssertEqual(dependencyID, id)
      let result = try apply(
        db, cutoverEnvelope(date: date, state: .active, version: v2))
      XCTAssertEqual(result, .applied)
      XCTAssertEqual(try apply(db, segment), .applied)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT series_cutover_id FROM calendar_events WHERE id = ?",
          arguments: [id]), id)
    }

    let deletedStore = try SyncTestSupport.freshStore()
    try deletedStore.writer.write { db in
      let segment = try baseEventEnvelope(
        id: id, startDate: date, version: v1, marker: id)
      guard case .deferred = try apply(db, segment) else {
        return XCTFail("segment must wait for its durable cutover")
      }
      XCTAssertEqual(
        try apply(db, cutoverEnvelope(date: date, state: .deleted, version: v2)),
        .applied)
      let result = try apply(db, segment)
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM calendar_events WHERE id = ?", arguments: [id]))
      try fulfill(db, result: result, successor: v3)
      let deletion = try XCTUnwrap(
        pendingEnvelope(db, entityType: .calendarEvent, entityID: id))
      XCTAssertEqual(deletion.operation, .delete)
      XCTAssertEqual(deletion.version.description, v3)
      XCTAssertGreaterThan(deletion.version, try parsed(v2))
    }
  }

  func testDecisionBeforeAndAfterBoundaryIsTerminallyRemovedOutsideOwnedInterval() throws {
    let date = "2026-08-14"
    let generation = v1
    let occurrence = "2026-08-15"
    let decision = try decisionEnvelope(
      ownerID: rootID, occurrenceDate: occurrence,
      generation: generation, version: v2)

    let beforeStore = try SyncTestSupport.freshStore()
    try beforeStore.writer.write { db in
      XCTAssertEqual(try apply(db, decision), .applied)
      let result = try apply(
        db, cutoverEnvelope(date: date, state: .active, version: v3))
      let repair = try cleanupObligation(result)
      XCTAssertTrue(
        repair.targets.contains(
          CalendarCleanupRepairTarget(
            entityType: .calendarEvent, entityId: decision.entityId,
            operation: .delete)))
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM calendar_events WHERE id = ?",
          arguments: [decision.entityId]))
      try fulfill(db, result: result, successor: v4)
      XCTAssertEqual(
        try pendingEnvelope(
          db, entityType: .calendarEvent, entityID: decision.entityId)?.operation,
        .delete)
    }

    let afterStore = try SyncTestSupport.freshStore()
    try afterStore.writer.write { db in
      XCTAssertEqual(
        try apply(db, cutoverEnvelope(date: date, state: .active, version: v1)),
        .applied)
      let result = try apply(db, decision)
      let repair = try cleanupObligation(result)
      XCTAssertEqual(repair.floor.description, v2)
      XCTAssertTrue(
        repair.targets.contains(
          CalendarCleanupRepairTarget(
            entityType: .calendarEvent, entityId: decision.entityId,
            operation: .delete)))
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM calendar_events WHERE id = ?",
          arguments: [decision.entityId]))
    }
  }

  func testOutOfOrderD3DecisionForUnknownD2IsRemovedWhenD2Arrives() throws {
    let d2Date = "2026-08-12"
    let d3Date = "2026-08-14"
    let d2ID = cutoverID(d2Date)
    let decision = try decisionEnvelope(
      ownerID: d2ID, occurrenceDate: "2026-08-15",
      generation: v1, version: v3)
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(
        try apply(db, cutoverEnvelope(date: d3Date, state: .active, version: v1)),
        .applied)
      // D2 is not yet in the relation, so the receiver cannot classify the
      // owner and must temporarily retain the decision.
      XCTAssertEqual(try apply(db, decision), .applied)
      XCTAssertNotNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM calendar_events WHERE id = ?",
          arguments: [decision.entityId]))

      let result = try apply(
        db, cutoverEnvelope(date: d2Date, state: .active, version: v4))
      let repair = try cleanupObligation(result)
      XCTAssertTrue(
        repair.targets.contains(
          CalendarCleanupRepairTarget(
            entityType: .calendarEvent, entityId: decision.entityId,
            operation: .delete)))
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM calendar_events WHERE id = ?",
          arguments: [decision.entityId]))
    }
  }

  func testDeletedSegmentCleanupPropagatesEventEdgeAndFocusAggregateMutations() throws {
    let date = "2026-08-16"
    let segmentID = cutoverID(date)
    let keepDate = "2026-08-17"
    let emptyDate = "2026-08-18"
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(
        try apply(db, cutoverEnvelope(date: date, state: .active, version: v1)), .applied)
      XCTAssertEqual(
        try apply(
          db,
          baseEventEnvelope(
            id: segmentID, startDate: date, version: v2,
            marker: segmentID, recurring: false)),
        .applied)
      try db.execute(
        sql: """
          INSERT INTO tasks (id, list_id, title, status, version, created_at, updated_at)
          VALUES (?, 'inbox', 'Linked task', 'open', ?, ?, ?)
          """,
        arguments: [taskID, v1, timestamp, timestamp])
      try db.execute(
        sql: """
          INSERT INTO task_calendar_event_links
            (task_id, calendar_event_id, version, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [taskID, segmentID, v2, timestamp, timestamp])
      for planDate in [keepDate, emptyDate] {
        try db.execute(
          sql: """
            INSERT INTO focus_schedule (date, rationale, timezone, version, created_at, updated_at)
            VALUES (?, 'Plan', 'UTC', ?, ?, ?)
            """,
          arguments: [planDate, v2, timestamp, timestamp])
        try db.execute(
          sql: """
            INSERT INTO focus_schedule_blocks
              (date, position, block_type, start_minutes, end_minutes,
               calendar_event_id, event_source, title)
            VALUES (?, 0, 'event', 540, 600, ?, 'canonical', 'Segment')
            """,
          arguments: [planDate, segmentID])
      }
      try db.execute(
        sql: """
          INSERT INTO focus_schedule_blocks
            (date, position, block_type, start_minutes, end_minutes, title)
          VALUES (?, 1, 'buffer', 600, 630, 'Keep')
          """,
        arguments: [keepDate])

      let result = try apply(
        db, cutoverEnvelope(date: date, state: .deleted, version: v3))
      let repair = try cleanupObligation(result)
      XCTAssertEqual(
        Set(repair.targets.map { "\($0.entityType.asString)|\($0.entityId)|\($0.operation.asString)" }),
        Set([
          "calendar_event|\(segmentID)|delete",
          "task_calendar_event_link|\(taskID):\(segmentID)|delete",
          "focus_schedule|\(keepDate)|upsert",
          "focus_schedule|\(emptyDate)|delete",
        ]))
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE date = ?",
          arguments: [keepDate]), 1)
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT date FROM focus_schedule WHERE date = ?",
          arguments: [emptyDate]))

      try fulfill(db, result: result, successor: v5)
      let pending = try Outbox.getPending(db).map(\.envelope)
      func envelope(_ kind: EntityKind, _ id: String) -> SyncEnvelope? {
        pending.first { $0.entityType == kind && $0.entityId == id }
      }
      XCTAssertEqual(envelope(.calendarEvent, segmentID)?.operation, .delete)
      XCTAssertEqual(
        envelope(.taskCalendarEventLink, "\(taskID):\(segmentID)")?.operation, .delete)
      XCTAssertEqual(envelope(.focusSchedule, keepDate)?.operation, .upsert)
      XCTAssertEqual(envelope(.focusSchedule, emptyDate)?.operation, .delete)
      for repaired in pending {
        XCTAssertEqual(repaired.version.description, v5)
        XCTAssertGreaterThan(repaired.version, try parsed(v3))
      }
      XCTAssertFalse(
        try XCTUnwrap(envelope(.focusSchedule, keepDate)).payload.contains(segmentID))
    }
  }

  func testDeletedBoundaryCleansSoftFocusReferenceEvenWhenSegmentNeverArrived() throws {
    let date = "2026-08-19"
    let segmentID = cutoverID(date)
    let planDate = "2026-08-20"
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO focus_schedule (date, timezone, version, created_at, updated_at)
          VALUES (?, 'UTC', ?, ?, ?)
          """,
        arguments: [planDate, v1, timestamp, timestamp])
      try db.execute(
        sql: """
          INSERT INTO focus_schedule_blocks
            (date, position, block_type, start_minutes, end_minutes,
             calendar_event_id, event_source, title)
          VALUES (?, 0, 'event', 540, 600, ?, 'canonical', 'Not arrived')
          """,
        arguments: [planDate, segmentID])

      let result = try apply(
        db, cutoverEnvelope(date: date, state: .deleted, version: v2))
      let repair = try cleanupObligation(result)
      XCTAssertTrue(
        repair.targets.contains(
          CalendarCleanupRepairTarget(
            entityType: .focusSchedule, entityId: planDate,
            operation: .delete)))
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT date FROM focus_schedule WHERE date = ?",
          arguments: [planDate]))
    }
  }

  func testBoundaryIdentityRemovesLegacyDecisionOccupyingSegmentID() throws {
    let date = "2026-08-21"
    let segmentID = cutoverID(date)
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      // The production applier rejects this deterministic-id mismatch. Seed it
      // as a legacy/corrupt persisted row to prove the durable boundary owns its
      // identity even when the decision belongs to an unrelated series.
      try db.execute(
        sql: """
          INSERT INTO calendar_events
            (id, title, start_date, start_time, end_date, end_time, all_day,
             event_type, series_id, recurrence_instance_date, occurrence_state,
             recurrence_generation, version, created_at, updated_at)
          VALUES (?, 'Hostile legacy decision', ?, '09:00', ?, '10:00', 0,
                  'event', ?, ?, 'replacement', ?, ?, ?, ?)
          """,
        arguments: [
          segmentID, date, date, otherRootID, date, v1, v1, timestamp, timestamp,
        ])

      let result = try apply(
        db, cutoverEnvelope(date: date, state: .active, version: v2))
      let repair = try cleanupObligation(result)
      XCTAssertTrue(
        repair.targets.contains(
          CalendarCleanupRepairTarget(
            entityType: .calendarEvent, entityId: segmentID,
            operation: .delete)))
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM calendar_events WHERE id = ?",
          arguments: [segmentID]))
    }
  }

  func testAuthoritativeAbsencePromotesAndReemitsPermanentCutover() throws {
    let date = "2026-08-22"
    let id = cutoverID(date)
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(
        try apply(db, cutoverEnvelope(date: date, state: .deleted, version: v2)),
        .applied)
      let intents = try AuthoritativeSnapshot.includingAbsentAuthoritativeDependencies(
        db, intents: [], authoritativeLiveRecordNames: [], deviceId: deviceID)
      XCTAssertEqual(intents.count, 1)
      XCTAssertNil(intents[0].outboxID)
      XCTAssertEqual(intents[0].envelope.entityType, .calendarSeriesCutover)
      XCTAssertEqual(intents[0].envelope.entityId, id)
      XCTAssertEqual(intents[0].envelope.operation, .upsert)
      XCTAssertTrue(intents[0].envelope.payload.contains(#""state":"deleted""#))

      var report = AuthoritativeSnapshotReport()
      try AuthoritativeSnapshot.replayPostSessionLocalIntents(
        db, intents: intents, registry: registry,
        hlc: HlcSession(handle: try LockedHlcHandle()),
        deviceId: deviceID, report: &report)
      let reemit = try XCTUnwrap(
        pendingEnvelope(db, entityType: .calendarSeriesCutover, entityID: id))
      XCTAssertEqual(reemit.operation, .upsert)
      XCTAssertGreaterThan(reemit.version, try parsed(v2))
      XCTAssertEqual(try localCutover(db, date: date).state, .deleted)
      XCTAssertTrue(report.changedEntityTypes.contains(.calendarSeriesCutover))
    }
  }

  func testCutoverTimestampsMustBeCanonicalAndMonotonic() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let canonical = try cutoverEnvelope(
        date: "2026-08-23", state: .active, version: v1,
        createdAt: timestamp, updatedAt: timestamp)
      let noncanonical = try replacingPayloadField(
        "created_at", with: .string("2026-07-17T00:00:00Z"), in: canonical)
      XCTAssertThrowsError(try apply(db, noncanonical))

      let reversed = try cutoverEnvelope(
        date: "2026-08-24", state: .active, version: v1,
        createdAt: "2026-07-18T00:00:00.000Z",
        updatedAt: "2026-07-17T00:00:00.000Z")
      XCTAssertThrowsError(try apply(db, reversed))
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM calendar_series_cutovers"), 0)
    }
  }
}
