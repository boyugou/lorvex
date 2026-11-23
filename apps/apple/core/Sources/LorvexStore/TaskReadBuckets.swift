import Foundation

/// SQL predicate builders for the canonical open-task day buckets:
/// `overdue`, `today_pool`, and `upcoming`.
///
/// A task's day is its action date: `planned_date` when it has one, else
/// `due_date`. The three buckets partition the dated tasks by that day:
/// `overdue` and `today_pool` together hold every task whose day is `<date>`
/// or earlier (split by whether the deadline has passed), and `upcoming` holds
/// the tasks whose day is later. A task planned for a later day is therefore
/// in `upcoming` even when its deadline has passed: planning it is how it
/// leaves the day, and it returns on the day it was planned for.
///
/// All three predicates operate over a `tasks` row scoped by the caller's
/// outer `WHERE status IN ('open', 'in_progress') AND archived_at IS NULL`.
/// The `taskAlias` argument is the table alias used in the surrounding SQL
/// (typically `"tasks"` or `"t"`); the `*Placeholder` arguments are the SQL
/// parameter placeholders the caller binds (`"?"`, `"?1"`, `":today"`, etc.).
///
/// Every shape reads the action date as `COALESCE(planned_date, due_date)`
/// rather than a column-split OR so it can hit the
/// `idx_tasks_action_date_actionable` expression index, whose partial
/// predicate is byte-aligned with the callers' exact
/// `status IN ('open', 'in_progress') AND archived_at IS NULL` guards.
public enum TaskReadBuckets {
  /// Overdue predicate: the deadline (`due_date`) has passed, and the action
  /// date is on or before `<date>`. A passed deadline with no planned date
  /// qualifies by itself, since the deadline is then the action date.
  public static func overdueBucketPredicate(
    taskAlias: String, datePlaceholder: String
  ) -> String {
    "(\(taskAlias).due_date < \(datePlaceholder)"
      + " AND COALESCE(\(taskAlias).planned_date, \(taskAlias).due_date) <= \(datePlaceholder))"
  }

  /// Today-pool predicate: action date (planned else due) is on or before
  /// `<date>`, AND the deadline (due_date) either is absent or has not yet
  /// passed (`>= <date>`). The deadline guard excludes the overdue case.
  public static func todayPoolBucketPredicate(
    taskAlias: String, datePlaceholder: String
  ) -> String {
    "(COALESCE(\(taskAlias).planned_date, \(taskAlias).due_date) <= \(datePlaceholder)"
      + " AND (\(taskAlias).due_date IS NULL OR \(taskAlias).due_date >= \(datePlaceholder)))"
  }

  /// Upcoming predicate: action date falls inside `(from, to]`.
  /// `fromPlaceholder` is exclusive (`> from`); `toPlaceholder` is inclusive
  /// (`<= to`). The deadline plays no part, so a task whose deadline has
  /// passed and that is planned for a later day is upcoming on that day.
  public static func upcomingBucketPredicate(
    taskAlias: String, fromPlaceholder: String, toPlaceholder: String
  ) -> String {
    "(COALESCE(\(taskAlias).planned_date, \(taskAlias).due_date) > \(fromPlaceholder)"
      + " AND COALESCE(\(taskAlias).planned_date, \(taskAlias).due_date) <= \(toPlaceholder))"
  }

  /// Defer-until (`available_from`) visibility conjunct, with **overdue-wins**:
  /// a task is visible on `<date>` when it is not hidden (`available_from` is
  /// null or already reached) OR it is overdue (`due_date` strictly before
  /// `<date>`). An overdue task is never hidden — a hide-until must not silently
  /// suppress a missed deadline. Callers AND this into `WHERE status = 'open'`
  /// day-surface reads (today pool, upcoming, high-priority-undated). The
  /// OVERDUE bucket deliberately omits it so hidden-but-overdue rows still
  /// surface there.
  public static func availableVisibilityPredicate(
    taskAlias: String, datePlaceholder: String
  ) -> String {
    "(\(taskAlias).available_from IS NULL"
      + " OR \(taskAlias).available_from <= \(datePlaceholder)"
      + " OR (\(taskAlias).due_date IS NOT NULL AND \(taskAlias).due_date < \(datePlaceholder)))"
  }

  /// Hidden-and-scheduled conjunct — the exact negation of
  /// ``availableVisibilityPredicate(taskAlias:datePlaceholder:)``: rows whose
  /// `available_from` is strictly after `<date>` AND that are not overdue.
  /// Backs the Scheduled section read and the `availability = hidden` list
  /// filter.
  public static func hiddenScheduledPredicate(
    taskAlias: String, datePlaceholder: String
  ) -> String {
    "(\(taskAlias).available_from IS NOT NULL"
      + " AND \(taskAlias).available_from > \(datePlaceholder)"
      + " AND NOT (\(taskAlias).due_date IS NOT NULL AND \(taskAlias).due_date < \(datePlaceholder)))"
  }
}
