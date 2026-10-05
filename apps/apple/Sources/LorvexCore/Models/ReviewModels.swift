import Foundation

public struct WeeklyReviewSnapshot: Equatable, Sendable {
  public var windowTitle: String
  public var completedThisWeek: Int
  public var createdThisWeek: Int
  public var overdueOpen: Int
  public var deferredOpen: Int
  public var someday: Int
  public var estimateCoverageRatio: Double?
  public var topCompleted: [ReviewTaskSummary]
  public var frequentlyDeferred: [ReviewTaskSummary]
  /// Open tasks due before the window's last day, earliest due first; the
  /// `overdueOpen` field above is the total count.
  public var overdueTasks: [ReviewTaskSummary]
  /// The most recently parked Someday/Maybe items (`status='someday'`), ordered
  /// `created_at DESC` — someday entries are undated, so recency is the axis a
  /// review pass scans by. The `someday` field above is the total count.
  public var topSomeday: [ReviewTaskSummary]

  public init(
    windowTitle: String,
    completedThisWeek: Int,
    createdThisWeek: Int,
    overdueOpen: Int,
    deferredOpen: Int,
    someday: Int,
    estimateCoverageRatio: Double?,
    topCompleted: [ReviewTaskSummary],
    frequentlyDeferred: [ReviewTaskSummary],
    overdueTasks: [ReviewTaskSummary] = [],
    topSomeday: [ReviewTaskSummary]
  ) {
    self.windowTitle = windowTitle
    self.completedThisWeek = completedThisWeek
    self.createdThisWeek = createdThisWeek
    self.overdueOpen = overdueOpen
    self.deferredOpen = deferredOpen
    self.someday = someday
    self.estimateCoverageRatio = estimateCoverageRatio
    self.topCompleted = topCompleted
    self.frequentlyDeferred = frequentlyDeferred
    self.overdueTasks = overdueTasks
    self.topSomeday = topSomeday
  }
}

extension WeeklyReviewSnapshot {
  /// How many of the week's finished tasks the capped ``topCompleted`` list
  /// leaves out of ``completedThisWeek``.
  public var hiddenCompletedCount: Int { max(0, completedThisWeek - topCompleted.count) }

  /// The window as a localized month-and-day range for a page's date line
  /// ("September 22 – 28", "September 29 – October 5"), read from the
  /// `"YYYY-MM-DD - YYYY-MM-DD"` form the core writes into `windowTitle`.
  /// With `includesYear`, the range carries its year ("September 22 – 28,
  /// 2026") for text read outside the week. A `windowTitle` in any other form
  /// is returned unchanged.
  public func windowRangeLabel(locale: Locale = .autoupdatingCurrent, includesYear: Bool = false) -> String {
    let parts = windowTitle.components(separatedBy: " - ")
    guard parts.count == 2,
      let start = LorvexDateFormatters.ymd.date(from: parts[0]),
      let end = LorvexDateFormatters.ymd.date(from: parts[1]),
      start <= end
    else { return windowTitle }
    let style = Date.IntervalFormatStyle.interval.month(.wide).day().locale(locale)
    return (start..<end).formatted(includesYear ? style.year() : style)
  }
}

public struct DailyReviewEntry: Equatable, Sendable {
  public var date: String
  public var summary: String
  public var mood: Int?
  public var energyLevel: Int?
  public var wins: String?
  public var blockers: String?
  public var learnings: String?
  public var timezone: String?
  public var updatedAt: String?
  public var linkedTaskIDs: [String]
  public var linkedListIDs: [String]

  public init(
    date: String,
    summary: String,
    mood: Int?,
    energyLevel: Int?,
    wins: String?,
    blockers: String?,
    learnings: String?,
    timezone: String?,
    updatedAt: String?,
    linkedTaskIDs: [String],
    linkedListIDs: [String]
  ) {
    self.date = date
    self.summary = summary
    self.mood = mood
    self.energyLevel = energyLevel
    self.wins = wins
    self.blockers = blockers
    self.learnings = learnings
    self.timezone = timezone
    self.updatedAt = updatedAt
    self.linkedTaskIDs = linkedTaskIDs
    self.linkedListIDs = linkedListIDs
  }
}

