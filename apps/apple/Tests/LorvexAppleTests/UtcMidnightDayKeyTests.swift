import Foundation
import Testing

@testable import LorvexCore

@Suite("UTC midnight of a day key")
struct UtcMidnightDayKeyTests {
  @Test("It agrees with the UTC formatter on every day from 1700 to 2300")
  func agreesWithTheFormatter() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    var day = calendar.date(from: DateComponents(year: 1700, month: 1, day: 1))!
    let end = calendar.date(from: DateComponents(year: 2300, month: 1, day: 1))!
    var checked = 0
    while day < end {
      let key = LorvexDateFormatters.ymdUTC.string(from: day)
      #expect(LorvexDateFormatters.utcMidnight(ofDayKey: key) == day, "\(key)")
      day = calendar.date(byAdding: .day, value: 1, to: day)!
      checked += 1
    }
    #expect(checked > 219_000)
  }

  @Test("It rejects what is not a real day written yyyy-MM-dd")
  func rejectsInvalidKeys() {
    for key in [
      "", "2026-1-05", "2026-10-5", "26-10-05", "2026/10/05", "2026-10-05T00", "2026-13-01",
      "2026-00-10", "2026-02-29", "2100-02-29", "2026-04-31", "2026-10-00", "2026-10-32",
      "abcd-ef-gh", "2026-10-0٥", " 2026-10-05", "0000-01-01",
    ] {
      #expect(LorvexDateFormatters.utcMidnight(ofDayKey: key) == nil, "\(key)")
    }
    #expect(LorvexDateFormatters.utcMidnight(ofDayKey: "2024-02-29") != nil)
    #expect(LorvexDateFormatters.utcMidnight(ofDayKey: "2000-02-29") != nil)
  }
}
