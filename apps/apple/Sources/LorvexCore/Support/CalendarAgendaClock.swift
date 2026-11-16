import Foundation

/// A shared chronological coordinate for an agenda containing projected
/// events and civil-clock tasks. A task's ambiguous clock uses the first
/// reading, like the planner; an event keeps its known instant.
struct CalendarAgendaClock {
  let calendar: Calendar?
  let dayStart: Date?

  init(day: String, events: [CalendarTimelineEvent]) {
    let zone = events.lazy.compactMap { $0.projection?.timezone }.compactMap(TimeZone.init(identifier:)).first
    let calendar = zone.map { LorvexDateFormatters.gregorianCalendar(timeZone: $0) }
    self.calendar = calendar
    if let calendar, let civil = LorvexDateFormatters.ymdUTC.date(from: day) {
      let parts = LorvexDateFormatters.gregorianCalendar(timeZone: .gmt)
        .dateComponents([.year, .month, .day], from: civil)
      dayStart = calendar.date(from: parts)
    } else { dayStart = nil }
  }

  func position(minute: Int) -> Double {
    guard let calendar, let dayStart else { return Double(minute) }
    let day = calendar.date(byAdding: .day, value: minute / 1440, to: dayStart) ?? dayStart
    let instant = calendar.date(
      bySettingHour: (minute % 1440) / 60, minute: minute % 60, second: 0, of: day,
      matchingPolicy: .nextTime, repeatedTimePolicy: .first) ?? day
    return position(instant: instant)
  }

  func position(instant: Date) -> Double {
    guard let dayStart else { return 0 }
    return instant.timeIntervalSince(dayStart) / 60
  }

  func position(event: CalendarTimelineEvent, minute: Int) -> Double {
    if let projection = event.projection, dayStart != nil {
      return max(0, position(instant: projection.start))
    }
    return position(minute: minute)
  }
}

extension CalendarTimelineEvent {
  /// Use the real clock to decide whether an event is finished. A minute of
  /// the repeated hour alone cannot tell which reading is current.
  public func hasPassed(
    on day: String, nowMinutes: Int?, now: Date? = nil, includingPointEvents: Bool = false
  ) -> Bool {
    guard let nowMinutes, let span = clockSpan(on: day) else { return false }
    if let projection {
      if let now, let endpoint = projection.end ?? (includingPointEvents ? projection.start : nil) {
        return endpoint <= now
      }
      if needsClockOffsets { return false }
    }
    guard let end = span.end ?? (includingPointEvents ? span.start : nil) else { return false }
    return end <= nowMinutes
  }
}
