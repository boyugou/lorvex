import Foundation
import GRDB
import LorvexDomain

/// One task-defer event reconstructed from an `ai_changelog` row, newest-first.
///
/// `deferredAt` is the changelog row timestamp; `initiatedBy` is the row's
/// actor column (system-controlled). `structuredReason` and `note` are the
/// per-defer coarse enum and free-text detail supplied at that defer, recovered
/// from the reserved `_defer` object embedded in the row's `after_json`
/// snapshot (see ``AiChangelogDeferHistory/deferDetailKey``). Both are `nil`
/// when the defer supplied neither — a clean defer records no `_defer` object,
/// and rows predating the feature carry none.
public struct AiChangelogDeferHistoryRow: Sendable, Equatable {
  public let deferredAt: String
  public let structuredReason: String?
  public let note: String?
  public let initiatedBy: String?

  public init(
    deferredAt: String,
    structuredReason: String? = nil,
    note: String? = nil,
    initiatedBy: String? = nil
  ) {
    self.deferredAt = deferredAt
    self.structuredReason = structuredReason
    self.note = note
    self.initiatedBy = initiatedBy
  }
}

/// Read side of the per-task defer trail carried on `ai_changelog`.
///
/// The write side embeds a reserved ``deferDetailKey`` object into the defer
/// changelog row's `after_json` (`{"structured_reason": …, "note": …}`); this
/// query re-reads it. No dedicated column or child table backs defer history —
/// it rides entirely on the existing append-only changelog.
public enum AiChangelogDeferHistory {
  /// Reserved key under which a defer changelog row's `after_json` carries the
  /// per-defer detail object. Chosen with a leading underscore so it never
  /// collides with a real task column in the enriched-task snapshot.
  public static let deferDetailKey = "_defer"

  /// The `ai_changelog` operation strings that represent a task deferral: the
  /// single `defer_task` write and the `batch_defer_tasks` bulk write.
  static let deferOperations = ["defer", "batch_defer"]

  /// Recent defer events for `taskId`, newest first, capped at `limit`.
  ///
  /// Unions the scalar `entity_id` match (single defers, and the anchor id of a
  /// batch) with the `ai_changelog_entities` registry join (every task in a
  /// batch defer), so a task deferred as one of many in a batch is included
  /// even when it is not the batch's anchor id. `limit` must be strictly
  /// positive.
  public static func deferHistory(
    _ db: Database, taskId: String, limit: Int
  ) throws -> [AiChangelogDeferHistoryRow] {
    precondition(limit > 0, "AiChangelogDeferHistory.deferHistory limit must be > 0")
    let opPlaceholders = deferOperations.map { _ in "?" }.joined(separator: ", ")
    let sql = """
      SELECT id, timestamp, after_json, initiated_by FROM ( \
        SELECT id, timestamp, after_json, initiated_by \
        FROM ai_changelog \
        WHERE entity_id = ? AND entity_type = 'task' AND operation IN (\(opPlaceholders)) \
        UNION \
        SELECT ac.id, ac.timestamp, ac.after_json, ac.initiated_by \
        FROM ai_changelog ac \
        JOIN ai_changelog_entities ace ON ace.changelog_id = ac.id \
        WHERE ace.entity_id = ? AND ac.entity_type = 'task' AND ac.operation IN (\(opPlaceholders)) \
      ) \
      ORDER BY timestamp DESC, id DESC \
      LIMIT ?
      """
    var args: [DatabaseValueConvertible?] = []
    args.append(taskId)
    args.append(contentsOf: deferOperations.map { $0 as DatabaseValueConvertible? })
    args.append(taskId)
    args.append(contentsOf: deferOperations.map { $0 as DatabaseValueConvertible? })
    args.append(limit)

    let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
    return rows.map { row in
      let afterJson: String? = row[2]
      let detail = parseDeferDetail(afterJson)
      return AiChangelogDeferHistoryRow(
        deferredAt: row[1],
        structuredReason: detail.structuredReason,
        note: detail.note,
        initiatedBy: row[3])
    }
  }

  /// Extract `structured_reason` / `note` from the reserved `_defer` object in a
  /// defer row's `after_json`. Returns `(nil, nil)` when the JSON is absent,
  /// represented by a size-capped truncation sentinel, or carries no `_defer`.
  static func parseDeferDetail(
    _ afterJson: String?
  ) -> (structuredReason: String?, note: String?) {
    guard let afterJson,
      case .object(let obj)? = JSONValue.parse(afterJson),
      case .object(let detail)? = obj[deferDetailKey]
    else {
      return (nil, nil)
    }
    var structuredReason: String?
    var note: String?
    if case .string(let value)? = detail["structured_reason"] { structuredReason = value }
    if case .string(let value)? = detail["note"] { note = value }
    return (structuredReason, note)
  }
}
