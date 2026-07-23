import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// `UNIQUE(key)` dedup convergence for the `memory` aggregate — the memory analog
/// of ``ApplyTagMerge``.
///
/// A memory row is routed by its opaque `id`; the human-authored `key` title is a
/// plain secondary UNIQUE column. When two devices create the SAME key offline
/// they each mint a distinct random `id`, so on inbound sync the second memory
/// trips `memories`' `UNIQUE(key)`. Without convergence that constraint escapes
/// ``ApplyKVAggregate`` as the batch-fatal ``ApplyError/db`` and wedges the whole
/// inbound page. The shared ``AggregateMergeEngine`` collapses the duplicates
/// instead: `min(id)` wins IDENTITY and the max-HLC participant's `content` wins
/// (carried onto the winner id when it differs); the loser row is deleted and
/// tombstoned with a redirect so its references and future envelopes resolve to
/// the winner. One `tag_merge` conflict-log row is emitted per content-loser
/// (every participant except the surviving-content one), carrying that memory's
/// own payload so the discarded content stays auditable in
/// Settings → Sync → Conflicts.
///
/// The merge is deterministic per device (every peer re-derives the same winner id
/// AND the same surviving content), so no synced edge is emitted.
enum ApplyMemoryMerge {

  /// The memory realization of ``AggregateMergeEngine``. `carryContent` copies the
  /// max-HLC memory's `content`/`updated_at` onto the winner; the hook deletes the
  /// loser row; each content-loser's own payload is pre-read (before any carry or
  /// delete) for the conflict log.
  static var merger: AggregateMergeEngine {
    AggregateMergeEngine(
      entityName: EntityName.memory,
      table: "memories",
      resolutionType: ResolutionName.tagMerge,
      savepointName: "merge_memory",
      mergeLabel: "memory",
      alwaysLogConflict: true,
      foldsCreatedAtFloor: false,
      carryContent: { db, winnerId, sourceId, mode in
        do {
          guard
            let source = try Row.fetchOne(
              db, sql: "SELECT key, content, updated_at FROM memories WHERE id = ?",
              arguments: [sourceId])
          else { throw ApplyError.store("memory carry source row missing for id=\(sourceId)") }
          let sourceKey: String = source["key"]
          let carriesKey: Bool
          switch mode {
          case .naturalKey:
            carriesKey = false
          case .permanentAlias:
            carriesKey = true
            // The alias can arrive after the source key was renamed. Vacate its
            // UNIQUE slot before carrying that full content identity to the
            // canonical row; natural-key collision staging retains its existing
            // specialized restore path.
            try db.execute(
              sql: "UPDATE memories SET key = ? WHERE id = ?",
              arguments: [stagingKey(for: sourceId), sourceId])
          }
          let keyAssignment = carriesKey ? "key = :key," : ""
          try db.execute(
            sql: """
              UPDATE memories SET
                  \(keyAssignment) content = :content, updated_at = :updated_at
               WHERE id = :winner
              """,
            arguments: [
              "key": sourceKey, "content": source["content"] as String,
              "updated_at": source["updated_at"] as String, "winner": winnerId,
            ])
        } catch { throw ApplyError.lift(error) }
      },
      prepareDivergence: { db, _, participantIds in
        // Pre-read each content-loser's whole payload BEFORE carryContent
        // overwrites the surviving row, so a content-loser that is itself the
        // min-id winner still records its pre-carry content. Memory content is
        // user-meaningful, unlike a duplicate calendar feed, so it is worth
        // preserving in the conflict row (redacted downstream).
        var payloads: [String: String] = [:]
        for id in participantIds {
          if let json = loadMemoryPayloadJSON(db, id: id) { payloads[id] = json }
        }
        return { loserId in payloads[loserId] }
      },
      repointAndDeleteLoser: { db, loserId, _, _, _ in
        // The loser id survives only as the permanent alias the engine writes
        // next, so the loser's own row is simply deleted here.
        do {
          try db.execute(sql: "DELETE FROM memories WHERE id = ?", arguments: [loserId])
        } catch { throw ApplyError.lift(error) }
      })
  }

