import Foundation
import LorvexDomain

public struct LorvexTask: Identifiable, Equatable, Sendable {
  public enum Priority: String, CaseIterable, Sendable, Comparable {
    case p1 = "P1"
    case p2 = "P2"
    case p3 = "P3"

    /// The numeric tier (P1 → 1, P2 → 2, P3 → 3): the integer form stored in the
    /// `tasks.priority` column and carried in the widget-snapshot `priority`
    /// field. The single canonical Priority→Int converter; ``init(tier:)`` is
    /// the inverse. Also the sort key — P1 < P2 < P3, so ascending order puts
    /// the highest priority first.
    public var tier: Int {
      switch self {
      case .p1: 1
      case .p2: 2
      case .p3: 3
      }
    }

    /// Reconstruct a priority from its numeric ``tier`` (1 → P1, 2 → P2,
    /// 3 → P3), returning `nil` for any other value. The inverse of ``tier``.
    public init?(tier: Int) {
      switch tier {
      case 1: self = .p1
      case 2: self = .p2
      case 3: self = .p3
      default: return nil
      }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.tier < rhs.tier }
  }

  public enum Status: String, Sendable, Comparable {
    case open
    /// Work has started and is not finished. Actionable like `open`; an
    /// optional "started" marker that any terminal transition replaces. Raw
    /// value is the snake-case wire string `"in_progress"` (the other cases
    /// take their case name verbatim).
    case inProgress = "in_progress"
    case someday
    case completed
    case cancelled

    private var sortIndex: Int {
      switch self {
      case .open: 0
      case .inProgress: 1
      case .someday: 2
      case .completed: 3
      case .cancelled: 4
      }
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.sortIndex < rhs.sortIndex }

    /// The matching domain ``TaskStatus``. Both enums share identical wire raw
    /// values, so this total mapping lets the app-layer classification predicates
    /// (``isActionable`` / ``isActive`` / ``isResolved``) derive from the domain's
    /// single definition rather than re-deciding membership here.
    public var domainStatus: TaskStatus {
      switch self {
      case .open: .open
      case .inProgress: .inProgress
      case .someday: .someday
      case .completed: .completed
      case .cancelled: .cancelled
      }
    }

    /// A terminal status: the task has been dealt with (`completed` or
    /// `cancelled`) and no longer needs action. The complement of ``isActive``.
    public var isResolved: Bool { domainStatus.isTerminal }

    /// The working set — `open` or `in_progress` (started). The surfaces that
    /// show actionable work (Today lanes, reminders, widget / watch / CarPlay /
    /// menu-bar / badge, the Tasks-workspace open lane, batch eligibility) filter
    /// on this so a started task behaves exactly like open work. Excludes
    /// soft-parked `someday` and the terminal states. Mirrors the SQL
    /// `StatusName.actionableStatusSqlList` via ``TaskStatus/isActionable``.
    public var isActionable: Bool { domainStatus.isActionable }

    /// A live status: the task still needs action (`open` / `in_progress`) or is
    /// parked for later (`someday`). The complement of ``isResolved``. Broader
    /// than ``isActionable`` because it also counts `someday`.
    public var isActive: Bool { domainStatus.isActive }

    /// The status string the core task queries (`list_tasks` / `search_tasks`)
    /// filter on. A workspace lane not backed by a status — the date-derived
    /// `deferred` / `scheduled` lanes pass `nil` — reads across `open`.
    public static func coreQueryString(for status: Status?) -> String {
      status?.rawValue ?? "open"
    }

    /// The wire `status` value that selects the actionable working set
    /// (`open` + `in_progress`) for `list_tasks` / `search_tasks`. Not a status
    /// itself — the working-set lanes (Tasks-workspace open lane, dependency
    /// picker) pass this instead of `"open"` so a started task stays visible.
    public static let actionableFilter = "actionable"
  }

