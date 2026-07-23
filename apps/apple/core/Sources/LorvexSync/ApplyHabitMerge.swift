import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// `lookup_key` dedup convergence for the `habit` aggregate root (W-1), the habit
/// analog of ``ApplyTagMerge`` (both collapse duplicates sharing a normalized
/// `lookup_key`).
///
/// When two devices create the SAME habit offline they each mint a distinct id but
/// the domain normalizer derives one `lookup_key` for both. On inbound sync the
/// second habit trips the partial `UNIQUE(lookup_key) WHERE archived = 0`; without
/// convergence that constraint escapes ``ApplyHabit`` as the batch-fatal
/// ``ApplyError/db`` and wedges the whole inbound page. The shared
/// ``AggregateMergeEngine`` collapses the duplicates instead: `min(id)` wins
/// IDENTITY while the max-HLC participant `P*` wins CONTENT. This file supplies the
/// habit hooks. `carryContent` copies `P*`'s `name` + nine scalar columns +
/// `updated_at` onto the winner, and — because `habit_weekdays` is the habit's
/// content-bearing collection, not a re-pointable child — REPLACES the winner's
/// `habit_weekdays` rows with `P*`'s (before any loser delete, since `P*` may be an
/// identity-loser whose own rows are about to cascade away). The loser's synced
/// children re-point to the winner: the `habit_completions` composite edge merges
/// on `(habit_id, completed_date)` via
/// ``ApplyHabitCompletionMerge/mergeHabitCompletions(_:winnerId:loserId:mergeVersion:applyTs:)`` — a date
/// only one side completed re-points outright; a date BOTH sides completed is a
/// genuine content collision, HLC-arbitrated (independently of the habit-root
/// content policy) with the discarded `value`/`note` logged as an `lww` conflict —
/// and `habit_reminder_policies` move to the winner: policies colliding in the
/// same `(winner, reminder_time)` slot are themselves min-id/max-HLC merged, so
/// the newer `enabled` content survives and the identity loser is tombstoned with
/// a redirect to the canonical policy. One `tag_merge`
/// conflict-log row is emitted per content-loser (`entity_type` distinguishes it
/// from the tag/policy dedup merges that share the resolution type), carrying that
/// loser's diverging `icon`/`color`/`cue`/`frequency_type`/`per_period_target`/
/// `day_of_month`/`target_count`/`milestone_target`/`position` as its payload (`nil`
/// when every field matches the surviving content). `weekdays` is deliberately NOT captured in
/// the audit snapshot: the `habit_weekdays` child is rebuilt from the payload at a
/// point that differs between the two merge entry points (before the
/// insert-collision merge, after the post-upsert dedup tail), so comparing it there
/// would read stale/empty state — the same ordering hazard
/// the aggregate merge engine avoids for opaque annotations. (It is still CARRIED as
/// content; only its appearance in the conflict-log diff is suppressed.)
///
/// Only ACTIVE habits participate: an archived habit is outside the partial UNIQUE
/// index (a user may recreate a habit with the same name after archiving the old
/// one), so archived rows never collide and are never merged.
enum ApplyHabitMerge {

