import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class TaskRegisterLocalIntentReplayTests: XCTestCase {
  private let taskID = "01966a3f-7c8b-7d4e-8f3a-00000000f201"
  private let deviceID = "task-register-replay-device"
  private let registry = EntityApplierRegistry(
    appliers: EntityApplierRegistry.defaultEntityAppliers())

  private func version(_ physical: UInt64, suffix: String = "1111222233334444") throws -> Hlc {
    try Hlc(physicalMs: physical, counter: 0, deviceSuffix: suffix)
  }

  private func recurringTaskEnvelope(
    id: String, title: String, status: String, dueDate: String,
    completedAt: JSONValue, recurrenceGroupId: String,
    spawnedFrom: JSONValue = .null, spawnedFromVersion: JSONValue = .null,
    contentVersion: Hlc, scheduleVersion: Hlc, lifecycleVersion: Hlc,
    archiveVersion: Hlc, rolloverState: String,
    successorId: JSONValue = .null, rowVersion: Hlc
  ) throws -> SyncEnvelope {
    var object: [String: JSONValue] = [
      "title": .string(title), "status": .string(status),
      "list_id": .string("inbox"), "due_date": .string(dueDate),
      "recurrence": .string("{\"FREQ\":\"DAILY\"}"),
      "recurrence_group_id": .string(recurrenceGroupId),
      "canonical_occurrence_date": .string(dueDate),
      "spawned_from": spawnedFrom,
      "spawned_from_version": spawnedFromVersion,
      "completed_at": completedAt,
      "content_version": .string(contentVersion.description),
      "schedule_version": .string(scheduleVersion.description),
      "lifecycle_version": .string(lifecycleVersion.description),
      "archive_version": .string(archiveVersion.description),
      "recurrence_rollover_state": .string(rolloverState),
      "recurrence_successor_id": successorId,
      "created_at": .string("2026-07-17T08:00:00.000Z"),
      "updated_at": .string("2026-07-17T09:00:00.000Z"),
    ]
    if case .string = spawnedFrom {
      object["recurrence_instance_key"] = .string("\(recurrenceGroupId):\(dueDate)")
    }
    let partial = try SyncCanonicalize.canonicalizeJSON(.object(object))
    return try SyncTestSupport.completeEnvelope(
      entityType: .task, entityId: id, operation: .upsert,
      version: rowVersion, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: partial, deviceId: deviceID)
  }

  func testInferenceAndRawEncodingCoverAllTaskRegisterCombinations() throws {
    let older = try version(1_800_000_000_100)
    let row = try version(1_800_000_000_200)
    let payload: JSONValue = .object([
      "version": .string(row.description),
      "content_version": .string(row.description),
      "schedule_version": .string(older.description),
      "lifecycle_version": .string(row.description),
      "archive_version": .string(older.description),
    ])

    XCTAssertEqual(
      TaskRegisterIntent.inferredLocalMutation(from: payload),
      [.content, .lifecycle])
    XCTAssertEqual(
      EntityRegisterIntent.task([.content, .lifecycle]).rawValue,
      TaskRegisterIntent.content.rawValue | TaskRegisterIntent.lifecycle.rawValue)
  }

  func testTaskIntentRetentionTracksRegisterBytesRatherThanTransportVersion() throws {
    let contentVersion = try version(1_800_000_000_100)
    let firstTransport = try version(1_800_000_000_200)
    let secondTransport = try version(1_800_000_000_300)
    let first = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "title": .string("Local title"),
        "body": .null, "raw_input": .null, "ai_notes": .null,
        "list_id": .string("inbox"), "priority": .null,
        "content_version": .string(contentVersion.description),
        "version": .string(firstTransport.description),
      ]))
    let sameContent = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "title": .string("Local title"),
        "body": .null, "raw_input": .null, "ai_notes": .null,
        "list_id": .string("inbox"), "priority": .null,
        "content_version": .string(contentVersion.description),
        "version": .string(secondTransport.description),
      ]))
    let changedContent = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "title": .string("Different title"),
        "body": .null, "raw_input": .null, "ai_notes": .null,
        "list_id": .string("inbox"), "priority": .null,
        "content_version": .string(contentVersion.description),
        "version": .string(secondTransport.description),
      ]))

    XCTAssertEqual(
      TaskRegisterIntent.content.retainingUnchangedRegisters(
        existingPayload: first, replacementPayload: sameContent),
      .content)
    XCTAssertEqual(
      TaskRegisterIntent.content.retainingUnchangedRegisters(
        existingPayload: first, replacementPayload: changedContent),
      [])
  }

  func testFutureLwwTaskRepairRestagesSurvivingContentIntent() throws {
    let store = try SyncTestSupport.freshStore()
    let base = try version(1_800_000_000_100, suffix: "aaaaaaaaaaaaaaaa")
    let completion = try version(1_800_000_000_200, suffix: "aaaaaaaaaaaaaaaa")
    let localContent = try version(1_800_000_000_300, suffix: "bbbbbbbbbbbbbbbb")
    let remoteReopen = try version(1_800_000_000_400, suffix: "cccccccccccccccc")
    let groupId = "01966a3f-7c8b-7d4e-8f3a-00000000f202"
    let successorId = TaskRecurrenceSuccessorID.make(
      parentTaskId: taskID, recurrenceGroupId: groupId)
    let completedParent = try recurringTaskEnvelope(
      id: taskID, title: "Original", status: "completed", dueDate: "2026-07-17",
      completedAt: .string("2026-07-17T09:00:00.000Z"),
      recurrenceGroupId: groupId,
      contentVersion: base, scheduleVersion: completion,
      lifecycleVersion: completion, archiveVersion: base,
      rolloverState: "authorized", successorId: .string(successorId),
      rowVersion: completion)
    let successor = try recurringTaskEnvelope(
      id: successorId, title: "Next", status: "open", dueDate: "2026-07-18",
      completedAt: .null, recurrenceGroupId: groupId,
      spawnedFrom: .string(taskID),
      spawnedFromVersion: .string(completion.description),
      contentVersion: completion, scheduleVersion: completion,
      lifecycleVersion: completion, archiveVersion: completion,
      rolloverState: "none", rowVersion: completion)
    let localTitleEdit = try recurringTaskEnvelope(
      id: taskID, title: "Durable local title", status: "completed",
      dueDate: "2026-07-17",
      completedAt: .string("2026-07-17T09:00:00.000Z"),
      recurrenceGroupId: groupId,
      contentVersion: localContent, scheduleVersion: completion,
      lifecycleVersion: completion, archiveVersion: base,
      rolloverState: "authorized", successorId: .string(successorId),
      rowVersion: localContent)
    let remoteReopenedParent = try recurringTaskEnvelope(
      id: taskID, title: "Original", status: "open", dueDate: "2026-07-17",
      completedAt: .null, recurrenceGroupId: groupId,
      contentVersion: base, scheduleVersion: remoteReopen,
      lifecycleVersion: remoteReopen, archiveVersion: base,
      rolloverState: "revoked", successorId: .string(successorId),
      rowVersion: remoteReopen)

    try store.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: completedParent), .applied)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: successor), .applied)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: localTitleEdit), .applied)
      _ = try Outbox.enqueueCoalesced(
        db, localTitleEdit, registerIntent: .task(.content))
      try FutureRecordHold.fenceExistingLocalIntent(
        db, entityType: EntityName.task, entityId: taskID,
        heldVersion: remoteReopen.description)

      let outcome = try Apply.applyEnvelope(
        db, registry: registry, envelope: remoteReopenedParent)
      guard case .repairRequired(.propagateTaskRollover) = outcome else {
        return XCTFail("reopen must normalize the already-materialized successor")
      }
      try FutureRecordHold.reconcileTerminalEnvelope(
        db, envelope: remoteReopenedParent, outcome: outcome)

      let queued = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT payload, register_intent, disposition
            FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [EntityName.task, taskID]))
      XCTAssertEqual(
        queued["register_intent"] as Int64,
        TaskRegisterIntent.content.rawValue)
      XCTAssertNil(queued["disposition"] as String?)
      guard case .object(let object)? = JSONValue.parse(queued["payload"] as String) else {
        return XCTFail("expected rebuilt task payload")
      }
      XCTAssertEqual(object["title"], .string("Durable local title"))
      XCTAssertEqual(object["status"], .string("open"))
      XCTAssertEqual(object["recurrence_rollover_state"], .string("revoked"))
    }
  }
}
