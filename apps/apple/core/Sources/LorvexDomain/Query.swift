import Foundation

/// Canonical query predicates — pure business-rule definitions.
///
/// Encodes what each query means in domain terms with no SQL or storage
/// coupling. Repository layers translate predicates to SQL; the MCP host and
/// platform surfaces construct predicates from their own parameters and call
/// the same repository method, so WHERE-clause logic lives in exactly one place.
public struct TodayPredicate: Sendable, Equatable {
  public var date: IsoDate.YMD
  public init(date: IsoDate.YMD) { self.date = date }
}

/// `due_date < as_of_date AND status = 'open'`.
public struct OverduePredicate: Sendable, Equatable {
  public var asOfDate: IsoDate.YMD
  public init(asOfDate: IsoDate.YMD) { self.asOfDate = asOfDate }
}

/// Effective action date (`planned_date` when present, otherwise `due_date`)
/// falls strictly after `from_date` and on or before `from_date + days`,
/// while the task is not already deadline-overdue.
public struct UpcomingPredicate: Sendable, Equatable {
  public var fromDate: IsoDate.YMD
  public var days: UInt32
  public init(fromDate: IsoDate.YMD, days: UInt32) {
    self.fromDate = fromDate
    self.days = days
  }
}

/// Canonical lateness state for an open task. Snake-case wire form is the
/// canonical IPC and MCP serialization.
public enum TaskLateness: String, Sendable, Equatable, Codable {
  case pastPlanned = "past_planned"
  case overdueUnhandled = "overdue_unhandled"
  case overdueAcknowledged = "overdue_acknowledged"
}

/// Full-text search with optional filters. `query` is FTS5-sanitized before use.
public struct SearchPredicate: Sendable, Equatable {
  public var query: String
  public var statusFilter: [String]?
  public var listFilter: [String]?
  public var tagFilter: [String]?

  public init(
    query: String,
    statusFilter: [String]? = nil,
    listFilter: [String]? = nil,
    tagFilter: [String]? = nil
  ) {
    self.query = query
    self.statusFilter = statusFilter
    self.listFilter = listFilter
    self.tagFilter = tagFilter
  }
}

/// Full-text search for calendar events.
public struct CalendarSearchPredicate: Sendable, Equatable {
  public var query: String
  public var from: String?
  public var to: String?
  public init(query: String, from: String? = nil, to: String? = nil) {
    self.query = query
    self.from = from
    self.to = to
  }
}

/// Common pagination parameters for list queries.
public struct Pagination: Sendable, Equatable {
  public var limit: UInt32
  public var offset: UInt32
  public init(limit: UInt32 = 100, offset: UInt32 = 0) {
    self.limit = limit
    self.offset = offset
  }

  public static let `default` = Pagination()
}

public enum Query {
  /// Deadline-overdue means the external due date has passed.
  public static func isDeadlineOverdue(dueDate: IsoDate.YMD?, asOfDate: IsoDate.YMD) -> Bool {
    guard let due = dueDate else { return false }
    return due < asOfDate
  }

  /// Derive the canonical lateness state for an open task.
  ///
  /// Rules:
  /// - `due_date < today` => overdue.
  /// - overdue + `planned_date >= today` => acknowledged overdue.
  /// - overdue + no meaningful re-plan => unhandled overdue.
  /// - `planned_date < today` without deadline-overdue => past-planned.
  public static func deriveOpenTaskLateness(
    plannedDate: IsoDate.YMD?, dueDate: IsoDate.YMD?, asOfDate: IsoDate.YMD
  ) -> TaskLateness? {
    if isDeadlineOverdue(dueDate: dueDate, asOfDate: asOfDate) {
      if let planned = plannedDate, planned >= asOfDate {
        return .overdueAcknowledged
      } else {
        return .overdueUnhandled
      }
    }
    if let planned = plannedDate, planned < asOfDate {
      return .pastPlanned
    }
    return nil
  }

}
