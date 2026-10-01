import Foundation
import Testing

@testable import LorvexApple

/// A toolbar range writes a shared month once and two different months twice,
/// like the system's own date intervals.
@Test
func monthDayRangeWritesASharedMonthOnce() throws {
  let ymd = DateFormatter()
  ymd.calendar = Calendar(identifier: .gregorian)
  ymd.locale = Locale(identifier: "en_US_POSIX")
  ymd.dateFormat = "yyyy-MM-dd"
  let sep22 = try #require(ymd.date(from: "2026-09-22"))
  let sep28 = try #require(ymd.date(from: "2026-09-28"))
  let sep27 = try #require(ymd.date(from: "2026-09-27"))
  let oct3 = try #require(ymd.date(from: "2026-10-03"))

  let monthName = DateFormatter()
  monthName.setLocalizedDateFormatFromTemplate("MMM")
  let september = monthName.string(from: sep22)
  let october = monthName.string(from: oct3)

  let sameMonth = LorvexMonthDayFormatter.localRange(from: sep22, to: sep28)
  #expect(sameMonth.components(separatedBy: september).count == 2)
  #expect(sameMonth.contains("22") && sameMonth.contains("28"))

  let acrossMonths = LorvexMonthDayFormatter.localRange(from: sep27, to: oct3)
  #expect(acrossMonths.contains(september) && acrossMonths.contains(october))

  #expect(
    ReviewsWeekRangeFormatter.format("2026-09-22 - 2026-09-28") == sameMonth)
}
