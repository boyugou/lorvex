import Foundation
import LorvexCore
import Testing

@Suite("Clock and day labels")
struct LorvexClockTimeTests {
  @Test func minutesLabelMatchesTheStoredClockLabel() {
    #expect(lorvexClockTimeLabel(minutes: 13 * 60 + 5) == lorvexClockTimeLabel("13:05"))
    #expect(lorvexClockTimeLabel(minutes: 0) == lorvexClockTimeLabel("00:00"))
  }

  @Test func minutesLabelWrapsOntoTheClock() {
    #expect(lorvexClockTimeLabel(minutes: 1440) == lorvexClockTimeLabel("00:00"))
    #expect(lorvexClockTimeLabel(minutes: -30) == lorvexClockTimeLabel("23:30"))
  }

  @Test func storedSpanReadsLikeTheMinutesSpan() {
    #expect(
      lorvexClockRangeLabel(start: "09:00", end: "09:30")
        == lorvexClockRangeLabel(startMinutes: 9 * 60, endMinutes: 9 * 60 + 30))
    // A span that runs to midnight at the end of the day names both ends.
    #expect(
      lorvexClockRangeLabel(start: "22:00", end: "24:00")
        == lorvexClockRangeLabel(startMinutes: 22 * 60, endMinutes: 1440))
    // Without an end, or with one that adds nothing, the start stands alone.
    for end in [nil, "09:00", "later"] {
      #expect(lorvexClockRangeLabel(start: "09:00", end: end) == lorvexClockTimeLabel("09:00"))
    }
  }

  /// The locale's standard short time, as spans pad their ends: a 24-hour clock
  /// keeps the hour's leading zero, which `Date.FormatStyle`'s `.shortened`
  /// time drops ("9:45"), so a lone time would disagree with a span beside it.
  @Test func clockTimeKeepsTheLeadingZeroOfA24HourClock() throws {
    let nineFortyFive = try #require(
      Calendar(identifier: .gregorian).date(
        from: DateComponents(timeZone: .gmt, year: 2026, month: 9, day: 29, hour: 9, minute: 45)))
    for identifier in ["zh_CN", "de_DE", "en_GB", "fr_FR"] {
      let locale = Locale(identifier: identifier)
      #expect(LorvexDateFormatters.clockTime(nineFortyFive, timeZone: .gmt, locale: locale) == "09:45")
      #expect(
        LorvexDateFormatters.dayAndClockTime(nineFortyFive, timeZone: .gmt, locale: locale)
          .hasSuffix("09:45"))
    }
    let twelveHour = LorvexDateFormatters.clockTime(
      nineFortyFive, timeZone: .gmt, locale: Locale(identifier: "en_US"))
    #expect(twelveHour.hasPrefix("9:45"))
    #expect(twelveHour.hasSuffix("AM"))
  }

  @Test func clockTimeFollowsTheTimeZoneItIsGiven() throws {
    let noonUTC = try #require(
      Calendar(identifier: .gregorian).date(
        from: DateComponents(timeZone: .gmt, year: 2026, month: 9, day: 29, hour: 12)))
    let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
    #expect(
      LorvexDateFormatters.clockTime(noonUTC, timeZone: tokyo, locale: Locale(identifier: "en_GB"))
        == "21:00")
  }

  @Test func dayLineSpellsTheDayWithoutTheYear() {
    let line = lorvexDayLine(logicalDay: "2026-09-22")
    #expect(!line.contains("2026"))
    #expect(line.contains("22"))
    #expect(lorvexDayLine(logicalDay: "not a day") == "not a day")
  }
}
