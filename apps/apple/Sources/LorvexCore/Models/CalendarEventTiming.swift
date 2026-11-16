import Foundation

/// When a calendar event happens, as the event forms hold it.
///
/// A timed event with an end runs from `start` to `end`, and the
/// end may fall on a later day: an overnight event such as 22:00 to 01:00, or
/// one that spans several days. An all-day event covers every day from the day
/// of `start` through the day of `end`, both included. It keeps its clock times
/// only so that turning All Day off brings back the block it had. A timed event
/// that ends exactly at midnight occupies only the days before it, so turning
/// All Day on ends the all-day span on the day before that midnight. Turning
/// All Day off again puts a one-night event's end back on its midnight; a
/// longer event keeps the end day the span gave it.
///
/// Days and clock times are read in the Gregorian `calendar`. Event forms use
/// the timeline's display zone, or the source zone for a raw stored event;
/// floating and all-day events use the caller's fallback zone. Lengths are
/// kept as wall-clock minutes, so moving an event
/// across a daylight-saving change keeps its clock times. A positive span
/// whose clocks repeat or run backwards instead moves by its elapsed length.
public struct CalendarEventTiming: Equatable, Sendable {
  public var start: Date
  public var end: Date
  /// Without an end time, `end` is only the editor's proposed value.
  public var hasEndTime: Bool
  public var allDay: Bool {
    didSet {
      guard allDay != oldValue else { return }
      if allDay {
        if hasEndTime { endAllDaySpanBeforeMidnightEnd() }
        else { end = start }
      } else {
        if hasEndTime { restoreEndAfterStart() }
        else { end = Self.timed(startingAt: start, calendar: calendar).end }
      }
    }
  }
  public let calendar: Calendar

  /// A timing read in `calendar`. A calendar other than the Gregorian one
  /// contributes only its time zone, since the stored day keys are Gregorian.
  public init(
    start: Date, end: Date, allDay: Bool, calendar: Calendar = Self.deviceCalendar,
    hasEndTime: Bool = true
  ) {
    self.start = start
    self.end = end
    self.hasEndTime = hasEndTime
    self.allDay = allDay
    self.calendar = Self.gregorian(calendar)
  }

  /// A Gregorian calendar in the device's current time zone: the reading of the
  /// stored day and clock-time fields.
  public static var deviceCalendar: Calendar {
    LorvexDateFormatters.gregorianCalendar(timeZone: .current)
  }

  /// A timed event of `minutes` that starts at `start`. Its end may fall on the
  /// next day.
  public static func timed(
    startingAt start: Date, minutes: Int = 60, calendar: Calendar = deviceCalendar
  ) -> CalendarEventTiming {
    let calendar = gregorian(calendar)
    let (day, minute) = dayAndMinute(start, in: calendar)
    return CalendarEventTiming(
      start: start, end: instant(on: day, minute: minute + minutes, in: calendar, preservingOffsetOf: start), allDay: false,
      calendar: calendar)
  }

  /// A block on the grid's civil day in `timeZone`. The day label comes from
  /// `dayCalendar`; constructing its clock directly in the target zone avoids
  /// applying a different device zone's daylight-saving gap to the selection.
  public static func timed(
    on day: Date, atMinute minute: Int, minutes: Int = 60, timeZone: TimeZone,
    dayCalendar: Calendar = deviceCalendar
  ) -> CalendarEventTiming {
    let calendar = LorvexDateFormatters.gregorianCalendar(timeZone: timeZone)
    let parts = gregorian(dayCalendar).dateComponents([.year, .month, .day], from: day)
    let targetDay = calendar.date(from: parts) ?? day
    return timed(
      startingAt: instant(on: targetDay, minute: minute, in: calendar),
      minutes: minutes, calendar: calendar)
  }

  /// The one-hour block a new event offers at `now`, as Apple Calendar does:
  /// from the next full hour, or from `now` when it is exactly on the hour.
  public static func nextHourBlock(
    after now: Date, calendar: Calendar = deviceCalendar
  ) -> CalendarEventTiming {
    let calendar = gregorian(calendar)
    let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
    let start = hourStart < now ? hourStart.addingTimeInterval(3_600) : hourStart
    return timed(startingAt: start, calendar: calendar)
  }

