import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Per-entity apply handler for the `tag` independent child, with lookup_key
/// convergence (duplicate-tag merge).
///
/// Upsert: scrub `display_name`, re-derive `lookup_key` via
/// ``normalizeLookupKey(_:)`` (never trusting the inbound key), run the shared
/// LWW-gated upsert, then — only when the upsert actually modified a row
/// (`changesCount > 0`) — run the duplicate-tag merge so a stale envelope with a
/// smaller tag id cannot tombstone the live tag.
///
/// Delete: LWW-gated DELETE (task_tags rows cascade via FK).
///
/// Merge contract: when two tags share a `lookup_key`, the tag with the
/// lexicographically smallest `id` wins IDENTITY, and the max-HLC participant's
/// `display_name` / `color` win CONTENT (carried onto the winner id when they
/// differ). The convergence scaffold lives in ``AggregateMergeEngine``; this file
/// supplies the tag hooks — the `display_name` / derived `lookup_key` / `color`
/// carry, the divergence
/// read for the conflict log, and the `task_tags` re-point SQL. A `tag_merge`
/// conflict-log row is written iff a content-loser's `display_name` / `color`
/// diverge from the surviving content.
public struct TagApplier: EntityApplier {
  public init() {}

  public var handledEntityTypes: [String] { [EntityKind.tag.asString] }

  public func applyUpsert(
    _ db: Database, envelope: SyncEnvelope, tieBreak: LwwTieBreak, applyTs: String
  ) throws -> EntityApplyOutcome {
    try ApplyTagMerge.applyTagUpsert(
      db, entityId: envelope.entityId, payload: envelope.payload,
      version: envelope.version.description, tieBreak: tieBreak, applyTs: applyTs)
    return .applied
  }

  public func applyDelete(
    _ db: Database, envelope: SyncEnvelope, applyTs: String
  ) throws -> EntityApplyOutcome {
    try ApplyTagMerge.applyTagDelete(
      db, entityId: envelope.entityId, version: envelope.version.description)
    return .applied
  }
}

enum ApplyTagMerge {
  /// The tag realization of ``AggregateMergeEngine``.
  static var merger: AggregateMergeEngine {
    AggregateMergeEngine(
      entityName: EntityName.tag,
      table: "tags",
      resolutionType: ResolutionName.tagMerge,
      savepointName: "merge_tags",
      mergeLabel: "tag",
      alwaysLogConflict: false,
      foldsCreatedAtFloor: true,
      carryContent: { db, winnerId, sourceId, _ in
        do {
          guard
            let source = try Row.fetchOne(
              db,
              sql: "SELECT display_name, color, updated_at FROM tags WHERE id = ?",
              arguments: [sourceId])
          else { throw ApplyError.store("tag carry source row missing for id=\(sourceId)") }
          let displayName: String = source["display_name"]
          try db.execute(
            sql: """
              UPDATE tags SET
                  display_name = :display_name, lookup_key = :lookup_key,
                  color = :color, updated_at = :updated_at
               WHERE id = :winner
              """,
            arguments: [
              "display_name": displayName,
              "lookup_key": normalizeLookupKey(displayName),
              "color": source["color"] as String?,
              "updated_at": source["updated_at"] as String,
              "winner": winnerId,
            ])
        } catch { throw ApplyError.lift(error) }
      },
      prepareDivergence: AggregateMergeEngine.snapshotDivergence(
        label: "tag",
        read: { db, ids in try readTagMergeFields(db, ids: ids) },
        compare: divergentTagLoserFields),
      repointAndDeleteLoser: { db, loserId, winnerId, _, _ in
        do {
          // A task-tag edge has its own LWW register. Preserve the winning edge
          // participant's authored version + created_at; stamping it with the
          // parent merge HLC or local apply time makes a late source-addressed
          // edge (remapped through the permanent tag alias) lose on one peer but
          // win on another. Equal edge HLCs choose the byte-stable earlier
          // created_at, so this UPSERT is commutative even for a corrupt/reused
          // edge clock.
          try db.execute(
            sql: """
              INSERT INTO task_tags (task_id, tag_id, created_at, version)
               SELECT task_id, :winner_id, created_at, version
                 FROM task_tags WHERE tag_id = :loser_id
               ON CONFLICT(task_id, tag_id) DO UPDATE SET
                   created_at = CASE
                       WHEN excluded.version > task_tags.version THEN excluded.created_at
                       WHEN excluded.version = task_tags.version
                         THEN min(excluded.created_at, task_tags.created_at)
                       ELSE task_tags.created_at END,
                   version = max(task_tags.version, excluded.version)
              """,
            arguments: ["winner_id": winnerId, "loser_id": loserId])
          try db.execute(sql: "DELETE FROM task_tags WHERE tag_id = ?", arguments: [loserId])
          try db.execute(sql: "DELETE FROM tags WHERE id = ?", arguments: [loserId])
        } catch { throw ApplyError.lift(error) }
      })
  }

