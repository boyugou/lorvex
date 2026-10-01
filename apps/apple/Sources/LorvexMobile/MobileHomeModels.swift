import LorvexCore

/// What the iPhone and iPad home surfaces read: the day's Today snapshot and
/// the viewed weekly review window.
public struct MobileHomeSnapshot: Equatable, Sendable {
  public var today: TodaySnapshot
  public var weeklyReview: WeeklyReviewSnapshot?

  public init(today: TodaySnapshot, weeklyReview: WeeklyReviewSnapshot?) {
    self.today = today
    self.weeklyReview = weeklyReview
  }

  /// Every started task in the day snapshot, for surfaces that want what is
  /// underway rather than the whole list.
  public var inProgressTasks: [LorvexTask] {
    today.inProgressTasks
  }

  /// Ids of Today's tasks that cannot start because a task they depend on is
  /// still active.
  public var blockedTaskIDs: Set<LorvexTask.ID> {
    today.blockedTaskIDs
  }
}