  public let id: String
  public var title: String
  public var notes: String
  public var aiNotes: String?
  /// The user's verbatim original capture text (the `tasks.raw_input`
  /// column), preserved alongside the AI-parsed `title`/`notes` so a client
  /// can show how the structured task maps back to what the user actually
  /// typed/said. `nil` when no raw capture was recorded.
  public var rawInput: String?
  public var priority: Priority
  public var status: Status
  /// External deadline (the `tasks.due_date` column). Independent of
  /// ``plannedDate`` — a task can have a deadline with no planned work day, a
  /// planned day with no deadline, or both.
  public var dueDate: Date?
  /// Intended work date (the `tasks.planned_date` column), set by `defer_task`
  /// or a direct update. Independent of ``dueDate``.
  public var plannedDate: Date?
  /// The task's time on its planned day (the `tasks.planned_start_minutes` and
  /// `tasks.planned_end_minutes` columns) as minutes since midnight in the
  /// configured timezone: an appointment with oneself. Never set without a
  /// ``plannedDate``; read it through ``time(on:)``.
  public var plannedTime: Range<Int>?
  /// Defer-until / hide-until date (the `tasks.available_from` column):
  /// the task is hidden from day surfaces until this civil date, unless it is
  /// overdue. UTC-midnight anchored like ``plannedDate``. `nil` means the task
  /// is never hidden.
  public var availableFrom: Date?
  public var estimatedMinutes: Int?
  public var tags: [String]
  public var dependsOn: [String]
  public var checklistItems: [TaskChecklistItem]
  public var reminders: [TaskReminder]
  public var latenessState: String?
  public var recurrence: TaskRecurrenceRule?
  public var recurrenceExceptions: [String]
  /// The stored day a repeat counts its schedule from (the
  /// `tasks.canonical_occurrence_date` column, a UTC midnight like
  /// ``dueDate``): set to the deadline, or today without one, when the task
  /// starts repeating, moved by a new deadline, and kept by a deferral. Nil
  /// when the task does not repeat.
  public var canonicalOccurrenceDate: Date?
  public var listID: LorvexList.ID?
  /// How many times the task has been deferred (the `tasks.defer_count`
  /// column), incremented by every `defer_task`. Surfaced for pattern tracking.
  public var deferCount: Int
  /// The structured reason recorded by the most recent defer (the
  /// `tasks.last_defer_reason` column): one of the `DeferReason` categories, or
  /// nil when the task has never been deferred with a reason.
  public var lastDeferReason: String?
  /// ISO-8601 timestamp of the most recent defer (the `tasks.last_deferred_at`
  /// column), or nil when the task has never been deferred.
  public var lastDeferredAt: String?
  /// ISO-8601 creation timestamp from the `tasks.created_at` column.
  public var createdAt: String?
  /// ISO-8601 update timestamp from the `tasks.updated_at` column.
  public var updatedAt: String?
  /// ISO-8601 completion timestamp from the `tasks.completed_at` column.
  public var completedAt: String?
  /// ISO-8601 Trash timestamp from the `tasks.archived_at` column. Non-nil
  /// means the task row is soft-deleted and hidden from active task surfaces.
  public var archivedAt: String?

  public init(
    id: String,
    title: String,
    notes: String,
    aiNotes: String? = nil,
    rawInput: String? = nil,
    priority: Priority,
    status: Status,
    dueDate: Date?,
    plannedDate: Date? = nil,
    plannedTime: Range<Int>? = nil,
    availableFrom: Date? = nil,
    estimatedMinutes: Int?,
    tags: [String],
    dependsOn: [String] = [],
    checklistItems: [TaskChecklistItem] = [],
    reminders: [TaskReminder] = [],
    latenessState: String? = nil,
    recurrence: TaskRecurrenceRule? = nil,
    recurrenceExceptions: [String] = [],
    canonicalOccurrenceDate: Date? = nil,
    listID: LorvexList.ID? = nil,
    deferCount: Int = 0,
    lastDeferReason: String? = nil,
    lastDeferredAt: String? = nil,
    createdAt: String? = nil,
    updatedAt: String? = nil,
    completedAt: String? = nil,
    archivedAt: String? = nil
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.aiNotes = aiNotes
    self.rawInput = rawInput
    self.priority = priority
    self.status = status
    self.dueDate = dueDate
    self.plannedDate = plannedDate
    self.plannedTime = plannedDate == nil ? nil : plannedTime
    self.availableFrom = availableFrom
    self.estimatedMinutes = estimatedMinutes
    self.tags = tags
    self.dependsOn = dependsOn
    self.checklistItems = checklistItems
    self.reminders = reminders
    self.latenessState = latenessState
    self.recurrence = recurrence
    self.recurrenceExceptions = recurrenceExceptions
    self.canonicalOccurrenceDate = canonicalOccurrenceDate
    self.listID = listID
    self.deferCount = deferCount
    self.lastDeferReason = lastDeferReason
    self.lastDeferredAt = lastDeferredAt
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.completedAt = completedAt
    self.archivedAt = archivedAt
  }
}

extension LorvexTask {
  /// The task's time on `logicalDay` (`yyyy-MM-dd`): its ``plannedTime`` when
  /// the task is planned for that day, else nil. A time belongs to the day the
  /// task is planned for, so no other day draws it.
  public func time(on logicalDay: String) -> Range<Int>? {
    guard let plannedTime, let plannedDate,
      LorvexDateFormatters.ymdUTC.string(from: plannedDate) == logicalDay
    else { return nil }
    return plannedTime
  }

  /// The stored day a schedule-anchored repeat of this task counts from:
  /// ``canonicalOccurrenceDate`` while the task repeats, else the day turning
  /// repeating on would anchor it to, which is the deadline, or `logicalDay`
  /// (the product's today, `yyyy-MM-dd`) when there is none. A weekly repeat
  /// without chosen weekdays falls on this day's weekday.
  public func recurrenceAnchorDay(logicalDay: String) -> Date? {
    if recurrence != nil, let canonicalOccurrenceDate { return canonicalOccurrenceDate }
    return dueDate ?? LorvexDateFormatters.ymdUTC.date(from: logicalDay)
  }
}

extension Sequence where Element == LorvexTask {
  /// Each task's time on `logicalDay`, keyed by task id; tasks without one are
  /// absent.
  public func times(on logicalDay: String) -> [LorvexTask.ID: Range<Int>] {
    var times: [LorvexTask.ID: Range<Int>] = [:]
    for task in self {
      if let time = task.time(on: logicalDay) { times[task.id] = time }
    }
    return times
  }
}
