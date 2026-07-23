import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

@Suite("Habit rhythm strip")
struct HabitRhythmStripTests {
  private func calendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    cal.locale = Locale(identifier: "en_US_POSIX")
    return cal
  }

  private func date(_ string: String) -> Date {
    let parts = string.split(separator: "-").compactMap { Int($0) }
    return calendar().date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
  }

  private func habit(
    frequencyType: String, weekdays: [Int]? = nil, perPeriodTarget: Int? = nil
  ) -> LorvexHabit {
    LorvexHabit(
      id: "h", name: "H", icon: nil, color: nil, cue: nil,
      frequencyType: frequencyType, targetCount: 1, completionsToday: 0,
      totalCompletions: 0, completionRate30d: 0, archived: false,
      weekdays: weekdays, perPeriodTarget: perPeriodTarget, dayOfMonth: nil)
  }

  @Test("Granularity follows the cadence")
  func granularity() {
    #expect(HabitRhythmStrip.granularity(forFrequencyType: "daily") == .day)
    #expect(HabitRhythmStrip.granularity(forFrequencyType: "weekly") == .week)
    #expect(HabitRhythmStrip.granularity(forFrequencyType: "times_per_week") == .week)
    #expect(HabitRhythmStrip.granularity(forFrequencyType: "monthly") == .month)
  }

  @Test("Daily shows 7 day cells with today last and ringed")
  func daily() {
    let cells = HabitRhythmStrip.cells(
      completions: ["2026-06-24", "2026-06-22"], habit: habit(frequencyType: "daily"),
      today: date("2026-06-24"), calendar: calendar())
    #expect(cells.count == 7)
    #expect(cells.last == HabitRhythmStrip.Cell(filled: true, isCurrent: true))
    #expect(cells[cells.count - 3].filled)  // two days ago (06-22)
    #expect(cells.filter(\.isCurrent).count == 1)
  }

  @Test("Weekly buckets into 8 rolling weeks")
  func weekly() {
    // A completion three weeks before today fills a non-current week cell.
    let cells = HabitRhythmStrip.cells(
      completions: ["2026-06-03"],
      habit: habit(frequencyType: "weekly", weekdays: [2]),
      today: date("2026-06-24"), calendar: calendar())
    #expect(cells.count == 8)
    #expect(cells.last?.isCurrent == true)
    #expect(cells.last?.filled == false)  // current week had no completion
    #expect(cells.contains { $0.filled })
  }

  @Test("Weekly cells fill only after the cadence quota is met")
  func weeklyQuota() {
    let habit = habit(frequencyType: "times_per_week", perPeriodTarget: 3)
    let partial = HabitRhythmStrip.cells(
      completions: ["2026-06-22", "2026-06-23"], habit: habit,
      today: date("2026-06-24"), calendar: calendar())
    #expect(partial.last?.filled == false)

    let complete = HabitRhythmStrip.cells(
      completions: ["2026-06-22", "2026-06-23", "2026-06-24"], habit: habit,
      today: date("2026-06-24"), calendar: calendar())
    #expect(complete.last?.filled == true)
  }

  @Test("Weekly cells use Monday based calendar weeks")
  func weeklyCalendarBoundary() {
    let cells = HabitRhythmStrip.cells(
      completions: ["2026-06-21"],
      habit: habit(frequencyType: "weekly", weekdays: [6]),
      today: date("2026-06-24"), calendar: calendar())
    #expect(cells.last?.filled == false, "the prior Sunday is not in the current Monday-first week")
    #expect(cells[cells.count - 2].filled == true)
  }

  @Test("Monthly buckets into 6 calendar months")
  func monthly() {
    let cells = HabitRhythmStrip.cells(
      completions: ["2026-04-10"], habit: habit(frequencyType: "monthly"),
      today: date("2026-06-24"), calendar: calendar())
    #expect(cells.count == 6)
    // April is two months before June → the third-from-last cell is filled.
    #expect(cells[3] == HabitRhythmStrip.Cell(filled: true, isCurrent: false))
    #expect(cells.last == HabitRhythmStrip.Cell(filled: false, isCurrent: true))
  }
}

