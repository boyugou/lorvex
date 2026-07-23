import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// `(habit_id, reminder_time)` dedup convergence for the `habit_reminder_policy`
/// independent child (W-1), the reminder-policy analog of ``ApplyTagMerge``.
///
/// When two devices add a reminder for the SAME habit at the SAME time offline they
/// each mint a distinct policy id but share one `(habit_id, reminder_time)` pair. On
/// inbound sync the second policy trips `habit_reminder_policies`'
/// `UNIQUE(habit_id, reminder_time)`; without convergence that constraint escapes
/// ``ApplyChild`` as the batch-fatal ``ApplyError/db`` and wedges the whole inbound
/// page. The shared ``AggregateMergeEngine`` collapses the duplicates instead:
/// `min(id)` wins IDENTITY and the max-HLC participant's `enabled` wins CONTENT
/// (carried onto the winner id when it differs); the loser row is deleted (its
/// device-local `habit_reminder_delivery_state` cascades away) and tombstoned with
/// a redirect so its references and future envelopes resolve to the winner. One
/// `tag_merge` conflict-log row is emitted per content-loser (`entity_type`
/// distinguishes it from the tag/habit dedup merges that share the resolution
/// type), carrying that loser's diverging `enabled` as its payload (`nil` when it
/// matches the surviving content; `reminder_time` is the collision key and never
/// diverges).
///
/// A policy id carries no synced foreign-key references (only the device-local
/// delivery-state row keys off it), so a merge re-points no synced edges — the
/// collapse is a delete + tombstone-with-redirect.
enum ApplyHabitReminderPolicyMerge {

  /// The policy realization of ``AggregateMergeEngine``.
  static var merger: AggregateMergeEngine {
    AggregateMergeEngine(
      entityName: EntityName.habitReminderPolicy,
      table: "habit_reminder_policies",
      resolutionType: ResolutionName.tagMerge,
      savepointName: "merge_habit_reminder_policy",
      mergeLabel: "habit reminder policy",
      alwaysLogConflict: true,
      foldsCreatedAtFloor: true,
      carryContent: { db, winnerId, sourceId, mode in
        do {
          switch mode {
          case .naturalKey:
            // The natural-key insert path may stage the incoming policy under a
            // synthetic time, so only the independent enabled content is carried.
            try db.execute(
              sql: """
                UPDATE habit_reminder_policies SET
                    enabled = (SELECT enabled FROM habit_reminder_policies WHERE id = :src),
                    updated_at = (SELECT updated_at FROM habit_reminder_policies WHERE id = :src)
                 WHERE id = :winner
                """,
              arguments: ["src": sourceId, "winner": winnerId])
          case .permanentAlias:
            // A source-addressed edit can change its parent habit or time after
            // the alias was authored. Alias-late must match alias-first, where
            // that complete payload is remapped onto the canonical id. Capture
            // it, vacate the UNIQUE slot, then update the winner atomically.
            guard
              let source = try Row.fetchOne(
                db,
                sql: """
                  SELECT habit_id, reminder_time, enabled, updated_at
                    FROM habit_reminder_policies WHERE id = ?
                  """,
                arguments: [sourceId])
            else {
              throw ApplyError.store(
                "habit reminder policy carry source row missing for id=\(sourceId)")
            }
            try db.execute(
              sql: "UPDATE habit_reminder_policies SET reminder_time = ? WHERE id = ?",
              arguments: [stagingReminderTime(for: sourceId), sourceId])
            try db.execute(
              sql: """
                UPDATE habit_reminder_policies SET
                    habit_id = :habit_id, reminder_time = :reminder_time,
                    enabled = :enabled, updated_at = :updated_at
                 WHERE id = :winner
                """,
              arguments: [
                "habit_id": source["habit_id"] as String,
                "reminder_time": source["reminder_time"] as String,
                "enabled": source["enabled"] as Int64,
                "updated_at": source["updated_at"] as String,
                "winner": winnerId,
              ])
          }
        } catch { throw ApplyError.lift(error) }
      },
      prepareDivergence: AggregateMergeEngine.snapshotDivergence(
        label: "habit reminder policy",
        read: { db, ids in try readPolicyFieldSnapshots(db, ids: ids) },
        compare: divergentPolicyLoserFields),
      repointAndDeleteLoser: { db, loserId, _, _, _ in
        do {
          // Delete the loser policy. Its device-local
          // `habit_reminder_delivery_state` row (PK = policy_id) cascades away; the
          // winner keeps its own. There are no synced references to re-point.
          try db.execute(
            sql: "DELETE FROM habit_reminder_policies WHERE id = ?", arguments: [loserId])
        } catch { throw ApplyError.lift(error) }
      })
  }