  /// A synthetic, guaranteed-non-colliding `key` used to stage the incoming
  /// memory beside an existing claimant during an insert-collision merge. The
  /// leading NUL can never appear in a real key (`Memory.normalizeMemoryKey`
  /// strips invisibles), and embedding the entity id keeps two concurrent
  /// stagings distinct; the merge restores the real key to the winner afterward.
  static func stagingKey(for entityId: String) -> String {
    "\u{0}lorvex-memory-merge-stage:\(entityId)"
  }

  /// Entry point wired into ``ApplyKVAggregate`` after a landed memory upsert.
  static func mergeDuplicateMemories(
    _ db: Database, justUpsertedId: String, version: String, applyTs: String
  ) throws {
    try merger.mergeDuplicate(
      db, justUpsertedId: justUpsertedId,
      whereClause: "key = (SELECT key FROM memories WHERE id = ?)", whereArgs: [justUpsertedId],
      triggeringVersion: version, applyTs: applyTs)
  }

  // MARK: - Insert-collision merge

  /// Resolve a `UNIQUE(key)` collision raised by a memory upsert: stage the
  /// incoming row (via `stageIncomingWithSyntheticKey`, which lands it under a
  /// non-colliding synthetic key), then collapse the duplicates. `min(id)` wins;
  /// when the incoming row is the winner its real key is restored.
  static func insertMemoryByMergingCollision(
    _ db: Database, entityId: String, key: String, version: String, applyTs: String,
    originalError: DatabaseError, stageIncomingWithSyntheticKey: (Database) throws -> Void
  ) throws -> CollisionMergeOutcome {
    let existingRows = try collisionRows(db, key: key, excludingId: entityId)
    return try merger.insertByMergingCollision(
      db, entityId: entityId, version: version, applyTs: applyTs, existingRows: existingRows,
      originalError: originalError, collisionSavepoint: "memory_collision",
      stageIncoming: stageIncomingWithSyntheticKey,
      restoreWinner: { db in
        try db.execute(sql: "UPDATE memories SET key = ? WHERE id = ?", arguments: [key, entityId])
      })
  }

  private static func collisionRows(
    _ db: Database, key: String, excludingId: String
  ) throws -> [(String, String)] {
    do {
      // `key` is a plain UNIQUE column, so the claimant is an exact-match probe —
      // no normalization expression to mirror (unlike the tag/habit merges, whose
      // claimant is keyed on a derived `lookup_key`).
      return try Row.fetchAll(
        db,
        sql: "SELECT id, version FROM memories WHERE key = ? AND id != ? ORDER BY id ASC",
        arguments: [key, excludingId]
      ).map { ($0[0], $0[1]) }
    } catch { throw ApplyError.lift(error) }
  }

  /// The canonical memory sync payload for `id`, or `nil` when the row is absent
  /// (or its columns won't canonicalize). Used to attach the loser's diverging
  /// content to the merge conflict-log row. The `key`/`content` are scrubbed so a
  /// loser still holding the synthetic staging key (which embeds a NUL sentinel)
  /// canonicalizes cleanly — the diverging `content` is what matters for audit.
  private static func loadMemoryPayloadJSON(_ db: Database, id: String) -> String? {
    guard
      let row = try? Row.fetchOne(
        db, sql: "SELECT id, key, content, version, updated_at FROM memories WHERE id = ?",
        arguments: [id])
    else { return nil }
    let idVal: String = row["id"]
    let keyVal: String = row["key"]
    let contentVal: String = row["content"]
    let versionVal: String = row["version"]
    let updatedAtVal: String = row["updated_at"]
    let payload = JSONValue.object([
      "id": .string(idVal),
      "key": .string(ApplyAggregate.scrub(keyVal)),
      "content": .string(ApplyAggregate.scrub(contentVal)),
      "version": .string(versionVal),
      "updated_at": .string(updatedAtVal),
    ])
    return try? SyncCanonicalize.canonicalizeJSON(payload)
  }
}
