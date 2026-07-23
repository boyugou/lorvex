import Foundation
import GRDB
import LorvexDomain

/// Composable LWW-gate helpers for `UPDATE`/`DELETE` statements that maintain
/// an HLC `version` column.
///
/// Existing per-repository call sites inline the LWW gate by hand; that pattern
/// is fine when a repository owns one well-known table. Composite write paths
/// (task/write, mutation orchestrators) need a structured helper so dynamic
/// SET-clause assembly + the staleness check live in one place.
///
/// Behavior:
/// - `executeUpdate` runs `UPDATE … WHERE id = ? AND ? > version`. If zero rows
///   are affected, throws ``StoreError/staleVersion(entity:id:)``. It does NOT
///   probe for existence: an absent row and a stale-version miss are
///   indistinguishable, and other Swift surfaces
///   (e.g. ``ListRepo/updateListPatched(_:id:patch:version:now:)``) follow the
///   same contract.
/// - `executeDeleteById` runs `DELETE FROM <table> WHERE <id_col> = ? AND ? > version`.
///   On zero rows it disambiguates by running an existence probe: when the row
///   still exists, throws ``StoreError/staleVersion``; otherwise returns `0`.
///   A successful delete returns `1`.
public enum LwwOps {
  /// Run a LWW-gated UPDATE.
  ///
  /// `setClauses` and `bindings` are the dynamic SET-clause halves the caller
  /// assembles (e.g. `["name = ?", "color = ?", "version = ?", "updated_at = ?"]`
  /// + matching argument list). The helper appends the canonical
  /// `WHERE <id_col> = ? AND ? > version` gate and binds `id` and `version` for
  /// it. `version` is always written into the row (so the row's stored version
  /// advances on every successful write) — the caller must include the
  /// `version = ?` set clause + binding themselves to match the existing
  /// repository style.
  ///
  /// Throws ``StoreError/staleVersion(entity:id:)`` when zero rows match
  /// (either the row is absent or the supplied version is not strictly newer).
  public static func executeUpdate(
    _ db: Database,
    table: String,
    idColumn: String = "id",
    entity: String,
    id: String,
    version: String,
    setClauses: [String],
    bindings: [(any DatabaseValueConvertible)?]
  ) throws {
    precondition(!setClauses.isEmpty, "LwwOps.executeUpdate: setClauses must not be empty")
    var args: [(any DatabaseValueConvertible)?] = bindings
    args.append(id)
    args.append(version)
    let sql =
      "UPDATE \(table) SET \(setClauses.joined(separator: ", ")) "
      + "WHERE \(idColumn) = ? AND ? > version"
    try db.execute(sql: sql, arguments: StatementArguments(args))
    if db.changesCount == 0 {
      throw StoreError.staleVersion(entity: entity, id: id)
    }
  }

  /// Run a LWW-gated hard DELETE by primary key.
  ///
  /// Returns `1` on a successful delete, `0` when no row with the given id
  /// existed. Throws ``StoreError/staleVersion(entity:id:)`` when the row
  /// exists but its stored `version` is greater than or equal to the supplied
  /// `version` (the local delete has lost the LWW race).
  @discardableResult
  public static func executeDeleteById(
    _ db: Database,
    table: String,
    idColumn: String = "id",
    entity: String,
    id: String,
    version: String
  ) throws -> Int {
    try db.execute(
      sql: "DELETE FROM \(table) WHERE \(idColumn) = ? AND ? > version",
      arguments: [id, version])
    if db.changesCount > 0 {
      return db.changesCount
    }
    // Disambiguate stale-version vs absent row.
    let exists = try Int64.fetchOne(
      db,
      sql: "SELECT 1 FROM \(table) WHERE \(idColumn) = ? LIMIT 1",
      arguments: [id]) != nil
    if exists {
      throw StoreError.staleVersion(entity: entity, id: id)
    }
    return 0
  }
}
