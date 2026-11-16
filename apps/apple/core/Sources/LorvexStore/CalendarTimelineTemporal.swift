import Foundation
import LorvexDomain

extension CalendarTimeline {

  /// Temporal-semantics classification of a timeline item: how its naive
  /// wall-clock fields should be interpreted before projection into the
  /// anchor timezone.
  enum TemporalSemantics: Equatable {
    case floating
    case utc
    case tzid(String)
  }

  static func temporalSemantics(_ item: CalendarTimelineItem) -> TemporalSemantics {
    if item.allDay || item.startTime == nil {
      return .floating
    }
    switch item.sourceTimeKind {
    case .some("utc"):
      return .utc
    case .some("tzid"):
      if let tzid = item.sourceTzid {
        return .tzid(tzid)
      }
      return .floating
    case .some:
      return .floating
    case .none:
      switch item.timezone {
      case .some("UTC"):
        return .utc
      case .some(let tz) where !tz.isEmpty:
        return .tzid(tz)
      default:
        return .floating
      }
    }
  }

  /// Buffer of extra days to scan on each side of the query window so an
  /// occurrence whose local wall clock crosses midnight under timezone
  /// projection is not dropped.
  static func projectionBufferDays(_ item: CalendarTimelineItem) -> Int64 {
    if item.allDay || item.startTime == nil {
      return 0
    }
    switch temporalSemantics(item) {
    case .floating: return 0
    case .utc, .tzid: return 1
    }
  }

  /// Whether the item's `[start, end]` span overlaps `[from, to]` (all
  /// inclusive).
  static func overlapsItemRange(_ item: CalendarTimelineItem, _ from: RDate, _ to: RDate) -> Bool {
    let start = (try? CalendarRecurrence.parseYmd(item.startDate.asString)) ?? from
    let endStr = item.endDate?.asString ?? item.startDate.asString
    let end = (try? CalendarRecurrence.parseYmd(endStr)) ?? start
    return start <= to && end >= from
  }

  /// Project a timed item from its source temporal semantics into the
  /// `anchorTimezone`, preserving the same UTC instant and re-reading the
  /// wall clock in the anchor zone. All-day / time-less items are returned
  /// unchanged.
  static func projectItemToAnchor(
    _ item: CalendarTimelineItem, _ anchorTimezone: String
  ) throws -> CalendarTimelineItem {
    if item.allDay || item.startTime == nil {
      return item
    }
    let semantics = temporalSemantics(item)
    if semantics == .floating {
      return item
    }

    guard let anchorTz = TimeZone(identifier: anchorTimezone) else {
      throw StoreError.validation(
        "invalid anchor timezone for calendar event \(item.id): \(anchorTimezone)")
    }

    if let projection = item.projection {
      return projectInstants(
        item, start: projection.start, end: projection.end,
        anchorTimezone: anchorTimezone, anchorTz: anchorTz)
    }

    let sourceStartDate = item.timing.startDate
    guard let sourceStartTime = item.timing.startTime else {
      throw StoreError.validation("missing start_time for calendar event \(item.id)")
    }
    let sourceEndDate = item.timing.endDate ?? sourceStartDate
    let sourceEndTime = item.timing.endTime

    let anchorStart = try convertNaiveToAnchor(
      sourceStartDate, sourceStartTime, semantics, anchorTz, item.id)

    var anchorEnd: (LorvexDate, TimeOfDay, Date)? = nil
    if let endTime = sourceEndTime {
      anchorEnd = try convertNaiveToAnchor(sourceEndDate, endTime, semantics, anchorTz, item.id)
    }

    if let end = anchorEnd, end.2 < anchorStart.2 {
      throw StoreError.validation(
        "calendar event end instant is before start for \(item.id)")
    }
    // Source validation is deliberately unchanged. A display projection is
    // ordered by instants, not wall clocks (01:45 EDT → 01:15 EST is valid).
    return projectInstants(
      item, start: anchorStart.2, end: anchorEnd?.2,
      anchorTimezone: anchorTimezone, anchorTz: anchorTz)
  }

