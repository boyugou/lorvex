import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// Dates written for people follow the display locale — its region's order,
/// its calendar, and its digits — in the time zone they are shown in, while
/// stored day keys stay Gregorian.
struct LorvexDateDisplayTests {
  private let utc = TimeZone(identifier: "UTC")!
  private let english = Locale(identifier: "en_US")

  private func day(_ key: String) throws -> Date {
    try #require(LorvexDateFormatters.ymdUTC.date(from: key))
  }

  @Test("A date takes its region's order, not just its language's")
  func aDateTakesTheRegionsOrder() throws {
    let date = try day("2026-09-29")
    func medium(_ identifier: String) -> String {
      LorvexDateFormatters.string(
        date, dateStyle: .medium, timeZone: utc, locale: Locale(identifier: identifier))
    }
    #expect(medium("en_US") == "Sep 29, 2026")
    #expect(medium("en_GB") == "29 Sep 2026")
    #expect(medium("zh_Hans_CN") == "2026年9月29日")
  }

  @Test("A date is written in its locale's calendar and digits, as its grid lays it out")
  func aDateIsWrittenInTheLocalesCalendarAndDigits() throws {
    let date = try day("2026-09-29")
    let thai = Locale(identifier: "th_TH")
    #expect(LorvexDateFormatters.string(date, dateStyle: .medium, timeZone: utc, locale: thai).contains("2569"))
    #expect(LorvexDateFormatters.dayNumber(date, timeZone: utc, locale: Locale(identifier: "fa_IR")) == "۷")
    #expect(LorvexDateFormatters.dayNumber(date, timeZone: utc, locale: Locale(identifier: "ar_EG")) == "٢٩")
    #expect(LorvexDateFormatters.dayNumber(date, timeZone: utc, locale: Locale(identifier: "zh_Hans_CN")) == "29")

    let persian = LorvexDateFormatters.displayCalendar(timeZone: utc, locale: Locale(identifier: "fa_IR"))
    #expect(persian.identifier == .persian)
    #expect(persian.component(.day, from: date) == 7)
  }

  @Test("Each pattern keeps its own cached formatter")
  func eachPatternKeepsItsOwnFormatter() throws {
    let date = try day("2026-09-29")
    #expect(LorvexDateFormatters.string(date, dateStyle: .medium, timeZone: utc, locale: english) == "Sep 29, 2026")
    #expect(
      LorvexDateFormatters.string(date, dateStyle: .full, timeZone: utc, locale: english)
        == "Tuesday, September 29, 2026")
    #expect(LorvexDateFormatters.string(date, template: "EEE", timeZone: utc, locale: english) == "Tue")
    #expect(LorvexDateFormatters.string(date, template: "yMMMM", timeZone: utc, locale: english) == "September 2026")
  }

  @Test("A date is written in the zone it is shown in")
  func aDateIsWrittenInTheZoneItIsShownIn() throws {
    // 02:00 UTC on Sep 29 is still Sep 28 in Los Angeles.
    let instant = try #require(ISO8601DateFormatter().date(from: "2026-09-29T02:00:00Z"))
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    #expect(LorvexDateFormatters.dayNumber(instant, timeZone: utc, locale: english) == "29")
    #expect(LorvexDateFormatters.dayNumber(instant, timeZone: losAngeles, locale: english) == "28")
  }

  /// A toolbar range writes a shared month once and two different months
  /// twice, like the system's own date intervals.
  @Test("A range writes a shared month once")
  func aRangeWritesASharedMonthOnce() throws {
    let sameMonth = LorvexDateFormatters.range(
      from: try day("2026-09-22"), to: try day("2026-09-28"), template: "MMMd", timeZone: utc,
      locale: english)
    #expect(sameMonth == "Sep 22\u{2009}\u{2013}\u{2009}28")
    let acrossMonths = LorvexDateFormatters.range(
      from: try day("2026-09-27"), to: try day("2026-10-03"), template: "MMMd", timeZone: utc,
      locale: english)
    #expect(acrossMonths == "Sep 27\u{2009}\u{2013}\u{2009}Oct 3")
  }

  @Test("The review window reads as a range of local days")
  func theReviewWindowIsARangeOfLocalDays() throws {
    let start = try #require(LorvexDateFormatters.ymd.date(from: "2026-09-22"))
    let end = try #require(LorvexDateFormatters.ymd.date(from: "2026-09-28"))
    #expect(
      ReviewsWeekRangeFormatter.format("2026-09-22 - 2026-09-28")
        == LorvexDateFormatters.range(
          from: start, to: end, template: "MMMd", timeZone: .autoupdatingCurrent))
    #expect(ReviewsWeekRangeFormatter.format("this week") == "this week")
  }

  @Test("Relative days use the language's own words")
  func relativeDaysNameTheDay() {
    #expect(LorvexDateFormatters.relativeDays(0, locale: english) == "today")
    #expect(LorvexDateFormatters.relativeDays(1, locale: english) == "tomorrow")
    #expect(LorvexDateFormatters.relativeDays(-3, locale: english) == "3 days ago")
  }

  @Test("A date without its year is one in the logical today's year, as the locale's calendar counts it")
  func theYearIsLeftOutOnlyWithinTheCalendarsYear() throws {
    // March 15, 2027 is Esfand 24, 1405: the Persian year of the logical
    // today (Farvardin 5, 1406) has already turned, so the year is written.
    let persian = Locale(identifier: "fa_IR")
    let lastPersianYear = LorvexDayPhrase.phrase(
      for: try day("2027-03-15"), logicalDay: "2027-03-25", position: .inline, locale: persian)
    #expect(lastPersianYear.contains("۱۴۰۵"))
    let sameYear = LorvexDayPhrase.phrase(
      for: try day("2027-03-15"), logicalDay: "2027-03-25", position: .inline, locale: english)
    #expect(sameYear == "Mar 15")
  }
}
