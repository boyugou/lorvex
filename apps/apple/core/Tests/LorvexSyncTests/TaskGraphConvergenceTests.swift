import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class TaskGraphConvergenceTests: XCTestCase {
  private let parentId = "66666666-6666-7666-8666-666666666661"
  private let recurrenceGroupId = "66666666-6666-7666-8666-666666666662"
  private let otherTaskId = "66666666-6666-7666-8666-666666666663"
  private let completedTaskId = "66666666-6666-7666-8666-666666666664"
  private let cancelledTaskId = "66666666-6666-7666-8666-666666666665"
  private let reminderId = "66666666-6666-7666-8666-666666666666"
  private let currentFocusDate = "2026-07-22"
  private let focusScheduleDate = "2026-07-23"
  private let base = "1760000000100_0000_aaaaaaaaaaaaaaaa"
  private let completion = "1760000000200_0000_bbbbbbbbbbbbbbbb"
  private let contradiction = "1760000000300_0000_cccccccccccccccc"
  private let dependentVersion = "1760000000500_0000_dddddddddddddddd"
  private let successorDeleteVersion = "1760000000600_0000_ffffffffffffffff"
  private let lateDependentVersion = "1760000000700_0000_1212121212121212"
  private let registry = EntityApplierRegistry(
    appliers: EntityApplierRegistry.defaultEntityAppliers())

  private var successorId: String {
    TaskRecurrenceSuccessorID.make(
      parentTaskId: parentId, recurrenceGroupId: recurrenceGroupId)
  }

  func testRepairTargetCoalescingUnionsTaskIntentAndLetsDeleteDominate() throws {
    let older = try Hlc.parseCanonical(base)
    let newer = try Hlc.parseCanonical(dependentVersion)
    XCTAssertEqual(
      TaskGraphRepairTarget.coalesced([
        .taskUpsert(taskId: parentId, registerIntent: .content),
        .taskUpsert(taskId: parentId, registerIntent: .lifecycle),
        .relatedEntity(
          entityType: .taskDependency, entityId: "\(parentId):\(otherTaskId)",
          operation: .upsert, knownVersionFloor: newer),
        .relatedEntity(
          entityType: .taskDependency, entityId: "\(parentId):\(otherTaskId)",
          operation: .delete, knownVersionFloor: older),
      ]),
      [
        .taskUpsert(taskId: parentId, registerIntent: [.content, .lifecycle]),
        .relatedEntity(
          entityType: .taskDependency, entityId: "\(parentId):\(otherTaskId)",
          operation: .delete, knownVersionFloor: newer),
      ])
  }

  func testRepairObligationReportsEveryDerivedEntityKind() throws {
    let floor = try Hlc.parseCanonical(base)
    let obligation = ApplyRepairObligation.propagateTaskRollover(
      targets: [
        .taskUpsert(taskId: parentId, registerIntent: .lifecycle),
        .relatedEntity(
          entityType: .taskReminder, entityId: reminderId,
          operation: .upsert, knownVersionFloor: floor),
        .relatedEntity(
          entityType: .taskDependency, entityId: "\(parentId):\(otherTaskId)",
          operation: .delete, knownVersionFloor: floor),
        .relatedEntity(
          entityType: .currentFocus, entityId: currentFocusDate,
          operation: .upsert, knownVersionFloor: floor),
      ],
      additionalFloor: floor)

    XCTAssertEqual(
      obligation.affectedEntityTypes,
      [.task, .taskReminder, .taskDependency, .currentFocus])
  }

  func testReminderBeforeParentContradictionIsCancelledAndReemitted() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedAuthorizedChain(db)
      XCTAssertEqual(try apply(db, reminderEnvelope()), .applied)

      let obligation = try contradictionObligation(db)
      let reminderFloor = try Hlc.parseCanonical(dependentVersion)
      XCTAssertTrue(
        obligation.targets.contains(
          .relatedEntity(
            entityType: .taskReminder, entityId: reminderId, operation: .upsert,
            knownVersionFloor: reminderFloor)))
      XCTAssertNotNil(
        try String.fetchOne(
          db, sql: "SELECT cancelled_at FROM task_reminders WHERE id = ?1",
          arguments: [reminderId]))

      try fulfill(db, obligation: obligation.value)
      let outbox = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql:
            "SELECT operation, version, payload FROM sync_outbox "
            + "WHERE entity_type = 'task_reminder' AND entity_id = ?1",
          arguments: [reminderId]))
      XCTAssertEqual(outbox["operation"] as String, "upsert")
      XCTAssertGreaterThan(try Hlc.parseCanonical(outbox["version"]), reminderFloor)
      XCTAssertTrue((outbox["payload"] as String).contains("cancelled_at"))
    }
  }

  func testReminderAfterParentContradictionCannotReactivateTerminalSuccessor() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedContradictedChain(db)
      let outcome = try apply(db, reminderEnvelope())
      let obligation = try unwrapTaskGraphObligation(outcome)
      XCTAssertEqual(
        obligation.targets,
        [
          .relatedEntity(
            entityType: .taskReminder, entityId: reminderId, operation: .upsert,
            knownVersionFloor: try Hlc.parseCanonical(dependentVersion))
        ])
      XCTAssertNotNil(
        try String.fetchOne(
          db, sql: "SELECT cancelled_at FROM task_reminders WHERE id = ?1",
          arguments: [reminderId]))
      try fulfill(db, obligation: obligation.value)
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql:
            "SELECT operation FROM sync_outbox "
            + "WHERE entity_type = 'task_reminder' AND entity_id = ?1",
          arguments: [reminderId]),
        "upsert")
    }
  }

  func testLaterReminderDeleteInSamePageSupersedesPendingCancellationUpsert() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedAuthorizedChain(db)
      XCTAssertEqual(try apply(db, reminderEnvelope()), .applied)
      let contradictionRepair = try contradictionObligation(db)

      XCTAssertEqual(
        try apply(
          db,
          deleteEnvelope(
            entityType: .taskReminder, entityId: reminderId,
            version: successorDeleteVersion)),
        .applied)
      try fulfill(db, obligation: contradictionRepair.value)

      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM task_reminders WHERE id = ?1",
          arguments: [reminderId]))
      let tombstone = try XCTUnwrap(
        try Tombstone.getTombstone(
          db, entityType: EntityKind.taskReminder.asString, entityId: reminderId))
      XCTAssertGreaterThan(
        try Hlc.parseCanonical(tombstone.version),
        try Hlc.parseCanonical(successorDeleteVersion))
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql:
            "SELECT operation FROM sync_outbox "
            + "WHERE entity_type = 'task_reminder' AND entity_id = ?1",
          arguments: [reminderId]),
        "delete")
    }
  }

  func testLaterSuccessorDeleteInSamePageSupersedesPendingTaskUpsert() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedAuthorizedChain(db)
      let contradictionRepair = try contradictionObligation(db)

      XCTAssertEqual(
        try apply(
          db,
          deleteEnvelope(
            entityType: .task, entityId: successorId,
            version: successorDeleteVersion)),
        .applied)
      try fulfill(db, obligation: contradictionRepair.value)

      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM tasks WHERE id = ?1", arguments: [successorId]))
      let tombstone = try XCTUnwrap(
        try Tombstone.getTombstone(
          db, entityType: EntityKind.task.asString, entityId: successorId))
      XCTAssertGreaterThan(
        try Hlc.parseCanonical(tombstone.version),
        try Hlc.parseCanonical(successorDeleteVersion))
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql:
            "SELECT operation FROM sync_outbox "
            + "WHERE entity_type = 'task' AND entity_id = ?1",
          arguments: [successorId]),
        "delete")
    }
  }

  func testDependencyBeforeParentContradictionIsDetachedAndTombstoned() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedAuthorizedChain(db)
      try applyOrdinaryTask(db, id: otherTaskId, status: "open", version: base)
      XCTAssertEqual(try apply(db, dependencyEnvelope()), .applied)

      let obligation = try contradictionObligation(db)
      let edgeId = "\(successorId):\(otherTaskId)"
      let edgeFloor = try Hlc.parseCanonical(dependentVersion)
      XCTAssertTrue(
        obligation.targets.contains(
          .relatedEntity(
            entityType: .taskDependency, entityId: edgeId, operation: .delete,
            knownVersionFloor: edgeFloor)))
      XCTAssertEqual(try dependencyCount(db), 0)

      try fulfill(db, obligation: obligation.value)
      let tombstone = try XCTUnwrap(
        try Tombstone.getTombstone(
          db, entityType: EntityKind.taskDependency.asString, entityId: edgeId))
      XCTAssertGreaterThan(try Hlc.parseCanonical(tombstone.version), edgeFloor)
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql:
            "SELECT operation FROM sync_outbox "
            + "WHERE entity_type = 'task_dependency' AND entity_id = ?1",
          arguments: [edgeId]),
        "delete")
    }
  }

  func testDependencyAfterParentContradictionCannotReenterGraph() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedContradictedChain(db)
      try applyOrdinaryTask(db, id: otherTaskId, status: "open", version: base)
      let outcome = try apply(db, dependencyEnvelope())
      let obligation = try unwrapTaskGraphObligation(outcome)
      let edgeId = "\(successorId):\(otherTaskId)"
      XCTAssertEqual(try dependencyCount(db), 0)
      XCTAssertEqual(
        obligation.targets,
        [
          .relatedEntity(
            entityType: .taskDependency, entityId: edgeId, operation: .delete,
            knownVersionFloor: try Hlc.parseCanonical(dependentVersion))
        ])

      try fulfill(db, obligation: obligation.value)
      XCTAssertNotNil(
        try Tombstone.getTombstone(
          db, entityType: EntityKind.taskDependency.asString, entityId: edgeId))
    }
  }

  func testLaterValidDependencyUpsertSupersedesPendingDerivedDelete() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try applyOrdinaryTask(db, id: cancelledTaskId, status: "cancelled", version: base)
      try applyOrdinaryTask(db, id: otherTaskId, status: "open", version: base)
      let edgeId = "\(cancelledTaskId):\(otherTaskId)"
      let deleteRepair = try unwrapTaskGraphObligation(
        try apply(
          db,
          dependencyEnvelope(
            taskId: cancelledTaskId, dependsOnTaskId: otherTaskId,
            version: dependentVersion)))

      try applyOrdinaryTask(
        db, id: cancelledTaskId, status: "open", version: successorDeleteVersion)
      XCTAssertEqual(
        try apply(
          db,
          dependencyEnvelope(
            taskId: cancelledTaskId, dependsOnTaskId: otherTaskId,
            version: lateDependentVersion)),
        .applied)
      try fulfill(db, obligation: deleteRepair.value)

      XCTAssertEqual(try dependencyCount(db), 1)
      XCTAssertNil(
        try Tombstone.getTombstone(
          db, entityType: EntityKind.taskDependency.asString, entityId: edgeId))
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql:
            "SELECT operation FROM sync_outbox "
            + "WHERE entity_type = 'task_dependency' AND entity_id = ?1",
          arguments: [edgeId]),
        "upsert")
    }
  }

  func testFocusRootsBeforeParentContradictionRemoveOnlyGeneratedSuccessor() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedAuthorizedChain(db)
      try applyOrdinaryTask(db, id: otherTaskId, status: "open", version: base)
      XCTAssertEqual(
        try apply(db, currentFocusEnvelope(taskIds: [successorId, otherTaskId])), .applied)
      XCTAssertEqual(
        try apply(db, focusScheduleEnvelope(taskIds: [successorId, otherTaskId])), .applied)

      let obligation = try contradictionObligation(db)
      let rootFloor = try Hlc.parseCanonical(dependentVersion)
      XCTAssertTrue(
        obligation.targets.contains(
          .relatedEntity(
            entityType: .currentFocus, entityId: currentFocusDate, operation: .upsert,
            knownVersionFloor: rootFloor)))
      XCTAssertTrue(
        obligation.targets.contains(
          .relatedEntity(
            entityType: .focusSchedule, entityId: focusScheduleDate, operation: .upsert,
            knownVersionFloor: rootFloor)))
      XCTAssertEqual(try currentFocusTaskIds(db), [otherTaskId])
      XCTAssertEqual(try focusScheduleTaskIds(db), [otherTaskId])

      try fulfill(db, obligation: obligation.value)
      XCTAssertEqual(
        try String.fetchAll(
          db,
          sql:
            "SELECT entity_type FROM sync_outbox "
            + "WHERE entity_type IN ('current_focus', 'focus_schedule') "
            + "ORDER BY entity_type"),
        ["current_focus", "focus_schedule"])
    }
  }

  func testFocusRootsAfterParentContradictionPreserveOrdinaryTerminalTasks() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedContradictedChain(db)
      try applyOrdinaryTask(db, id: completedTaskId, status: "completed", version: base)
      try applyOrdinaryTask(db, id: cancelledTaskId, status: "cancelled", version: base)
      let ids = [successorId, completedTaskId, cancelledTaskId]

      let currentOutcome = try apply(db, currentFocusEnvelope(taskIds: ids))
      let currentRepair = try unwrapTaskGraphObligation(currentOutcome)
      XCTAssertEqual(
        currentRepair.targets,
        [
          .relatedEntity(
            entityType: .currentFocus, entityId: currentFocusDate, operation: .upsert,
            knownVersionFloor: try Hlc.parseCanonical(dependentVersion))
        ])
      XCTAssertEqual(try currentFocusTaskIds(db), [completedTaskId, cancelledTaskId])
      try fulfill(db, obligation: currentRepair.value)

      let scheduleOutcome = try apply(db, focusScheduleEnvelope(taskIds: ids))
      let scheduleRepair = try unwrapTaskGraphObligation(scheduleOutcome)
      XCTAssertEqual(
        scheduleRepair.targets,
        [
          .relatedEntity(
            entityType: .focusSchedule, entityId: focusScheduleDate, operation: .upsert,
            knownVersionFloor: try Hlc.parseCanonical(dependentVersion))
        ])
      XCTAssertEqual(try focusScheduleTaskIds(db), [completedTaskId, cancelledTaskId])
      try fulfill(db, obligation: scheduleRepair.value)
    }
  }

  func testSuccessorDeleteAfterParentAuthorizationEndsAuthorization() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedAuthorizedChain(db)
      let repair = try unwrapTaskGraphObligation(
        try apply(
          db,
          deleteEnvelope(
            entityType: .task, entityId: successorId,
            version: successorDeleteVersion)))

      XCTAssertEqual(try parentRolloverState(db), "ended")
      XCTAssertTrue(
        repair.targets.contains(
          .taskUpsert(taskId: parentId, registerIntent: .lifecycle)))
      try fulfill(db, obligation: repair.value)
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql:
            "SELECT operation FROM sync_outbox "
            + "WHERE entity_type = 'task' AND entity_id = ?1",
          arguments: [parentId]),
        "upsert")
    }
  }

  func testSuccessorDeleteBeforeParentAuthorizationEndsDominatedAuthorization() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(
        try apply(
          db,
          deleteEnvelope(
            entityType: .task, entityId: successorId,
            version: successorDeleteVersion)),
        .applied)
      let repair = try unwrapTaskGraphObligation(
        try apply(db, completedParentEnvelope()))

      XCTAssertEqual(try parentRolloverState(db), "ended")
      XCTAssertTrue(
        repair.targets.contains(
          .taskUpsert(taskId: parentId, registerIntent: .lifecycle)))
      try fulfill(db, obligation: repair.value)
      XCTAssertGreaterThan(
        try Hlc.parseCanonical(
          try XCTUnwrap(
            try String.fetchOne(
              db, sql: "SELECT lifecycle_version FROM tasks WHERE id = ?1",
              arguments: [parentId]))),
        try Hlc.parseCanonical(successorDeleteVersion))
    }
  }

  func testOlderSuccessorTombstoneDoesNotEndNewerParentAuthorization() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(
        try apply(
          db,
          deleteEnvelope(
            entityType: .task, entityId: successorId, version: base)),
        .applied)
      XCTAssertEqual(try apply(db, completedParentEnvelope()), .applied)
      XCTAssertEqual(try parentRolloverState(db), "authorized")

      XCTAssertEqual(try apply(db, successorEnvelope()), .applied)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT status FROM tasks WHERE id = ?1",
          arguments: [successorId]),
        "open")
      XCTAssertNil(
        try Tombstone.getTombstone(
          db, entityType: EntityKind.task.asString, entityId: successorId))
    }
  }

  private func seedAuthorizedChain(_ db: Database) throws {
    XCTAssertEqual(try apply(db, completedParentEnvelope()), .applied)
    XCTAssertEqual(try apply(db, successorEnvelope()), .applied)
  }

  private func seedContradictedChain(_ db: Database) throws {
    try seedAuthorizedChain(db)
    _ = try contradictionObligation(db)
  }

  private func contradictionObligation(
    _ db: Database
  ) throws -> (targets: [TaskGraphRepairTarget], value: ApplyRepairObligation) {
    try unwrapTaskGraphObligation(try apply(db, reopenedParentEnvelope()))
  }

  private func unwrapTaskGraphObligation(
    _ result: ApplyResult
  ) throws -> (targets: [TaskGraphRepairTarget], value: ApplyRepairObligation) {
    guard case .repairRequired(let obligation) = result,
      case .propagateTaskRollover(let targets, _) = obligation
    else {
      XCTFail("expected task-graph repair, got \(result)")
      throw NSError(domain: "TaskGraphConvergenceTests", code: 1)
    }
    return (targets, obligation)
  }

  private func fulfill(_ db: Database, obligation: ApplyRepairObligation) throws {
    var counter = 0
    try ApplyRepair.fulfill(
      db, obligation: obligation,
      mintVersion: { floor in
        defer { counter += 1 }
        let raw = String(
          format: "1760000009000_%04d_eeeeeeeeeeeeeeee", counter)
        if let floor, let parsed = try? Hlc.parseCanonical(raw) {
          XCTAssertGreaterThan(parsed, floor)
        }
        return raw
      },
      deviceId: "66666666-6666-7666-8666-666666666699")
  }

  private func apply(_ db: Database, _ envelope: SyncEnvelope) throws -> ApplyResult {
    try Apply.applyEnvelope(db, registry: registry, envelope: envelope)
  }

  private func completedParentEnvelope() throws -> SyncEnvelope {
    try taskEnvelope(
      id: parentId, title: "Parent", status: "completed",
      completedAt: .string("2026-07-21T10:00:00.000Z"),
      contentVersion: base, scheduleVersion: completion,
      lifecycleVersion: completion, rollover: "authorized",
      successorId: .string(successorId), rowVersion: completion,
      recurrence: .string("{\"FREQ\":\"DAILY\"}"), dueDate: .string("2026-07-21"),
      recurrenceGroupId: .string(recurrenceGroupId),
      canonicalOccurrenceDate: .string("2026-07-21"))
  }

  private func reopenedParentEnvelope() throws -> SyncEnvelope {
    try taskEnvelope(
      id: parentId, title: "Parent", status: "open", completedAt: .null,
      contentVersion: base, scheduleVersion: contradiction,
      lifecycleVersion: contradiction, rollover: "revoked",
      successorId: .string(successorId), rowVersion: contradiction,
      recurrence: .string("{\"FREQ\":\"DAILY\"}"), dueDate: .string("2026-07-21"),
      recurrenceGroupId: .string(recurrenceGroupId),
      canonicalOccurrenceDate: .string("2026-07-21"))
  }

  private func successorEnvelope() throws -> SyncEnvelope {
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "title": .string("Successor"), "status": .string("open"),
        "completed_at": .null, "recurrence": .string("{\"FREQ\":\"DAILY\"}"),
        "due_date": .string("2026-07-22"),
        "recurrence_group_id": .string(recurrenceGroupId),
        "canonical_occurrence_date": .string("2026-07-22"),
        "spawned_from": .string(parentId),
        "spawned_from_version": .string(completion),
        "recurrence_instance_key": .string("\(recurrenceGroupId):2026-07-22"),
        "content_version": .string(completion),
        "schedule_version": .string(completion),
        "lifecycle_version": .string(completion),
        "archive_version": .string(completion),
        "recurrence_rollover_state": .string("none"),
        "recurrence_successor_id": .null,
        "created_at": .string("2026-07-21T10:00:00.000Z"),
        "updated_at": .string("2026-07-21T10:00:00.000Z"),
      ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .task, entityId: successorId, operation: .upsert,
      version: Hlc.parse(completion), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: "peer")
  }

  private func taskEnvelope(
    id: String, title: String, status: String, completedAt: JSONValue,
    contentVersion: String, scheduleVersion: String, lifecycleVersion: String,
    rollover: String, successorId: JSONValue, rowVersion: String,
    recurrence: JSONValue, dueDate: JSONValue, recurrenceGroupId: JSONValue,
    canonicalOccurrenceDate: JSONValue
  ) throws -> SyncEnvelope {
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "title": .string(title), "status": .string(status),
        "completed_at": completedAt, "recurrence": recurrence, "due_date": dueDate,
        "recurrence_group_id": recurrenceGroupId,
        "canonical_occurrence_date": canonicalOccurrenceDate,
        "content_version": .string(contentVersion),
        "schedule_version": .string(scheduleVersion),
        "lifecycle_version": .string(lifecycleVersion),
        "archive_version": .string(base),
        "recurrence_rollover_state": .string(rollover),
        "recurrence_successor_id": successorId,
        "created_at": .string("2026-07-21T08:00:00.000Z"),
        "updated_at": .string("2026-07-21T12:00:00.000Z"),
      ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .task, entityId: id, operation: .upsert,
      version: Hlc.parse(rowVersion), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: "peer")
  }

  private func applyOrdinaryTask(
    _ db: Database, id: String, status: String, version: String
  ) throws {
    let completedAt: JSONValue =
      status == "completed" ? .string("2026-07-21T11:00:00.000Z") : .null
    let rollover = status == "completed" || status == "cancelled" ? "ended" : "none"
    let envelope = try taskEnvelope(
      id: id, title: "Ordinary", status: status, completedAt: completedAt,
      contentVersion: version, scheduleVersion: version, lifecycleVersion: version,
      rollover: rollover, successorId: .null, rowVersion: version,
      recurrence: .null, dueDate: .null, recurrenceGroupId: .null,
      canonicalOccurrenceDate: .null)
    let result = try apply(db, envelope)
    switch result {
    case .applied, .repairRequired:
      break
    default:
      XCTFail("ordinary task apply failed: \(result)")
    }
  }

  private func reminderEnvelope() throws -> SyncEnvelope {
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "task_id": .string(successorId),
        "reminder_at": .string("2026-07-24T09:00:00.000Z"),
        "dismissed_at": .null, "cancelled_at": .null,
        "created_at": .string("2026-07-21T12:00:00.000Z"),
      ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .taskReminder, entityId: reminderId, operation: .upsert,
      version: Hlc.parse(dependentVersion),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: "peer")
  }

  private func dependencyEnvelope() throws -> SyncEnvelope {
    try dependencyEnvelope(
      taskId: successorId, dependsOnTaskId: otherTaskId,
      version: dependentVersion)
  }

  private func dependencyEnvelope(
    taskId: String, dependsOnTaskId: String, version: String
  ) throws -> SyncEnvelope {
    let edgeId = "\(taskId):\(dependsOnTaskId)"
    return try SyncTestSupport.completeEnvelope(
      entityType: .taskDependency, entityId: edgeId, operation: .upsert,
      version: Hlc.parse(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(
        .object(["created_at": .string("2026-07-21T12:00:00.000Z")])),
      deviceId: "peer")
  }

  private func currentFocusEnvelope(taskIds: [String]) throws -> SyncEnvelope {
    try SyncTestSupport.completeEnvelope(
      entityType: .currentFocus, entityId: currentFocusDate, operation: .upsert,
      version: Hlc.parse(dependentVersion),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(
        .object([
          "task_ids": .array(taskIds.map(JSONValue.string)),
          "created_at": .string("2026-07-21T12:00:00.000Z"),
          "updated_at": .string("2026-07-21T12:00:00.000Z"),
        ])),
      deviceId: "peer")
  }

  private func focusScheduleEnvelope(taskIds: [String]) throws -> SyncEnvelope {
    let blocks = taskIds.enumerated().map { index, taskId in
      JSONValue.object([
        "block_type": .string("task"), "start_minutes": .int(Int64(480 + index * 60)),
        "end_minutes": .int(Int64(510 + index * 60)), "task_id": .string(taskId),
        "calendar_event_id": .null, "event_source": .null, "title": .string("Task"),
      ])
    }
    return try SyncTestSupport.completeEnvelope(
      entityType: .focusSchedule, entityId: focusScheduleDate, operation: .upsert,
      version: Hlc.parse(dependentVersion),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(
        .object([
          "blocks": .array(blocks),
          "created_at": .string("2026-07-21T12:00:00.000Z"),
          "updated_at": .string("2026-07-21T12:00:00.000Z"),
        ])),
      deviceId: "peer")
  }

  private func deleteEnvelope(
    entityType: EntityKind, entityId: String, version: String
  ) throws -> SyncEnvelope {
    SyncEnvelope(
      entityType: entityType, entityId: entityId, operation: .delete,
      version: try Hlc.parseCanonical(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(
        .object(["version": .string(version)])),
      deviceId: "peer")
  }

  private func parentRolloverState(_ db: Database) throws -> String? {
    try String.fetchOne(
      db, sql: "SELECT recurrence_rollover_state FROM tasks WHERE id = ?1",
      arguments: [parentId])
  }

  private func dependencyCount(_ db: Database) throws -> Int {
    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM task_dependencies") ?? -1
  }

  private func currentFocusTaskIds(_ db: Database) throws -> [String] {
    try String.fetchAll(
      db,
      sql:
        "SELECT task_id FROM current_focus_items WHERE date = ?1 "
        + "ORDER BY position",
      arguments: [currentFocusDate])
  }

  private func focusScheduleTaskIds(_ db: Database) throws -> [String] {
    try String.fetchAll(
      db,
      sql:
        "SELECT task_id FROM focus_schedule_blocks "
        + "WHERE date = ?1 AND task_id IS NOT NULL ORDER BY position",
      arguments: [focusScheduleDate])
  }
}
