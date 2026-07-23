import Foundation

/// SQL predicate builders for the canonical open-task day buckets:
/// `overdue`, `today_pool`, and `upcoming`.
///
/// All three predicates operate over a `tasks` row scoped by the caller's
/// outer `WHERE status = 'open' AND archived_at IS NULL`. The `taskAlias`
/// argument is the table alias used in the surrounding SQL (typically
/// `"tasks"` or `"t"`); the `*Placeholder` arguments are the SQL parameter
/// placeholders the caller binds (`"?"`, `"?1"`, `":today"`, etc.).
///
/// The `today_pool` and `upcoming` shapes use `COALESCE(planned_date,
/// due_date)` rather than a column-split OR so they can hit the
/// `idx_tasks_action_date_actionable` expression index, whose partial
/// predicate is byte-aligned with the callers' exact
/// `status IN ('open', 'in_progress') AND archived_at IS NULL` guards.
/// The transformation is algebraically equivalent under that status guard.
public enum TaskReadBuckets {
  /// `<alias>.due_date < <date>`. Rows whose due date has already passed.
  public static func overdueBucketPredicate(
    taskAlias: String, datePlaceholder: String
  ) -> String {
    "\(taskAlias).due_date < \(datePlaceholder)"
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

  /// Upcoming predicate: action date falls inside `(from, to]` and the
  /// deadline is either absent or `>= from`. `fromPlaceholder` is exclusive
  /// (`> from`); `toPlaceholder` is inclusive (`<= to`).
  public static func upcomingBucketPredicate(
    taskAlias: String, fromPlaceholder: String, toPlaceholder: String
  ) -> String {
    "((\(taskAlias).due_date IS NULL OR \(taskAlias).due_date >= \(fromPlaceholder))"
      + " AND COALESCE(\(taskAlias).planned_date, \(taskAlias).due_date) > \(fromPlaceholder)"
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
