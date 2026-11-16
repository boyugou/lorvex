import Foundation

/// A real occupied interval on one civil day's 24-hour clock. Offset changes
/// split the interval so a repeated hour is not lost and a skipped hour is not
/// invented. At a transition, the preceding piece ends on its old clock.
public struct CalendarWallClockSegment: Sendable, Equatable {
  public let start: Date
  public let end: Date
  public let startMinutes: Int
  public let endMinutes: Int
  public let secondsFromGMT: Int

  /// Clip before walking transitions: querying a day in a years-long event
  /// must cost no more than querying that day in a short event.
  public static func segments(
    from start: Date, to end: Date, on day: LorvexDate, in zone: TimeZone
  ) -> [Self] {
    guard end > start else { return [] }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let ymd = day.ymd
    guard let midnight = calendar.date(from: DateComponents(year: ymd.year, month: ymd.month, day: ymd.day)),
      calendar.component(.year, from: midnight) == ymd.year,
      calendar.component(.month, from: midnight) == ymd.month,
      calendar.component(.day, from: midnight) == ymd.day,
      let bounds = calendar.dateInterval(of: .day, for: midnight),
      let civilMidnight = IsoDate.calendar.date(from: DateComponents(year: ymd.year, month: ymd.month, day: ymd.day))
    else { return [] }
    var cursor = max(start, bounds.start)
    let upper = min(end, bounds.end)
    var result: [Self] = []
    while cursor < upper {
      let offset = zone.secondsFromGMT(for: cursor)
      let transition = zone.nextDaylightSavingTimeTransition(after: cursor)
      let boundary = min(upper, transition.flatMap { $0 > cursor ? $0 : nil } ?? upper)
      func minute(_ instant: Date) -> Double {
        (instant.timeIntervalSince(civilMidnight) + Double(offset)) / 60
      }
      let first = max(0, min(1440, Int(floor(minute(cursor)))))
      let last = max(0, min(1440, Int(ceil(minute(boundary)))))
      if first < last {
        result.append(Self(start: cursor, end: boundary, startMinutes: first,
          endMinutes: last, secondsFromGMT: offset))
      }
      cursor = boundary
    }
    return result
  }

  /// Whether the same local clock has two readings around a backwards offset
  /// change. This also covers half-hour changes, without assuming a 02:00 cutover.
  public static func isRepeatedClock(_ instant: Date, in zone: TimeZone) -> Bool {
    guard let transition = zone.nextDaylightSavingTimeTransition(after: instant.addingTimeInterval(-172_800))
    else { return false }
    let change = zone.secondsFromGMT(for: transition.addingTimeInterval(-1))
      - zone.secondsFromGMT(for: transition)
    guard change > 0 else { return false }
    let distance = instant.timeIntervalSince(transition)
    return distance >= -Double(change) && distance < Double(change)
  }
}