  /// The habit realization of ``AggregateMergeEngine``.
  static var merger: AggregateMergeEngine {
    AggregateMergeEngine(
      entityName: EntityName.habit,
      table: "habits",
      resolutionType: ResolutionName.tagMerge,
      savepointName: "merge_habit",
      mergeLabel: "habit",
      alwaysLogConflict: true,
      foldsCreatedAtFloor: true,
      carryContent: { db, winnerId, sourceId, mode in
        do {
          // Copy P*'s name + the nine divergence-snapshot scalars + updated_at.
          // A natural-key collision already guarantees identical lookup keys and
          // must ignore the insert path's temporary archived staging bit. A
          // permanent alias is stronger: a post-merge edit may have renamed or
          // archived the still-live source, so copy those fields too.
          guard
            let row = try Row.fetchOne(
              db,
              sql: """
                SELECT name, icon, color, cue, frequency_type, per_period_target, day_of_month,
                       target_count, milestone_target, archived, position, updated_at
                 FROM habits WHERE id = ?
                """,
              arguments: [sourceId])
          else {
            throw ApplyError.store("habit carry source row missing for id=\(sourceId)")
          }
          let name: String = row["name"]
          let aliasColumns: String
          switch mode {
          case .naturalKey:
            aliasColumns = ""
          case .permanentAlias:
            // Vacate the source's active partial-UNIQUE slot before assigning
            // its derived key to the winner. The source is deleted later in this
            // savepoint; its captured archived bit is applied to the winner.
            try db.execute(
              sql: "UPDATE habits SET archived = 1 WHERE id = ?", arguments: [sourceId])
            aliasColumns = "lookup_key = :lookup_key, archived = :archived,"
          }
          try db.execute(
            sql: """
              UPDATE habits SET
                  name = :name, icon = :icon, color = :color, cue = :cue,
                  frequency_type = :frequency_type, per_period_target = :per_period_target,
                  day_of_month = :day_of_month, target_count = :target_count,
                  milestone_target = :milestone_target, \(aliasColumns) position = :position,
                  updated_at = :updated_at
               WHERE id = :winner
              """,
            arguments: [
              "name": name, "icon": row["icon"] as String?,
              "color": row["color"] as String?, "cue": row["cue"] as String?,
              "frequency_type": row["frequency_type"] as String,
              "per_period_target": row["per_period_target"] as Int64,
              "day_of_month": row["day_of_month"] as Int64?,
              "target_count": row["target_count"] as Int64,
              "milestone_target": row["milestone_target"] as Int64?,
              "lookup_key": normalizeLookupKey(name),
              "archived": row["archived"] as Int64,
              "position": row["position"] as Int64,
              "updated_at": row["updated_at"] as String, "winner": winnerId,
            ])
          // Replace the winner's habit_weekdays with P*'s. This runs BEFORE the
          // loser loop, so when P* is an identity-loser its own rows still exist to
          // copy (they cascade away only when the loser row is later deleted).
          try db.execute(
            sql: "DELETE FROM habit_weekdays WHERE habit_id = ?", arguments: [winnerId])
          try db.execute(
            sql: """
              INSERT INTO habit_weekdays (habit_id, weekday)
               SELECT :winner, weekday FROM habit_weekdays WHERE habit_id = :src
              """,
            arguments: ["winner": winnerId, "src": sourceId])
        } catch { throw ApplyError.lift(error) }
      },
      prepareDivergence: AggregateMergeEngine.snapshotDivergence(
        label: "habit",
        read: { db, ids in try readHabitFieldSnapshots(db, ids: ids) },
        compare: divergentHabitLoserFields),
      repointAndDeleteLoser: { db, loserId, winnerId, mergeVersion, now in
        // habit_completions — composite edge PK `(habit_id, completed_date)`. A
        // date neither side completed re-points outright; a date BOTH sides
        // completed is a genuine content collision (unlike every other re-pointed
        // child here, a completion carries user-authored `value`/`note`), resolved
        // by ``ApplyHabitCompletionMerge/mergeHabitCompletions(_:winnerId:loserId:mergeVersion:applyTs:)``.
        try ApplyHabitCompletionMerge.mergeHabitCompletions(
          db, winnerId: winnerId, loserId: loserId, mergeVersion: mergeVersion, applyTs: now)

        do {
          // habit_reminder_policies — independent child, UNIQUE(habit_id, reminder_time).
          // Move the movable policies to the winner; ones whose reminder_time slot is
          // already taken under the winner are skipped by UPDATE OR IGNORE and handled
          // as duplicates below.
          try db.execute(
            sql: """
              UPDATE OR IGNORE habit_reminder_policies
                 SET habit_id = :winner_id
               WHERE habit_id = :loser_id
              """,
            arguments: ["winner_id": winnerId, "loser_id": loserId])

          // Leftover loser policies collided with a winner policy at the same
          // reminder_time. Resolve identity by min-id and CONTENT by policy HLC,
          // then move the survivor to the winner habit. Dropping the leftover
          // outright would lose a later `enabled` edit.
          let leftovers = try Row.fetchAll(
            db,
            sql: "SELECT id, reminder_time FROM habit_reminder_policies WHERE habit_id = ?",
            arguments: [loserId]
          ).map { (id: $0[0] as String, reminderTime: $0[1] as String) }
          for leftover in leftovers {
            let winnerPolicyId = try String.fetchOne(
              db,
              sql:
                "SELECT id FROM habit_reminder_policies WHERE habit_id = ? AND reminder_time = ? LIMIT 1",
              arguments: [winnerId, leftover.reminderTime])
            guard let winnerPolicyId else {
              throw ApplyError.store(
                "habit merge policy collision target missing at \(leftover.reminderTime)")
            }
            _ = try ApplyHabitReminderPolicyMerge.mergePoliciesDuringHabitMerge(
              db, firstPolicyId: leftover.id, secondPolicyId: winnerPolicyId,
              winnerHabitId: winnerId, applyTs: now)
          }

          // Delete the loser habit. Any stragglers (none remain) cascade.
          try db.execute(sql: "DELETE FROM habits WHERE id = ?", arguments: [loserId])
        } catch { throw ApplyError.lift(error) }
      })
  }