  /// A synthetic, guaranteed-non-colliding `reminder_time` used to stage the
  /// incoming policy beside an existing claimant during an insert-collision merge.
  /// It embeds the entity id so the staged `(habit_id, reminder_time)` pair is
  /// unique; the merge restores the real reminder_time to the winner afterward.
  static func stagingReminderTime(for entityId: String) -> String {
    "__merge_stage__:\(entityId)"
  }

  /// Entry point wired into ``ApplyChild`` after a landed policy upsert.
  static func mergeDuplicatePolicies(
    _ db: Database, justUpsertedId: String, habitId: String, reminderTime: String, version: String,
    applyTs: String
  ) throws {
    try merger.mergeDuplicate(
      db, justUpsertedId: justUpsertedId, whereClause: "habit_id = ? AND reminder_time = ?",
      whereArgs: [habitId, reminderTime], triggeringVersion: version, applyTs: applyTs)
  }

  /// Resolve two same-time policies while their parent habits are being merged.
  /// Policy identity/content convergence mints from the policy participants only
  /// (not the parent stamp), keeping the result independent of whether the child
  /// collision happens before, during, or after the parent merge.
  static func mergePoliciesDuringHabitMerge(
    _ db: Database, firstPolicyId: String, secondPolicyId: String,
    winnerHabitId: String, applyTs: String
  ) throws -> String {
    let rows: [(id: String, version: String, reminderTime: String)]
    do {
      rows = try Row.fetchAll(
        db,
        sql: """
          SELECT id, version, reminder_time FROM habit_reminder_policies
           WHERE id IN (?, ?) ORDER BY id
          """,
        arguments: [firstPolicyId, secondPolicyId]
      ).map { (id: $0[0], version: $0[1], reminderTime: $0[2]) }
    } catch { throw ApplyError.lift(error) }
    guard rows.count == 2, rows[0].reminderTime == rows[1].reminderTime else {
      throw ApplyError.store("habit merge policy collision rows are missing or disagree on time")
    }
    guard
      let triggeringVersion = rows.compactMap({ try? Hlc.parseCanonical($0.version) }).max()?
        .description
    else {
      throw ApplyError.invalidVersion("habit merge policy collision has no canonical version")
    }
    guard
      let survivor = try merger.mergeKnownDuplicate(
        db, rows: rows.map { ($0.id, $0.version) },
        triggeringVersion: triggeringVersion, applyTs: applyTs,
        beforeWinnerEnqueue: { db, winnerId in
          // The aggregate engine snapshots the canonical winner payload after
          // this hook. Re-point here, not after mergeKnownDuplicate returns, or
          // the queued winner upsert retains the deleted parent habit id and can
          // reintroduce the stale FK on another peer.
          try db.execute(
            sql: "UPDATE habit_reminder_policies SET habit_id = ? WHERE id = ?",
            arguments: [winnerHabitId, winnerId])
          guard db.changesCount == 1 else {
            throw ApplyError.store("habit merge policy survivor disappeared before re-point")
          }
        })
    else {
      throw ApplyError.store("habit merge policy collision produced no survivor")
    }
    guard
      try String.fetchOne(
        db, sql: "SELECT habit_id FROM habit_reminder_policies WHERE id = ?",
        arguments: [survivor]) == winnerHabitId
    else { throw ApplyError.store("habit merge policy survivor re-point did not persist") }
    return survivor
  }

