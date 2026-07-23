import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  public func setTaskAINotes(taskID: LorvexTask.ID, notes: String) async throws -> LorvexTask {
    try withWrite { db, hlc, deviceId in
      let normalized = try TaskAiNotes.prepareAiNotes(notes)
      let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: taskID))
      let current = try String.fetchOne(
        db, sql: "SELECT ai_notes FROM tasks WHERE id = ?", arguments: [taskID])
      guard normalized != current else {
        return try SwiftLorvexTaskDeserializers.task(before)
      }

      let version = hlc.nextVersionString()
      try TaskAiNotes.setAiNotesOp(
        db, taskId: TaskId(trusted: taskID), notes: normalized,
        version: version, now: SyncTimestampFormat.syncTimestampNow())
      try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: taskID)
      let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: taskID))
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "set_task_ai_notes", entityId: taskID,
          summary: "Updated AI context for '\(TaskResponse.taskTitle(after))'",
          before: before, after: after),
        deviceId: deviceId)
      return try SwiftLorvexTaskDeserializers.task(after)
    }
  }

  public func appendToTaskBody(taskID: LorvexTask.ID, additionalNotes: String) async throws
    -> LorvexTask
  {
    try withWrite { db, hlc, deviceId in
      let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: taskID))
      // `LifecycleBody.appendToTaskBody` already reads the current body and joins
      // it with the new text under a blank-line separator, so pass only the new
      // text — pre-combining here appended the existing body a second time.
      let version = hlc.nextVersionString()
      _ = try LifecycleBody.appendToTaskBody(
        db, taskId: TaskId(trusted: taskID), text: additionalNotes,
        version: version, now: SyncTimestampFormat.syncTimestampNow())
      try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .task, entityId: taskID)
      let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: taskID))
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "append_to_task_body", entityId: taskID,
          summary: "Appended to '\(TaskResponse.taskTitle(after))'",
          before: before, after: after),
        deviceId: deviceId)
      return try SwiftLorvexTaskDeserializers.task(after)
    }
  }
}
