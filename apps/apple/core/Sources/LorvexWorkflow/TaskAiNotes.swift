import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Canonical `ai_notes` mutation shared by MCP `set_task_ai_notes` and the
/// CLI mirror. Owns the `ai_notes` + content-register SQL with LWW gating.
///
/// The UPDATE is gated by `?version > version` so a stale caller stamp
/// cannot clobber a freshly-applied peer envelope. Zero rows changed
/// disambiguates between a missing row and a stale stamp via a follow-up
/// existence probe: ``StoreError/notFound`` when the row is gone,
/// ``StoreError/staleVersion`` when the gate rejected our stamp.
public enum TaskAiNotes {
  /// Hard cap on assistant-maintained task context. Mirrors task
  /// create/update so this field has one invariant regardless of write path.
  public static let maxAiNotesLength: Int = TaskCreatePrepared.maxAiNotesLength

  /// Sanitize, trim, collapse visually-empty notes to nil, and enforce the
  /// canonical length limit before any task `ai_notes` write.
  public static func prepareAiNotes(_ notes: String) throws -> String? {
    let sanitized = UnicodeHygiene.sanitizeUserText(notes)
    let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !ValidationText.isVisuallyEmpty(trimmed) else { return nil }
    switch ValidationText.validateStringLength(
      trimmed, field: "ai_notes", max: maxAiNotesLength)
    {
    case .success:
      break
    case .failure(let error):
      throw StoreError.validation(error.description)
    }
    switch PayloadByteBudget.validateEscapedBudget(
      trimmed, field: "ai_notes", budget: PayloadByteBudget.aiNotesEscapedBytes)
    {
    case .success:
      return trimmed
    case .failure(let error):
      throw StoreError.validation(error.description)
    }
  }

  /// Stamp the current `ai_notes` blob onto the row, alongside a fresh
  /// `version` and `updated_at`. Throws ``StoreError/notFound(entity:id:)``
  /// when the row does not exist and ``StoreError/staleVersion(entity:id:)``
  /// when the LWW gate rejects the write.
  public static func setAiNotesOp(
    _ db: Database,
    taskId: TaskId,
    notes: String?,
    version: String,
    now: String
  ) throws {
    try db.execute(
      sql:
        "UPDATE tasks SET ai_notes = ?, "
        + "content_version = ?, version = ?, updated_at = ? "
        + "WHERE id = ? AND ? > version",
      arguments: [notes, version, version, now, taskId.rawValue, version])
    if db.changesCount == 0 {
      let exists = try Row.fetchOne(
        db, sql: "SELECT 1 FROM tasks WHERE id = ?",
        arguments: [taskId.rawValue]) != nil
      if exists {
        throw StoreError.staleVersion(entity: EntityName.task, id: taskId.asString)
      } else {
        throw StoreError.notFound(entity: EntityName.task, id: taskId.asString)
      }
    }
  }
}
