import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Primary `tasks` row UPDATE for a single-row task update. No-op when
/// the prepared patch carries no row-level field. Status changes flow
/// through ``TaskUpdateStatus`` and never land here.
public enum TaskUpdateRow {

  /// `true` when at least one `tasks` row column other than status is
  /// being patched.
  public static func hasPrimaryRowPatch(_ prepared: PreparedTaskUpdate) -> Bool {
    return prepared.title != nil
      || prepared.body.isSetOrClear
      || prepared.rawInput.isSetOrClear
      || prepared.aiNotes.isSetOrClear
      || prepared.listId.isSetOrClear
      || prepared.priority.isSetOrClear
      || prepared.estimatedMinutes.isSetOrClear
      || prepared.plannedDate.isSetOrClear
      || prepared.availableFrom.isSetOrClear
  }

  public static func applyPrimaryRowPatch(
    _ db: Database,
    hlc: HlcSession,
    taskId: String,
    prepared: PreparedTaskUpdate,
    now: String
  ) throws {
    if !hasPrimaryRowPatch(prepared) { return }
    let version = hlc.nextVersionString()
    let patch = TaskUpdatePatch(
      taskId: taskId,
      version: version,
      now: now,
      title: prepared.title,
      body: prepared.body,
      rawInput: prepared.rawInput,
      aiNotes: prepared.aiNotes,
      status: nil,
      listId: prepared.listId,
      priority: prepared.priority,
      estimatedMinutes: prepared.estimatedMinutes,
      plannedDate: prepared.plannedDate,
      availableFrom: prepared.availableFrom,
      archivedAt: .unset,
      beforeStatus: prepared.beforeStatus)
    try TaskRepo.Write.applyTaskUpdate(db, patch: patch)
  }
}
