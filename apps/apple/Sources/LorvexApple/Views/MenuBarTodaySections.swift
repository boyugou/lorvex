import LorvexCore

/// What the menu bar panel's Today body lists, in its order: the lead task,
/// the rest of the day on the clock, then the tasks without a time, overdue
/// ones apart.
///
/// The schedule is Today's schedule (``LorvexTodayTimeline``) cut down to what
/// is still ahead: all-day events, the timed events the clock has not cleared,
/// and the timed tasks still open, by start. It leaves out the clock's row,
/// the events that have ended (the facts line counts only the meetings left),
/// and the lead, which the panel draws above it. A task whose time passed
/// unfinished still needs doing, so it stays. Every task appears once: a task
/// with a time today under the schedule, any other under ``overdue`` or
/// ``tasks``, in Today's order.
struct MenuBarTodaySections: Equatable {
  /// One row of the schedule.
  enum Entry: Identifiable, Equatable {
    case task(LorvexCalmToday.Item)
    case event(CalendarTimelineEvent)

    var id: String {
      switch self {
      case .task(let item): "task:\(item.id)"
      case .event(let event): "event:\(event.id)"
      }
    }
  }

  var lead: LorvexCalmToday.Item?
  var schedule: [Entry]
  var overdue: [LorvexCalmToday.Item]
  var tasks: [LorvexCalmToday.Item]

  /// True when nothing is left on the day: no task and no event still ahead.
  var isEmpty: Bool {
    lead == nil && schedule.isEmpty && overdue.isEmpty && tasks.isEmpty
  }

  /// - Parameters:
  ///   - page: Today's page; each item's ``LorvexCalmToday/Item/time`` places
  ///     it on the schedule.
  ///   - events: the events that occur on `logicalDay`.
  ///   - logicalDay: the product day as `yyyy-MM-dd`.
  ///   - nowMinutes: minutes since midnight in the product day, which decides
  ///     which events have ended.
  ///   - isOverdue: whether a task without a time lists under Overdue.
  init(
    page: LorvexCalmToday, events: [CalendarTimelineEvent], logicalDay: String, nowMinutes: Int?,
    isOverdue: (LorvexTask) -> Bool
  ) {
    lead = page.lead
    let itemsByID = Dictionary(page.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let times = itemsByID.compactMapValues(\.time)
    schedule = LorvexTodayTimeline.build(
      day: logicalDay, events: events, tasks: page.items.map(\.task), times: times,
      nowMinutes: nowMinutes
    ).compactMap { row -> Entry? in
      switch row.kind {
      case .task(let task):
        guard task.id != page.leadID else { return nil }
        return itemsByID[task.id].map(Entry.task)
      case .event(let event):
        return row.isPast ? nil : .event(event)
      case .now:
        return nil
      }
    }
    let untimed = page.items.filter { $0.id != page.leadID && $0.time == nil }
    overdue = untimed.filter { isOverdue($0.task) }
    tasks = untimed.filter { !isOverdue($0.task) }
  }
}
