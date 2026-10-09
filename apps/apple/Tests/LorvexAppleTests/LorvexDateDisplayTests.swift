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

  /// A week names its year only once it reaches outside the current one, so a
  /// week of another year never reads as one of this year, and it breaks only
  /// after its dash.
  @Test("A week range omits the current year and names any other")
  func aWeekRangeOmitsTheCurrentYear() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    let now = try day("2026-09-30")
    func label(_ start: String, _ locale: Locale) throws -> String {
      LorvexDateFormatters.weekRange(
        startingOn: try day(start), now: now, calendar: calendar, locale: locale)
    }
    let chinese = Locale(identifier: "zh_Hans")
    let thisYear = try label("2026-09-27", english)
    let acrossNewYear = try label("2026-12-27", english)
    let lastYear = try label("2025-12-14", english)
    let chineseThisYear = try label("2026-09-27", chinese)
    let chineseAcrossNewYear = try label("2026-12-27", chinese)

    #expect(thisYear == "Sep\u{00A0}27\u{202F}–\u{2009}Oct\u{00A0}3")
    #expect(
      acrossNewYear == "Dec\u{00A0}27,\u{00A0}2026\u{202F}–\u{2009}Jan\u{00A0}2,\u{00A0}2027")
    #expect(lastYear.contains("2025"))
    #expect(!chineseThisYear.contains("年"))
    #expect(chineseAcrossNewYear.contains("2027年"))
  }

  @Test("The review window reads as a range of local days, with its years outside this year")
  func theReviewWindowIsARangeOfLocalDays() throws {
    let start = try #require(LorvexDateFormatters.ymd.date(from: "2026-09-22"))
    let end = try #require(LorvexDateFormatters.ymd.date(from: "2026-09-28"))
    let now = try #require(LorvexDateFormatters.ymd.date(from: "2026-09-30"))
    #expect(
      ReviewsWeekRangeFormatter.format("2026-09-22 - 2026-09-28", now: now)
        == lorvexUnbreakable(
          LorvexDateFormatters.range(
            from: start, to: end, template: "MMMd", timeZone: .autoupdatingCurrent)))
    #expect(ReviewsWeekRangeFormatter.format("2025-12-22 - 2025-12-28", now: now).contains("2025"))
    #expect(ReviewsWeekRangeFormatter.format("this week", now: now) == "this week")
  }

  @Test("Relative days use the language's own words")
  func relativeDaysNameTheDay() {
    #expect(LorvexDateFormatters.relativeDays(0, locale: english) == "today")
    #expect(LorvexDateFormatters.relativeDays(1, locale: english) == "tomorrow")
    #expect(LorvexDateFormatters.relativeDays(-3, locale: english) == "3 days ago")
  }

  @Test("The abbreviated relative style never reads as a bare signed number")
  func abbreviatedRelativeDaysKeepTheirPhrase() throws {
    // French, Russian, and Romanian abbreviate "45 days ago" to "-45 j",
    // "-45 дн", and "-45 zile", which reads as arithmetic; their short style
    // keeps the whole phrase, so that is what is shown.
    for identifier in ["fr_FR", "ru_RU", "ro_RO"] {
      let locale = Locale(identifier: identifier)
      let phrase = LorvexDateFormatters.relativeDays(-45, unitsStyle: .abbreviated, locale: locale)
      #expect(phrase == LorvexDateFormatters.relativeDays(-45, unitsStyle: .short, locale: locale), "\(identifier)")
      let first = try #require(phrase.first)
      #expect(!"-\u{2212}+".contains(first), "\(identifier) starts with a sign")
    }
    // A language whose abbreviated style is already a phrase keeps it.
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = english
    formatter.unitsStyle = .abbreviated
    formatter.dateTimeStyle = .named
    #expect(
      LorvexDateFormatters.relativeDays(-3, unitsStyle: .abbreviated, locale: english)
        == formatter.localizedString(from: DateComponents(day: -3)))
  }

  @Test("Malay keeps \"yesterday\" whole where its abbreviated style would cut the word")
  func malayAbbreviatedStyleKeepsYesterday() {
    let malay = Locale(identifier: "ms_MY")
    let abbreviated = LorvexDateFormatters.relativeDays(-1, unitsStyle: .abbreviated, locale: malay)
    #expect(abbreviated == "semalam")
    #expect(abbreviated == LorvexDateFormatters.relativeDays(-1, unitsStyle: .short, locale: malay))
  }

  @Test("A relative phrase starts in lowercase, which Vietnamese's capitalized day words would not")
  func relativePhrasesStartInLowercase() {
    let vietnamese = Locale(identifier: "vi_VN")
    let styles: [RelativeDateTimeFormatter.UnitsStyle] = [.full, .short, .abbreviated]
    for days in -2...2 {
      for style in styles {
        let phrase = LorvexDateFormatters.relativeDays(days, unitsStyle: style, locale: vietnamese)
        #expect(phrase.first?.isLowercase == true, "\(days) days, style \(style.rawValue): \(phrase)")
      }
    }
    #expect(LorvexDateFormatters.relativeDays(-1, locale: vietnamese) == "hôm qua")
    #expect(LorvexDateFormatters.relativeDays(2, unitsStyle: .abbreviated, locale: vietnamese) == "ngày kia")
    // A phrase that is already lowercase, and one that opens with a count, is unchanged.
    #expect(LorvexDateFormatters.relativeDays(-3, locale: vietnamese) == "3 ngày trước")
    #expect(LorvexDateFormatters.relativeDays(1, locale: english) == "tomorrow")
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
