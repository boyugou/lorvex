import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  // MARK: - Checklist

  public func addTaskChecklistItem(taskID: LorvexTask.ID, text: String) async throws -> LorvexTask {
    try checklistMutation(operation: "checklist_add") { db, hlc in
      try TaskChecklist.addTaskChecklistItem(
        db, hlc: hlc, input: TaskChecklist.AddInput(taskId: TaskId(trusted: taskID), text: text))
    }
  }

  public func updateTaskChecklistItem(itemID: TaskChecklistItem.ID, text: String) async throws
    -> LorvexTask
  {
    try checklistMutation(operation: "checklist_update") { db, hlc in
      try TaskChecklist.updateTaskChecklistItem(
        db, hlc: hlc,
        input: TaskChecklist.UpdateInput(itemId: ChecklistItemId(trusted: itemID), text: text))
    }
  }

  public func toggleTaskChecklistItem(itemID: TaskChecklistItem.ID, completed: Bool) async throws
    -> LorvexTask
  {
    try checklistMutation(operation: "checklist_toggle") { db, hlc in
      try TaskChecklist.toggleTaskChecklistItem(
        db, hlc: hlc,
        input: TaskChecklist.ToggleInput(
          itemId: ChecklistItemId(trusted: itemID), completed: completed))
    }
  }

  public func removeTaskChecklistItem(itemID: TaskChecklistItem.ID) async throws -> LorvexTask {
    try checklistMutation(operation: "checklist_remove") { db, hlc in
      try TaskChecklist.removeTaskChecklistItem(
        db, hlc: hlc,
        input: TaskChecklist.RemoveInput(itemId: ChecklistItemId(trusted: itemID)))
    }
  }

  public func reorderTaskChecklistItems(taskID: LorvexTask.ID, itemIDs: [TaskChecklistItem.ID])
    async throws -> LorvexTask
  {
    try checklistMutation(operation: "checklist_reorder") { db, hlc in
      try TaskChecklist.reorderTaskChecklistItems(
        db, hlc: hlc,
        input: TaskChecklist.ReorderInput(
          taskId: TaskId(trusted: taskID),
          itemIds: itemIDs.map { ChecklistItemId(trusted: $0) }))
    }
  }

  private func checklistMutation(
    operation: String,
    _ mutate: (Database, HlcSession) throws -> TaskChecklist.MutationResult
  ) throws -> LorvexTask {
    try withWrite { db, hlc, deviceId in
      try self.checklistMutationInTx(db, hlc: hlc, deviceId: deviceId, operation: operation, mutate)
    }
  }

  /// One checklist mutation (sync fanout + changelog) inside an open write
  /// transaction, shared by the public checklist entries and the
  /// single-transaction batch record create.
  func checklistMutationInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, operation: String,
    _ mutate: (Database, HlcSession) throws -> TaskChecklist.MutationResult
  ) throws -> LorvexTask {
    let result = try mutate(db, hlc)
    for change in result.itemSyncChanges {
      switch change.operation {
      case .upsert:
        try self.enqueueUpsert(
          db, deviceId: deviceId, kind: .taskChecklistItem, entityId: change.itemId,
          version: change.version)
      case .delete:
        if let snapshot = change.snapshot {
          try self.enqueueDelete(
            db, deviceId: deviceId, kind: .taskChecklistItem,
            entityId: change.itemId, payload: snapshot, version: change.version)
        }
      }
    }
    try self.writeChangelogRow(
      db,
      ChangelogEntry(
        operation: operation, entityId: result.taskId, summary: result.summary,
        before: result.beforeTask, after: result.afterTask),
      deviceId: deviceId)
    return try SwiftLorvexTaskDeserializers.task(result.afterTask)
  }
}
