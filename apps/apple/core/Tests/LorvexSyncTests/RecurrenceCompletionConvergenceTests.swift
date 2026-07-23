import GRDB
import LorvexDomain
import LorvexWorkflow
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Cross-device convergence for COMPLETION-anchored recurring successors.
///
/// Two devices can compute different completion-anchored dates, but successor
/// identity is deterministic from the parent and recurrence group. Grouped
/// schedule joining therefore resolves the date/key disagreement on one row;
/// there is no second identity to merge or redirect.
final class RecurrenceCompletionConvergenceTests: XCTestCase {
  private func tid(_ s: String) -> TaskId { TaskId(trusted: s) }

  private static let parentId = "00000000-0000-7000-8000-000000000ac1"
  private static let groupId = "00000000-0000-7000-8000-000000000ac2"
  private static let recurrence = #"{"ANCHOR":"completion","FREQ":"WEEKLY","INTERVAL":1}"#

  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  /// Anchor `todayYmd` to UTC so the completion day (and thus the spawned due
  /// date + instance key) is deterministic regardless of the host timezone.
  private func seedUtcTimezone(_ store: LorvexStore) throws {
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO preferences (key, value, version, updated_at) "
          + "VALUES ('timezone', '\"UTC\"', "
          + "        '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00.000Z')")
    }
  }

  private func seedCompletionAnchoredParent(_ store: LorvexStore) throws {
    try store.writer.write { db in
      try db.execute(
        sql:
          "INSERT INTO tasks ("
          + "id, title, status, list_id, due_date, canonical_occurrence_date, "
          + "recurrence, recurrence_group_id, version, created_at, updated_at"
          + ") VALUES (?1, 'Water the plant', 'open', 'inbox', '2026-03-15', '2026-03-15', "
          + "?2, ?3, '0000000000000_0000_0000000000000abc', "
          + "'2026-03-10T00:00:00.000Z', '2026-03-10T00:00:00.000Z')",
        arguments: [Self.parentId, Self.recurrence, Self.groupId])
    }
  }

  private func complete(_ store: LorvexStore, now: String, version: String) throws -> String {
    let result = try store.writer.write { db in
      try LifecycleTransitions.applyCompletionTransition(
        db, taskId: tid(Self.parentId), now: now, reminderVersion: version)
    }
    XCTAssertTrue(result.updated)
    return try XCTUnwrap(result.spawnedSuccessorId)
  }

  private func instanceKey(_ store: LorvexStore, _ taskId: String) throws -> String? {
    try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT recurrence_instance_key FROM tasks WHERE id = ?", arguments: [taskId])
    }
  }

  private func projectTaskEnvelope(
    _ store: LorvexStore, taskId: String, deviceId: String
  ) throws -> SyncEnvelope {
    let projection = try store.writer.read { db -> (payload: String, version: Hlc) in
      let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.task, entityId: taskId)
      let rawVersion = try XCTUnwrap(
        try String.fetchOne(
          db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [taskId]))
      return (
        try SyncCanonicalize.canonicalizeJSON(payload),
        try Hlc.parseCanonical(rawVersion)
      )
    }
    return SyncEnvelope(
      entityType: .task, entityId: taskId, operation: .upsert,
      version: projection.version,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: projection.payload, deviceId: deviceId)
  }

  private func applyEnvelope(
    _ store: LorvexStore, _ envelope: SyncEnvelope
  ) throws -> ApplyResult {
    try store.writer.write { db in
      try Apply.applyEnvelope(db, registry: self.registry, envelope: envelope)
    }
  }

  private func taskPayload(_ store: LorvexStore, taskId: String) throws -> JSONValue {
    try store.writer.read { db in
      try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.task, entityId: taskId)
    }
  }

  private func openSuccessorIds(_ store: LorvexStore) throws -> [String] {
    try store.writer.read { db in
      try String.fetchAll(
        db,
        sql:
          "SELECT id FROM tasks WHERE spawned_from = ? AND status = 'open' ORDER BY id ASC",
        arguments: [Self.parentId])
    }
  }

  func testCompletionAnchoredSuccessorsConvergeAcrossDevices() throws {
    let storeA = try SyncTestSupport.freshStore()
    let storeB = try SyncTestSupport.freshStore()
    for store in [storeA, storeB] {
      try seedUtcTimezone(store)
      try seedCompletionAnchoredParent(store)
    }

    // Two devices complete the SAME occurrence offline on DIFFERENT days: the
    // successors land on completion + 7 days, so their instance keys differ.
    let versionA = "1711000000000_0000_dec0000a00000001"
    let versionB = "1711400000000_0000_dec0000b00000002"
    let sA = try complete(storeA, now: "2026-03-20T10:00:00.000Z", version: versionA)
    let sB = try complete(storeB, now: "2026-03-24T10:00:00.000Z", version: versionB)
    XCTAssertEqual(
      sA,
      TaskRecurrenceSuccessorID.make(
        parentTaskId: Self.parentId, recurrenceGroupId: Self.groupId))
    XCTAssertEqual(sA, sB)

    let keyA = try instanceKey(storeA, sA)
    let keyB = try instanceKey(storeB, sB)
    XCTAssertEqual(keyA, "\(Self.groupId):2026-03-27")
    XCTAssertEqual(keyB, "\(Self.groupId):2026-03-31")
    XCTAssertNotEqual(keyA, keyB)

    let parentA = try projectTaskEnvelope(
      storeA, taskId: Self.parentId, deviceId: "device-a")
    let parentB = try projectTaskEnvelope(
      storeB, taskId: Self.parentId, deviceId: "device-b")
    let successorA = try projectTaskEnvelope(storeA, taskId: sA, deviceId: "device-a")
    let successorB = try projectTaskEnvelope(storeB, taskId: sB, deviceId: "device-b")

    _ = try applyEnvelope(storeA, parentB)
    _ = try applyEnvelope(storeB, parentA)
    _ = try applyEnvelope(storeA, successorB)
    XCTAssertEqual(
      try applyEnvelope(storeB, successorA),
      .repairRequired(
        .propagateTaskRollover(
          targets: [.taskUpsert(taskId: sA, registerIntent: [])],
          additionalFloor: try Hlc.parseCanonical(versionA))))

    XCTAssertEqual(
      try openSuccessorIds(storeA), [sA],
      "store A must retain one deterministic completion-anchored successor")
    XCTAssertEqual(
      try openSuccessorIds(storeB), [sA],
      "store B must retain one deterministic completion-anchored successor")
    XCTAssertEqual(try taskPayload(storeA, taskId: sA), try taskPayload(storeB, taskId: sA))
    if case .repairRequired = try applyEnvelope(storeB, successorA) {
      XCTFail("replaying the already-joined earlier timestamp must not loop a root repair")
    }

    for store in [storeA, storeB] {
      try store.writer.read { db in
        XCTAssertEqual(
          try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM sync_entity_redirects WHERE source_type = 'task'"),
          0)
        XCTAssertEqual(
          try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = 'task'"),
          0)
      }
    }
  }
}
