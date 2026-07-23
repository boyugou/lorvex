import Foundation
import GRDB
import LorvexDomain

/// `preferences`-table write operations.
///
/// LWW correctness is enforced inline in the SQL (UPSERT branch + DELETE):
/// the new write proceeds only if its `version` is strictly greater than
/// the row's stored version. Equal-version writes are no-ops by design —
/// preference upserts do not merge surplus fields the way natural-key
/// aggregate merges do.
public enum PreferenceRepo {
  /// Upsert a preference, gated by `excluded.version > preferences.version`
  /// on the conflict branch. Returns `true` when the row actually wrote
  /// (fresh insert or version-newer update); `false` when the LWW gate
  /// rejected a stale write.
  @discardableResult
  public static func setPreference(
    _ db: Database, key: String, value: String, version: String, now: String
  ) throws -> Bool {
    try db.execute(
      sql: """
        INSERT INTO preferences (key, value, version, updated_at) \
        VALUES (?, ?, ?, ?) \
        ON CONFLICT(key) DO UPDATE SET \
           value = excluded.value, version = excluded.version, updated_at = excluded.updated_at \
        WHERE excluded.version > preferences.version
        """,
      arguments: [key, value, version, now])
    return db.changesCount > 0
  }

  /// Delete a preference under the LWW gate (`version > preferences.version`,
  /// strict-greater). Returns `1` when the row was deleted, `0` when no row with
  /// `key` existed.
  ///
  /// Throws ``StoreError/staleVersion`` when the row is present but its stored
  /// version is `>=` the supplied `version` (a future-stamped row the local
  /// clear lost the LWW race to). The two "nothing deleted" cases are kept
  /// distinct so an explicit local delete can always supersede the row it
  /// targets: an ABSENT key is a benign no-op, but a gate-REFUSED row must
  /// surface so the write-surface retry advances the clock past it and re-runs
  /// the delete (matching the memory / task hard-delete paths).
  @discardableResult
  public static func clearPreference(
    _ db: Database, key: String, version: String
  ) throws -> Int {
    try LwwOps.executeDeleteById(
      db, table: "preferences", idColumn: "key", entity: EntityName.preference,
      id: key, version: version)
  }
}