  /// The policy's content-bearing columns worth capturing on merge loss.
  /// `reminder_time` is the collision key (identical by construction, and the
  /// insert-collision path stages the incoming row under
  /// ``stagingReminderTime(for:)`` before the merge runs, so its raw column value
  /// is unreliable at merge time); `habit_id` is fixed identical (both belong to
  /// the same habit). `enabled` is the only field that can genuinely diverge.
  private struct PolicyFieldSnapshot {
    var enabled: Int64
  }

  /// Batched pre-merge field-content read for the winner + every loser, keyed by id.
  private static func readPolicyFieldSnapshots(
    _ db: Database, ids: [String]
  ) throws -> [String: PolicyFieldSnapshot] {
    let placeholders = Sql.sqlInPlaceholders(ids.count, 0)
    var out: [String: PolicyFieldSnapshot] = [:]
    do {
      for row in try Row.fetchAll(
        db,
        sql: "SELECT id, enabled FROM habit_reminder_policies WHERE id IN (\(placeholders))",
        arguments: StatementArguments(ids))
      {
        let id: String = row[0]
        out[id] = PolicyFieldSnapshot(enabled: row[1])
      }
    } catch { throw ApplyError.lift(error) }
    return out
  }

  /// Compare the surviving content reference `P*` and one content-loser's fields
  /// and return the loser's divergent values as canonical (sorted-key) JSON, or
  /// `nil` when every field matches — a JSON object of `{field: loserValue}` for
  /// only the fields that differ.
  private static func divergentPolicyLoserFields(
    _ reference: PolicyFieldSnapshot, _ loser: PolicyFieldSnapshot
  ) -> String? {
    guard reference.enabled != loser.enabled else { return nil }
    return try? SyncCanonicalize.canonicalizeJSON(.object(["enabled": .bool(loser.enabled != 0)]))
  }

  // MARK: - Insert-collision merge

  /// Resolve a `(habit_id, reminder_time)` UNIQUE collision raised by a policy
  /// upsert: stage the incoming row (via `stageIncomingWithSyntheticTime`, which
  /// lands it with a non-colliding synthetic reminder_time), then collapse the
  /// duplicates. `min(id)` wins; when the incoming row is the winner its real
  /// reminder_time is restored.
  static func insertPolicyByMergingCollision(
    _ db: Database, entityId: String, habitId: String, reminderTime: String, version: String,
    applyTs: String, originalError: DatabaseError,
    stageIncomingWithSyntheticTime: (Database) throws -> Void
  ) throws -> CollisionMergeOutcome {
    let existingRows = try collisionRows(
      db, habitId: habitId, reminderTime: reminderTime, excludingId: entityId)
    return try merger.insertByMergingCollision(
      db, entityId: entityId, version: version, applyTs: applyTs, existingRows: existingRows,
      originalError: originalError, collisionSavepoint: "habit_reminder_policy_collision",
      stageIncoming: stageIncomingWithSyntheticTime,
      restoreWinner: { db in
        try db.execute(
          sql: "UPDATE habit_reminder_policies SET reminder_time = ? WHERE id = ?",
          arguments: [reminderTime, entityId])
      })
  }

  private static func collisionRows(
    _ db: Database, habitId: String, reminderTime: String, excludingId: String
  ) throws -> [(String, String)] {
    do {
      return try Row.fetchAll(
        db,
        sql: """
          SELECT id, version FROM habit_reminder_policies
           WHERE habit_id = ? AND reminder_time = ? AND id != ?
           ORDER BY id ASC
          """,
        arguments: [habitId, reminderTime, excludingId]
      ).map { ($0[0], $0[1]) }
    } catch { throw ApplyError.lift(error) }
  }
}
