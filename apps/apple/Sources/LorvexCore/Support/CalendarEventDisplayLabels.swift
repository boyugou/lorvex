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
    return (first, offsetClockRangeLabel() ?? lorvexClockRangeLabel(start: startTime, end: endTime))
  }

  /// How the event repeats, in the words the repeat editor uses ("Every 2
  /// weeks · Mon, Wed · 10 times"): the source's own summary for a mirrored
  /// event, else the stored rule's. A one-off change to a series occurrence
  /// carries no rule of its own and reads as `generic`.
  /// An implicit weekly day follows the source clock, even when the timeline
  /// displays that occurrence on a different day. Day anchors are UTC-midnight
  /// civil values, as the shared recurrence formatter requires.
  ///
  /// - Parameter generic: the surface's words for a repeating event whose
  ///   rule is not known ("Repeating event").
  public func recurrenceDescription(generic: String) -> String {
    if let recurrenceSummary, !recurrenceSummary.isEmpty { return recurrenceSummary }
    guard let rule = TaskRecurrenceRule.bridgeRule(from: recurrenceRule, requiringKnownFields: true)
    else { return generic }
    let sourceDay = !allDay && projection != nil
      ? CalendarEventTiming(event: self, fallbackDay: .distantPast).storing(for: self).startDate
      : startDate
    return rule.localizedDisplaySummary(
      anchorDay: LorvexDateFormatters.ymdUTC.date(from: sourceDay))
  }

  /// Names the recurrence clock when it differs from the displayed one, so a
  /// source Monday shown on Tuesday does not appear to contradict its rule.
  /// All-day and floating events have no separate recurrence zone to explain.
  public var recurrenceTimeZoneNote: String? {
    guard hasRecurrenceRow, !allDay,
      timezone.flatMap(TimeZone.init(identifier:)) != nil,
      let displayZone = projection.flatMap({ TimeZone(identifier: $0.timezone) })
    else { return nil }
    return CalendarEventTiming(event: self, fallbackDay: .distantPast)
      .storing(for: self).recurrenceTimeZoneNote(comparedTo: displayZone)
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

extension CalendarEventTiming {
  /// A repeat editor's note when its source clock differs from the date/time
  /// controls. Uses the event's seasonal offset, not today's offset.
  public func recurrenceTimeZoneNote(comparedTo displayTimeZone: TimeZone) -> String? {
    guard !allDay, calendar.timeZone != displayTimeZone else { return nil }
    return String(
      localized: "calendar.repeat.time_zone", defaultValue: "Repeats in \(timeZoneSummary)",
      table: "Localizable", bundle: CoreL10n.bundle)
  }
}
