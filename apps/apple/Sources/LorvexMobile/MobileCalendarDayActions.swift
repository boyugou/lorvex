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

  /// Shows `day` at once, without paging, as a freshly switched mode opens.
  func showWithoutPaging(_ day: Date) {
    dayOffset = offset(showing: day)
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
    store.calendarDraft = MobileCalendarDraft.timedDefault(start: start, calendar: calendar)
    isShowingCreateEvent = true
  }

  /// Commits a drag-to-reschedule from the day column. Preserves the event's
  /// duration; only the start and end move.
  @MainActor
  func reschedule(
    _ event: CalendarTimelineEvent, toDay targetDay: Date, minute newStartMinute: Int
  ) async {
    let durationSeconds: TimeInterval = {
      let s = event.startTime.flatMap { hmToMinutes($0) } ?? 0
      let e = event.endTime.flatMap { hmToMinutes($0) } ?? (s + 60)
      return TimeInterval((e - s) * 60)
    }()
    guard
      let newStart = calendar.date(
        bySettingHour: newStartMinute / 60,
        minute: newStartMinute % 60,
        second: 0,
        of: targetDay)
    else { return }
    let newEnd = newStart.addingTimeInterval(durationSeconds)
    await store.rescheduleCalendarEvent(event, newStart: newStart, newEnd: newEnd)
  }

  func defaultCreateMinutes(on date: Date) -> Int {
    if calendar.isDate(date, inSameDayAs: store.now()) {
      let now = store.now()
      return calendar.component(.hour, from: now) * 60
    }
    return 9 * 60
  }

  private func hmToMinutes(_ hm: String) -> Int? {
    let parts = hm.split(separator: ":")
    guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
    return h * 60 + m
  }
}
