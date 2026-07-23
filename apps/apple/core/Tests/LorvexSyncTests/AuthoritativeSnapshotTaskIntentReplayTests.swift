import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class AuthoritativeSnapshotTaskIntentReplayTests: XCTestCase {
  private let parentId = "55555555-5555-7555-8555-000000000002"
  private let groupId = "55555555-5555-7555-8555-555555555553"
  private let deviceId = "authoritative-task-replay"
  private let registry = EntityApplierRegistry(
    appliers: EntityApplierRegistry.defaultEntityAppliers())

  private var successorId: String {
    TaskRecurrenceSuccessorID.make(
      parentTaskId: parentId, recurrenceGroupId: groupId)
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

  private func version(_ physical: UInt64) throws -> Hlc {
    try Hlc(
      physicalMs: physical, counter: 0,
      deviceSuffix: "1111222233334444")
  }

  private func taskEnvelope(
    id: String, title: String, status: String, dueDate: String,
    completedAt: JSONValue, spawnedFrom: JSONValue,
    spawnedFromVersion: JSONValue, rolloverState: String,
    successorId: JSONValue, version: Hlc
  ) throws -> SyncEnvelope {
    var object: [String: JSONValue] = [
      "title": .string(title), "status": .string(status),
      "list_id": .string("inbox"), "due_date": .string(dueDate),
      "recurrence": .string("{\"FREQ\":\"DAILY\"}"),
      "recurrence_group_id": .string(groupId),
      "canonical_occurrence_date": .string(dueDate),
      "spawned_from": spawnedFrom,
      "spawned_from_version": spawnedFromVersion,
      "completed_at": completedAt,
      "content_version": .string(version.description),
      "schedule_version": .string(version.description),
      "lifecycle_version": .string(version.description),
      "archive_version": .string(version.description),
      "recurrence_rollover_state": .string(rolloverState),
      "recurrence_successor_id": successorId,
      "created_at": .string("2026-07-17T08:00:00.000Z"),
      "updated_at": .string("2026-07-17T09:00:00.000Z"),
    ]
    if case .string = spawnedFrom {
      object["recurrence_instance_key"] = .string("\(groupId):\(dueDate)")
    }
    let partial = try SyncCanonicalize.canonicalizeJSON(.object(object))
    return try SyncTestSupport.completeEnvelope(
      entityType: .task, entityId: id, operation: .upsert,
      version: version, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: partial, deviceId: deviceId)
  }

  private func deleteEnvelope(id: String, version: Hlc) throws -> SyncEnvelope {
    SyncEnvelope(
      entityType: .task, entityId: id, operation: .delete,
      version: version, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(
        .object(["version": .string(version.description)])),
      deviceId: deviceId)
  }

  private func replay(
    _ db: Database, intents: [AuthoritativeSnapshotLocalIntent]
  ) throws -> AuthoritativeSnapshotReport {
    var report = AuthoritativeSnapshotReport()
    try AuthoritativeSnapshot.replayPostSessionLocalIntents(
      db, intents: intents, registry: registry,
      hlc: HlcSession(handle: try LockedHlcHandle()),
      deviceId: deviceId, report: &report)
    return report
  }

  func testSuccessorWhoseUUIDSortsFirstReplaysAfterItsCapturedParent() throws {
    let captured = try version(1_800_000_000_100)
    XCTAssertLessThan(successorId, parentId, "fixture must reproduce the old UUID sort bug")
    let parent = try taskEnvelope(
      id: parentId, title: "Completed parent", status: "completed",
      dueDate: "2026-07-17",
      completedAt: .string("2026-07-17T09:00:00.000Z"),
      spawnedFrom: .null, spawnedFromVersion: .null,
      rolloverState: "authorized", successorId: .string(successorId),
      version: captured)
    let successor = try taskEnvelope(
      id: successorId, title: "Next occurrence", status: "open",
      dueDate: "2026-07-18", completedAt: .null,
      spawnedFrom: .string(parentId),
      spawnedFromVersion: .string(captured.description),
      rolloverState: "none", successorId: .null, version: captured)
    let intents = [
      AuthoritativeSnapshotLocalIntent(
        outboxID: nil, envelope: successor, registerIntent: .task(.all)),
      AuthoritativeSnapshotLocalIntent(
        outboxID: nil, envelope: parent, registerIntent: .task(.all)),
    ]
    let ordered = try AuthoritativeSnapshot.orderedPostSessionLocalIntents(intents)
    XCTAssertEqual(ordered.map(\.envelope.entityId), [parentId, successorId])

    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let report = try replay(db, intents: intents)
      let parent = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: "SELECT lifecycle_version, recurrence_rollover_state FROM tasks WHERE id = ?",
          arguments: [parentId]))
      let child = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: "SELECT spawned_from, spawned_from_version, status FROM tasks WHERE id = ?",
          arguments: [successorId]))
      XCTAssertEqual(parent["recurrence_rollover_state"] as String, "authorized")
      XCTAssertEqual(child["spawned_from"] as String?, parentId)
      XCTAssertEqual(
        child["spawned_from_version"] as String?,
        parent["lifecycle_version"] as String)
      XCTAssertEqual(child["status"] as String, "open")
      XCTAssertEqual(report.changedEntityTypes, [.task])
    }
  }

  func testRerootedSuccessorDoesNotAcquirePermanentDependencyOnDeletedParent() throws {
    let captured = try version(1_800_000_000_100)
    let parentDelete = try deleteEnvelope(id: parentId, version: captured)
    let rerooted = try taskEnvelope(
      id: successorId, title: "Independent edited successor", status: "open",
      dueDate: "2026-07-18", completedAt: .null,
      spawnedFrom: .null, spawnedFromVersion: .null,
      rolloverState: "none", successorId: .null, version: captured)
    let intents = [
      AuthoritativeSnapshotLocalIntent(
        outboxID: nil, envelope: parentDelete, registerIntent: .none),
      AuthoritativeSnapshotLocalIntent(
        outboxID: nil, envelope: rerooted, registerIntent: .task(.all)),
    ]
    let ordered = try AuthoritativeSnapshot.orderedPostSessionLocalIntents(intents)
    XCTAssertEqual(ordered.map(\.envelope.entityId), [successorId, parentId])

    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      _ = try replay(db, intents: intents)
      let child = try XCTUnwrap(
        try Row.fetchOne(
          db, sql: "SELECT spawned_from, spawned_from_version FROM tasks WHERE id = ?",
          arguments: [successorId]))
      XCTAssertNil(child["spawned_from"] as String?)
      XCTAssertNil(child["spawned_from_version"] as String?)
      XCTAssertNotNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.task, entityId: parentId))
    }
  }
}