  static func applyTagUpsert(
    _ db: Database, entityId: String, payload: String, version: String, tieBreak: LwwTieBreak,
    applyTs: String
  ) throws {
    let val = try ApplyJSON.parseObject(payload)

    let displayName = ApplyAggregate.scrub(
      try ApplyJSON.requiredStr(val, "display_name", entity: "tag"))
    let color = ApplyAggregate.nullableStrOrClear(
      try ApplyAggregate.optionalStrPreservingEmpty(val, "color", "tag"))
    let createdAt = try ApplyJSON.requiredStr(val, "created_at", entity: "tag")
    let updatedAt = try ApplyJSON.requiredStr(val, "updated_at", entity: "tag")

    let lookupKey = normalizeLookupKey(displayName)

    let sql = LwwUpsertSpec(
      table: "tags",
      columns: SyncEntityDescriptor.require(.tag).plainColumns,
      conflict: ["id"], tieBreak: tieBreak, createdAtFloor: true
    ).buildSQL()
    do {
      try db.execute(
        sql: sql,
        arguments: [
          "id": entityId, "display_name": displayName, "lookup_key": lookupKey, "color": color,
          "created_at": createdAt, "updated_at": updatedAt, "version": version,
        ])
    } catch { throw ApplyError.lift(error) }
    let upsertModifiedRow = db.changesCount > 0
    // Version-rejected payloads still lower the creation floor (min-register;
    // see ApplyLww.foldCreatedAtFloor) — an alias-remapped envelope may be the
    // only witness of the canonical creation time this peer ever receives.
    try ApplyLww.foldCreatedAtFloor(
      db, table: "tags", pkValue: entityId, incomingCreatedAt: createdAt)

    // Convergence only when the upsert actually modified a row. A stale envelope
    // with a smaller tag id that lost the version check must NOT tombstone the
    // live tag.
    if upsertModifiedRow {
      try merger.mergeDuplicate(
        db, justUpsertedId: entityId, whereClause: "lookup_key = ?", whereArgs: [lookupKey],
        triggeringVersion: version, applyTs: applyTs)
    }
  }

  static func applyTagDelete(_ db: Database, entityId: String, version: String) throws {
    try ApplyLww.lwwGatedDelete(
      db, table: "tags", pkColumns: ["id"], pkValues: [entityId], incomingVersion: version)
  }

  /// `(display_name, color)` for the winner + every loser in one
  /// `WHERE id IN (...)` round-trip, keyed by id.
  private static func readTagMergeFields(
    _ db: Database, ids: [String]
  ) throws -> [String: (displayName: String, color: String?)] {
    let placeholders = Sql.sqlInPlaceholders(ids.count, 0)
    let sql = "SELECT id, display_name, color FROM tags WHERE id IN (\(placeholders))"
    var out: [String: (displayName: String, color: String?)] = [:]
    do {
      for row in try Row.fetchAll(db, sql: sql, arguments: StatementArguments(ids)) {
        let id: String = row[0]
        out[id] = (displayName: row[1], color: row[2])
      }
    } catch { throw ApplyError.lift(error) }
    return out
  }

  /// Compare the surviving content reference `P*` and one content-loser's fields
  /// and return the loser's divergent values as canonical (sorted-key) JSON, or
  /// `nil` when both `display_name` and `color` match exactly — a JSON object of
  /// `{field: loserValue}` for only the fields that differ.
  ///
  /// Emitted via ``SyncCanonicalize/canonicalizeJSON(_:)`` — the same byte-stable
  /// escaping + UTF-8-sorted-key serializer every other divergence hook uses — so
  /// the `loser_payload` TEXT that lands in `sync_conflict_log` (read by
  /// cross-device diagnostics) cannot drift from the shared canonical form. The
  /// sort places `color` before `display_name`.
  private static func divergentTagLoserFields(
    _ reference: (displayName: String, color: String?),
    _ loser: (displayName: String, color: String?)
  ) -> String? {
    var divergent: [String: JSONValue] = [:]
    if reference.displayName != loser.displayName {
      divergent["display_name"] = .string(loser.displayName)
    }
    if reference.color != loser.color {
      divergent["color"] = loser.color.map { .string($0) } ?? .null
    }
    if divergent.isEmpty { return nil }
    return try? SyncCanonicalize.canonicalizeJSON(.object(divergent))
  }
}