  /// The timing of an event in its timeline's display zone, or its stored zone
  /// when read outside a timeline. An explicit `calendar` instead reads the
  /// displayed fields as civil labels, as calendar-grid geometry needs.
  /// A timed event runs from its start date and time to its end
  /// date (its start date when it has none) and end time. When it has no end,
  /// the editor proposes one hour without storing it. An all-day event has no clock times, so it gets 09:00
  /// on its first day and 10:00 on its last: turning All Day off then offers a
  /// one-hour block at each end. `fallbackDay` stands in for a start date that
  /// does not parse, and an end date before the start date reads as the start
  /// date.
  public init(
    event: CalendarTimelineEvent, fallbackDay: Date, calendar: Calendar? = nil,
    fallbackTimeZone: TimeZone = .current
  ) {
    if calendar == nil, !event.allDay, let projection = event.projection,
      let zone = TimeZone(identifier: projection.timezone)
    {
      let calendar = LorvexDateFormatters.gregorianCalendar(timeZone: zone)
      self.init(
        start: projection.start,
        end: projection.end ?? Self.timed(startingAt: projection.start, calendar: calendar).end,
        allDay: false, calendar: calendar, hasEndTime: projection.end != nil)
      return
    }
    let sourceCalendar = event.timezone.flatMap(TimeZone.init(identifier:)).map {
      LorvexDateFormatters.gregorianCalendar(timeZone: $0)
    }
    let calendar = Self.gregorian(
      calendar ?? (event.allDay ? nil : sourceCalendar)
        ?? LorvexDateFormatters.gregorianCalendar(timeZone: fallbackTimeZone))
    let firstDay =
      Self.day(fromKey: event.startDate, in: calendar) ?? calendar.startOfDay(for: fallbackDay)
    let lastDay = max(
      event.endDate.flatMap { Self.day(fromKey: $0, in: calendar) } ?? firstDay, firstDay)
    let startMinute = event.allDay ? nil : event.startTime.flatMap(Self.minuteOfDay(fromKey:))
    let endMinute = event.allDay ? nil : event.endTime.flatMap(Self.minuteOfDay(fromKey:))
    let start = Self.instant(on: firstDay, minute: startMinute ?? 9 * 60, in: calendar)
    let end: Date
    switch (startMinute, endMinute) {
    case (_, let endMinute?):
      end = Self.instant(on: lastDay, minute: endMinute, in: calendar)
    case (let startMinute?, nil):
      end = Self.instant(on: lastDay, minute: startMinute + 60, in: calendar)
    case (nil, nil):
      end = Self.instant(on: lastDay, minute: 10 * 60, in: calendar)
    }
    self.init(
      start: start, end: end, allDay: event.allDay, calendar: calendar,
      hasEndTime: event.allDay || event.endTime != nil)
  }

  // MARK: Edits

  /// Moves the start to `newStart` and the end with it, so the event keeps its
  /// length, as Apple Calendar does when the start changes.
  public mutating func moveStart(to newStart: Date) {
    guard newStart != start else { return }
    if !allDay, !hasEndTime {
      start = newStart
      end = Self.timed(startingAt: newStart, calendar: calendar).end
      return
    }
    let length = wallMinutes(from: start, to: end)
    let elapsed = end.timeIntervalSince(start)
    if !allDay, length <= 0, elapsed > 0 {
      start = newStart
      end = newStart.addingTimeInterval(elapsed)
      return
    }
    let (day, minute) = Self.dayAndMinute(newStart, in: calendar)
    start = newStart
    end = Self.instant(on: day, minute: minute + length, in: calendar, preservingOffsetOf: newStart)
  }

  /// Moves the event to start on the day of `day`, at the same clock time,
  /// keeping its length.
  public mutating func setStartDay(_ day: Date) {
    guard !calendar.isDate(day, inSameDayAs: start) else { return }
    let minute = Self.dayAndMinute(start, in: calendar).minute
    moveStart(to: Self.instant(on: calendar.startOfDay(for: day), minute: minute, in: calendar))
  }

  /// Moves the event to start at the clock time of `time` (its day is ignored)
  /// on the same day, keeping its length.
  public mutating func setStartTime(_ time: Date) {
    let day = Self.dayAndMinute(start, in: calendar).day
    let minute = Self.dayAndMinute(time, in: calendar).minute
    guard minute != Self.dayAndMinute(start, in: calendar).minute else { return }
    moveStart(to: Self.instant(on: day, minute: minute, in: calendar, preservingOffsetOf: start))
  }

