import LorvexCore
import SwiftUI

extension MobileCalendarDayView {
  /// Pages to `day` with the page animation, as Today and the week strip's
  /// day buttons do: Day mode to that day, Week mode to its week, focused on
  /// it.
  func jump(to day: Date) {
    withAnimation { dayOffset = offset(showing: day) }
    focusWeek(on: day)
  }

  private func focusWeek(on day: Date) {
    if weekMode { weekDayIndex = Self.dayIndexInWeek(of: day, calendar: calendar) }
  }

  /// The pager page that shows `day`, within the pager's range.
  func offset(showing day: Date) -> Int {
    let target = Self.pageOffset(showing: day, weekMode: weekMode, today: today, calendar: calendar)
    return min(max(target, pageRange.lowerBound), pageRange.upperBound)
  }

  /// The day a mode switch carries to the other mode.
  var modeSwitchDay: Date {
    Self.modeSwitchDay(
      weekMode: weekMode, visibleDate: visibleDate, weekDayIndex: weekDayIndex, calendar: calendar)
  }

  /// The pager page that shows `day`, counted from today's page: its day
  /// offset from today in Day mode, the week offset of its week from the
  /// current week in Week mode.
  nonisolated static func pageOffset(
    showing day: Date, weekMode: Bool, today: Date, calendar: Calendar
  ) -> Int {
    guard weekMode else {
      return calendar.dateComponents(
        [.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: day)
      ).day ?? 0
    }
    let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
    let dayWeekStart = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
    return (calendar.dateComponents([.day], from: currentWeekStart, to: dayWeekStart).day ?? 0) / 7
  }

  /// How many days `day` lies after the first day of its week, 0 through 6.
  nonisolated static func dayIndexInWeek(of day: Date, calendar: Calendar) -> Int {
    let dayWeekStart = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
    let index =
      calendar.dateComponents([.day], from: dayWeekStart, to: calendar.startOfDay(for: day)).day
      ?? 0
    return min(max(index, 0), 6)
  }

  /// The day a mode switch carries to the other mode: Day mode's first
  /// visible day, or, in Week mode, the day `weekDayIndex` days into the
  /// visible week, which starts on `visibleDate`.
  nonisolated static func modeSwitchDay(
    weekMode: Bool, visibleDate: Date, weekDayIndex: Int, calendar: Calendar
  ) -> Date {
    guard weekMode else { return visibleDate }
    return calendar.date(byAdding: .day, value: weekDayIndex, to: visibleDate) ?? visibleDate
  }

  func prepareCreate(at day: Date, minutes: Int) {
    let start =
      calendar.date(
        bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day
      ) ?? day
    store.calendarDraft = MobileCalendarDraft.timedDefault(start: start)
    isShowingCreateEvent = true
  }

  /// Commits a drag-to-reschedule from the day column. Only the start and end
  /// move, and the event keeps its length in clock time
  /// (``CalendarEventTiming/moveStart(to:)``), so one that ends at midnight or
  /// runs past it keeps its length too.
  @MainActor
  func reschedule(
    _ event: CalendarTimelineEvent, toDay targetDay: Date, minute newStartMinute: Int
  ) async {
    guard
      let newStart = calendar.date(
        bySettingHour: newStartMinute / 60,
        minute: newStartMinute % 60,
        second: 0,
        of: targetDay)
    else { return }
    var timing = CalendarEventTiming(event: event, fallbackDay: targetDay, calendar: calendar)
    timing.moveStart(to: newStart)
    await store.rescheduleCalendarEvent(event, newStart: timing.start, newEnd: timing.end)
  }
}