@Suite("Habit period progress")
struct HabitPeriodProgressTests {
  private func calendar() -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    cal.locale = Locale(identifier: "en_US_POSIX")
    return cal
  }

  private func date(_ string: String) -> Date {
    let parts = string.split(separator: "-").compactMap { Int($0) }
    return calendar().date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
  }

  private func habit(
    freq: String, weekdays: [Int]? = nil, perPeriodTarget: Int? = nil, dayOfMonth: Int? = nil,
    target: Int = 1, today: Int = 0
  ) -> LorvexHabit {
    LorvexHabit(
      id: "h", name: "H", icon: nil, color: nil, cue: nil, frequencyType: freq,
      targetCount: target, completionsToday: today, totalCompletions: 0, completionRate30d: 0,
      archived: false, weekdays: weekdays, perPeriodTarget: perPeriodTarget, dayOfMonth: dayOfMonth)
  }

  // today = 2026-06-24 (Wed); current Mon–Sun week is 2026-06-22…06-28; month June.

  @Test("Daily uses today's count against the per-day target")
  func daily() {
    let value = HabitPeriodProgress.current(
      habit: habit(freq: "daily", target: 8, today: 3), recentCompletions: [],
      today: date("2026-06-24"), calendar: calendar())
    #expect(value == HabitPeriodProgress.Value(completed: 3, required: 8))
    #expect(!value.isComplete)
  }

  @Test("Times-a-week counts this week's completions toward N, not just today")
  func timesPerWeek() {
    let value = HabitPeriodProgress.current(
      habit: habit(freq: "times_per_week", perPeriodTarget: 3),
      recentCompletions: ["2026-06-22", "2026-06-23", "2026-06-15"],  // Mon, Tue this week; one last week
      today: date("2026-06-24"), calendar: calendar())
    #expect(value == HabitPeriodProgress.Value(completed: 2, required: 3))
    #expect(!value.isComplete)
  }

  @Test("Specific weekdays complete only when the whole week's days are done")
  func weeklySpecificDays() {
    let value = HabitPeriodProgress.current(
      habit: habit(freq: "weekly", weekdays: [0, 2, 4]),
      recentCompletions: ["2026-06-22", "2026-06-24", "2026-06-26"],  // Mon, Wed, Fri
      today: date("2026-06-24"), calendar: calendar())
    #expect(value == HabitPeriodProgress.Value(completed: 3, required: 3))
    #expect(value.isComplete)
  }

  @Test("Weekly every-day progress requires all seven met days")
  func weeklyEveryDay() {
    let value = HabitPeriodProgress.current(
      habit: habit(freq: "weekly", weekdays: []),
      recentCompletions: ["2026-06-22"],
      today: date("2026-06-24"), calendar: calendar())
    #expect(value == HabitPeriodProgress.Value(completed: 1, required: 7))
    #expect(!value.isComplete)
  }

  @Test("Monthly is done when this month has a completion, and persists across days")
  func monthly() {
    let done = HabitPeriodProgress.current(
      habit: habit(freq: "monthly", dayOfMonth: 1),
      recentCompletions: ["2026-06-01"],  // earlier this month, not today
      today: date("2026-06-24"), calendar: calendar())
    #expect(done == HabitPeriodProgress.Value(completed: 1, required: 1))
    #expect(done.isComplete)

    let lastMonthOnly = HabitPeriodProgress.current(
      habit: habit(freq: "monthly", dayOfMonth: 1),
      recentCompletions: ["2026-05-10"],
      today: date("2026-06-24"), calendar: calendar())
    #expect(!lastMonthOnly.isComplete)
  }

  @Test("Accumulative (multi-count) non-daily habits track today's count, not days-in-period")
  func accumulativeNonDailyTracksToday() {
    // A weekly/monthly habit whose per-day target is above one accrues within
    // the day, so each check-in must visibly fill the ring. Tracking
    // days-in-period (the single-count behavior) would leave taps with no
    // feedback — the bug where a "21×/day" weekly habit's ring never moved.
    let value = HabitPeriodProgress.current(
      habit: habit(
        freq: "weekly",
        weekdays: [0, 1, 2, 3, 4, 5, 6],
        target: 21, today: 5),
      recentCompletions: ["2026-06-22", "2026-06-23"],
      today: date("2026-06-24"), calendar: calendar())
    #expect(value == HabitPeriodProgress.Value(completed: 5, required: 21))
    #expect(!value.isComplete)

    let met = HabitPeriodProgress.current(
      habit: habit(freq: "weekly", weekdays: [0], target: 3, today: 3),
      recentCompletions: [], today: date("2026-06-24"), calendar: calendar())
    #expect(met == HabitPeriodProgress.Value(completed: 3, required: 3))
    #expect(met.isComplete)
  }
}
