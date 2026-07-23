import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Two-device convergence probes for task content/schedule/lifecycle/archive.
final class TaskGroupedMergeTests: XCTestCase {
  private let taskId = "55555555-5555-7555-8555-555555555551"
  private let recurrenceGroupId = "55555555-5555-7555-8555-555555555553"
  private let reenabledRecurrenceGroupId = "55555555-5555-7555-8555-555555555554"
  private var successorId: String {
    TaskRecurrenceSuccessorID.make(
      parentTaskId: taskId, recurrenceGroupId: recurrenceGroupId)
  }
  private var successorInstanceKey: String {
    Recurrence.generateInstanceKey(
      recurrenceGroupID: recurrenceGroupId,
      canonicalOccurrenceDate: "2026-07-21")!
  }
  private let registry = EntityApplierRegistry(
    appliers: EntityApplierRegistry.defaultEntityAppliers())
  private let base = "1760000000100_0000_aaaaaaaaaaaaaaaa"
  private let completion = "1760000000200_0000_bbbbbbbbbbbbbbbb"
  private let titleEdit = "1760000000300_0000_cccccccccccccccc"

  private func envelope(
    title: String, status: String, completedAt: JSONValue,
    contentVersion: String, scheduleVersion: String, lifecycleVersion: String,
    archiveVersion: String? = nil, rollover: String, successor: JSONValue,
    rowVersion: String, archivedAt: JSONValue = .null
  ) throws -> SyncEnvelope {
    let partial = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "title": .string(title), "status": .string(status),
        "completed_at": completedAt, "recurrence": .string("{\"FREQ\":\"DAILY\"}"),
        "due_date": .string("2026-07-20"),
        "recurrence_group_id": .string(recurrenceGroupId),
        "canonical_occurrence_date": .string("2026-07-20"),
        "content_version": .string(contentVersion),
        "schedule_version": .string(scheduleVersion),
        "lifecycle_version": .string(lifecycleVersion),
        "archive_version": .string(archiveVersion ?? base),
        "recurrence_rollover_state": .string(rollover),
        "recurrence_successor_id": successor, "archived_at": archivedAt,
        "created_at": .string("2026-07-20T08:00:00.000Z"),
        "updated_at": .string("2026-07-20T12:00:00.000Z"),
      ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .task, entityId: taskId, operation: .upsert,
      version: Hlc.parse(rowVersion), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: partial, deviceId: "peer")
  }

  private func snapshot(_ db: Database) throws -> [String: String?] {
    let row = try XCTUnwrap(
      try Row.fetchOne(
        db,
        sql: """
          SELECT title, status, completed_at, recurrence_rollover_state,
                 recurrence_successor_id, recurrence_group_id, archived_at,
                 content_version, schedule_version, lifecycle_version,
                 archive_version, version
            FROM tasks WHERE id = ?
          """,
        arguments: [taskId]))
    return [
      "title": row["title"], "status": row["status"],
      "completed_at": row["completed_at"],
      "recurrence_rollover_state": row["recurrence_rollover_state"],
      "recurrence_successor_id": row["recurrence_successor_id"],
      "recurrence_group_id": row["recurrence_group_id"],
      "archived_at": row["archived_at"], "content_version": row["content_version"],
      "schedule_version": row["schedule_version"],
      "lifecycle_version": row["lifecycle_version"],
      "archive_version": row["archive_version"], "version": row["version"],
    ]
  }

  private func successorEnvelope(
    title: String = "Next occurrence", contentVersion: String? = nil,
    rowVersion: String? = nil
  ) throws -> SyncEnvelope {
    let resolvedContent = contentVersion ?? completion
    let resolvedRow = rowVersion ?? max(resolvedContent, completion)
    let partial = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "title": .string(title), "status": .string("open"), "completed_at": .null,
        "recurrence": .string("{\"FREQ\":\"DAILY\"}"),
        "due_date": .string("2026-07-21"),
        "recurrence_group_id": .string(recurrenceGroupId),
        "canonical_occurrence_date": .string("2026-07-21"),
        "spawned_from": .string(taskId),
        "spawned_from_version": .string(completion),
        "recurrence_instance_key": .string(successorInstanceKey),
        "content_version": .string(resolvedContent),
        "schedule_version": .string(completion),
        "lifecycle_version": .string(completion),
        "archive_version": .string(completion),
        "recurrence_rollover_state": .string("none"),
        "recurrence_successor_id": .null,
        "created_at": .string("2026-07-20T10:00:00.000Z"),
        "updated_at": .string("2026-07-20T10:00:00.000Z"),
      ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .task, entityId: successorId, operation: .upsert,
      version: Hlc.parse(resolvedRow), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: partial, deviceId: "peer")
  }

  private func reenabledEnvelope() throws -> SyncEnvelope {
    let partial = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "title": .string("Original"), "status": .string("open"),
        "completed_at": .null, "recurrence": .string("{\"FREQ\":\"DAILY\"}"),
        "due_date": .string("2026-07-25"),
        "recurrence_group_id": .string(reenabledRecurrenceGroupId),
        "canonical_occurrence_date": .string("2026-07-25"),
        "content_version": .string(base),
        "schedule_version": .string(titleEdit),
        "lifecycle_version": .string(base),
        "archive_version": .string(base),
        "recurrence_rollover_state": .string("none"),
        "recurrence_successor_id": .null, "archived_at": .null,
        "created_at": .string("2026-07-20T08:00:00.000Z"),
        "updated_at": .string("2026-07-20T12:00:00.000Z"),
      ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .task, entityId: taskId, operation: .upsert,
      version: Hlc.parse(titleEdit),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: partial, deviceId: "peer")
  }

  private func deleteEnvelope(id: String, version: String) throws -> SyncEnvelope {
    SyncEnvelope(
      entityType: .task, entityId: id, operation: .delete,
      version: try Hlc.parseCanonical(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(
        .object(["version": .string(version)])),
      deviceId: "peer")
  }

  func testLaterTitleEditCannotReopenCompletedRecurringParentInEitherArrivalOrder() throws {
    let completed = try envelope(
      title: "Original", status: "completed",
      completedAt: .string("2026-07-20T10:00:00.000Z"), contentVersion: base,
      scheduleVersion: completion, lifecycleVersion: completion,
      rollover: "authorized", successor: .string(successorId), rowVersion: completion)
    // This is the production failure shape: a later transport snapshot contains
    // a genuine title edit but stale open lifecycle/schedule bytes.
    let renamed = try envelope(
      title: "Renamed", status: "open", completedAt: .null,
      contentVersion: titleEdit, scheduleVersion: base, lifecycleVersion: base,
      rollover: "none", successor: .null, rowVersion: titleEdit)
    let left = try SyncTestSupport.freshStore()
    let right = try SyncTestSupport.freshStore()

    try left.writer.write { db in
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: completed), .applied)
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: renamed), .applied)
    }
    try right.writer.write { db in
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: renamed), .applied)
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: completed), .applied)
    }

    let leftRow = try left.writer.read { try self.snapshot($0) }
    let rightRow = try right.writer.read { try self.snapshot($0) }
    XCTAssertEqual(leftRow, rightRow)
    XCTAssertEqual(leftRow["title"]!, "Renamed")
    XCTAssertEqual(leftRow["status"]!, "completed")
    XCTAssertEqual(leftRow["recurrence_rollover_state"]!, "authorized")
    XCTAssertEqual(leftRow["recurrence_successor_id"]!, successorId)
    XCTAssertEqual(leftRow["content_version"]!, titleEdit)
    XCTAssertEqual(leftRow["schedule_version"]!, completion)
    XCTAssertEqual(leftRow["lifecycle_version"]!, completion)
    XCTAssertEqual(leftRow["version"]!, titleEdit)
  }

  func testRegroupedScheduleAndOldGroupCompletionConvergeInEitherArrivalOrder() throws {
    let completedOldGroup = try envelope(
      title: "Original", status: "completed",
      completedAt: .string("2026-07-20T10:00:00.000Z"), contentVersion: base,
      scheduleVersion: completion, lifecycleVersion: completion,
      rollover: "authorized", successor: .string(successorId), rowVersion: completion)
    let reenabled = try reenabledEnvelope()
    let left = try SyncTestSupport.freshStore()
    let right = try SyncTestSupport.freshStore()

    try left.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: completedOldGroup),
        .applied)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: reenabled),
        .repairRequired(
          .propagateTaskRollover(
            targets: [.taskUpsert(taskId: taskId, registerIntent: .lifecycle)],
            additionalFloor: try Hlc.parseCanonical(titleEdit))))
    }
    try right.writer.write { db in
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: reenabled), .applied)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: completedOldGroup),
        .repairRequired(
          .propagateTaskRollover(
            targets: [.taskUpsert(taskId: taskId, registerIntent: .lifecycle)],
            additionalFloor: try Hlc.parseCanonical(completion))))
    }

    let leftRow = try left.writer.read { try self.snapshot($0) }
    let rightRow = try right.writer.read { try self.snapshot($0) }
    XCTAssertEqual(leftRow, rightRow)
    XCTAssertEqual(leftRow["status"]!, "completed")
    XCTAssertEqual(leftRow["recurrence_group_id"]!, reenabledRecurrenceGroupId)
    XCTAssertEqual(leftRow["recurrence_rollover_state"]!, "ended")
    XCTAssertNil(leftRow["recurrence_successor_id"]!)
    XCTAssertEqual(leftRow["schedule_version"]!, titleEdit)
    XCTAssertEqual(leftRow["lifecycle_version"]!, completion)
  }

  func testOldGroupSuccessorConvergesWhenItArrivesBeforeOrAfterRegroupJoin() throws {
    let completedOldGroup = try envelope(
      title: "Original", status: "completed",
      completedAt: .string("2026-07-20T10:00:00.000Z"), contentVersion: base,
      scheduleVersion: completion, lifecycleVersion: completion,
      rollover: "authorized", successor: .string(successorId), rowVersion: completion)
    let reenabled = try reenabledEnvelope()
    let child = try successorEnvelope()
    let childAndParentTargets = TaskGraphRepairTarget.coalesced([
      .taskUpsert(taskId: taskId, registerIntent: .lifecycle),
      .taskUpsert(taskId: successorId, registerIntent: .lifecycle),
    ])
    let left = try SyncTestSupport.freshStore()
    let right = try SyncTestSupport.freshStore()

    try left.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: completedOldGroup),
        .applied)
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: child), .applied)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: reenabled),
        .repairRequired(
          .propagateTaskRollover(
            targets: childAndParentTargets,
            additionalFloor: try Hlc.parseCanonical(titleEdit))))
    }
    try right.writer.write { db in
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: reenabled), .applied)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: completedOldGroup),
        .repairRequired(
          .propagateTaskRollover(
            targets: [.taskUpsert(taskId: taskId, registerIntent: .lifecycle)],
            additionalFloor: try Hlc.parseCanonical(completion))))
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: child),
        .repairRequired(
          .propagateTaskRollover(
            targets: [.taskUpsert(taskId: successorId, registerIntent: .lifecycle)],
            additionalFloor: try Hlc.parseCanonical(completion))))
    }

    let leftParent = try left.writer.read { try self.snapshot($0) }
    let rightParent = try right.writer.read { try self.snapshot($0) }
    XCTAssertEqual(leftParent, rightParent)
    let leftChild = try left.writer.read {
      try XCTUnwrap(try TaskSyncRow.load($0, id: successorId))
    }
    let rightChild = try right.writer.read {
      try XCTUnwrap(try TaskSyncRow.load($0, id: successorId))
    }
    XCTAssertEqual(leftChild, rightChild)
    XCTAssertEqual(leftChild.status, "cancelled")
    XCTAssertEqual(leftChild.recurrenceRolloverState, "ended")
    XCTAssertEqual(leftChild.spawnedFrom, taskId)
  }

  func testMismatchedInstanceKeyCannotMergeOrRedirectAnUnrelatedTask() throws {
    let existingId = "55555555-5555-7555-8555-555555555558"
    let incomingId = "55555555-5555-7555-8555-555555555559"
    let occurrenceDate = "2026-07-21"
    let existingKey = try XCTUnwrap(
      Recurrence.generateInstanceKey(
        recurrenceGroupID: recurrenceGroupId,
        canonicalOccurrenceDate: occurrenceDate))
    let malformedPayload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "title": .string("Malformed peer task"),
        "recurrence_group_id": .string(reenabledRecurrenceGroupId),
        "canonical_occurrence_date": .string(occurrenceDate),
        "recurrence_instance_key": .string(existingKey),
      ]))
    let malformedEnvelope = try SyncTestSupport.completeEnvelope(
      entityType: .task, entityId: incomingId, operation: .upsert,
      version: Hlc.parse(titleEdit),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: malformedPayload, deviceId: "peer")
    let store = try SyncTestSupport.freshStore()

    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO tasks (
            id, title, status, list_id, recurrence_group_id,
            canonical_occurrence_date, recurrence_instance_key,
            version, created_at, updated_at
          ) VALUES (?1, 'Unrelated task', 'open', 'inbox', ?2, ?3, ?4, ?5,
                    '2026-07-20T08:00:00.000Z', '2026-07-20T08:00:00.000Z')
          """,
        arguments: [existingId, recurrenceGroupId, occurrenceDate, existingKey, base])

      XCTAssertThrowsError(
        try Apply.applyEnvelope(
          db, registry: registry, envelope: malformedEnvelope)
      ) { error in
        guard case .invalidPayload(let message) = error as? ApplyError else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("non-canonical recurrence_instance_key"))
      }
      XCTAssertNotNil(try TaskSyncRow.load(db, id: existingId))
      XCTAssertNil(try TaskSyncRow.load(db, id: incomingId))
      XCTAssertNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.task, entityId: existingId))
      XCTAssertNil(
        try EntityRedirect.get(
          db, sourceType: EntityName.task, sourceId: existingId))
    }
  }

  func testGeneratedSuccessorWithoutInstanceKeyIsRejected() throws {
    let parent = try envelope(
      title: "Original", status: "completed",
      completedAt: .string("2026-07-20T10:00:00.000Z"), contentVersion: base,
      scheduleVersion: completion, lifecycleVersion: completion,
      rollover: "authorized", successor: .string(successorId), rowVersion: completion)
    var malformedChild = try successorEnvelope()
    guard case .object(var object)? = JSONValue.parse(malformedChild.payload) else {
      return XCTFail("successor fixture must be a JSON object")
    }
    object["recurrence_instance_key"] = .null
    malformedChild.payload = try SyncCanonicalize.canonicalizeJSON(.object(object))
    let store = try SyncTestSupport.freshStore()

    try store.writer.write { db in
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: parent), .applied)
      XCTAssertThrowsError(
        try Apply.applyEnvelope(
          db, registry: registry, envelope: malformedChild)
      ) { error in
        guard case .invalidPayload(let message) = error as? ApplyError else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("generated successor requires recurrence_instance_key"))
      }
      XCTAssertNil(try TaskSyncRow.load(db, id: successorId))
    }
  }

  func testArchiveRegisterCannotBeClearedByNewerContentTransport() throws {
    let archived = try envelope(
      title: "Original", status: "open", completedAt: .null,
      contentVersion: base, scheduleVersion: base, lifecycleVersion: base,
      archiveVersion: completion, rollover: "none", successor: .null,
      rowVersion: completion, archivedAt: .string("2026-07-20T10:00:00.000Z"))
    let renamed = try envelope(
      title: "Renamed", status: "open", completedAt: .null,
      contentVersion: titleEdit, scheduleVersion: base, lifecycleVersion: base,
      archiveVersion: base, rollover: "none", successor: .null, rowVersion: titleEdit)
    let store = try SyncTestSupport.freshStore()

    try store.writer.write { db in
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: archived), .applied)
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: renamed), .applied)
      let row = try snapshot(db)
      XCTAssertEqual(row["title"]!, "Renamed")
      XCTAssertEqual(row["archived_at"]!, "2026-07-20T10:00:00.000Z")
      XCTAssertEqual(row["archive_version"]!, completion)
      XCTAssertEqual(
        try AbsencePreserveReemit.convergenceReemitTarget(db, envelope: renamed),
        AbsenceReemitTarget(entityType: EntityName.task, entityId: taskId))
    }
  }

  func testEarlySuccessorDefersUntilExactParentAuthorizationArrives() throws {
    let child = try successorEnvelope()
    let parent = try envelope(
      title: "Original", status: "completed",
      completedAt: .string("2026-07-20T10:00:00.000Z"), contentVersion: base,
      scheduleVersion: completion, lifecycleVersion: completion,
      rollover: "authorized", successor: .string(successorId), rowVersion: completion)
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: child),
        .deferred(reason: .missingDependency(entityType: .task, entityId: taskId)))
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: parent), .applied)
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: child), .applied)
      let lineage = try Row.fetchOne(
        db,
        sql: "SELECT spawned_from, spawned_from_version, status FROM tasks WHERE id = ?",
        arguments: [successorId])
      XCTAssertEqual(lineage?["spawned_from"] as String?, taskId)
      XCTAssertEqual(lineage?["spawned_from_version"] as String?, completion)
      XCTAssertEqual(lineage?["status"] as String?, "open")
    }
  }

  func testLaterReopenCancelsPristineSuccessorAndReturnsRepairTargets() throws {
    let completedParent = try envelope(
      title: "Original", status: "completed",
      completedAt: .string("2026-07-20T10:00:00.000Z"), contentVersion: base,
      scheduleVersion: completion, lifecycleVersion: completion,
      rollover: "authorized", successor: .string(successorId), rowVersion: completion)
    let child = try successorEnvelope()
    let reopenVersion = titleEdit
    let reopenedParent = try envelope(
      title: "Original", status: "open", completedAt: .null,
      contentVersion: base, scheduleVersion: reopenVersion,
      lifecycleVersion: reopenVersion, rollover: "revoked",
      successor: .string(successorId), rowVersion: reopenVersion)
    let store = try SyncTestSupport.freshStore()
    let expectedTargets = TaskGraphRepairTarget.coalesced([
      .taskUpsert(taskId: taskId, registerIntent: []),
      .taskUpsert(taskId: successorId, registerIntent: .lifecycle),
    ])

    try store.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: completedParent), .applied)
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: child), .applied)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: reopenedParent),
        .repairRequired(
          .propagateTaskRollover(
            targets: expectedTargets,
            additionalFloor: try Hlc.parse(reopenVersion))))
      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT status, recurrence_rollover_state, spawned_from
              FROM tasks WHERE id = ?
            """,
          arguments: [successorId]))
      XCTAssertEqual(row["status"] as String, "cancelled")
      XCTAssertEqual(row["recurrence_rollover_state"] as String, "ended")
      XCTAssertEqual(row["spawned_from"] as String?, taskId)
    }
  }

  func testDeletingHistoricalParentReRootsSuccessorAndStillWritesParentTombstone() throws {
    let parent = try envelope(
      title: "Original", status: "completed",
      completedAt: .string("2026-07-20T10:00:00.000Z"), contentVersion: base,
      scheduleVersion: completion, lifecycleVersion: completion,
      rollover: "authorized", successor: .string(successorId), rowVersion: completion)
    let child = try successorEnvelope()
    let deletion = try deleteEnvelope(id: taskId, version: titleEdit)
    let store = try SyncTestSupport.freshStore()

    try store.writer.write { db in
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: parent), .applied)
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: child), .applied)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: deletion),
        .repairRequired(
          .propagateTaskRollover(
            targets: [
              TaskGraphRepairTarget.taskUpsert(
                taskId: successorId, registerIntent: .schedule)
            ],
            additionalFloor: try Hlc.parseCanonical(titleEdit))))
      XCTAssertNil(try TaskSyncRow.load(db, id: taskId))
      let survivingChild = try XCTUnwrap(try TaskSyncRow.load(db, id: successorId))
      XCTAssertNil(survivingChild.spawnedFrom)
      XCTAssertNil(survivingChild.spawnedFromVersion)
      XCTAssertEqual(survivingChild.scheduleVersion, titleEdit)
      XCTAssertEqual(
        try Tombstone.getTombstone(db, entityType: EntityName.task, entityId: taskId)?.version,
        titleEdit)
    }
  }

  func testDeletingAuthorizedSuccessorEndsPredecessorAndWritesSuccessorTombstone() throws {
    let parent = try envelope(
      title: "Original", status: "completed",
      completedAt: .string("2026-07-20T10:00:00.000Z"), contentVersion: base,
      scheduleVersion: completion, lifecycleVersion: completion,
      rollover: "authorized", successor: .string(successorId), rowVersion: completion)
    let child = try successorEnvelope()
    let deletion = try deleteEnvelope(id: successorId, version: titleEdit)
    let store = try SyncTestSupport.freshStore()

    try store.writer.write { db in
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: parent), .applied)
      XCTAssertEqual(try Apply.applyEnvelope(db, registry: registry, envelope: child), .applied)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: deletion),
        .repairRequired(
          .propagateTaskRollover(
            targets: [
              TaskGraphRepairTarget.taskUpsert(
                taskId: taskId, registerIntent: .lifecycle)
            ],
            additionalFloor: try Hlc.parseCanonical(titleEdit))))
      XCTAssertNil(try TaskSyncRow.load(db, id: successorId))
      let survivingParent = try XCTUnwrap(try TaskSyncRow.load(db, id: taskId))
      XCTAssertEqual(survivingParent.recurrenceRolloverState, "ended")
      XCTAssertNil(survivingParent.recurrenceSuccessorId)
      XCTAssertEqual(survivingParent.lifecycleVersion, titleEdit)
      XCTAssertEqual(
        try Tombstone.getTombstone(
          db, entityType: EntityName.task, entityId: successorId)?.version,
        titleEdit)
    }
  }
}