  static func projectProviderOccurrence(
    _ template: CalendarTimelineItem, _ occurrence: ProviderOccurrenceInstant,
    _ anchorTimezone: String
  ) throws -> CalendarTimelineItem {
    guard let timing = occurrence.utcTiming, let zone = TimeZone(identifier: anchorTimezone) else {
      throw StoreError.validation("invalid provider occurrence timing for \(template.eventId)")
    }
    var item = template
    item.timing = timing
    item.sourceTimeKind = "utc"
    if item.isRecurring { item.id = "\(item.eventId):occurrence:\(occurrence.date)" }
    return projectInstants(
      item, start: occurrence.start, end: occurrence.end,
      anchorTimezone: anchorTimezone, anchorTz: zone)
  }

  private static func projectInstants(
    _ item: CalendarTimelineItem, start: Date, end: Date?,
    anchorTimezone: String, anchorTz: TimeZone
  ) -> CalendarTimelineItem {
    let first = readWallClock(start, anchorTz)
    let last = end.map { readWallClock($0, anchorTz) }
    var projected = item
    projected.projection = CalendarTimelineProjection(
      timezone: anchorTimezone, start: start, end: end,
      startDate: first.0, startTime: first.1,
      endDate: last.flatMap { $0.0 == first.0 ? nil : $0.0 }, endTime: last?.1)
    return projected
  }

  /// Resolve a naive wall clock to a UTC instant under `semantics`, then
  /// re-read its `(date, time)` in `anchorTz`.
  private static func convertNaiveToAnchor(
    _ date: LorvexDate, _ time: TimeOfDay,
    _ semantics: TemporalSemantics, _ anchorTz: TimeZone, _ eventId: String
  ) throws -> (LorvexDate, TimeOfDay, Date) {
    let naive = NaiveDateTime(
      year: date.ymd.year, month: date.ymd.month, day: date.ymd.day,
      hour: time.hour, minute: time.minute, second: time.second)

    let instant: Date
    switch semantics {
    case .floating:
      instant = try resolveOrThrow(
        naive, anchorTz,
        "invalid floating local datetime for calendar event \(eventId)")
    case .utc:
      instant = utcInstant(naive)
    case .tzid(let tzid):
      guard let sourceTz = TimeZone(identifier: tzid) else {
        throw StoreError.validation(
          "invalid source timezone for calendar event \(eventId): \(tzid)")
      }
      instant = try resolveOrThrow(
        naive, sourceTz,
        "invalid source local datetime for calendar event \(eventId)")
    }

    let wallClock = readWallClock(instant, anchorTz)
    return (wallClock.0, wallClock.1, instant)
  }

  /// Resolve `naive` in `tz`, mapping DST shapes to a single instant:
  /// Valid → the instant, Ambiguous → earlier instant, Skipped →
  /// snapped-forward instant. Never returns nil for a real IANA zone.
  private static func resolveOrThrow(
    _ naive: NaiveDateTime, _ tz: TimeZone, _ message: String
  ) throws -> Date {
    switch DstResolution.resolveLocalDatetime(timezone: tz, local: naive) {
    case .valid(let dt): return dt
    case .ambiguous(let earlier, _): return earlier
    case .skipped(_, let snappedTo): return snappedTo
    }
  }

  /// Interpret `naive` as a UTC wall clock and return the instant.
  private static func utcInstant(_ naive: NaiveDateTime) -> Date {
    let cal = IsoDate.calendar
    var dc = DateComponents()
    dc.year = naive.year
    dc.month = naive.month
    dc.day = naive.day
    dc.hour = naive.hour
    dc.minute = naive.minute
    dc.second = naive.second
    return cal.date(from: dc) ?? Date(timeIntervalSince1970: 0)
  }

  /// Read the `(date, time)` wall clock of `instant` as observed in `tz`.
  /// The components come from a real instant in a real zone, so the canonical
  /// `YYYY-MM-DD` / `HH:MM` renderings always parse.
  private static func readWallClock(_ instant: Date, _ tz: TimeZone) -> (LorvexDate, TimeOfDay) {
    var cal = Calendar(identifier: .gregorian)
    cal.locale = Locale(identifier: "en_US_POSIX")
    cal.timeZone = tz
    let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
    let date = LorvexDate(ymd: IsoDate.YMD(year: c.year!, month: c.month!, day: c.day!))
    let time = (try? TimeOfDay.parse(String(format: "%02d:%02d", c.hour!, c.minute!)).get())!
    return (date, time)
  }
}

extension ValidationError {
  /// Best-effort message extraction for interpolating a typed-timing failure
  /// into a `StoreError.validation` string.
  var messageString: String { "\(self)" }
}
