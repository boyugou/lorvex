import Foundation
import LorvexDomain

extension CalendarTimeline {
  /// Order timed rows by their real start, within the displayed day. Floating
  /// clocks use the anchor zone only as a sort coordinate; they remain floating
  /// in the returned data. Computing every row's key first avoids a comparator
  /// cycle when floating and projected clocks mix during a repeated hour.
  static func sorted(
    _ items: [CalendarTimelineItem], anchorTimezone: String
  ) throws -> [CalendarTimelineItem] {
    guard let zone = TimeZone(identifier: anchorTimezone) else {
      throw StoreError.validation("invalid anchor timezone: \(anchorTimezone)")
    }
    let keyed = items.map { (item: $0, instant: orderingInstant($0, zone: zone)) }
    return keyed.sorted { lhs, rhs in
      let a = lhs.item
      let b = rhs.item
      if a.startDate != b.startDate { return a.startDate < b.startDate }
      switch (lhs.instant, rhs.instant) {
      case (let a?, let b?) where a != b: return a < b
      case (.some, nil): return true
      case (nil, .some): return false
      default: break
      }
      if !a.title.utf8.elementsEqual(b.title.utf8) {
        return a.title.utf8.lexicographicallyPrecedes(b.title.utf8)
      }
      return a.id.utf8.lexicographicallyPrecedes(b.id.utf8)
    }.map(\.item)
  }

  private static func orderingInstant(_ item: CalendarTimelineItem, zone: TimeZone) -> Date? {
    if let projection = item.projection { return projection.start }
    guard let time = item.startTime else { return nil }
    let day = item.startDate.ymd
    let local = NaiveDateTime(
      year: day.year, month: day.month, day: day.day,
      hour: time.hour, minute: time.minute, second: time.second)
    switch DstResolution.resolveLocalDatetime(timezone: zone, local: local) {
    case .valid(let instant): return instant
    case .ambiguous(let earlier, _): return earlier
    case .skipped(_, let snappedTo): return snappedTo
    }
  }
}
