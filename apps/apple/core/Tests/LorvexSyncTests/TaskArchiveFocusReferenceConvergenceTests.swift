import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Task archive is an absorbing boundary for both task-bearing day-plan roots,
/// independent of CloudKit arrival order.
final class TaskArchiveFocusReferenceConvergenceTests: XCTestCase {
  private let taskId = "88888888-8888-4888-8888-888888888881"
  private let currentDate = "2026-08-06"
  private let planDate = "2026-08-07"
  private let timestamp = "2026-08-06T12:00:00.000Z"
  private let v1 = "1760000020000_0001_1111111111111111"
  private let v2 = "1760000020100_0001_2222222222222222"
  private let v3 = "1760000020200_0001_3333333333333333"
  private let deviceId = "88888888-8888-4888-8888-888888888899"
  private let registry = EntityApplierRegistry(
    appliers: EntityApplierRegistry.defaultEntityAppliers())

  func testArchiveAfterDayRootsRemovesAndReemitsBothRoots() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(try apply(db, taskEnvelope(archived: false)), .applied)
      XCTAssertEqual(try apply(db, currentFocusEnvelope()), .applied)
      XCTAssertEqual(try apply(db, focusScheduleEnvelope()), .applied)

      let repair = try taskRepair(try apply(db, taskEnvelope(archived: true)))
      let floor = try Hlc.parseCanonical(v2)
      XCTAssertTrue(
        repair.targets.contains(
          .relatedEntity(
            entityType: .currentFocus, entityId: currentDate,
            operation: .delete, knownVersionFloor: floor)))
      XCTAssertTrue(
        repair.targets.contains(
          .relatedEntity(
            entityType: .focusSchedule, entityId: planDate,
            operation: .delete, knownVersionFloor: floor)))
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT date FROM current_focus WHERE date = ?1",
          arguments: [currentDate]))
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT date FROM focus_schedule WHERE date = ?1",
          arguments: [planDate]))

      try fulfill(db, obligation: repair.obligation)
      XCTAssertEqual(try pending(db, kind: .currentFocus, id: currentDate)?.operation, .delete)
      XCTAssertEqual(try pending(db, kind: .focusSchedule, id: planDate)?.operation, .delete)
    }
  }

  func testDayRootsAfterArchiveCannotRestoreArchivedReferences() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(try apply(db, taskEnvelope(archived: true)), .applied)

      let currentRepair = try taskRepair(try apply(db, currentFocusEnvelope()))
      XCTAssertEqual(
        currentRepair.targets,
        [
          .relatedEntity(
            entityType: .currentFocus, entityId: currentDate,
            operation: .delete, knownVersionFloor: try Hlc.parseCanonical(v2))
        ])
      try fulfill(db, obligation: currentRepair.obligation)

      let scheduleRepair = try taskRepair(try apply(db, focusScheduleEnvelope()))
      XCTAssertEqual(
        scheduleRepair.targets,
        [
          .relatedEntity(
            entityType: .focusSchedule, entityId: planDate,
            operation: .delete, knownVersionFloor: try Hlc.parseCanonical(v2))
        ])
      try fulfill(db, obligation: scheduleRepair.obligation)

      XCTAssertNotNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.currentFocus, entityId: currentDate))
      XCTAssertNotNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.focusSchedule, entityId: planDate))
    }
  }

  func testHardDeleteAfterDayRootsRemovesAndReemitsBothRoots() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(try apply(db, taskEnvelope(archived: false)), .applied)
      XCTAssertEqual(try apply(db, currentFocusEnvelope()), .applied)
      XCTAssertEqual(try apply(db, focusScheduleEnvelope()), .applied)

      let repair = try taskRepair(try apply(db, taskDeleteEnvelope()))
      let floor = try Hlc.parseCanonical(v2)
      XCTAssertTrue(
        repair.targets.contains(
          .relatedEntity(
            entityType: .currentFocus, entityId: currentDate,
            operation: .delete, knownVersionFloor: floor)))
      XCTAssertTrue(
        repair.targets.contains(
          .relatedEntity(
            entityType: .focusSchedule, entityId: planDate,
            operation: .delete, knownVersionFloor: floor)))
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT date FROM current_focus WHERE date = ?1",
          arguments: [currentDate]))
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT date FROM focus_schedule WHERE date = ?1",
          arguments: [planDate]))
      XCTAssertNotNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.task, entityId: taskId))

      try fulfill(db, obligation: repair.obligation)
      XCTAssertEqual(try pending(db, kind: .currentFocus, id: currentDate)?.operation, .delete)
      XCTAssertEqual(try pending(db, kind: .focusSchedule, id: planDate)?.operation, .delete)
    }
  }

  func testHardDeletePreservesAndReemitsNonemptyDayRoots() throws {
    let survivingTaskId = "88888888-8888-4888-8888-888888888882"
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(try apply(db, taskEnvelope(archived: false)), .applied)
      XCTAssertEqual(
        try apply(db, taskEnvelope(id: survivingTaskId, archived: false)), .applied)
      XCTAssertEqual(
        try apply(db, currentFocusEnvelope(taskIds: [taskId, survivingTaskId])), .applied)
      XCTAssertEqual(
        try apply(db, focusScheduleEnvelope(taskIds: [taskId, survivingTaskId])), .applied)

      let repair = try taskRepair(try apply(db, taskDeleteEnvelope()))
      let floor = try Hlc.parseCanonical(v2)
      XCTAssertTrue(
        repair.targets.contains(
          .relatedEntity(
            entityType: .currentFocus, entityId: currentDate,
            operation: .upsert, knownVersionFloor: floor)))
      XCTAssertTrue(
        repair.targets.contains(
          .relatedEntity(
            entityType: .focusSchedule, entityId: planDate,
            operation: .upsert, knownVersionFloor: floor)))
      XCTAssertEqual(
        try String.fetchAll(
          db,
          sql: "SELECT task_id FROM current_focus_items WHERE date = ?1 ORDER BY position",
          arguments: [currentDate]),
        [survivingTaskId])
      XCTAssertEqual(
        try String.fetchAll(
          db,
          sql:
            "SELECT task_id FROM focus_schedule_blocks "
            + "WHERE date = ?1 AND task_id IS NOT NULL ORDER BY position",
          arguments: [planDate]),
        [survivingTaskId])

      try fulfill(db, obligation: repair.obligation)
      let current = try XCTUnwrap(pending(db, kind: .currentFocus, id: currentDate))
      let schedule = try XCTUnwrap(pending(db, kind: .focusSchedule, id: planDate))
      XCTAssertEqual(current.operation, .upsert)
      XCTAssertEqual(schedule.operation, .upsert)
      XCTAssertTrue(current.payload.contains(survivingTaskId))
      XCTAssertFalse(current.payload.contains(taskId))
      XCTAssertTrue(schedule.payload.contains(survivingTaskId))
      XCTAssertFalse(schedule.payload.contains(taskId))
    }
  }

  func testDayRootsAfterHardDeleteCannotRestoreDeletedReferences() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(try apply(db, taskEnvelope(archived: false)), .applied)
      XCTAssertEqual(try apply(db, taskDeleteEnvelope()), .applied)

      let currentRepair = try taskRepair(try apply(db, currentFocusEnvelope()))
      XCTAssertEqual(
        currentRepair.targets,
        [
          .relatedEntity(
            entityType: .currentFocus, entityId: currentDate,
            operation: .delete, knownVersionFloor: try Hlc.parseCanonical(v2))
        ])
      try fulfill(db, obligation: currentRepair.obligation)

      let scheduleRepair = try taskRepair(try apply(db, focusScheduleEnvelope()))
      XCTAssertEqual(
        scheduleRepair.targets,
        [
          .relatedEntity(
            entityType: .focusSchedule, entityId: planDate,
            operation: .delete, knownVersionFloor: try Hlc.parseCanonical(v2))
        ])
      try fulfill(db, obligation: scheduleRepair.obligation)

      XCTAssertNotNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.currentFocus, entityId: currentDate))
      XCTAssertNotNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.focusSchedule, entityId: planDate))
    }
  }

  func testMissingTaskWithoutTombstoneRemainsASoftReference() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(try apply(db, currentFocusEnvelope()), .applied)
      XCTAssertEqual(try apply(db, focusScheduleEnvelope()), .applied)

      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: "SELECT task_id FROM current_focus_items WHERE date = ?1",
          arguments: [currentDate]),
        taskId)
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: "SELECT task_id FROM focus_schedule_blocks WHERE date = ?1",
          arguments: [planDate]),
        taskId)
    }
  }

  private func apply(_ db: Database, _ envelope: SyncEnvelope) throws -> ApplyResult {
    try Apply.applyEnvelope(db, registry: registry, envelope: envelope)
  }

  private func taskRepair(
    _ result: ApplyResult
  ) throws -> (targets: [TaskGraphRepairTarget], obligation: ApplyRepairObligation) {
    guard case .repairRequired(let obligation) = result,
      case .propagateTaskRollover(let targets, _) = obligation
    else {
      XCTFail("expected task-graph repair, got \(result)")
      throw NSError(domain: "TaskArchiveFocusReferenceConvergenceTests", code: 1)
    }
    return (targets, obligation)
  }

  private func fulfill(_ db: Database, obligation: ApplyRepairObligation) throws {
    var counter = 0
    try ApplyRepair.fulfill(
      db, obligation: obligation,
      mintVersion: { _ in
        defer { counter += 1 }
        return String(format: "1760000029000_%04d_eeeeeeeeeeeeeeee", counter)
      },
      deviceId: deviceId)
  }

  private func pending(
    _ db: Database, kind: EntityKind, id: String
  ) throws -> SyncEnvelope? {
    try Outbox.getPending(db).first {
      $0.envelope.entityType == kind && $0.envelope.entityId == id
    }?.envelope
  }

  private func taskEnvelope(archived: Bool) throws -> SyncEnvelope {
    try taskEnvelope(id: taskId, archived: archived)
  }

  private func taskEnvelope(id: String, archived: Bool) throws -> SyncEnvelope {
    let version = archived ? v3 : v1
    return try SyncTestSupport.completeEnvelope(
      entityType: .task, entityId: id, operation: .upsert,
      version: Hlc.parse(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(
        .object([
          "title": .string("Task"), "status": .string("open"),
          "archived_at": archived ? .string(timestamp) : .null,
          "content_version": .string(v1), "schedule_version": .string(v1),
          "lifecycle_version": .string(v1), "archive_version": .string(version),
          "created_at": .string(timestamp), "updated_at": .string(timestamp),
        ])),
      deviceId: deviceId)
  }

  private func taskDeleteEnvelope() throws -> SyncEnvelope {
    return try SyncTestSupport.completeEnvelope(
      entityType: .task, entityId: taskId, operation: .delete,
      version: Hlc.parse(v3), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(
        .object(["version": .string(v3)])),
      deviceId: deviceId)
  }

  private func currentFocusEnvelope() throws -> SyncEnvelope {
    try currentFocusEnvelope(taskIds: [taskId])
  }

  private func currentFocusEnvelope(taskIds: [String]) throws -> SyncEnvelope {
    try SyncTestSupport.completeEnvelope(
      entityType: .currentFocus, entityId: currentDate, operation: .upsert,
      version: Hlc.parse(v2), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(
        .object([
          "date": .string(currentDate), "briefing": .string("Focus"),
          "timezone": .string("UTC"), "task_ids": .array(taskIds.map(JSONValue.string)),
          "created_at": .string(timestamp), "updated_at": .string(timestamp),
        ])),
      deviceId: deviceId)
  }

  private func focusScheduleEnvelope() throws -> SyncEnvelope {
    try focusScheduleEnvelope(taskIds: [taskId])
  }

  private func focusScheduleEnvelope(taskIds: [String]) throws -> SyncEnvelope {
    let blocks = taskIds.enumerated().map { index, id in
      JSONValue.object([
        "block_type": .string("task"), "start_minutes": .int(Int64(540 + index * 60)),
        "end_minutes": .int(Int64(600 + index * 60)), "task_id": .string(id),
        "calendar_event_id": .null, "event_source": .null, "title": .string("Task"),
      ])
    }
    return try SyncTestSupport.completeEnvelope(
      entityType: .focusSchedule, entityId: planDate, operation: .upsert,
      version: Hlc.parse(v2), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(
        .object([
          "date": .string(planDate), "rationale": .string("Schedule"),
          "timezone": .string("UTC"),
          "blocks": .array(blocks),
          "created_at": .string(timestamp), "updated_at": .string(timestamp),
        ])),
      deviceId: deviceId)
  }
}
