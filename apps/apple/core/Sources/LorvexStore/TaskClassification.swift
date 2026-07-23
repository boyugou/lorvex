import Foundation
import GRDB
import LorvexDomain

/// Pre-write validation helpers for the task-classification path.
///
/// These guard the contracts every task-create / task-update call needs to
/// satisfy before any LWW-gated UPDATE runs:
///
/// - The target `list_id` must be non-empty and reference an existing
///   `lists` row.
///
/// `resolveRequiredTaskListId`: with an explicit list id it validates the row
/// exists; without one it reads the `default_list_id` preference (a JSON-string
/// scalar) and, when that default is unset or dangling, heals to the canonical
/// `inbox` list so implicit task creation never fails on a bad pointer.
public enum TaskClassification {
  /// Resolve the list id the create / update path must write to.
  ///
  /// An EXPLICIT list id is validated strictly and throws
  /// ``StoreError/validation(_:)`` when absent (`"list_id must not be empty"`)
  /// or missing from `lists` (`"list '<id>' does not exist"`).
  ///
  /// Without an explicit id, the `default_list_id` preference is used, healing
  /// to the always-present `inbox` list when the default is unset (deleted
  /// preference, or a device before setup) or dangling (its list was deleted, or
  /// a synced default references a list not present locally). This never throws:
  /// the managed open ensures the `inbox` row on every open (see
  /// ``LorvexStore/ensureInboxListRow(_:)``) and list deletion refuses it.
  public static func resolveRequiredTaskListId(
    _ db: Database, explicitListId: String?
  ) throws -> String {
    if let listId = explicitListId {
      try validateTaskListExists(db, listId: ListId(trusted: listId))
      return listId
    }
    let raw = try String.fetchOne(
      db,
      sql: "SELECT value FROM preferences WHERE key = ?1",
      arguments: [PreferenceKeys.prefDefaultListId])
    // Fall back to the always-present `inbox` list when no valid default is
    // configured, so implicit task creation never fails on a bad pointer. The
    // default can be UNSET (its preference was deleted, or a fresh device before
    // setup) or DANGLING (its list was deleted locally, or a synced default
    // references a list not yet/never present on this device). `inbox` is the
    // canonical fallback, ensured on every managed open and refused by list
    // deletion, so it is guaranteed to exist. Local set/`complete_setup` reject a non-existent
    // default up front, and list deletion repoints a deleted default to `inbox`;
    // this read-time heal is the backstop for the delete-preference and sync-drift
    // paths those write-time guards cannot reach.
    guard let defaultId = Parsing.parseJsonStringPreference(raw) else {
      return inboxListId
    }
    let exists =
      try Int64.fetchOne(
        db, sql: "SELECT 1 FROM lists WHERE id = ?",
        arguments: [defaultId]) != nil
    return exists ? defaultId : inboxListId
  }

  /// Validate that `listId` is non-empty and resolves to a row in `lists`.
  ///
  /// Throws ``StoreError/validation(_:)`` with the canonical message shapes
  /// (`"list_id must not be empty"` / `"list '<id>' does not exist"`) that MCP
  /// error rendering relies on.
  public static func validateTaskListExists(
    _ db: Database, listId: ListId
  ) throws {
    if listId.rawValue.isEmpty {
      throw StoreError.validation("list_id must not be empty")
    }
    let exists = try Int64.fetchOne(
      db,
      sql: "SELECT 1 FROM lists WHERE id = ?",
      arguments: [listId.rawValue]) != nil
    if !exists {
      throw StoreError.validation("list '\(listId.rawValue)' does not exist")
    }
  }
}
