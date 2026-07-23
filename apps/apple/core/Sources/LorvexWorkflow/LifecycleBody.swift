import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Atomic append-to-task-body primitive.
public enum LifecycleBody {
  /// Append `text` to a task's body separated by a blank line, returning
  /// the new body. Enforces the combined-body length cap at the store
  /// layer so every caller is protected against
  /// "200 × 50K chunks → 10 MB body" growth.
  ///
  /// Stamps a fresh `version` alongside `updated_at`. The UPDATE is gated
  /// by `?2 > version`; zero rows changed surfaces as
  /// ``StoreError/staleVersion`` so the boundary layer can re-stamp HLC
  /// and retry instead of treating the silent no-op as success. The
  /// TOCTOU between the `SELECT body` read and the gated UPDATE is
  /// acceptable because callers wrap in an immediate transaction.
  public static func appendToTaskBody(
    _ db: Database,
    taskId: TaskId,
    text: String,
    version: String,
    now: String
  ) throws -> String {
    let currentBody: String? = try String.fetchOne(
      db,
      sql: "SELECT body FROM tasks WHERE id = ?1",
      arguments: [taskId.asString])

    let newBody: String
    if let existing = currentBody, !existing.isEmpty {
      newBody = "\(existing)\n\n\(text)"
    } else {
      newBody = text
    }

    switch ValidationText.validateBody(newBody) {
    case .success: break
    case .failure(let err):
      throw StoreError.validation(err.description)
    }

    try db.execute(
      sql:
        "UPDATE tasks SET body = ?1, content_version = ?2, version = ?2, updated_at = ?3 "
        + "WHERE id = ?4 AND ?2 > version",
      arguments: [newBody, version, now, taskId.asString])
    if db.changesCount == 0 {
      throw StoreError.staleVersion(entity: "task", id: taskId.asString)
    }
    return newBody
  }
}
