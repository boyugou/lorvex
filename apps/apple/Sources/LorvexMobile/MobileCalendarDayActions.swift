import LorvexCore
import SwiftUI

extension MobileCalendarDayView {
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
