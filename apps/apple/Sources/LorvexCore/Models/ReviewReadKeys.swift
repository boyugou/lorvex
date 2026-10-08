import Foundation

/// What a day review page's own reads follow: the habits as they stood on the
/// reviewed day and, for the review of today, tomorrow's agenda.
///
/// The day's evidence moves with its own tasks and habit check-ins. It does not
/// hold tomorrow's agenda, so a task that the assistant or another device plans
/// for tomorrow leaves the evidence equal. The task revision (the store's
/// counter of task data re-read after a change) moves in that case too, and the
/// page re-reads when either part moves.
public struct DayReviewReadKey: Equatable, Sendable {
  public var date: String
  public var evidence: DayReviewSummary?
  public var taskRevision: UInt64

  public init(date: String, evidence: DayReviewSummary?, taskRevision: UInt64) {
    self.date = date
    self.evidence = evidence
    self.taskRevision = taskRevision
  }
}

/// What a week review page's own reads follow: the seven days ahead and the
/// count of tasks finished on each day of the week.
///
/// The weekly snapshot holds what happened in the week, not what is planned for
/// the days after today, so planning a task for next week leaves it equal. The
/// task revision moves in that case too, and the page re-reads when either part
/// moves.
public struct WeekReviewReadKey: Equatable, Sendable {
  public var review: WeeklyReviewSnapshot?
  public var taskRevision: UInt64

  public init(review: WeeklyReviewSnapshot?, taskRevision: UInt64) {
    self.review = review
    self.taskRevision = taskRevision
  }
}
