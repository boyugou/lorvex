import LorvexCore

public struct MobileHomeSnapshot: Equatable, Sendable {
  public var today: TodaySnapshot
  public var currentFocus: CurrentFocusPlan?
  public var weeklyReview: WeeklyReviewSnapshot?

  public init(
    today: TodaySnapshot,
    currentFocus: CurrentFocusPlan?,
    weeklyReview: WeeklyReviewSnapshot?
  ) {
    self.today = today
    self.currentFocus = currentFocus
    self.weeklyReview = weeklyReview
  }

  /// Open Today tasks with no planned work day — the canonical "open" section,
  /// matching the macOS split (a task carrying a `plannedDate` is the "deferred"
  /// stand-in and is excluded here). This is the Tasks-workspace notion of
  /// "open"; the Today task list shows the whole day's open work via
  /// ``todayTasks``.
  public var openTasks: [LorvexTask] {
    today.tasks.lorvexOpenSection
  }

  /// Every open task in the day snapshot, in canonical order — the source for
  /// the Today task list. Unlike ``openTasks`` it keeps planned-for-today work,
  /// mirroring the macOS Today "Next Up" lane (`remainingTodayTasks`) rather
  /// than the Tasks-workspace open/deferred split.
  public var todayTasks: [LorvexTask] {
    today.tasks.filter { $0.status == .open }
  }

  /// Started tasks pinned into Today's "In Progress" section, read from the
  /// snapshot's uncapped `inProgressTasks` query so every started task shows —
  /// not just those inside the priority-capped `today.tasks` overview pool.
  /// Pulled out of the focus / next / today lanes (which filter `today.tasks` to
  /// non-started work) so a started task shows in exactly one place.
  public var inProgressTasks: [LorvexTask] {
    today.inProgressTasks
  }

  public var focusTasks: [LorvexTask] {
    LorvexTaskSections.focus(order: currentFocus?.taskIDs ?? []) { id in
      today.tasks.first { $0.id == id }
    }
    .filter { $0.status != .inProgress }
  }

  public var nextTask: LorvexTask? {
    focusTasks.first ?? todayTasks.first
  }
}

public struct MobileHomeSummary: Equatable, Sendable {
  public var focusTitle: String
  public var openTaskCount: Int
  public var focusTaskCount: Int
  public var nextTaskTitle: String?
  public var weeklyReviewTitle: String?

  public init(
    focusTitle: String,
    openTaskCount: Int,
    focusTaskCount: Int,
    nextTaskTitle: String?,
    weeklyReviewTitle: String?
  ) {
    self.focusTitle = focusTitle
    self.openTaskCount = openTaskCount
    self.focusTaskCount = focusTaskCount
    self.nextTaskTitle = nextTaskTitle
    self.weeklyReviewTitle = weeklyReviewTitle
  }

  public var taskStatusText: String {
    guard let nextTaskTitle else {
      return String(
        format: String(localized: "today.metrics.summary.a11y", defaultValue: "Open tasks: %1$lld, Focus tasks: %2$lld", table: "Localizable", bundle: MobileL10n.bundle),
        openTaskCount,
        focusTaskCount
      )
    }
    return String(
      format: String(localized: "today.metrics.summary_with_next.a11y", defaultValue: "Open tasks: %1$lld, Focus tasks: %2$lld, Next: %3$@", table: "Localizable", bundle: MobileL10n.bundle),
      openTaskCount,
      focusTaskCount,
      nextTaskTitle
    )
  }
}

public struct MobileHomeProjector: Sendable {
  public init() {}

  public func summary(from snapshot: MobileHomeSnapshot) -> MobileHomeSummary {
    MobileHomeSummary(
      focusTitle: snapshot.today.focusTitle,
      openTaskCount: snapshot.openTasks.count,
      focusTaskCount: snapshot.focusTasks.count,
      nextTaskTitle: snapshot.nextTask?.title,
      weeklyReviewTitle: snapshot.weeklyReview?.windowTitle
    )
  }
}
