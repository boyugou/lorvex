import LorvexCore
import SwiftUI

extension MobileCalendarDayView {
  /// Step the visible page by `direction` (−1 back, +1 forward), clamped to
  /// `pageRange`. One step is a week in week mode and a day otherwise, matching
  /// what `date(forOffset:)` reads out of `dayOffset`.
  func stepPage(_ direction: Int) {
    let target = dayOffset + direction
    guard pageRange.contains(target) else { return }
    withAnimation { dayOffset = target }
  }

  /// Horizontal swipe paging for the week surfaces, which render a plain column
  /// rather than the day mode's paged `TabView` and would otherwise only move
  /// through the header's chevrons.
  ///
  /// Applied with `simultaneousGesture` so the agenda list and time grid keep
  /// their vertical scrolling; the dominance check keeps a mostly-vertical drag
  /// (or a diagonal flick while scrolling) from paging the week sideways.
  var weekPagingSwipe: some Gesture {
    DragGesture(minimumDistance: 24)
      .onEnded { value in
        let horizontal = value.translation.width
        guard abs(horizontal) > abs(value.translation.height) * 1.5 else { return }
        stepPage(horizontal < 0 ? 1 : -1)
      }
  }

  func jump(to day: Date) {
    let target =
      calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: day)).day ?? 0
    withAnimation { dayOffset = min(max(target, pageRange.lowerBound), pageRange.upperBound) }
  }

  func prepareCreate(at day: Date, minutes: Int) {
    let start =
      calendar.date(
        bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day
      ) ?? day
    let end = start.addingTimeInterval(60 * 60)
    store.calendarDraft = MobileCalendarDraft(
      date: day, startTime: start, endTime: end, allDay: false
    )
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
