#if DEBUG
  import Foundation

  /// A state of Today a preview run can open in: the states a seeded busy day
  /// never reaches by itself, so captures can show the pages they draw.
  /// `-lorvexPreviewDayState <empty|allDone|overbooked>` selects one on every
  /// platform, and ``apply(to:)`` moves a freshly seeded store into it through
  /// ordinary writes.
  public enum LorvexPreviewDayState: String, Sendable, CaseIterable {
    /// Nothing on Today, nothing done today, no meeting today, and no briefing.
    case empty
    /// Every task on Today done. The day's meetings stay, so the page calls the
    /// day done only once the preview clock (`-lorvexPreviewNow`) is past them.
    case allDone
    /// More estimated work than the working time left: two long tasks without
    /// a deadline join the day, which makes them the ones the page offers to
    /// move to tomorrow.
    case overbooked

    /// The state the launch arguments ask for, or nil.
    public static var requested: LorvexPreviewDayState? {
      let arguments = CommandLine.arguments
      guard let index = arguments.firstIndex(of: "-lorvexPreviewDayState"),
        index + 1 < arguments.count
      else { return nil }
      return LorvexPreviewDayState(rawValue: arguments[index + 1])
    }

    /// Moves `core`'s seeded day into this state. `empty` deletes what Today
    /// lists, what was done today (archiving each first, as the store's
    /// two-step delete requires), today's events, and the day's briefing, which
    /// was written about the deleted work; `allDone` completes what Today
    /// lists; `overbooked` plans two long tasks for today, titled and tagged
    /// through `text` like the rest of the sample day.
    public func apply(to core: SwiftLorvexCoreService, text: LorvexSampleText = .english) async throws {
      let today = try await core.loadToday()
      let listed = Self.unique(today.inProgressTasks + today.tasks)
      switch self {
      case .empty:
        let done = try await core.loadWidgetStatsSource().completedTodayTasks
        for task in Self.unique(listed + done) {
          _ = try await core.archiveTask(id: task.id)
          try await core.deleteTask(id: task.id)
        }
        if let day = today.logicalDay {
          for event in try await core.loadCalendarTimeline(from: day, to: day).events {
            try await core.deleteCalendarEvent(id: event.id)
          }
          _ = try await core.setDailyBriefingForMcp(date: day, briefing: nil)
        }
      case .allDone:
        for task in listed {
          _ = try await core.completeTask(id: task.id)
        }
      case .overbooked:
        guard let day = today.logicalDay, let date = LorvexDateFormatters.ymdUTC.date(from: day)
        else { return }
        for (title, minutes) in [("Outline the board deck", 150), ("Draft the hiring plan", 120)] {
          _ = try await core.createTask(
            TaskCreateDraft(
              title: text(title), priority: .p3, estimatedMinutes: minutes, plannedDate: date,
              tags: text(["work"])))
        }
      }
    }

    /// `tasks` without repeats, first occurrence kept.
    private static func unique(_ tasks: [LorvexTask]) -> [LorvexTask] {
      var seen = Set<LorvexTask.ID>()
      return tasks.filter { seen.insert($0.id).inserted }
    }
  }
#endif