  /// Ends the event on the day of `day`, at the same clock time.
  public mutating func setEndDay(_ day: Date) {
    if !allDay { hasEndTime = true }
    guard !calendar.isDate(day, inSameDayAs: end) else { return }
    let minute = Self.dayAndMinute(end, in: calendar).minute
    end = Self.instant(on: calendar.startOfDay(for: day), minute: minute, in: calendar)
  }

  /// Ends the event at the clock time of `time` (its day is ignored). While the
  /// event ends on its start day or the next, a repeated-hour end keeps its
  /// current reading when valid; otherwise it lands at the first moment after
  /// the start that shows that clock time: a 22:00 start and a 01:00 end
  /// make an overnight event, and picking 23:00 afterwards brings the end back
  /// to the start day. An event that ends two or more days after it starts
  /// keeps its end day.
  public mutating func setEndTime(_ time: Date) {
    if !allDay { hasEndTime = true }
    let minute = Self.dayAndMinute(time, in: calendar).minute
    if minute == Self.dayAndMinute(end, in: calendar).minute, allDay || end > start { return }
    let startDay = Self.dayAndMinute(start, in: calendar).day
    let endDay = Self.dayAndMinute(end, in: calendar).day
    if allDay || days(from: startDay, to: endDay) > 1 {
      end = Self.instant(on: endDay, minute: minute, in: calendar, preservingOffsetOf: end)
    } else {
      // Keep the current reading when possible. Otherwise try both readings
      // of today's clock before moving an earlier-looking end to tomorrow.
      let preferred = Self.instant(on: startDay, minute: minute, in: calendar, preservingOffsetOf: end)
      let first = Self.instant(on: startDay, minute: minute, in: calendar)
      let last = Self.instant(on: startDay, minute: minute, in: calendar, repeatedTimePolicy: .last)
      end = preferred > start ? preferred
        : [first, last].filter { $0 > start }.min()
          ?? Self.instant(on: startDay, minute: minute + 24 * 60, in: calendar)
    }
  }

  /// Takes a new end from a picker that edits the day and the clock time
  /// together. A value on the end's current day is a clock-time change
  /// (``setEndTime(_:)``); a value on another day is a day change and is kept
  /// as given.
  public mutating func setEnd(_ newEnd: Date) {
    if !allDay { hasEndTime = true }
    if calendar.isDate(newEnd, inSameDayAs: end) {
      setEndTime(newEnd)
    } else {
      end = newEnd
    }
  }

  // MARK: Reading

  /// Expresses this edited instant in the event's storage zone without changing
  /// that zone or its recurrence semantics. All-day dates and floating clocks
  /// remain civil values and are never shifted.
  public func storing(for event: CalendarTimelineEvent) -> CalendarEventTiming {
    guard !allDay, let identifier = event.timezone,
      let zone = TimeZone(identifier: identifier)
    else { return self }
    return CalendarEventTiming(
      start: start, end: end, allDay: false,
      calendar: LorvexDateFormatters.gregorianCalendar(timeZone: zone), hasEndTime: hasEndTime)
  }

  /// Interprets the same day and clock labels in `timeZone`. Grid coordinates
  /// use device-local dates as labels; their drops belong to the product zone.
  /// An unchanged endpoint keeps its original instant so resizing the other
  /// end cannot jump between the two readings of a repeated fall-back hour.
  public func interpretingWallClock(
    in timeZone: TimeZone, preserving projection: CalendarEventProjection? = nil
  ) -> CalendarEventTiming {
    let target = LorvexDateFormatters.gregorianCalendar(timeZone: timeZone)
    func reinterpret(_ date: Date, original: Date?) -> Date {
      let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
      if let original,
        parts == target.dateComponents([.year, .month, .day, .hour, .minute], from: original)
      { return original }
      return target.date(from: parts) ?? date
    }
    return CalendarEventTiming(
      start: reinterpret(start, original: projection?.start),
      end: reinterpret(end, original: projection?.end), allDay: allDay, calendar: target,
      hasEndTime: hasEndTime)
  }

  /// A localized zone label at the event's start, including its seasonal offset.
  public var timeZoneSummary: String {
    LorvexTimeZoneChoice(identifier: calendar.timeZone.identifier, now: start)?.summary
      ?? calendar.timeZone.identifier
  }

  /// An explicit timed end must follow the start. An all-day event's last day
  /// cannot precede its first. A timed event may have no end.
  public var isValid: Bool {
    allDay
      ? calendar.startOfDay(for: end) >= calendar.startOfDay(for: start)
      : !hasEndTime || end > start
  }

