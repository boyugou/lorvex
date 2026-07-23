/// Typed task lifecycle status. The wire format (`rawValue` / ``asString``) is
/// the canonical lower-snake-case identifier shared across the SQL
/// `tasks.status` column, sync envelopes, and the frontend.
public enum TaskStatus: String, Sendable, Hashable, Codable, CaseIterable, CustomStringConvertible {
  /// The default state for newly-created tasks. Eligible for scheduling,
  /// surfacing in Today, etc.
  case open = "open"
  /// Work has started and is not finished. Actionable — surfaces everywhere
  /// `open` does (Today, Upcoming, list health, batch eligibility, blocking
  /// graph). An optional "started" marker that any terminal transition
  /// (`completed` / `cancelled`) replaces automatically. Orthogonal to
  /// `current_focus` (today's shortlist) and the focus schedule (a time plan):
  /// `in_progress` is a lifecycle status, not a planning affordance.
  case inProgress = "in_progress"
  /// Terminal — task was finished. `completed_at` is set; the row no longer
  /// surfaces in active queries.
  case completed = "completed"
  /// Terminal — task was abandoned. `completed_at` is cleared and `defer`
  /// state is reset.
  case cancelled = "cancelled"
  /// Soft-park — task is tracked but excluded from the active list until
  /// manually re-opened. Distinct from `cancelled` (terminal) and `open`
  /// (actionable).
  case someday = "someday"

  /// Wire-format string (matches the SQL `tasks.status` column).
  public var asString: String { rawValue }

  public var description: String { rawValue }

  /// Parse a wire-format string into a typed status. Returns `nil` for unknown
  /// values — callers should surface `nil` as a validation error.
  public static func parse(_ s: String) -> TaskStatus? {
    TaskStatus(rawValue: s)
  }

  /// `true` for `completed` / `cancelled`.
  public var isTerminal: Bool {
    self == .completed || self == .cancelled
  }

  /// `true` for `open` / `in_progress` — the "can be worked now" working set.
  /// The single Swift-level definition of actionability: every surface that
  /// shows the working set (Today / Upcoming pools, list health, reminders,
  /// widget / watch / CarPlay / menu-bar / badge, the Tasks-workspace open lane,
  /// batch eligibility) filters on this, and ``StatusName/actionableStatusSqlList``
  /// derives from it so the SQL and Swift checks cannot drift. Excludes the
  /// soft-parked `someday` and the terminal states.
  public var isActionable: Bool {
    self == .open || self == .inProgress
  }

  /// `true` for every non-terminal task — `open` / `in_progress` / `someday`,
  /// the complement of ``isTerminal``. Surfaces that also include parked work
  /// (the dependency graph, duplicate detection) filter on this, and
  /// ``StatusName/activeStatusSqlList`` derives from it. Broader than
  /// ``isActionable`` because it also counts soft-parked `someday`.
  public var isActive: Bool {
    !isTerminal
  }
}

/// Task lifecycle status string constants, mirroring ``TaskStatus`` raw values.
public enum StatusName {
  public static let open = TaskStatus.open.rawValue
  public static let inProgress = TaskStatus.inProgress.rawValue
  public static let completed = TaskStatus.completed.rawValue
  public static let cancelled = TaskStatus.cancelled.rawValue
  public static let someday = TaskStatus.someday.rawValue

  /// The "active task" predicate value list, ready to drop into a
  /// `WHERE status IN ({…})` SQL fragment. "Active" means a non-terminal task
  /// that still participates in the dependency graph and duplicate detection:
  /// `open`, `in_progress`, or `someday`. Broader than ``actionableStatusSqlList``
  /// because it also counts soft-parked `someday` tasks. Derived from
  /// ``TaskStatus/isActive`` so the SQL membership and the Swift predicate share
  /// one definition and cannot drift.
  public static let activeStatusSqlList = sqlList { $0.isActive }

  /// The "actionable / day-surfacing" predicate value list, ready to drop into a
  /// `WHERE status IN ({…})` SQL fragment. These are the statuses that surface
  /// in day/Today pools, Upcoming, Scheduled, reminders, open counts, and
  /// batch/defer eligibility: `open` or `in_progress` (started). Excludes
  /// soft-parked `someday` and the terminal states. Derived from
  /// ``TaskStatus/isActionable`` so the SQL membership and the Swift predicate
  /// share one definition and cannot drift.
  public static let actionableStatusSqlList = sqlList { $0.isActionable }

  /// Render the ``TaskStatus`` cases satisfying `predicate` into a
  /// comma-separated quoted `'x', 'y'` list for a `status IN (…)` SQL fragment,
  /// in ``TaskStatus/allCases`` declaration order. The single builder both
  /// status lists derive from, so membership is defined once (by the predicate)
  /// rather than hand-transcribed.
  private static func sqlList(_ predicate: (TaskStatus) -> Bool) -> String {
    TaskStatus.allCases.filter(predicate).map { "'\($0.rawValue)'" }.joined(separator: ", ")
  }
}

/// `provider_scope_runtime_state.availability_state` vocabulary. Every SQL
/// builder shares one substitutable token so a typo can't silently fall out of
/// the `availability_state IN (...)` predicate.
public enum AvailabilityState {
  /// The scope is healthy and queryable.
  public static let enabled = "enabled"
  /// The user turned the scope off; it is not queried until re-enabled.
  public static let disabled = "disabled"
  /// The OS denied the scope's permission (Calendar, Reminders, Photos, etc.).
  public static let permissionDenied = "permission_denied"
  /// The OS returned an authorization-shaped error during the fetch (permission
  /// nominally granted, but the fetch is rejected — revoked TCC, container races).
  public static let authorizationError = "authorization_error"
  /// The provider connector itself failed (network, RPC, OS API timeout).
  public static let fetchError = "fetch_error"
  /// The fetched payload could not be parsed into a provider event row.
  public static let parseError = "parse_error"
}
