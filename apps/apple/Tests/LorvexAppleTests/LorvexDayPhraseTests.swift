import Foundation
import LorvexCore
import Testing

/// How a stored day reads in a sentence: relative within a day of the logical
/// today, a weekday within the coming week, and a date otherwise.
@Suite("Day phrases")
struct LorvexDayPhraseTests {
  private let locale = Locale(identifier: "en_US")
  /// A Tuesday.
  private let logicalDay = "2026-09-22"

  private func day(_ ymd: String) throws -> Date {
    try #require(LorvexDateFormatters.ymdUTC.date(from: ymd))
  }

  private func phrase(_ ymd: String, _ position: LorvexDayPhrase.Position) throws -> String {
    LorvexDayPhrase.phrase(for: try day(ymd), logicalDay: logicalDay, position: position, locale: locale)
  }

  @Test func aRelativeDayIsCapitalizedOnlyWhereItOpensTheSentence() throws {
    #expect(try phrase("2026-09-21", .leading) == "Yesterday")
    #expect(try phrase("2026-09-21", .inline) == "yesterday")
    #expect(try phrase("2026-09-22", .leading) == "Today")
    #expect(try phrase("2026-09-22", .inline) == "today")
    #expect(try phrase("2026-09-23", .leading) == "Tomorrow")
    #expect(try phrase("2026-09-23", .inline) == "tomorrow")
  }

  @Test func theComingWeekReadsAsWeekdaysAndLaterDaysAsDates() throws {
    #expect(try phrase("2026-09-24", .inline) == "Thursday")
    #expect(try phrase("2026-09-28", .inline) == "Monday")
    // A week out repeats today's weekday, so it takes a date.
    #expect(try phrase("2026-09-29", .inline) == "Sep 29")
    #expect(try phrase("2026-09-20", .inline) == "Sep 20")
  }

  @Test func aDateNamesItsYearOnlyWhenItIsNotThisYear() throws {
    #expect(try phrase("2027-01-04", .inline) == "Jan 4, 2027")
    #expect(try phrase("2025-12-30", .leading) == "Dec 30, 2025")
    let unknownToday = LorvexDayPhrase.phrase(
      for: try day("2026-09-20"), logicalDay: "", position: .inline, locale: locale)
    #expect(unknownToday == "Sep 20, 2026")
  }

  @Test func aDueDayThatIsThePlannedDayIsNotNamedTwice() throws {
    #expect(
      LorvexDayPhrase.due(
        try day("2026-09-22"), plannedDay: try day("2026-09-22"), logicalDay: logicalDay, locale: locale)
        == "the same day")
    #expect(
      LorvexDayPhrase.due(
        try day("2026-09-23"), plannedDay: try day("2026-09-22"), logicalDay: logicalDay, locale: locale)
        == "tomorrow")
    #expect(
      LorvexDayPhrase.due(try day("2026-09-24"), plannedDay: nil, logicalDay: logicalDay, locale: locale)
        == "Thursday")
  }

  @Test func aDeadlinePastBeforeYesterdaySaysHowLateItIs() throws {
    #expect(
      LorvexDayPhrase.due(try day("2026-09-21"), plannedDay: nil, logicalDay: logicalDay, locale: locale)
        == "yesterday")
    #expect(
      LorvexDayPhrase.due(try day("2026-09-20"), plannedDay: nil, logicalDay: logicalDay, locale: locale)
        == "Sep 20 · 2 days late")
    #expect(
      LorvexDayPhrase.due(
        try day("2026-09-15"), plannedDay: try day("2026-09-15"), logicalDay: logicalDay, locale: locale)
        == "the same day · 7 days late")
  }

  @Test func dayOffsetCountsWholeStoredDays() throws {
    #expect(lorvexDayOffset(from: logicalDay, to: try day("2026-09-22")) == 0)
    #expect(lorvexDayOffset(from: logicalDay, to: try day("2026-09-20")) == -2)
    #expect(lorvexDayOffset(from: logicalDay, to: try day("2026-10-02")) == 10)
    #expect(lorvexDayOffset(from: "not a day", to: try day("2026-09-22")) == nil)
  }
}