  // MARK: - Post-upsert dedup (convergence tail)

  /// Entry point wired into ``ApplyHabit`` after a landed active-habit upsert.
  static func mergeDuplicateHabits(
    _ db: Database, justUpsertedId: String, lookupKey: String, version: String, applyTs: String
  ) throws {
    try merger.mergeDuplicate(
      db, justUpsertedId: justUpsertedId, whereClause: "lookup_key = ? AND archived = 0",
      whereArgs: [lookupKey], triggeringVersion: version, applyTs: applyTs)
  }

  /// Merge a caller-provided duplicate set. Used by the insert-collision path,
  /// where the incoming row is staged as `archived = 1` (outside the partial UNIQUE
  /// index) so the two duplicates can be collapsed. Returns the surviving
  /// (`min(id)`) winner, or `nil` when there is nothing to merge.
  @discardableResult
  static func mergeKnownDuplicateHabits(
    _ db: Database, rows: [(String, String)], triggeringVersion: String, applyTs: String
  ) throws -> String? {
    try merger.mergeKnownDuplicate(
      db, rows: rows, triggeringVersion: triggeringVersion, applyTs: applyTs)
  }

  /// `(icon, color, cue, frequency_type, per_period_target, day_of_month,
  /// target_count, milestone_target, position)` for one habit row — the divergence-audit
  /// snapshot set, a strict subset of the carry-set (`carryContent` additionally
  /// copies `name` + the `habit_weekdays` child). `lookup_key` is the collision key
  /// (identical by construction); `name` is carried but omitted from the audit diff
  /// (its normalized form IS `lookup_key`, so a real divergence there shows up as a
  /// scalar difference); archived/timestamps are not user-authored content.
  /// `position` is the synced user-authored board order. `weekdays` is intentionally NOT captured in the audit: the
  /// `habit_weekdays` child is rebuilt from the payload at a point that differs
  /// between the two merge entry points, so it reads stale in the snapshot (see the
  /// ``ApplyHabitMerge`` type docstring).
  private struct HabitFieldSnapshot {
    var icon: String?
    var color: String?
    var cue: String?
    var frequencyType: String
    var perPeriodTarget: Int64
    var dayOfMonth: Int64?
    var targetCount: Int64
    var milestoneTarget: Int64?
    var position: Int64
  }

  /// Batched pre-merge field-content read for the winner + every loser, keyed by id.
  private static func readHabitFieldSnapshots(
    _ db: Database, ids: [String]
  ) throws -> [String: HabitFieldSnapshot] {
    let placeholders = Sql.sqlInPlaceholders(ids.count, 0)
    var out: [String: HabitFieldSnapshot] = [:]
    do {
      for row in try Row.fetchAll(
        db,
        sql: """
          SELECT id, icon, color, cue, frequency_type, per_period_target, day_of_month,
                 target_count, milestone_target, position
           FROM habits WHERE id IN (\(placeholders))
          """,
        arguments: StatementArguments(ids))
      {
        let id: String = row[0]
        out[id] = HabitFieldSnapshot(
          icon: row[1], color: row[2], cue: row[3], frequencyType: row[4],
          perPeriodTarget: row[5], dayOfMonth: row[6], targetCount: row[7],
          milestoneTarget: row[8], position: row[9])
      }
    } catch { throw ApplyError.lift(error) }
    return out
  }

