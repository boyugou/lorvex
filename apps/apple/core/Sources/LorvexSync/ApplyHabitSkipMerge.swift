import Foundation
import GRDB
import LorvexDomain

/// Re-point of a loser habit's `habit_skips` rows onto the merge winner, used by
/// ``ApplyHabitMerge`` while collapsing duplicate habits.
///
/// A skip carries no content beyond its `(habit, date)` identity, so the two
/// habits' skips combine as a union: a date excused on either side stays excused
/// on the winner. A date both sides skipped keeps the row with the greater
/// authored `version`, so the outcome does not depend on arrival order. Every
/// surviving row keeps its ORIGINAL authored version rather than the merge
/// version, because the per-edge LWW gate compares the skip's own version: a
/// synthetic stamp would let a stale pre-merge edge regress a newer un-skip.
enum ApplyHabitSkipMerge {

  /// Move every `habit_skips` row of `loserId` onto `winnerId`, then drop the
  /// loser's rows.
  static func mergeHabitSkips(
    _ db: Database, winnerId: String, loserId: String
  ) throws {
    do {
      try db.execute(
        sql: """
          INSERT INTO habit_skips (habit_id, skipped_date, version, created_at, updated_at)
          SELECT ?1, skipped_date, version, created_at, updated_at
            FROM habit_skips
           WHERE habit_id = ?2
          ON CONFLICT (habit_id, skipped_date) DO UPDATE SET
              version = excluded.version, created_at = excluded.created_at,
              updated_at = excluded.updated_at
           WHERE excluded.version > habit_skips.version
          """,
        arguments: [winnerId, loserId])
      try db.execute(sql: "DELETE FROM habit_skips WHERE habit_id = ?", arguments: [loserId])
    } catch { throw ApplyError.lift(error) }
  }
}
