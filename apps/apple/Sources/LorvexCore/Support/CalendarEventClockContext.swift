import Foundation
import LorvexDomain

extension CalendarTimelineEvent {
  /// True when a single civil-clock drag cannot describe the real interval.
  /// Split blocks open the event editor instead of rescheduling one fragment.
  public var crossesClockChange: Bool {
    guard let projection, let end = projection.end, end > projection.start,
      let zone = TimeZone(identifier: projection.timezone),
      let transition = zone.nextDaylightSavingTimeTransition(after: projection.start)
    else { return false }
    return transition <= end
  }

  public var needsClockOffsets: Bool {
    guard let projection, let zone = TimeZone(identifier: projection.timezone) else { return false }
    return crossesClockChange || CalendarWallClockSegment.isRepeatedClock(projection.start, in: zone)
      || projection.end.map { CalendarWallClockSegment.isRepeatedClock($0, in: zone) } == true
  }

  public var elapsedMinutes: Int? {
    guard !allDay, let projection, let end = projection.end, end > projection.start else { return nil }
    return Int((end.timeIntervalSince(projection.start) / 60).rounded())
  }

  func clockSegments(on day: String) -> [CalendarWallClockSegment] {
    guard !allDay, let projection, let end = projection.end,
      let zone = TimeZone(identifier: projection.timezone), let day = try? LorvexDate.parse(day).get()
    else { return [] }
    return CalendarWallClockSegment.segments(from: projection.start, to: end, on: day, in: zone)
  }

  /// Format endpoints separately: interval formatters can collapse two
  /// different readings of the same hour even with an offset in the template.
  public func offsetClockRangeLabel(
    includingDays: Bool = false, locale: Locale = LorvexClockFormat.displayLocale
  ) -> String? {
    guard needsClockOffsets, let projection, let zone = TimeZone(identifier: projection.timezone) else { return nil }
    let template = includingDays ? "EEEEMMMMdjmmO" : "jmmO"
    func endpoint(_ instant: Date) -> String {
      LorvexDateFormatters.string(instant, template: template, timeZone: zone, locale: locale, position: .leading)
    }
    guard let end = projection.end, end > projection.start else { return endpoint(projection.start) }
    return endpoint(projection.start) + (locale.language.languageCode == .japanese ? "～" : " – ") + endpoint(end)
  }

  func offsetClockLabel(ending: Bool = false) -> String? {
    guard needsClockOffsets, let projection, let zone = TimeZone(identifier: projection.timezone),
      let instant = ending ? projection.end : projection.start
    else { return nil }
    return LorvexDateFormatters.string(instant, template: "jmmO", timeZone: zone)
  }
}

extension CalendarEventTiming {
  /// The editor explains a repeated or changing clock using the draft's real
  /// instants. Recompute after each edit; an original event's note goes stale.
  public var clockOffsetNote: String? {
    guard !allDay, isValid else { return nil }
    let zone = calendar.timeZone
    if !hasEndTime {
      guard CalendarWallClockSegment.isRepeatedClock(start, in: zone) else { return nil }
      return LorvexDateFormatters.string(start, template: "jmmO", timeZone: zone)
    }
    let transition = zone.nextDaylightSavingTimeTransition(after: start)
    guard transition.map({ $0 <= end }) == true
      || CalendarWallClockSegment.isRepeatedClock(start, in: zone)
      || CalendarWallClockSegment.isRepeatedClock(end, in: zone)
    else { return nil }
    let locale = LorvexClockFormat.displayLocale
    let template = calendar.isDate(start, inSameDayAs: end) ? "jmmO" : "EEEEMMMMdjmmO"
    func label(_ date: Date) -> String {
      LorvexDateFormatters.string(date, template: template, timeZone: zone, locale: locale, position: .leading)
    }
    return label(start) + (locale.language.languageCode == .japanese ? "～" : " – ") + label(end)
  }
}
