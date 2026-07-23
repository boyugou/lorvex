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
      case let .some(tz) where !tz.isEmpty:
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

    let sourceStartDate = item.startDate
    guard let sourceStartTime = item.startTime else {
      throw StoreError.validation("missing start_time for calendar event \(item.id)")
    }
    let sourceEndDate = item.endDate ?? sourceStartDate
    let sourceEndTime = item.endTime

    let anchorStart = try convertNaiveToAnchor(
      sourceStartDate, sourceStartTime, semantics, anchorTz, item.id)

    var anchorEnd: (LorvexDate, TimeOfDay)? = nil
    if let endTime = sourceEndTime {
      anchorEnd = try convertNaiveToAnchor(sourceEndDate, endTime, semantics, anchorTz, item.id)
    }

    let projectedTiming = CalendarEventTiming.fromFlatFields(
      startDate: anchorStart.0, startTime: anchorStart.1,
      endDate: anchorEnd?.0, endTime: anchorEnd?.1, allDay: false)
    switch projectedTiming {
    case let .success(t):
      var projected = item
      projected.timing = t
      return projected
    case let .failure(err):
      throw StoreError.validation(
        "projected timing invalid for calendar event \(item.id): \(err.messageString)")
    }
  }

  /// Resolve a naive wall clock to a UTC instant under `semantics`, then
  /// re-read its `(date, time)` in `anchorTz`.
  private static func convertNaiveToAnchor(
    _ date: LorvexDate, _ time: TimeOfDay,
    _ semantics: TemporalSemantics, _ anchorTz: TimeZone, _ eventId: String
  ) throws -> (LorvexDate, TimeOfDay) {
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
    case let .tzid(tzid):
      guard let sourceTz = TimeZone(identifier: tzid) else {
        throw StoreError.validation(
          "invalid source timezone for calendar event \(eventId): \(tzid)")
      }
      instant = try resolveOrThrow(
        naive, sourceTz,
        "invalid source local datetime for calendar event \(eventId)")
    }

    return readWallClock(instant, anchorTz)
  }

  /// Resolve `naive` in `tz`, mapping DST shapes to a single instant:
  /// Valid → the instant, Ambiguous → earlier instant, Skipped →
  /// snapped-forward instant. Never returns nil for a real IANA zone.
  private static func resolveOrThrow(
    _ naive: NaiveDateTime, _ tz: TimeZone, _ message: String
  ) throws -> Date {
    switch DstResolution.resolveLocalDatetime(timezone: tz, local: naive) {
    case let .valid(dt): return dt
    case let .ambiguous(earlier, _): return earlier
    case let .skipped(_, snappedTo): return snappedTo
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
