import XCTest

@testable import LorvexDomain

/// Excused days — days the user deliberately set a habit aside — in the streak
/// and due-occurrence math. An excused day never lengthens a streak, never ends
/// one, and is not counted as missed; it cannot make up for a day that was
/// simply not done.
final class HabitExcusedDayTests: XCTestCase {
  private func d(_ s: String) -> LorvexDate {
    guard case let .success(ymd) = IsoDate.parseIsoDate(s) else {
      XCTFail("invalid test date: \(s)")
      return LorvexDate(ymd: IsoDate.YMD(year: 1970, month: 1, day: 1))
    }
    return LorvexDate(ymd: ymd)
  }

  private func days(_ values: [String]) -> [LorvexDate] { values.map(d) }

  private func current(
    _ met: [String], today: String, _ frequency: HabitStreakFrequency, required: Int64 = 1,
    excused: [String] = []
  ) -> Int64 {
    computeHabitCurrentStreak(
      dates: days(met), today: d(today), frequency: frequency, targetCount: required,
      excused: days(excused))
  }

  private func longest(
    _ met: [String], _ frequency: HabitStreakFrequency, required: Int64 = 1,
    excused: [String] = []
  ) -> Int64 {
    computeHabitLongestStreak(
      dates: days(met), frequency: frequency, targetCount: required, excused: days(excused))
  }

  // MARK: Daily

  func testDailyCurrentStreakBridgesAnExcusedDay() {
    let met = ["2026-06-14", "2026-06-15", "2026-06-17"]
    XCTAssertEqual(current(met, today: "2026-06-18", .daily), 1)
    XCTAssertEqual(
      current(met, today: "2026-06-18", .daily, excused: ["2026-06-16"]), 3,
      "the excused day links the days on either side but adds nothing itself")
  }

  func testDailyExcusedDayCannotRescueAMissedDay() {
    let met = ["2026-06-14", "2026-06-17"]
    XCTAssertEqual(
      current(met, today: "2026-06-17", .daily, excused: ["2026-06-15"]), 1,
      "06-16 was missed and is not excused, so the chain stops before it")
  }

  func testDailyStreakStaysAliveWhenTodayIsExcused() {
    let met = ["2026-06-16", "2026-06-17"]
    XCTAssertEqual(current(met, today: "2026-06-18", .daily, excused: ["2026-06-18"]), 2)
  }

  func testDailyStreakStaysAliveAcrossAnExcusedYesterday() {
    XCTAssertEqual(current(["2026-06-16"], today: "2026-06-18", .daily), 0)
    XCTAssertEqual(
      current(["2026-06-16"], today: "2026-06-18", .daily, excused: ["2026-06-17"]), 1,
      "yesterday was excused and today is still open, so the streak is alive")
  }

  func testDailyExcusedDaysAloneNeverCreateAStreak() {
    XCTAssertEqual(current([], today: "2026-06-18", .daily, excused: ["2026-06-17"]), 0)
    XCTAssertEqual(longest([], .daily, excused: ["2026-06-17"]), 0)
  }

  func testDailyLongestStreakBridgesAnExcusedDay() {
    let met = ["2026-06-10", "2026-06-11", "2026-06-13", "2026-06-14"]
    XCTAssertEqual(longest(met, .daily), 2)
    XCTAssertEqual(longest(met, .daily, excused: ["2026-06-12"]), 4)
  }

  func testDailyStreakWithoutExcusedDaysIsUnchanged() {
    let met = ["2026-06-10", "2026-06-11", "2026-06-12", "2026-06-14"]
    XCTAssertEqual(current(met, today: "2026-06-14", .daily), 1)
    XCTAssertEqual(longest(met, .daily), 3)
  }

  // MARK: Weekly

  // 2026-06-15 is a Monday. Week 0 is 06-08...06-14, week 1 is 06-15...06-21 and
  // week 2 is 06-22...06-28. The habit is kept Monday, Wednesday and Friday, so
  // a week needs three met days.
  private let weekZeroMet = ["2026-06-08", "2026-06-10", "2026-06-12"]

  func testWeeklyExcusedDayLowersTheDaysAWeekNeeds() {
    let met = weekZeroMet + ["2026-06-15", "2026-06-19"]
    XCTAssertEqual(current(met, today: "2026-06-20", .weekly, required: 3), 1)
    XCTAssertEqual(
      current(met, today: "2026-06-20", .weekly, required: 3, excused: ["2026-06-17"]), 2)
    XCTAssertEqual(longest(met, .weekly, required: 3), 1)
    XCTAssertEqual(longest(met, .weekly, required: 3, excused: ["2026-06-17"]), 2)
  }