  /// Compare the surviving content reference `P*` and one content-loser's fields
  /// and return the loser's divergent values as canonical (sorted-key) JSON, or
  /// `nil` when every field matches — a JSON object of `{field: loserValue}` for
  /// only the fields that differ.
  private static func divergentHabitLoserFields(
    _ reference: HabitFieldSnapshot, _ loser: HabitFieldSnapshot
  ) -> String? {
    var divergent: [String: JSONValue] = [:]
    if reference.icon != loser.icon { divergent["icon"] = loser.icon.map { .string($0) } ?? .null }
    if reference.color != loser.color {
      divergent["color"] = loser.color.map { .string($0) } ?? .null
    }
    if reference.cue != loser.cue { divergent["cue"] = loser.cue.map { .string($0) } ?? .null }
    if reference.frequencyType != loser.frequencyType {
      divergent["frequency_type"] = .string(loser.frequencyType)
    }
    // `weekdays` is intentionally excluded from the audit diff — the
    // `habit_weekdays` child is rebuilt at points that differ across the two merge
    // entry points, so it reads stale here (see ``HabitFieldSnapshot`` / the type
    // docstring). It is still carried as content.
    if reference.perPeriodTarget != loser.perPeriodTarget {
      divergent["per_period_target"] = .int(loser.perPeriodTarget)
    }
    if reference.dayOfMonth != loser.dayOfMonth {
      divergent["day_of_month"] = loser.dayOfMonth.map { .int($0) } ?? .null
    }
    if reference.targetCount != loser.targetCount {
      divergent["target_count"] = .int(loser.targetCount)
    }
    if reference.milestoneTarget != loser.milestoneTarget {
      divergent["milestone_target"] = loser.milestoneTarget.map { .int($0) } ?? .null
    }
    if reference.position != loser.position {
      divergent["position"] = .int(loser.position)
    }
    if divergent.isEmpty { return nil }
    return try? SyncCanonicalize.canonicalizeJSON(.object(divergent))
  }

  // MARK: - Insert-collision merge

  /// Resolve a `lookup_key` UNIQUE collision raised by an active-habit upsert: stage
  /// the incoming row (via `stageIncomingArchived`, which lands it as `archived = 1`
  /// so it sits outside the partial UNIQUE index), then collapse the duplicates.
  /// `min(id)` wins; when the incoming row is the winner its real archived flag is
  /// restored.
  static func insertHabitByMergingCollision(
    _ db: Database, entityId: String, lookupKey: String, archived: Int64, version: String,
    applyTs: String, originalError: DatabaseError, stageIncomingArchived: (Database) throws -> Void
  ) throws -> CollisionMergeOutcome {
    let existingRows = try collisionRows(db, lookupKey: lookupKey, excludingId: entityId)
    return try merger.insertByMergingCollision(
      db, entityId: entityId, version: version, applyTs: applyTs, existingRows: existingRows,
      originalError: originalError, collisionSavepoint: "habit_collision",
      stageIncoming: stageIncomingArchived,
      restoreWinner: { db in
        try db.execute(
          sql: "UPDATE habits SET archived = ? WHERE id = ?", arguments: [archived, entityId])
      })
  }

  private static func collisionRows(
    _ db: Database, lookupKey: String, excludingId: String
  ) throws -> [(String, String)] {
    do {
      return try Row.fetchAll(
        db,
        sql: """
          SELECT id, version FROM habits
           WHERE lookup_key = ? AND archived = 0 AND id != ?
           ORDER BY id ASC
          """,
        arguments: [lookupKey, excludingId]
      ).map { ($0[0], $0[1]) }
    } catch { throw ApplyError.lift(error) }
  }
}
