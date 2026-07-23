import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Memory entry mutations — the canonical implementations every write surface
/// (MCP, app, CLI) delegates to. Each op LWW-gates on the version envelope so a
/// stale local stamp cannot clobber a freshly applied peer write.
public enum MemoryOps {
  /// Outcome of a memory mutation that actually changed a row.
  ///
  /// `memoryId` is the row's opaque, sync-stable `id` (NOT its human `key`) —
  /// the identity every downstream outbound sync envelope for this memory must
  /// route on, so the CloudKit `entity_id` stays opaque. `preDeletePayload`
  /// carries the canonical pre-delete snapshot for the delete op (used by the
  /// sync enqueue path); it is `nil` for upsert.
  public struct MemoryMutationResult: Sendable, Equatable {
    public let memoryKey: String
    public let memoryId: String
    public let preDeletePayload: JSONValue?
  }

  /// Find-or-create-by-`key` upsert. The `key` is a plain UNIQUE column, so the
  /// conflict target is `key`; `id` is written on the INSERT arm only and is
  /// deliberately absent from the `DO UPDATE SET` so an existing row keeps its
  /// original `id` across every content edit (a churning `id` would change the
  /// CloudKit `entity_id` per edit and break cross-edit LWW convergence).
  private static let upsertSQL =
    "INSERT INTO memories (id, key, content, version, updated_at) VALUES (?, ?, ?, ?, ?) "
    + "ON CONFLICT(key) DO UPDATE SET content = excluded.content, version = excluded.version, "
    + "updated_at = excluded.updated_at WHERE excluded.version > memories.version"

  /// The existing row's `id` for `key`, or a freshly minted UUIDv7 when the key
  /// is new. Resolved before the upsert so the returned `memoryId` is the row's
  /// stable identity whether the write created or updated it.
  private static func resolveMemoryId(_ db: Database, key: String) throws -> String {
    if let existing = try String.fetchOne(
      db, sql: "SELECT id FROM memories WHERE key = ?", arguments: [key])
    {
      return existing
    }
    return EntityID.newEntityIDString()
  }

  /// Upsert a memory entry.
  ///
  /// The UPDATE arm is gated by `excluded.version > memories.version`. When the
  /// gate rejects (the key exists with a strictly-newer version) the row is
  /// unchanged and `nil` is returned so callers skip the downstream sync enqueue
  /// / changelog.
  public static func upsertMemoryEntry(
    _ db: Database, key: String, content: String, version: String, now: String
  ) throws -> MemoryMutationResult? {
    let content = try Memory.normalizeContent(content)
    let id = try resolveMemoryId(db, key: key)
    try db.execute(sql: upsertSQL, arguments: [id, key, content, version, now])
    if db.changesCount == 0 { return nil }

    return MemoryMutationResult(memoryKey: key, memoryId: id, preDeletePayload: nil)
  }

  /// Atomically rename a memory to `newKey` (optionally replacing content) by
  /// updating the EXISTING row's mutable `key` column, keyed on its immutable
  /// `id`. Because `id` is unchanged, the sync-routing identity (CloudKit
  /// `entity_id`) and cross-edit LWW convergence are preserved — no second record
  /// is minted, unlike an upsert-under-a-new-key + delete-old-key pair.
  ///
  /// LWW-gated like upsert/delete on `version`: a genuinely ABSENT old key returns
  /// `nil` (nothing to rename); a row the gate REFUSED (a future-stamped row)
  /// throws ``StoreError/staleVersion`` so the write-surface retry advances the
  /// clock and re-runs. `content == nil` keeps the row's existing content.
  public static func renameMemoryEntry(
    _ db: Database, oldKey: String, newKey: String, content: String?,
    version: String, now: String
  ) throws -> MemoryMutationResult? {
    guard
      let id = try String.fetchOne(
        db, sql: "SELECT id FROM memories WHERE key = ?", arguments: [oldKey])
    else { return nil }
    let existingContent =
      try String.fetchOne(db, sql: "SELECT content FROM memories WHERE id = ?", arguments: [id])
      ?? ""
    let newContent = try content.map(Memory.normalizeContent) ?? existingContent
    try db.execute(
      sql: "UPDATE memories SET key = ?, content = ?, version = ?, updated_at = ? "
        + "WHERE id = ? AND version < ?",
      arguments: [newKey, newContent, version, now, id, version])
    if db.changesCount == 0 {
      // The row exists (resolved above) but the LWW gate refused a future-stamped
      // row — surface it so the write-surface retry advances the clock, mirroring
      // deleteMemoryEntry.
      throw StoreError.staleVersion(entity: EntityName.memory, id: id)
    }

    return MemoryMutationResult(memoryKey: newKey, memoryId: id, preDeletePayload: nil)
  }

  /// Delete a memory entry.
  ///
  /// Returns the result when the row existed and the delete passed the LWW gate
  /// (`memories.version < version`). The two "nothing deleted" cases are
  /// distinguished so an explicit local delete can always supersede the row it
  /// targets (SYNC17-HIGH-2):
  ///
  ///   * an ABSENT key returns `nil` (a benign no-op — nothing to delete);
  ///   * a row the LWW gate REFUSED (its stored version `>=` the incoming stamp,
  ///     i.e. a future-stamped row) throws ``StoreError/staleVersion`` so the
  ///     write-surface retry advances the clock past it and re-runs the delete.
  ///
  /// Either way the row is left untouched on the refusal. The pre-delete snapshot
  /// is captured before the DELETE.
  public static func deleteMemoryEntry(
    _ db: Database, key: String, version: String
  ) throws -> MemoryMutationResult? {
    let existingId = try String.fetchOne(
      db, sql: "SELECT id FROM memories WHERE key = ?", arguments: [key])
    let preDeletePayload = try PayloadLoaders.loadMemoryDeleteSnapshot(db, key: key)
    try db.execute(
      sql: "DELETE FROM memories WHERE key = ? AND version < ?", arguments: [key, version])
    if db.changesCount == 0 {
      // A row that never existed is a benign no-op; a row the gate refused is a
      // future-stamped row an explicit local delete must be able to supersede —
      // surface it so the write-surface retry advances the clock and re-runs.
      guard let existingId else { return nil }
      throw StoreError.staleVersion(entity: EntityName.memory, id: existingId)
    }
    // `changesCount > 0` means the row existed, so `existingId` was populated in
    // this same transaction; the delete envelope must route on that opaque id.
    guard let id = existingId else {
      throw StoreError.invariant("memory '\(key)' deleted but had no id")
    }

    return MemoryMutationResult(
      memoryKey: key, memoryId: id, preDeletePayload: preDeletePayload)
  }
}
