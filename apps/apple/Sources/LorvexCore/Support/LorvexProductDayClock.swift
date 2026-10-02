import Foundation
import LorvexDomain

/// Where the clock stands in the product day, for the "now" position every
/// Today surface draws.
public enum LorvexProductDayClock {
  /// Minutes since midnight in `timeZone`, the product day's own zone, or nil
  /// when the clock there is not on `logicalDay` (`yyyy-MM-dd`), where a "now"
  /// position would be meaningless. A preview run that pins its clock always
  /// reads the pinned minutes (``LorvexPreviewClock/pinnedMinutes``).
  ///
  /// The day is compared as a proleptic Gregorian key, the key every stored
  /// day uses, whatever calendar the person displays. It comes from the same
  /// calendar components as the minutes rather than from a date formatter,
  /// since a Today surface reads this on every render.
  public static func nowMinutes(on logicalDay: String, in timeZone: TimeZone, at now: Date = Date())
    -> Int?
  {
    if let pinned = LorvexPreviewClock.pinnedMinutes { return pinned }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
    guard let year = parts.year, let month = parts.month, let day = parts.day,
      let hour = parts.hour, let minute = parts.minute,
      IsoDate.YMD(year: year, month: month, day: day).canonicalString == logicalDay
    else { return nil }
    return hour * 60 + minute
  }
}