  /// Days from the start day to the end day: 0 for an event within one day, 1
  /// for an overnight one.
  public var daySpan: Int {
    !allDay && !hasEndTime ? 0
      : days(from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end))
  }

  /// The stored `start_date`: the day of `start` as `yyyy-MM-dd`.
  public var startDate: String { Self.dayKey(start, in: calendar) }

  /// The stored `end_date`: the day of `end` as `yyyy-MM-dd` when the event
  /// ends on a later day than it starts, and nil when it starts and ends on one
  /// day.
  public var endDate: String? {
    guard allDay || hasEndTime else { return nil }
    let key = Self.dayKey(end, in: calendar)
    return key == startDate ? nil : key
  }

  /// The stored `start_time` as `HH:mm`; nil for an all-day event.
  public var startTime: String? { allDay ? nil : Self.clockKey(start, in: calendar) }

  /// The stored `end_time` as `HH:mm`; nil for all-day events or an unknown end.
  public var endTime: String? { allDay || !hasEndTime ? nil : Self.clockKey(end, in: calendar) }

  /// True when this timing and `other` store the same `start_date`,
  /// `end_date`, `start_time`, `end_time`, and `all_day`. Turning All Day on
  /// and off again can leave a different `end` instant that stores the same
  /// fields, so an edit form asks this, not `==`, whether its timing changed.
  public func storesSameFields(as other: CalendarEventTiming) -> Bool {
    allDay == other.allDay && startDate == other.startDate && endDate == other.endDate
      && startTime == other.startTime && endTime == other.endTime
  }

  /// The `end_date` to send when updating an event stored with
  /// `storedEndDate`. The update contract reads nil as "keep the stored end
  /// date", so an event that had an end date and now starts and ends on one
  /// day sends its start date rather than nil.
  public func endDate(updating storedEndDate: String?) -> String? {
    endDate ?? (storedEndDate == nil ? nil : startDate)
  }

  /// The `start_date` and `end_date` a scoped edit of the recurring
  /// `occurrence` sends. Both are nil while the event keeps its day and its
  /// length in days, so an edit to the times or the details never re-anchors
  /// the series; otherwise they are this timing's own days, the end written
  /// out as ``endDate(updating:)`` does.
  public func scopedDates(
    for occurrence: CalendarTimelineEvent
  ) -> (startDate: String?, endDate: String?) {
    let stored = sourceFields(for: occurrence)
    let original = Self(event: occurrence, fallbackDay: start).sourceFields(for: occurrence)
    guard stored.startDate != original.startDate
      || Self.daySpan(startDate: stored.startDate, endDate: stored.endDate)
        != Self.daySpan(startDate: original.startDate, endDate: original.endDate)
    else {
      return (nil, nil)
    }
    return (stored.startDate, stored.endDate ?? stored.startDate)
  }

  /// True when this timing spans as many days as `event` does. A scoped edit
  /// that changes the span applies to this event or this and the following
  /// ones, never to all events: an all-events edit writes the series' own
  /// dates, which start on the series' first day rather than this
  /// occurrence's.
  public func keepsDaySpan(of event: CalendarTimelineEvent) -> Bool {
    let stored = sourceFields(for: event)
    let original = Self(event: event, fallbackDay: start).sourceFields(for: event)
    return Self.daySpan(startDate: stored.startDate, endDate: stored.endDate)
      == Self.daySpan(startDate: original.startDate, endDate: original.endDate)
  }

  public mutating func addEndTime() {
    if end <= start { end = Self.timed(startingAt: start, calendar: calendar).end }
    hasEndTime = true
  }

  public mutating func removeEndTime() {
    hasEndTime = false
  }

  /// True when saving this timing over the recurring `occurrence` leaves the
  /// series' own first day alone: the draft keeps the occurrence's day and its
  /// length in days, so ``scopedDates(for:)`` sends no dates. An all-events save
  /// that keeps the first day also keeps cancelled occurrences cancelled; one
  /// that moves it restarts the recurrence and clears every cancelled day.
  public func keepsSeriesFirstDay(of occurrence: CalendarTimelineEvent) -> Bool {
    scopedDates(for: occurrence).startDate == nil
  }

  /// Days from the stored `startDate` to the stored `endDate`, both
  /// `yyyy-MM-dd`: 0 for an event with no end date or one that cannot be read.
  public static func daySpan(startDate: String, endDate: String?) -> Int {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = .gmt
    guard let endDate,
      let first = day(fromKey: startDate, in: utc),
      let last = day(fromKey: endDate, in: utc)
    else { return 0 }
    return max(0, utc.dateComponents([.day], from: first, to: last).day ?? 0)
  }

  // MARK: All-day switch

  /// A timed event that ends exactly at midnight, on a later day than it
  /// starts, ends the all-day span on the day before that midnight; the end
  /// keeps its clock time (00:00) so turning All Day off can restore it.
  private mutating func endAllDaySpanBeforeMidnightEnd() {
    let (startDay, _) = Self.dayAndMinute(start, in: calendar)
    let (endDay, endMinute) = Self.dayAndMinute(end, in: calendar)
    guard endMinute == 0, days(from: startDay, to: endDay) >= 1 else { return }
    end = Self.instant(on: endDay, minute: -24 * 60, in: calendar)
  }

  /// Turning All Day off with an end before the start (the end clock time was
  /// kept at 00:00 while the span ended the day before) puts the end at the
  /// first moment after the start that shows its clock time, as
  /// ``setEndTime(_:)`` does. An end at the start's own instant is left for the
  /// form's end-after-start warning.
  private mutating func restoreEndAfterStart() {
    guard end < start else { return }
    setEndTime(end)
  }

  // MARK: Helpers

  private static func gregorian(_ calendar: Calendar) -> Calendar {
    calendar.identifier == .gregorian
      ? calendar : LorvexDateFormatters.gregorianCalendar(timeZone: calendar.timeZone)
  }

  private func days(from firstDay: Date, to lastDay: Date) -> Int {
    calendar.dateComponents([.day], from: firstDay, to: lastDay).day ?? 0
  }

  private func wallMinutes(from first: Date, to last: Date) -> Int {
    let (firstDay, firstMinute) = Self.dayAndMinute(first, in: calendar)
    let (lastDay, lastMinute) = Self.dayAndMinute(last, in: calendar)
    return days(from: firstDay, to: lastDay) * 24 * 60 + lastMinute - firstMinute
  }

  private static func dayAndMinute(_ date: Date, in calendar: Calendar) -> (day: Date, minute: Int) {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return (calendar.startOfDay(for: date), (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
  }

  /// The instant `minute` minutes after the start of `day`; minutes past one
  /// day, or before it, carry into the following or preceding days.
  private static func instant(
    on day: Date, minute: Int, in calendar: Calendar, repeatedTimePolicy: Calendar.RepeatedTimePolicy = .first
  ) -> Date {
    let dayOffset = Int((Double(minute) / Double(24 * 60)).rounded(.down))
    let minuteOfDay = minute - dayOffset * 24 * 60
    let shiftedDay = calendar.date(byAdding: .day, value: dayOffset, to: day) ?? day
    return calendar.date(
      bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: shiftedDay,
      matchingPolicy: .nextTime, repeatedTimePolicy: repeatedTimePolicy)
      ?? shiftedDay
  }

  private static func instant(
    on day: Date, minute: Int, in calendar: Calendar, preservingOffsetOf original: Date
  ) -> Date {
    let first = instant(on: day, minute: minute, in: calendar)
    guard calendar.isDate(first, inSameDayAs: original) else { return first }
    let last = instant(on: day, minute: minute, in: calendar, repeatedTimePolicy: .last)
    return calendar.timeZone.secondsFromGMT(for: last) == calendar.timeZone.secondsFromGMT(for: original)
      ? last : first
  }

  private static func dayKey(_ date: Date, in calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  private static func clockKey(_ date: Date, in calendar: Calendar) -> String {
    let minute = dayAndMinute(date, in: calendar).minute
    return String(format: "%02d:%02d", minute / 60, minute % 60)
  }

  /// The start of the day a `yyyy-MM-dd` key names, or nil when the key is not
  /// a real day.
  private static func day(fromKey key: String, in calendar: Calendar) -> Date? {
    let parts = key.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
    guard parts.count == 3, let year = parts[0], let month = parts[1], let day = parts[2],
      let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
      dayKey(date, in: calendar) == key
    else { return nil }
    return date
  }

  /// Minutes after midnight for an `HH:mm` key, or nil when it is not a clock
  /// time.
  private static func minuteOfDay(fromKey key: String) -> Int? {
    let parts = key.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
    guard parts.count == 2, let hour = parts[0], let minute = parts[1],
      (0..<24).contains(hour), (0..<60).contains(minute)
    else { return nil }
    return hour * 60 + minute
  }
}