/// Partial overrides applied by `amendDailyReview`. Only non-nil fields replace the existing value.
public struct DailyReviewPatch: Equatable, Sendable {
  public var summary: String?
  public var mood: Int?
  public var energyLevel: Int?
  public var wins: String?
  public var blockers: String?
  public var learnings: String?
  public var linkedTaskIDs: [String]?
  public var linkedListIDs: [String]?

  public init(
    summary: String? = nil,
    mood: Int? = nil,
    energyLevel: Int? = nil,
    wins: String? = nil,
    blockers: String? = nil,
    learnings: String? = nil,
    linkedTaskIDs: [String]? = nil,
    linkedListIDs: [String]? = nil
  ) {
    self.summary = summary
    self.mood = mood
    self.energyLevel = energyLevel
    self.wins = wins
    self.blockers = blockers
    self.learnings = learnings
    self.linkedTaskIDs = linkedTaskIDs
    self.linkedListIDs = linkedListIDs
  }
}

public struct ReviewTaskSummary: Identifiable, Equatable, Sendable {
  public var id: String
  public var title: String
  public var status: String
  public var deferCount: Int
  /// The task's due day as `YYYY-MM-DD`, when it has one.
  public var dueDate: String?
  /// The day the task is planned for as `YYYY-MM-DD`, when it has one.
  public var plannedDate: String?

  public init(
    id: String, title: String, status: String, deferCount: Int, dueDate: String? = nil,
    plannedDate: String? = nil
  ) {
    self.id = id
    self.title = title
    self.status = status
    self.deferCount = deferCount
    self.dueDate = dueDate
    self.plannedDate = plannedDate
  }
}

/// Objective "evidence" for a single calendar day, backing the Review-surface
/// day panel. Every field is a pure read over the existing tables — no schema
/// extension, no derived state stored anywhere.
///
/// `date` is a canonical `YYYY-MM-DD` interpreted in the user's configured
/// timezone (the same anchored-timezone convention `WeeklyReview` /
/// `WorkflowTimezone` use). The completed/created counts window on the UTC
/// instants bounding that local day; `dueOpenCount` compares the bare `date`
/// string against the `due_date` date column (also `YYYY-MM-DD`).
///
/// Habit metric: `habitsTotal` is the count of active (non-archived) habits
/// that belong to `date` — due that day by their cadence (a daily habit every
/// day, a weekly habit on its pinned weekdays, a monthly habit on its day of
/// the month; a times-per-week habit on no particular day) or checked in that
/// day — and `habitsCompleted` is the count of those whose logged completion
/// `value >= target_count` on `date`. A habit on a day it was not due is in
/// neither count, so a day on which no habit was due does not read as habits
/// missed.
///
/// Event count: calendar events whose `[start_date, end_date]` span covers
/// `date`, counted across BOTH `calendar_events` (Lorvex-owned) and
/// `provider_calendar_events` (the device-local system mirror). An all-day or
/// multi-day event covering the day counts once; recurrence is not expanded
/// (the span of the stored row is what is tested), matching the single-day
/// bound `start_date <= date AND COALESCE(end_date, start_date) >= date`.
public struct DayReviewSummary: Equatable, Sendable {
  public var date: String
  public var completedCount: Int
  public var topCompleted: [ReviewTaskSummary]
  public var createdCount: Int
  public var dueOpenCount: Int
  /// The first still-open tasks due that day, in the canonical task order;
  /// `dueOpenCount` is the total.
  public var dueOpenTasks: [ReviewTaskSummary]
  public var habitsCompleted: Int
  public var habitsTotal: Int
  public var eventCount: Int

  public init(
    date: String,
    completedCount: Int,
    topCompleted: [ReviewTaskSummary],
    createdCount: Int,
    dueOpenCount: Int,
    dueOpenTasks: [ReviewTaskSummary] = [],
    habitsCompleted: Int,
    habitsTotal: Int,
    eventCount: Int
  ) {
    self.date = date
    self.completedCount = completedCount
    self.topCompleted = topCompleted
    self.createdCount = createdCount
    self.dueOpenCount = dueOpenCount
    self.dueOpenTasks = dueOpenTasks
    self.habitsCompleted = habitsCompleted
    self.habitsTotal = habitsTotal
    self.eventCount = eventCount
  }
}

extension DayReviewSummary {
  /// How many of the day's finished tasks the capped ``topCompleted`` list
  /// leaves out of ``completedCount``.
  public var hiddenCompletedCount: Int { max(0, completedCount - topCompleted.count) }
}
