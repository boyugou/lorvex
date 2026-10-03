import Foundation

/// When a calendar event happens, as the event forms hold it.
///
/// A timed event runs from the `start` instant to the `end` instant, and the
/// end may fall on a later day: an overnight event such as 22:00 to 01:00, or
/// one that spans several days. An all-day event covers every day from the day
/// of `start` through the day of `end`, both included. It keeps its clock times
/// only so that turning All Day off brings back the block it had.
///
/// Days and clock times are read in `calendar`: a Gregorian calendar in the
/// device's time zone unless a caller passes another time zone, which is how
/// the stored `yyyy-MM-dd` and `HH:mm` event fields are written and read
/// across the app. Lengths are kept as wall-clock minutes, so moving an event
/// across a daylight-saving change keeps its clock times.
public struct CalendarEventTiming: Equatable, Sendable {
  public var start: Date
  public var end: Date
  public var allDay: Bool
  public let calendar: Calendar

  /// A timing read in `calendar`. A calendar other than the Gregorian one
  /// contributes only its time zone, since the stored day keys are Gregorian.
  public init(start: Date, end: Date, allDay: Bool, calendar: Calendar = Self.deviceCalendar) {
    self.start = start
    self.end = end
    self.allDay = allDay
    self.calendar = Self.gregorian(calendar)
  }

  /// A Gregorian calendar in the device's current time zone: the reading of the
  /// stored day and clock-time fields.
  public static var deviceCalendar: Calendar {
    LorvexDateFormatters.gregorianCalendar(timeZone: .autoupdatingCurrent)
  }

  /// A timed event of `minutes` that starts at `start`. Its end may fall on the
  /// next day.
  public static func timed(
    startingAt start: Date, minutes: Int = 60, calendar: Calendar = deviceCalendar
  ) -> CalendarEventTiming {
    let calendar = gregorian(calendar)
    let (day, minute) = dayAndMinute(start, in: calendar)
    return CalendarEventTiming(
      start: start, end: instant(on: day, minute: minute + minutes, in: calendar), allDay: false,
      calendar: calendar)
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

  /// The timing of a stored event, its date and time fields read in
  /// `calendar`. A timed event runs from its start date and time to its end
  /// date (its start date when it has none) and end time, or for one hour when
  /// it has no end time. An all-day event has no clock times, so it gets 09:00
  /// on its first day and 10:00 on its last: turning All Day off then offers a
  /// one-hour block at each end. `fallbackDay` stands in for a start date that
  /// does not parse, and an end date before the start date reads as the start
  /// date.
  public init(event: CalendarTimelineEvent, fallbackDay: Date, calendar: Calendar = deviceCalendar) {
    let calendar = Self.gregorian(calendar)
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
    self.init(start: start, end: end, allDay: event.allDay, calendar: calendar)
  }

  // MARK: Edits

  /// Moves the start to `newStart` and the end with it, so the event keeps its
  /// length, as Apple Calendar does when the start changes.
  public mutating func moveStart(to newStart: Date) {
    let length = wallMinutes(from: start, to: end)
    let (day, minute) = Self.dayAndMinute(newStart, in: calendar)
    start = newStart
    end = Self.instant(on: day, minute: minute + length, in: calendar)
  }

  /// Moves the event to start on the day of `day`, at the same clock time,
  /// keeping its length.
  public mutating func setStartDay(_ day: Date) {
    let minute = Self.dayAndMinute(start, in: calendar).minute
    moveStart(to: Self.instant(on: calendar.startOfDay(for: day), minute: minute, in: calendar))
  }

  /// Moves the event to start at the clock time of `time` (its day is ignored)
  /// on the same day, keeping its length.
  public mutating func setStartTime(_ time: Date) {
    let day = Self.dayAndMinute(start, in: calendar).day
    let minute = Self.dayAndMinute(time, in: calendar).minute
    moveStart(to: Self.instant(on: day, minute: minute, in: calendar))
  }

  /// Ends the event on the day of `day`, at the same clock time.
  public mutating func setEndDay(_ day: Date) {
    let minute = Self.dayAndMinute(end, in: calendar).minute
    end = Self.instant(on: calendar.startOfDay(for: day), minute: minute, in: calendar)
  }

  /// Ends the event at the clock time of `time` (its day is ignored). While the
  /// event ends on its start day or the next, the end lands at the first moment
  /// after the start that shows that clock time: a 22:00 start and a 01:00 end
  /// make an overnight event, and picking 23:00 afterwards brings the end back
  /// to the start day. An event that ends two or more days after it starts
  /// keeps its end day.
  public mutating func setEndTime(_ time: Date) {
    let minute = Self.dayAndMinute(time, in: calendar).minute
    let (startDay, startMinute) = Self.dayAndMinute(start, in: calendar)
    let endDay = Self.dayAndMinute(end, in: calendar).day
    if allDay || days(from: startDay, to: endDay) > 1 {
      end = Self.instant(on: endDay, minute: minute, in: calendar)
    } else {
      end = Self.instant(
        on: startDay, minute: minute > startMinute ? minute : minute + 24 * 60, in: calendar)
    }
  }

  /// Takes a new end from a picker that edits the day and the clock time
  /// together. A value on the end's current day is a clock-time change
  /// (``setEndTime(_:)``); a value on another day is a day change and is kept
  /// as given.
  public mutating func setEnd(_ newEnd: Date) {
    if calendar.isDate(newEnd, inSameDayAs: end) {
      setEndTime(newEnd)
    } else {
      end = newEnd
    }
  }

  // MARK: Reading

  /// True when the event ends after it starts: a timed event's end instant is
  /// later than its start, and an all-day event's last day is not before its
  /// first.
  public var isValid: Bool {
    allDay
      ? calendar.startOfDay(for: end) >= calendar.startOfDay(for: start)
      : end > start
  }

  /// Days from the start day to the end day: 0 for an event within one day, 1
  /// for an overnight one.
  public var daySpan: Int {
    days(from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end))
  }

