import Foundation

extension CalendarEventTiming {
  /// Converts edited endpoints to the source zone while retaining the original
  /// civil fields of untouched endpoints. A recurrence's 02:30 source clock
  /// can display as 03:00 during a spring gap; editing its end must not rewrite
  /// that inherited start clock.
  public func sourceFields(for event: CalendarTimelineEvent) -> CalendarEventSourceTiming {
    let original = Self(event: event, fallbackDay: start, fallbackTimeZone: calendar.timeZone)
    let originalStored = original.storing(for: event)
    let source = event.sourceTiming ?? CalendarEventSourceTiming(
      startDate: event.projection == nil ? event.startDate : originalStored.startDate,
      startTime: event.projection == nil ? event.startTime : originalStored.startTime,
      endDate: event.projection == nil ? event.endDate : originalStored.endDate,
      endTime: event.projection == nil ? event.endTime : originalStored.endTime,
      allDay: event.allDay, timezone: event.timezone)
    let stored = storing(for: event)
    let sameKind = allDay == original.allDay
    let keepsStart = sameKind && sameEndpoint(start, original.start)
    let keepsEnd = sameKind && hasEndTime == original.hasEndTime && sameEndpoint(end, original.end)
    let startDay = keepsStart ? source.startDate : stored.startDate
    let endDay: String?
    if !allDay && !hasEndTime { endDay = nil }
    else if keepsEnd { endDay = source.endDate ?? source.startDate }
    else { endDay = stored.endDate ?? stored.startDate }
    return CalendarEventSourceTiming(
      startDate: startDay,
      startTime: allDay ? nil : keepsStart ? source.startTime : stored.startTime,
      endDate: endDay == startDay ? nil : endDay,
      endTime: allDay || !hasEndTime ? nil : keepsEnd ? source.endTime : stored.endTime,
      allDay: allDay, timezone: event.timezone)
  }

  private func sameEndpoint(_ lhs: Date, _ rhs: Date) -> Bool {
    lhs.timeIntervalSince1970.rounded(.down) == rhs.timeIntervalSince1970.rounded(.down)
  }
}
