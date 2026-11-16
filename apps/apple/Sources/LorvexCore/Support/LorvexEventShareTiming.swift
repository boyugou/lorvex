import Foundation

/// The timing in a message must stand on its own: include the year and the
/// displayed clock's zone, and preserve both offsets across a DST change.
/// All-day and floating values remain civil dates without an inferred zone.
struct LorvexEventShareTiming {
  let when: String
  let timeZone: String?

  init(
    event: CalendarTimelineEvent, labels: LorvexEventShareLabels,
    locale: Locale = LorvexClockFormat.displayLocale
  ) {
    guard let firstDay = LorvexDateFormatters.ymdUTC.date(from: event.startDate) else {
      when = event.allDay ? labels.dayAtTime(event.startDate, labels.allDay)
        : event.startTime.map { labels.dayAtTime(event.startDate, lorvexClockRangeLabel(start: $0, end: event.endTime)) }
          ?? event.startDate
      timeZone = nil
      return
    }
    let civilDay = Self.day(firstDay, in: .gmt, locale: locale)
    if event.allDay {
      let lastDay = event.endDate.flatMap { LorvexDateFormatters.ymdUTC.date(from: $0) }
      let days = lastDay.map { last in
        last > firstDay ? LorvexDateFormatters.range(
          from: firstDay, to: last, template: "yEEEEMMMMd", timeZone: .gmt,
          locale: locale, position: .leading) : civilDay
      } ?? civilDay
      when = labels.dayAtTime(days, labels.allDay)
      timeZone = nil
      return
    }
    guard let startTime = event.startTime, lorvexMinutesSinceMidnight(startTime) != nil else {
      when = event.startTime.map { labels.dayAtTime(civilDay, $0) } ?? civilDay
      timeZone = nil
      return
    }

    // Older flat values can use 24:00; the editor timing model stores midnight
    // as 00:00 on the following civil day.
    var normalized = event
    if lorvexEndMinutesSinceMidnight(event.endTime) == 1440 {
      normalized.endDate = LorvexDateFormatters.ymdUTCAddingDays(event.endDate ?? event.startDate, days: 1)
      normalized.endTime = "00:00"
    }
    let projectionZone = event.projection.flatMap { TimeZone(identifier: $0.timezone) }
    let knownIdentifier = projectionZone != nil ? event.projection?.timezone : event.timezone
    let knownZone = knownIdentifier.flatMap(TimeZone.init(identifier:))
    let zone = knownZone ?? .gmt
    let timing = CalendarEventTiming(
      event: normalized, fallbackDay: firstDay,
      calendar: knownZone == nil ? LorvexDateFormatters.gregorianCalendar(timeZone: .gmt) : nil)
    let hasEnd = projectionZone != nil
      ? event.projection?.end != nil : lorvexEndMinutesSinceMidnight(normalized.endTime) != nil
    let end = hasEnd && timing.end > timing.start ? timing.end : nil
    let offsetChanges = end.map { zone.secondsFromGMT(for: $0) != zone.secondsFromGMT(for: timing.start) } ?? false

    when = Self.timed(
      start: timing.start, end: end, zone: zone, offsetChanges: offsetChanges,
      labels: labels, locale: locale)
    timeZone = knownIdentifier.flatMap {
      LorvexTimeZoneChoice(identifier: $0, now: timing.start, locale: locale)
    }.map { offsetChanges ? $0.city : $0.summary }
  }

  private static func day(_ date: Date, in zone: TimeZone, locale: Locale) -> String {
    LorvexDateFormatters.string(date, template: "yEEEEMMMMd", timeZone: zone, locale: locale, position: .leading)
  }

  private static func timed(
    start: Date, end: Date?, zone: TimeZone, offsetChanges: Bool,
    labels: LorvexEventShareLabels, locale: Locale
  ) -> String {
    guard let end else {
      return labels.dayAtTime(day(start, in: zone, locale: locale),
        LorvexDateFormatters.clockTime(start, timeZone: zone, locale: locale))
    }
    if offsetChanges {
      // DateIntervalFormatter collapses equal wall clocks even when a zone
      // template includes their different offsets. Format each actual instant.
      func endpoint(_ instant: Date) -> String {
        LorvexDateFormatters.string(
          instant, template: "yEEEEMMMMdjmmO", timeZone: zone, locale: locale, position: .leading)
      }
      let separator = locale.language.languageCode == .japanese ? "～" : " – "
      return endpoint(start) + separator + endpoint(end)
    }
    let calendar = LorvexDateFormatters.gregorianCalendar(timeZone: zone)
    if calendar.isDate(start, inSameDayAs: end) {
      func minutes(_ instant: Date) -> Int {
        calendar.component(.hour, from: instant) * 60 + calendar.component(.minute, from: instant)
      }
      return labels.dayAtTime(day(start, in: zone, locale: locale),
        lorvexClockRangeLabel(startMinutes: minutes(start), endMinutes: minutes(end), locale: locale))
    }
    // This compares endpoint days, not occupied grid days: a midnight end
    // still names the following date when the event is shared.
    return LorvexDateFormatters.range(
      from: start, to: end, template: "yEEEEMMMMdjmm", timeZone: zone,
      locale: locale, position: .leading)
  }
}
