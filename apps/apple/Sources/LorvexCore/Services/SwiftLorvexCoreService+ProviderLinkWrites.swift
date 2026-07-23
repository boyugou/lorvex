import GRDB
import LorvexDomain
import LorvexStore

extension SwiftLorvexCoreService {
  /// Returns whether a link row was removed (false is a no-op the caller reports
  /// honestly).
  @discardableResult
  func unlinkKnownProviderEvent(
    _ db: Database,
    taskID: LorvexTask.ID,
    fields: ProviderLinkFields,
    deviceId: String
  ) throws -> Bool {
    let deleted = try ProviderRepo.deleteProviderEventLink(
      db,
      taskId: TaskId(trusted: taskID),
      providerKind: fields.providerKind,
      providerScope: fields.providerScope,
      providerEventKey: fields.providerEventKey
    )
    guard deleted.before != nil else { return false }
    try writeChangelogRow(
      db,
      ChangelogEntry(
        operation: SyncNaming.opDelete,
        entityType: EntityName.task,
        entityId: taskID,
        // This row syncs; keep external provider identity and event details
        // entirely in the device-local provider tables.
        summary: "Removed a device-local calendar link for task \(taskID)."
      ),
      deviceId: deviceId
    )
    return true
  }

  /// Returns whether at least one link row was removed (false is a no-op the
  /// caller reports honestly).
  @discardableResult
  func unlinkProviderEventByKey(
    _ db: Database,
    taskID: LorvexTask.ID,
    providerEventID: String,
    deviceId: String
  ) throws -> Bool {
    try db.execute(
      sql: """
        DELETE FROM task_provider_event_links \
        WHERE task_id = ? AND provider_event_key = ?
      """,
      arguments: [taskID, providerEventID])
    guard db.changesCount > 0 else { return false }
    try writeChangelogRow(
      db,
      ChangelogEntry(
        operation: SyncNaming.opDelete,
        entityType: EntityName.task,
        entityId: taskID,
        summary: "Removed a device-local calendar link for task \(taskID)."
      ),
      deviceId: deviceId
    )
    return true
  }
}
