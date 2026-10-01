import Foundation

/// One day of an agenda of the days ahead — the menu bar panel's Next 7 Days,
/// the day review's look at tomorrow: the day's events and its open scheduled
/// tasks, each in reading order.
public struct LorvexAgendaDay: Identifiable, Equatable, Sendable {
  /// The logical day as `yyyy-MM-dd`.
  public let key: String
  /// All-day events first, then by start time, then by title.
  public var events: [CalendarTimelineEvent]
  /// Tasks with a time first, by start, then the rest in the canonical order
  /// they arrived in.
  public var tasks: [LorvexTask]

  public var id: String { key }

  public init(key: String, events: [CalendarTimelineEvent], tasks: [LorvexTask]) {
    self.key = key
    self.events = events
    self.tasks = tasks
  }

  /// The `dayCount` days after `todayKey` that have something on them, in
  /// order.
  ///
  /// An event belongs to every day its `[startDate, endDate]` span covers,
  /// except the end day of a timed event that ends exactly at midnight, which
  /// occupies no time there. A task belongs to the day the calendar draws it
  /// on (``CalendarGridModel/scheduledTaskDayKey(_:)``) while it is still
  /// actionable. Days with nothing on them are left out, so an empty result
  /// means the week ahead is free.
  public static func build(
    todayKey: String, events: [CalendarTimelineEvent], tasks: [LorvexTask], dayCount: Int = 7
  ) -> [LorvexAgendaDay] {
    (1...dayCount).compactMap { offset in
      guard let key = LorvexDateFormatters.ymdUTCAddingDays(todayKey, days: offset) else { return nil }
      let dayEvents = events.filter { covers($0, key) }.sorted(by: eventOrder)
      let dayTasks = tasks.enumerated()
        .filter { $0.element.status.isActionable && CalendarGridModel.scheduledTaskDayKey($0.element) == key }
        .sorted { lhs, rhs in
          let left = lhs.element.time(on: key)?.lowerBound ?? Int.max
          let right = rhs.element.time(on: key)?.lowerBound ?? Int.max
          return left != right ? left < right : lhs.offset < rhs.offset
        }
        .map(\.element)
      guard !dayEvents.isEmpty || !dayTasks.isEmpty else { return nil }
      return LorvexAgendaDay(key: key, events: dayEvents, tasks: dayTasks)
    }
  }

  private static func covers(_ event: CalendarTimelineEvent, _ key: String) -> Bool {
    let endKey = event.endDate ?? event.startDate
    guard event.startDate <= key, key <= endKey else { return false }
    if key == endKey, endKey != event.startDate, !event.allDay,
      CalendarGridModel.parseMinutes(event.endTime) == 0
    {
      return false
    }
    return true
  }

  private static func eventOrder(_ lhs: CalendarTimelineEvent, _ rhs: CalendarTimelineEvent) -> Bool {
    switch (lhs.startTime, rhs.startTime) {
    case (let left?, let right?) where left != right: left < right
    case (nil, _?): true
    case (_?, nil): false
    default: lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
  }
}

extension LorvexAgendaDay {
  /// The day after `todayKey` as `core` holds it: its events and its open
  /// scheduled tasks, read for that one day. A day with nothing on it comes
  /// back empty rather than nil, so a caller can say the day is free.
  public static func loadDay(after todayKey: String, from core: any LorvexCoreServicing)
    async throws -> LorvexAgendaDay
  {
    guard let key = LorvexDateFormatters.ymdUTCAddingDays(todayKey, days: 1) else {
      return LorvexAgendaDay(key: todayKey, events: [], tasks: [])
    }
    async let timeline = core.loadCalendarTimeline(from: key, to: key)
    async let tasks = core.getScheduledTasks(from: key, to: key, limit: 50)
    let built = build(todayKey: todayKey, events: try await timeline.events, tasks: try await tasks, dayCount: 1)
    return built.first ?? LorvexAgendaDay(key: key, events: [], tasks: [])
  }

  /// The seven days after `todayKey` as `core` holds them, leaving out the
  /// days with nothing on them; an empty result means the week ahead is free.
  public static func loadWeek(after todayKey: String, from core: any LorvexCoreServicing)
    async throws -> [LorvexAgendaDay]
  {
    guard let first = LorvexDateFormatters.ymdUTCAddingDays(todayKey, days: 1),
      let last = LorvexDateFormatters.ymdUTCAddingDays(todayKey, days: 7)
    else { return [] }
    async let timeline = core.loadCalendarTimeline(from: first, to: last)
    async let tasks = core.getScheduledTasks(from: first, to: last, limit: 200)
    return build(todayKey: todayKey, events: try await timeline.events, tasks: try await tasks)
  }
}
