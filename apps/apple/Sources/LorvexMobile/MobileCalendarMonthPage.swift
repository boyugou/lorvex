import LorvexCore
import SwiftUI

/// What every page of the month pager draws from: the loaded window's events
/// and tasks, the day the grid marks as today, and the calendar that lays
/// months out. The month view builds one value per body pass and shares it with
/// all of its pages, so a page costs only its own offset until its body runs.
struct MobileCalendarMonthPageSource: Equatable {
  /// The loaded window's events, narrowed by the calendar search.
  let events: [CalendarTimelineEvent]
  /// The loaded window's scheduled tasks.
  let tasks: [LorvexTask]
  /// The first day of today's month, the month that offset 0 shows.
  let currentMonthStart: Date
  /// The rows every month's grid keeps.
  let weeks: Int
  /// The logical today as `yyyy-MM-dd`.
  let todayKey: String
  let calendar: Calendar
}

/// What a tap, a drop, or a menu choice on a month grid does. One value is
/// shared by all pages, like ``MobileCalendarMonthPageSource``.
struct MobileCalendarMonthGridActions {
  /// Chooses a tapped day.
  let choose: (CalendarMonthGridDay) -> Void
  /// Opens an event's editor.
  let openEvent: (CalendarTimelineEvent) -> Void
  /// Opens a task's detail.
  let openTask: (LorvexTask) -> Void
  /// Creates an event on the day.
  let createEvent: (Date) -> Void
  /// Plans the dropped tasks on the day.
  let dropTasks: ([LorvexTaskRef], Date) -> Void
}

/// One month of the month pager, `offset` months from today's.
///
/// The pager lists every month in its range, so each page keeps one identity
/// however far the person pages. Only the pages near the visible month hold a
/// grid: a page given no `source` is an empty placeholder, so the grids of the
/// months the person has paged through are released rather than re-evaluated
/// on every change.
///
/// A grid's days are built in this view's body, so only the pages that hold a
/// grid pay for the build.
struct MobileCalendarMonthPage: View, Equatable {
  let offset: Int
  /// What the grid draws from, or nil for a page that holds no grid.
  let source: MobileCalendarMonthPageSource?
  /// The chosen day as `yyyy-MM-dd` when this page's grid can show it (the
  /// chosen day lies in this month or the month before or after), else empty.
  /// A page that cannot show the chosen day is the same page whichever day is
  /// chosen, so paging re-evaluates only the pages the choice moves between.
  let selectedKey: String
  let actions: MobileCalendarMonthGridActions

  /// Two pages draw the same for the same month of the same source and chosen
  /// day. The actions do the same thing whenever they are built, so they are
  /// not compared; this lets SwiftUI skip a page when only the pager's other
  /// pages changed.
  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.offset == rhs.offset && lhs.selectedKey == rhs.selectedKey && lhs.source == rhs.source
  }

  /// The `selectedKey` for the page `offset` months from today's month: the
  /// chosen day's key (`chosenKey`) when that day lies in the page's month or
  /// the month before or after it, whose days fill the first and last weeks of
  /// the grid, else empty. The month indexes come from
  /// ``MobileCalendarMonthView/monthIndex(of:calendar:)``: `currentMonthIndex`
  /// for today's month and `chosenMonthIndex` for the chosen day's.
  nonisolated static func selectedKey(
    _ chosenKey: String, chosenMonthIndex: Int, offset: Int, currentMonthIndex: Int
  ) -> String {
    abs(currentMonthIndex + offset - chosenMonthIndex) <= 1 ? chosenKey : ""
  }

  var body: some View {
    if let source {
      MobileCalendarMonthGrid(
        days: days(for: source),
        todayKey: source.todayKey,
        selectedKey: selectedKey,
        calendar: source.calendar,
        choose: actions.choose,
        openEvent: actions.openEvent,
        openTask: actions.openTask,
        createEvent: actions.createEvent,
        dropTasks: actions.dropTasks)
    } else {
      Color.clear
    }
  }

  /// The month's grid days: whole weeks, at least ``MobileCalendarMonthPageSource/weeks``
  /// rows, with the events and tasks that fall on each day.
  private func days(for source: MobileCalendarMonthPageSource) -> [CalendarMonthGridDay] {
    let calendar = source.calendar
    let anchor =
      calendar.date(byAdding: .month, value: offset, to: source.currentMonthStart)
      ?? source.currentMonthStart
    return CalendarMonthGridModel.buildDays(
      monthAnchor: anchor, calendar: calendar, events: source.events, tasks: source.tasks,
      minimumWeeks: source.weeks,
      dayKeyFor: { MobileCalendarMonthView.keyFormatter.string(from: $0) })
  }
}