  func testWeeklyFullyExcusedWeekBridgesWithoutAddingToTheStreak() {
    let met = weekZeroMet + ["2026-06-22", "2026-06-24", "2026-06-26"]
    let excused = ["2026-06-15", "2026-06-17", "2026-06-19"]
    XCTAssertEqual(current(met, today: "2026-06-27", .weekly, required: 3), 1)
    XCTAssertEqual(
      current(met, today: "2026-06-27", .weekly, required: 3, excused: excused), 2,
      "the week with every day excused neither counts nor ends the streak")
    XCTAssertEqual(longest(met, .weekly, required: 3, excused: excused), 2)
  }

  func testWeeklyPartiallyExcusedWeekStillEndsTheStreakWhenItsReducedQuotaIsMissed() {
    let met = weekZeroMet + ["2026-06-15", "2026-06-22", "2026-06-24", "2026-06-26"]
    XCTAssertEqual(
      current(met, today: "2026-06-27", .weekly, required: 3, excused: ["2026-06-17"]), 1,
      "week 1 needs two met days and has one")
  }

  func testWeeklyExcusedDaysAloneNeverCreateAStreak() {
    XCTAssertEqual(
      current([], today: "2026-06-20", .weekly, required: 3, excused: ["2026-06-17"]), 0)
    XCTAssertEqual(longest([], .weekly, required: 3, excused: ["2026-06-17"]), 0)
  }

  // MARK: Monthly

  func testMonthlyStreakIgnoresExcusedDays() {
    let met = ["2026-04-10", "2026-05-10", "2026-06-10"]
    let without = current(met, today: "2026-06-18", .monthly)
    XCTAssertGreaterThan(without, 0)
    XCTAssertEqual(current(met, today: "2026-06-18", .monthly, excused: ["2026-05-20"]), without)
    XCTAssertEqual(
      longest(met, .monthly, excused: ["2026-05-20"]), longest(met, .monthly))
  }

  // MARK: Due occurrences

  private func occurrences(
    _ cadence: HabitCadence, target: Int64 = 1, from: String, to: String, excused: [String] = []
  ) -> Double {
    habitScheduledOccurrencesDue(
      cadence, targetCount: target, from: d(from), to: d(to), excused: days(excused))
  }

  func testDailyExcusedDaysAreNotDue() {
    XCTAssertEqual(
      occurrences(.daily, from: "2026-06-15", to: "2026-06-21"), 7, accuracy: 1e-9)
    XCTAssertEqual(
      occurrences(
        .daily, from: "2026-06-15", to: "2026-06-21",
        excused: ["2026-06-16", "2026-06-18"]), 5, accuracy: 1e-9)
    XCTAssertEqual(
      occurrences(
        .daily, target: 2, from: "2026-06-15", to: "2026-06-21",
        excused: ["2026-06-16", "2026-06-18"]), 10, accuracy: 1e-9,
      "each remaining due day still expects the full per-day target")
    XCTAssertEqual(
      occurrences(.daily, from: "2026-06-15", to: "2026-06-21", excused: ["2026-06-30"]), 7,
      accuracy: 1e-9, "an excused day outside the window changes nothing")
  }

  func testWeeklyOnlyScheduledExcusedDaysAreNotDue() {
    let pinned = HabitCadence.weekly(days: [.mon, .wed, .fri])
    XCTAssertEqual(
      occurrences(pinned, from: "2026-06-15", to: "2026-06-21"), 3, accuracy: 1e-9)
    XCTAssertEqual(
      occurrences(pinned, from: "2026-06-15", to: "2026-06-21", excused: ["2026-06-17"]), 2,
      accuracy: 1e-9)
    XCTAssertEqual(
      occurrences(pinned, from: "2026-06-15", to: "2026-06-21", excused: ["2026-06-16"]), 3,
      accuracy: 1e-9, "Tuesday was never due, so excusing it removes nothing")
  }

  func testMonthlyAndTimesPerWeekIgnoreExcusedDays() {
    XCTAssertEqual(
      occurrences(
        .monthly(dayOfMonth: 15), from: "2026-06-01", to: "2026-06-30", excused: ["2026-06-15"]),
      1, accuracy: 1e-9)
    XCTAssertEqual(
      occurrences(
        .timesPerWeek(count: 3), from: "2026-06-15", to: "2026-06-21", excused: ["2026-06-17"]),
      3, accuracy: 1e-9)
  }
}
