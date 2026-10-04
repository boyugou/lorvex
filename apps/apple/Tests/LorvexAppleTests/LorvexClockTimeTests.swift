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

  /// A Japanese span joins two single times with a wave dash, since the
  /// Japanese span pattern spells them out ("15時00分～16時30分") where a single
  /// time reads "15:00"; a 12-hour clock names a shared AM or PM once.
  @Test func japaneseSpanReadsLikeTheTimesBesideIt() {
    let japanese = Locale(identifier: "ja_JP")
    #expect(lorvexClockRangeLabel(startMinutes: 15 * 60, endMinutes: 16 * 60 + 30, locale: japanese) == "15:00～16:30")
    #expect(lorvexClockRangeLabel(startMinutes: 22 * 60, endMinutes: 1440, locale: japanese) == "22:00～0:00")
    let twelveHour = LorvexClockFormat.twelveHour.applied(to: japanese)
    #expect(lorvexClockRangeLabel(startMinutes: 15 * 60, endMinutes: 16 * 60 + 30, locale: twelveHour) == "午後3:00～4:30")
    #expect(lorvexClockRangeLabel(startMinutes: 11 * 60, endMinutes: 13 * 60, locale: twelveHour) == "午前11:00～午後1:00")
    // Other languages keep the system's span.
    #expect(
      lorvexClockRangeLabel(startMinutes: 15 * 60, endMinutes: 16 * 60 + 30, locale: Locale(identifier: "en_US"))
        .hasSuffix("PM"))
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

  @Test func shortDayLineKeepsTheWeekdayAndDropsTheYear() {
    let short = lorvexShortDayLine(logicalDay: "2026-09-22")
    #expect(!short.contains("2026"))
    #expect(short.contains("22"))
    #expect(short.count <= lorvexDayLine(logicalDay: "2026-09-22").count)
    #expect(lorvexShortDayLine(logicalDay: "not a day") == "not a day")
  }
}
