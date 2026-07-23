import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Content-collision re-point of a loser habit's `habit_completions` rows onto the
/// merge winner, used by ``ApplyHabitMerge`` while collapsing duplicate habits.
///
/// Unlike every other child/edge re-pointed by an aggregate merge (`task_tags`-
/// shaped edges carry no content beyond their linkage), a completion carries
/// user-authored `value`/`note` that can legitimately diverge between the two
/// devices' copies of the same `(habit, date)`. This file arbitrates that content.
enum ApplyHabitCompletionMerge {

  /// One loser `habit_completions` row read prior to any mutation.
  private struct LoserCompletionRow {
    var date: String
    var value: Int64
    var note: String?
    var version: String
    var createdAt: String
    var updatedAt: String
  }

  /// `(value, note, version, created_at, updated_at)` for a winner's pre-existing completion at a date
  /// the loser also completed.
  private struct CompletionSnapshot {
    var value: Int64
    var note: String?
    var version: String
    var createdAt: String
    var updatedAt: String
  }

  /// Re-point the loser's `habit_completions` rows to the winner.
  ///
  /// A date only the loser completed is a plain re-point (no content at stake).
  /// A date BOTH sides completed is a genuine content collision: the row whose
  /// ORIGINAL `version` HLC dominates — ``compareVersionsWithFallback(_:_:)``, the
  /// same parse-then-byte-compare-fallback comparator
  /// ``ApplyLww/lwwGatedDelete(_:table:pkColumns:pkValues:incomingVersion:)`` uses
  /// for every other genuine LWW gate in this codebase — keeps its content; an
  /// unconditional `ON CONFLICT DO UPDATE` would let whichever row already occupied
  /// the `(winnerId, date)` slot win regardless of HLC order, silently discarding a
  /// genuinely later edit. The discarded side is logged as an `lww` conflict
  /// (entity_id `"{winnerId}:{date}"`) so the loss is auditable.
  ///
  /// Every surviving row keeps its ORIGINAL authored `version` (NOT the merge
  /// version). Because `habit_completions` is a content-carrying edge whose LWW
  /// gate compares the completion's own version (``ApplyLww/getLocalVersion`` reads
  /// the edge row, not the habit root), stamping the survivor at `mergeVersion`
  /// would erase its authored HLC: a genuinely-newer completion edge arriving after
  /// the merge would then lose to the synthetic stamp (2-device divergence), and a
  /// stale pre-merge edge whose version sits between `mergeVersion` and the
  /// survivor's true version could regress newer content. Preserving the original
  /// version keeps per-edge arbitration commutative regardless of arrival order and
  /// matches what a peer computes when it remaps the loser's completion edge onto
  /// the winner through the parent habit's permanent alias. The surviving
  /// content participant also supplies BOTH authored timestamps; `applyTs` is
  /// diagnostic metadata only and never enters the synced completion payload.
  static func mergeHabitCompletions(
    _ db: Database, winnerId: String, loserId: String, mergeVersion: String, applyTs: String
  ) throws {
    let loserRows: [LoserCompletionRow]
    do {
      loserRows = try Row.fetchAll(
        db,
        sql: """
          SELECT completed_date, value, note, version, created_at, updated_at
            FROM habit_completions
           WHERE habit_id = ?
          """,
        arguments: [loserId]
      ).map {
        LoserCompletionRow(
          date: $0[0], value: $0[1], note: $0[2], version: $0[3], createdAt: $0[4],
          updatedAt: $0[5])
      }
    } catch { throw ApplyError.lift(error) }

    if !loserRows.isEmpty {
      var winnerByDate: [String: CompletionSnapshot] = [:]
      do {
        let dates = loserRows.map { $0.date }
        // Explicit `?1` for `habit_id` + an offset-by-1 IN list — mixing a bare
        // `?` with the explicitly-numbered IN placeholders would collide (SQLite
        // assigns the bare `?` the next unused number, which is `1`, the same
        // number the IN list's first placeholder already claims).
        let placeholders = Sql.sqlInPlaceholders(dates.count, 1)
        var args: [DatabaseValueConvertible] = [winnerId]
        args.append(contentsOf: dates)
        for row in try Row.fetchAll(
          db,
          sql: """
            SELECT completed_date, value, note, version, created_at, updated_at
              FROM habit_completions
             WHERE habit_id = ?1 AND completed_date IN (\(placeholders))
            """,
          arguments: StatementArguments(args))
        {
          let date: String = row[0]
          winnerByDate[date] = CompletionSnapshot(
            value: row[1], note: row[2], version: row[3], createdAt: row[4], updatedAt: row[5])
        }
      } catch { throw ApplyError.lift(error) }

      for loserRow in loserRows {
        guard let winnerSnapshot = winnerByDate[loserRow.date] else {
          // No collision at this date — plain re-point.
          do {
            try db.execute(
              sql: """
                INSERT INTO habit_completions
                    (habit_id, completed_date, value, note, version, created_at, updated_at)
                 VALUES (:winner_id, :date, :value, :note, :orig_version, :created_at, :updated_at)
                """,
              arguments: [
                "winner_id": winnerId, "date": loserRow.date, "value": loserRow.value,
                "note": loserRow.note, "orig_version": loserRow.version,
                "created_at": loserRow.createdAt, "updated_at": loserRow.updatedAt,
              ])
          } catch { throw ApplyError.lift(error) }
          continue
        }

        // Genuine content collision: the ORIGINAL (pre-merge) HLC decides whose
        // value/note survives.
        let loserDominates =
          compareVersionsWithFallback(loserRow.version, winnerSnapshot.version)
          == .orderedDescending
        let survivingValue = loserDominates ? loserRow.value : winnerSnapshot.value
        let survivingNote = loserDominates ? loserRow.note : winnerSnapshot.note
        let survivingCreatedAt = loserDominates ? loserRow.createdAt : winnerSnapshot.createdAt
        let survivingUpdatedAt = loserDominates ? loserRow.updatedAt : winnerSnapshot.updatedAt
        let discardedValue = loserDominates ? winnerSnapshot.value : loserRow.value
        let discardedNote = loserDominates ? winnerSnapshot.note : loserRow.note
        let discardedVersion = loserDominates ? winnerSnapshot.version : loserRow.version
        // Stamp the survivor at its OWN original HLC (not the merge version) so a
        // later genuinely-newer edge wins the per-edge LWW gate and a stale
        // pre-merge edge cannot regress it.
        let survivingVersion = loserDominates ? loserRow.version : winnerSnapshot.version

        do {
          try db.execute(
            sql: """
              UPDATE habit_completions SET value = :value, note = :note,
                  version = :surviving_version, created_at = :created_at,
                  updated_at = :updated_at
               WHERE habit_id = :winner_id AND completed_date = :date
              """,
            arguments: [
              "value": survivingValue, "note": survivingNote, "surviving_version": survivingVersion,
              "created_at": survivingCreatedAt, "updated_at": survivingUpdatedAt,
              "winner_id": winnerId, "date": loserRow.date,
            ])
        } catch { throw ApplyError.lift(error) }

        if discardedValue != survivingValue || discardedNote != survivingNote {
          var divergent: [String: JSONValue] = [:]
          if discardedValue != survivingValue { divergent["value"] = .int(discardedValue) }
          if discardedNote != survivingNote {
            divergent["note"] = discardedNote.map { .string($0) } ?? .null
          }
          let payload = try? SyncCanonicalize.canonicalizeJSON(.object(divergent))
          let loserDeviceId = AggregateMergeEngine.loserDeviceSuffix(discardedVersion)
          try ConflictLog.logConflict(
            db,
            ConflictLog.Entry(
              entityType: EdgeName.habitCompletion, entityId: "\(winnerId):\(loserRow.date)",
              winnerVersion: mergeVersion, loserVersion: discardedVersion,
              loserDeviceId: loserDeviceId, loserPayload: payload, resolvedAt: applyTs,
              resolutionType: ResolutionName.lww))
        }
      }
    }

    do {
      try db.execute(sql: "DELETE FROM habit_completions WHERE habit_id = ?", arguments: [loserId])
    } catch { throw ApplyError.lift(error) }
  }
}
