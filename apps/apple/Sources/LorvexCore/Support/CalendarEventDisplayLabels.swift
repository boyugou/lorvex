import Foundation

extension CalendarTimelineEvent {
  /// The days the event takes time on, written with their weekdays: one day
  /// ("Friday, October 2"), or the first and last ("Friday, October 2 –
  /// Sunday, October 4") for an event that spans several
  /// (``lastOccupiedDay``). A day key that does not parse comes back as it
  /// was. The day keys name calendar days in the user's time zone, so they are
  /// read and written there.
  public var dayRangeLabel: String {
    guard let first = LorvexDateFormatters.ymd.date(from: startDate) else { return startDate }
    let lastDay = lastOccupiedDay
    guard lastDay > startDate, let last = LorvexDateFormatters.ymd.date(from: lastDay) else {
      return LorvexDateFormatters.string(
        first, template: "EEEEMMMMd", timeZone: .autoupdatingCurrent, position: .leading)
    }
    return LorvexDateFormatters.range(
      from: first, to: last, template: "EEEEMMMMd", timeZone: .autoupdatingCurrent,
      position: .leading)
  }

  /// What an event's When row says, in two lines the surface lays out as it
  /// likes. The first is the day or days, or, for a timed event that runs into
  /// a later day, the one span from its start to its end (``timedSpanLabel``).
  /// The second is `allDay` for an all-day event, the clock times of a timed
  /// event within one day, and nothing when the span already holds the times.
  ///
  /// - Parameter allDay: the surface's words for an all-day event ("All day").
  public func whenLines(allDay allDayText: String) -> (first: String, second: String?) {
    let span = timedSpanLabel
    let first = span ?? dayRangeLabel
    if allDay { return (first, allDayText) }
    guard span == nil, let startTime else { return (first, nil) }
    return (first, lorvexClockRangeLabel(start: startTime, end: endTime))
  }

  /// How the event repeats, in the words the repeat editor uses ("Every 2
  /// weeks · Mon, Wed · 10 times"): the source's own summary for a mirrored
  /// event, else the stored rule's. A one-off change to a series occurrence
  /// carries no rule of its own and reads as `generic`.
  ///
  /// - Parameter generic: the surface's words for a repeating event whose
  ///   rule is not known ("Repeating event").
  public func recurrenceDescription(generic: String) -> String {
    if let recurrenceSummary, !recurrenceSummary.isEmpty { return recurrenceSummary }
    guard let rule = TaskRecurrenceRule.bridgeRule(from: recurrenceRule) else { return generic }
    return rule.localizedDisplaySummary(
      anchorDay: LorvexDateFormatters.ymd.date(from: startDate))
  }

  /// Whether the event's detail has a Repeats row: it repeats, or it is a
  /// one-off change to a repeating series.
  public var hasRecurrenceRow: Bool { isRecurring || supportsScopedMutation }

  /// A link that opens Apple Calendar on the day the event starts (`calshow:`
  /// with the start as seconds since 2001-01-01 UTC). Lorvex shows an event a
  /// device calendar owns but cannot change it; Calendar can. Nil when the
  /// start day does not parse.
  public var appleCalendarURL: URL? {
    guard LorvexDateFormatters.ymd.date(from: startDate) != nil else { return nil }
    let start = CalendarEventTiming(event: self, fallbackDay: Date()).start
    return URL(string: "calshow:\(Int(start.timeIntervalSinceReferenceDate))")
  }
}
