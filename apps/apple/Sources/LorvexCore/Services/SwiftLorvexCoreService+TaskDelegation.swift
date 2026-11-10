import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// Handing a task to the person's assistant, over the pure-Swift core.
///
/// A delegated task has one `task_delegations` row keyed by the task and the
/// assignee, synced as a composite edge. The row's `state` says who has the
/// next move: `assistant` while the assistant holds the task, `returned` once
/// it handed the task back. What the assistant did goes into the task's AI
/// notes. Taking the task back deletes the row. A restated hand-off or return
/// writes nothing.
extension SwiftLorvexCoreService {

  public func delegateTask(id: LorvexTask.ID, request: String?) async throws -> LorvexTask {
    let request = try Self.preparedDelegationRequest(request)
    return try withWrite { db, hlc, deviceId in
      let taskId = TaskId(trusted: id)
      let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: taskId)
      let task = try SwiftLorvexTaskDeserializers.task(before)
      guard task.archivedAt == nil, task.status.isActionable else {
        throw LorvexCoreError.validation(
          field: "id",
          message: "Only a task that is still open can be handed to the assistant.")
      }
      let assignee = TaskDelegationAssignee.assistant
      let existing = try TaskDelegationRepo.delegation(db, taskId: id, assignee: assignee)
      if let existing, existing.state == .assistant, existing.request == request {
        return task
      }
      let entityId = "\(id):\(assignee)"
      let existingVersion = try String.fetchOne(
        db, sql: "SELECT version FROM task_delegations WHERE task_id = ? AND assignee = ?",
        arguments: [id, assignee])
      let version = try VersionFloor.mint(
        hlc: hlc, existingVersion: existingVersion,
        entityType: EntityKind.taskDelegation.asString, entityId: entityId)
      let now = SyncTimestampFormat.syncTimestampNow()
      // A task handed over again counts from this hand-over.
      try db.execute(
        sql: """
          INSERT INTO task_delegations
            (task_id, assignee, state, request, version, created_at, updated_at)
          VALUES (?1, ?2, 'assistant', ?3, ?4, ?5, ?5)
          ON CONFLICT (task_id, assignee) DO UPDATE SET
            state = excluded.state, request = excluded.request, version = excluded.version,
            created_at = excluded.created_at, updated_at = excluded.updated_at
          """,
        arguments: [id, assignee, request, version, now])
      try self.enqueueTaskDelegationUpsert(
        db, hlc: hlc, deviceId: deviceId, taskId: id, assignee: assignee)
      let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: taskId)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "delegate_task", entityId: id,
          summary: "Handed '\(TaskResponse.taskTitle(after))' to the assistant",
          before: before, after: after),
        deviceId: deviceId)
      return try SwiftLorvexTaskDeserializers.task(after)
    }
  }

  public func returnDelegatedTask(id: LorvexTask.ID, result: String?) async throws -> LorvexTask {
    try withWrite { db, hlc, deviceId in
      let taskId = TaskId(trusted: id)
      let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: taskId)
      let assignee = TaskDelegationAssignee.assistant
      guard let existing = try TaskDelegationRepo.delegation(db, taskId: id, assignee: assignee)
      else {
        throw LorvexCoreError.validation(
          field: "id", message: "This task was not handed to the assistant.")
      }

      // The result replaces the task's AI notes; no result leaves them as they are.
      var wroteNotes = false
      if let result, let notes = try TaskAiNotes.prepareAiNotes(result) {
        let current = try String.fetchOne(
          db, sql: "SELECT ai_notes FROM tasks WHERE id = ?", arguments: [id])
        if notes != current {
          try TaskAiNotes.setAiNotesOp(
            db, taskId: taskId, notes: notes, version: hlc.nextVersionString(),
            now: SyncTimestampFormat.syncTimestampNow())
          try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: id)
          wroteNotes = true
        }
      }

      if existing.state != .returned {
        let entityId = "\(id):\(assignee)"
        let existingVersion = try String.fetchOne(
          db, sql: "SELECT version FROM task_delegations WHERE task_id = ? AND assignee = ?",
          arguments: [id, assignee])
        let version = try VersionFloor.mint(
          hlc: hlc, existingVersion: existingVersion,
          entityType: EntityKind.taskDelegation.asString, entityId: entityId)
        try db.execute(
          sql: """
            UPDATE task_delegations SET state = 'returned', version = ?, updated_at = ?
            WHERE task_id = ? AND assignee = ?
            """,
          arguments: [version, SyncTimestampFormat.syncTimestampNow(), id, assignee])
        try self.enqueueTaskDelegationUpsert(
          db, hlc: hlc, deviceId: deviceId, taskId: id, assignee: assignee)
      } else if !wroteNotes {
        return try SwiftLorvexTaskDeserializers.task(before)
      }

      let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: taskId)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "return_task", entityId: id,
          summary: "Handed '\(TaskResponse.taskTitle(after))' back",
          before: before, after: after),
        deviceId: deviceId)
      return try SwiftLorvexTaskDeserializers.task(after)
    }
  }

  public func clearTaskDelegation(id: LorvexTask.ID) async throws -> LorvexTask {
    try withWrite { db, hlc, deviceId in
      let taskId = TaskId(trusted: id)
      let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: taskId)
      let assignee = TaskDelegationAssignee.assistant
      guard
        let existing = try Row.fetchOne(
          db,
          sql: """
            SELECT state, request, version, created_at, updated_at FROM task_delegations
            WHERE task_id = ? AND assignee = ?
            """,
          arguments: [id, assignee])
      else { return try SwiftLorvexTaskDeserializers.task(before) }

      let existingVersion: String = existing["version"]
      let payload = PayloadLoaders.taskDelegationPayload(
        taskId: id, assignee: assignee, state: existing["state"], request: existing["request"],
        version: existingVersion, createdAt: existing["created_at"],
        updatedAt: existing["updated_at"])
      try db.execute(
        sql: "DELETE FROM task_delegations WHERE task_id = ? AND assignee = ?",
        arguments: [id, assignee])
      let entityId = "\(id):\(assignee)"
      let deleteVersion = try VersionFloor.mint(
        hlc: hlc, existingVersion: existingVersion,
        entityType: EntityKind.taskDelegation.asString, entityId: entityId)
      try OutboxEnqueue.enqueuePayloadDelete(
        db,
        entityType: EntityKind.taskDelegation.asString,
        entityId: entityId,
        payload: payload,
        context: OutboxWriteContext(version: deleteVersion, deviceId: deviceId))

      let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: taskId)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "clear_task_delegation", entityId: id,
          summary: "Took '\(TaskResponse.taskTitle(after))' back from the assistant",
          before: before, after: after),
        deviceId: deviceId)
      return try SwiftLorvexTaskDeserializers.task(after)
    }
  }

  public func delegatedTaskCount(state: LorvexTaskDelegation.State) async throws -> Int {
    try read { db in
      try TaskDelegationRepo.count(
        db, assignee: TaskDelegationAssignee.assistant,
        state: state == .assistant ? .assistant : .returned)
    }
  }

  /// The request as stored: sanitized and trimmed, nil when nothing visible is
  /// left, refused when longer than the table allows.
  static func preparedDelegationRequest(_ request: String?) throws -> String? {
    guard let request else { return nil }
    let trimmed = UnicodeHygiene.sanitizeUserText(request)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !ValidationText.isVisuallyEmpty(trimmed) else { return nil }
    guard trimmed.count <= TaskDelegationRecord.maxRequestLength else {
      throw LorvexCoreError.validation(
        field: "request",
        message:
          "The request is too long. Keep it under \(TaskDelegationRecord.maxRequestLength) characters."
      )
    }
    return trimmed
  }
}
