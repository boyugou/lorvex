#if DEBUG
  import Foundation
  import LorvexCore

  /// DEBUG-only sample content for the widget gallery that QA's the widget
  /// design (the iOS app's `-lorvexWidgetGallery` screen).
  ///
  /// The Today models come from the real ``WidgetRenderModelBuilder`` over a
  /// sample day read at a fixed clock, so the gallery shows what the builder
  /// makes of a running time rather than hand-written rows.
  public enum WidgetGallerySample {
    /// 10:12, twenty-seven minutes into the first task's time.
    public static let runningClock = 10 * 60 + 12
    /// Before the first task's time starts.
    public static let earlyClock = 8 * 60 + 40

    public static var snapshot: WidgetSnapshot {
      // Title, status, saved time, estimate, priority tier.
      let day: [(String, String, String?, String?, Int?, Int)] = [
        ("Review the Q3 planning doc", "in_progress", "09:45", "10:30", 45, 1),
        ("Refactor the sync layer", "open", "11:00", "12:30", 90, 2),
        ("Reply to the investor update email", "open", "14:00", "14:30", 30, 1),
        ("Read the GRPO paper", "open", nil, nil, 40, 3),
        ("Renew passport", "open", nil, nil, nil, 2),
        ("Plan the team offsite", "open", nil, nil, 60, 3),
        ("Pay the electricity bill", "open", nil, nil, 5, 3),
      ]
      return WidgetSnapshot(
        generatedAt: "2026-06-30T12:00:00Z",
        timezone: TimeZone.current.identifier,
        stats: .init(todayCount: 7, overdueCount: 1, dueTodayCount: 3, completedTodayCount: 2),
        briefing:
          "The planning review first while the doc is fresh; the sync refactor takes the long block before lunch.",
        tasks: day.enumerated().map { index, row in
          .init(
            id: "task-\(index)", title: row.0, status: row.1, dueDate: nil, priority: row.5,
            listID: nil, estimatedMinutes: row.4, scheduledStart: row.2, scheduledEnd: row.3)
        },
        habits: habits)
    }

    /// Today at `clock` minutes past midnight in the device zone.
    public static func date(at clock: Int) -> Date {
      let calendar = Calendar.autoupdatingCurrent
      let start = calendar.startOfDay(for: Date())
      return calendar.date(bySettingHour: clock / 60, minute: clock % 60, second: 0, of: start)
        ?? start
    }

    public static func model(_ family: WidgetFamilyKind, at clock: Int = runningClock) -> WidgetRenderModel {
      model(snapshot, family: family, at: clock)
    }

    /// A day with tasks left but none leading: nothing timed, nothing started.
    public static func openDayModel(_ family: WidgetFamilyKind) -> WidgetRenderModel {
      // Title, estimate, priority tier.
      let day: [(String, Int?, Int)] = [
        ("Read the GRPO paper", 40, 1),
        ("Renew passport", nil, 2),
        ("Draft the offsite agenda", 90, 3),
        ("Book the dentist", 10, 3),
        ("Clean up the photo library", 30, 3),
      ]
      let open = WidgetSnapshot(
        generatedAt: "2026-06-30T12:00:00Z", timezone: TimeZone.current.identifier,
        stats: .init(todayCount: 5, overdueCount: 0, dueTodayCount: 2, completedTodayCount: 1),
        briefing: "Nothing is fixed today; the paper and the agenda are the two that matter.",
        tasks: day.enumerated().map { index, row in
          .init(
            id: "open-\(index)", title: row.0, status: "open", dueDate: nil, priority: row.2,
            listID: nil, estimatedMinutes: row.1, scheduledStart: nil, scheduledEnd: nil)
        })
      return model(open, family: family, at: runningClock)
    }

    /// A finished day: nothing left, four tasks done.
    public static func emptyModel(_ family: WidgetFamilyKind) -> WidgetRenderModel {
      model(finishedSnapshot, family: family, at: runningClock)
    }

    /// Three of eight done, five left on Today.
    public static var progressSnapshot: WidgetSnapshot {
      WidgetSnapshot(
        generatedAt: "2026-06-30T12:00:00Z", timezone: "UTC",
        stats: .init(todayCount: 5, overdueCount: 1, dueTodayCount: 3, completedTodayCount: 3),
        briefing: nil, tasks: [])
    }

    /// Nothing left on Today, four tasks done.
    public static var finishedSnapshot: WidgetSnapshot {
      WidgetSnapshot(
        generatedAt: "2026-06-30T12:00:00Z", timezone: TimeZone.current.identifier,
        stats: .init(todayCount: 0, overdueCount: 0, dueTodayCount: 0, completedTodayCount: 4),
        briefing: nil, tasks: [])
    }

    /// Five habits: one done, one part-way through a count of three, one with
    /// a chosen color, and the rest on their automatic hues.
    public static var habits: [WidgetSnapshot.HabitSummary] {
      [
        .init(id: "h1", name: "Meditate", icon: "brain.head.profile", completedToday: 1, target: 1),
        .init(id: "h2", name: "Read 30 minutes", icon: "book.fill", completedToday: 0, target: 1),
        .init(
          id: "h3", name: "Drink water", icon: "drop.fill", completedToday: 2, target: 3,
          color: "#3B82F6"),
        .init(id: "h4", name: "Morning run", icon: "figure.run", completedToday: 0, target: 1),
        .init(id: "h5", name: "Stretch", icon: "figure.mind.and.body", completedToday: 0, target: 2),
      ]
    }

    /// Three habits, every one met today.
    public static var allDoneHabits: [WidgetSnapshot.HabitSummary] {
      [
        .init(id: "h1", name: "Meditate", icon: "brain.head.profile", completedToday: 1, target: 1),
        .init(id: "h2", name: "Read 30 minutes", icon: "book.fill", completedToday: 1, target: 1),
        .init(
          id: "h3", name: "Drink water", icon: "drop.fill", completedToday: 3, target: 3,
          color: "#3B82F6"),
      ]
    }

    /// Three more habits, so a grid overflows and its last tile counts the
    /// rest; one name is long enough to truncate.
    public static var moreHabits: [WidgetSnapshot.HabitSummary] {
      [
        .init(id: "h6", name: "Lights out by 11 PM", icon: "moon.zzz.fill", completedToday: 0, target: 1),
        .init(id: "h7", name: "Vitamins", icon: "pills.fill", completedToday: 1, target: 1),
        .init(id: "h8", name: "Journal", icon: "text.book.closed.fill", completedToday: 0, target: 1),
      ]
    }

    private static func model(
      _ snapshot: WidgetSnapshot, family: WidgetFamilyKind, at clock: Int
    ) -> WidgetRenderModel {
      let entry = WidgetTimelineEntry(
        date: date(at: clock),
        state: .snapshot(snapshot, freshness: .fresh(ageSeconds: 0)),
        refreshAfter: date(at: clock).addingTimeInterval(3600))
      return WidgetRenderModelBuilder().model(entry: entry, family: family, statusText: "Updated now")
    }
  }
#endif