  /// The stored `start_date`: the day of `start` as `yyyy-MM-dd`.
  public var startDate: String { Self.dayKey(start, in: calendar) }

  /// The stored `end_date`: the day of `end` as `yyyy-MM-dd` when the event
  /// ends on a later day than it starts, and nil when it starts and ends on one
  /// day.
  public var endDate: String? {
    let key = Self.dayKey(end, in: calendar)
    return key == startDate ? nil : key
  }

  /// The stored `start_time` as `HH:mm`; nil for an all-day event.
  public var startTime: String? { allDay ? nil : Self.clockKey(start, in: calendar) }

  /// The stored `end_time` as `HH:mm`; nil for an all-day event.
  public var endTime: String? { allDay ? nil : Self.clockKey(end, in: calendar) }

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
    guard startDate != occurrence.startDate || !keepsDaySpan(of: occurrence) else {
      return (nil, nil)
    }
    return (startDate, endDate(updating: occurrence.endDate))
  }

  /// True when this timing spans as many days as `event` does. A scoped edit
  /// that changes the span applies to this event or this and the following
  /// ones, never to all events: an all-events edit writes the series' own
  /// dates, which start on the series' first day rather than this
  /// occurrence's.
  public func keepsDaySpan(of event: CalendarTimelineEvent) -> Bool {
    daySpan == Self.daySpan(startDate: event.startDate, endDate: event.endDate)
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
  private static func instant(on day: Date, minute: Int, in calendar: Calendar) -> Date {
    let dayOffset = Int((Double(minute) / Double(24 * 60)).rounded(.down))
    let minuteOfDay = minute - dayOffset * 24 * 60
    let shiftedDay = calendar.date(byAdding: .day, value: dayOffset, to: day) ?? day
    return calendar.date(
      bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: shiftedDay)
      ?? shiftedDay
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
