import Foundation

extension CalendarGridTimedBlock {
  /// The time an event's block shows on the calendar grids, which
  /// ``LorvexCalendarBlockText`` draws under or beside the title: the event's
  /// time for the part of it the block draws
  /// (``CalendarTimelineEvent/timeLabel(for:)``), its start ("11:00 PM") on a
  /// block that starts it and "Until 1:00 AM" on the block that ends an event
  /// that started the day before.
  public var timeLabel: String? { event.timeLabel(for: part) }

  /// The time range an event's block shows where it fits the width ("9:00 –
  /// 10:30 AM"), in place of ``timeLabel``: the block's own span when it draws
  /// the whole event. One day's block of an event that runs past midnight has
  /// none, since its span is only that day's share of the event.
  public var rangeLabel: String? {
    part == .whole ? lorvexClockRangeLabel(startMinutes: startMin, endMinutes: endMin) : nil
  }
}

extension CalendarTimelineEvent {
  /// The time this timed event shows on one day of a calendar grid or Today's
  /// schedule, for the part of the event that day holds
  /// (``dayPart(on:)``). The day it starts on shows its start ("11:00 PM").
  /// A later day it ends on shows when it ends ("Until 1:00 AM"), since that
  /// day's part starts at midnight rather than at a start of its own. Nil for
  /// a day in between, which the event fills and which reads as all day, and
  /// when the event lacks the time the part shows.
  public func timeLabel(for part: CalendarEventDayPart) -> String? {
    switch part {
    case .whole, .firstDay:
      return startTime.map(lorvexClockTimeLabel)
    case .middleDay:
      return nil
    case .lastDay:
      guard let endTime else { return nil }
      let time = lorvexClockTimeLabel(endTime)
      return String(
        localized: "calendar.block.until", defaultValue: "Until \(time)", table: "Localizable",
        bundle: CoreL10n.bundle)
    }
  }

  /// The time a pill in a calendar grid's all-day strip shows for this event
  /// on `day`. A timed event of a day or more sits in the strip, as a pill on
  /// each day it takes time on, and shows its start on the day it starts and
  /// "Until 5:00 PM" on the day it ends (``timeLabel(for:)``). Nil for an
  /// all-day event, for a day in between, which the event fills, and for an
  /// event without a readable start.
  public func allDayStripTimeLabel(on day: String) -> String? {
    guard !allDay, lorvexMinutesSinceMidnight(startTime) != nil else { return nil }
    return timeLabel(for: dayPart(on: day))
  }

  /// The time this event shows under `day` in a list of days, such as an
  /// agenda or a review's look ahead. `range` words a one-day event's start
  /// and end on the day's clock (``clockSpan(on:)``: the end is nil when the
  /// event has no end time and 1440 when it ends at midnight). One day of an
  /// event that runs past midnight reads as ``timeLabel(for:)`` gives it: its
  /// start on the first day, "Until 1:30 AM" on the last. Nil where the event
  /// has no place on the day's clock, which the list words as all day.
  public func listTimeLabel(on day: String, range: (_ start: Int, _ end: Int?) -> String) -> String? {
    guard let span = clockSpan(on: day) else { return nil }
    let part = dayPart(on: day)
    return part == .whole ? range(span.start, span.end) : timeLabel(for: part)
  }

  /// A timed event that runs into a later day, written as one span from its
  /// start day and time to its end day and time ("Friday, October 2, 10:00 PM –
  /// Saturday, October 3, 1:00 AM"), since a day range over a time range would
  /// read as the same hours on each day. Nil for an all-day event and for a
  /// timed event within one day (``isMultiDay``), which read as the day and the
  /// clock times.
  public var timedSpanLabel: String? {
    guard !allDay, isMultiDay else { return nil }
    let timing = CalendarEventTiming(event: self, fallbackDay: Date())
    return LorvexDateFormatters.range(
      from: timing.start, to: timing.end, template: "EEEEMMMMdjmm",
      timeZone: .autoupdatingCurrent)
  }
}
