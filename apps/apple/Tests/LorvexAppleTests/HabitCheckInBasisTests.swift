import LorvexCore
import Testing

/// `LorvexHabitCheckIn` on its two bases: the day a check-in is made on (a day's
/// list of open habits) and the habit's period (the Habits screens). They agree
/// except for a habit kept once a week or a month whose period earlier days
/// already met.
@Suite("Habit check-in basis")
struct HabitCheckInBasisTests {
  private static func habit(
    freq: String = "daily", weekdays: [Int]? = nil, perPeriodTarget: Int? = nil, target: Int = 1,
    today: Int = 0, met: Int = 0, excused: Int = 0, isSkipped: Bool = false
  ) -> LorvexHabit {
    LorvexHabit(
      id: "h", name: "H", icon: nil, color: nil, cue: nil, frequencyType: freq,
      targetCount: target, completionsToday: today, totalCompletions: 0, completionRate30d: 0,
      archived: false, weekdays: weekdays, perPeriodTarget: perPeriodTarget,
      periodMetDays: met, periodExcusedDays: excused, isSkipped: isSkipped)
  }

  private static let none = LorvexHabitCheckIn.none

  @Test("The day basis is the default and ignores the period")
  func dayBasisIgnoresThePeriod() {
    let met = Self.habit(freq: "times_per_week", perPeriodTarget: 2, met: 2)
    #expect(LorvexHabitCheckIn.action(for: met) == .complete)
    #expect(LorvexHabitCheckIn.action(for: met, basis: .day) == .complete)
  }

  @Test("A habit kept once a week is checked in until earlier days meet the week, then left alone")
  func timesPerWeekPeriodBasis() {
    #expect(LorvexHabitCheckIn.action(for: Self.habit(freq: "times_per_week", perPeriodTarget: 3, met: 1), basis: .period) == .complete)
    #expect(LorvexHabitCheckIn.action(for: Self.habit(freq: "times_per_week", perPeriodTarget: 3, met: 3), basis: .period) == Self.none)
  }

  @Test("A check-in made today is cleared by the next one, whether or not it met the week")
  func todaysCheckInIsCleared() {
    let unmet = Self.habit(freq: "times_per_week", perPeriodTarget: 3, today: 1, met: 1)
    let met = Self.habit(freq: "times_per_week", perPeriodTarget: 3, today: 1, met: 3)
    #expect(LorvexHabitCheckIn.action(for: unmet, basis: .period) == .uncomplete)
    #expect(LorvexHabitCheckIn.action(for: met, basis: .period) == .uncomplete)
  }

  @Test("A monthly habit met earlier this month has nothing to check in")
  func monthlyPeriodBasis() {
    let open = Self.habit(freq: "monthly")
    let done = Self.habit(freq: "monthly", met: 1)
    let doneToday = Self.habit(freq: "monthly", today: 1, met: 1)
    #expect(LorvexHabitCheckIn.action(for: open, basis: .period) == .complete)
    #expect(LorvexHabitCheckIn.action(for: done, basis: .period) == Self.none)
    #expect(LorvexHabitCheckIn.action(for: doneToday, basis: .period) == .uncomplete)
  }

  @Test("A weekly habit pinned to weekdays is met at the requirement the week's skips leave")
  func weeklyPeriodBasis() {
    let open = Self.habit(freq: "weekly", weekdays: [0, 2, 4], met: 1)
    let metBySkip = Self.habit(freq: "weekly", weekdays: [0, 2, 4], met: 2, excused: 1)
    #expect(LorvexHabitCheckIn.action(for: open, basis: .period) == .complete)
    #expect(LorvexHabitCheckIn.action(for: metBySkip, basis: .period) == Self.none)
  }

  @Test("A habit counted several times a day adds one until the day is met, on both bases")
  func multiCountIsTheSameOnBothBases() {
    for basis in [LorvexHabitCheckIn.Basis.day, .period] {
      #expect(LorvexHabitCheckIn.action(for: Self.habit(freq: "weekly", weekdays: [0], target: 3, today: 1), basis: basis) == .addOne)
      #expect(LorvexHabitCheckIn.action(for: Self.habit(freq: "weekly", weekdays: [0], target: 3, today: 3), basis: basis) == Self.none)
    }
  }

  @Test("A day set aside is checked in, which lifts the skip")
  func skippedDayChecksIn() {
    let skipped = Self.habit(freq: "times_per_week", perPeriodTarget: 3, met: 1, isSkipped: true)
    #expect(LorvexHabitCheckIn.action(for: skipped, basis: .period) == .complete)
  }
}
