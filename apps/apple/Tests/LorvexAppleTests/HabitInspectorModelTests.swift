import Foundation
import Testing

@testable import LorvexApple
@testable import LorvexCore

/// Fixed inputs for the habit inspector's models: a UTC Gregorian calendar
/// and a today of Wednesday 2026-09-30.
private enum Fixture {
  static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar
  }

  static var today: Date { day("2026-09-30") }

  static func day(_ string: String) -> Date {
    let parts = string.split(separator: "-").compactMap { Int($0) }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? Date()
  }

  static func string(daysBeforeToday offset: Int) -> String {
    let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  static func habit(
    frequencyType: String = "daily",
    targetCount: Int = 1,
    weekdays: [Int]? = nil,
    perPeriodTarget: Int? = nil,
    dayOfMonth: Int? = nil,
    completionsToday: Int = 0,
    milestone: HabitMilestoneInfo? = nil
  ) -> LorvexHabit {
    LorvexHabit(
      id: "h1", name: "Walk", icon: nil, color: nil, cue: nil, frequencyType: frequencyType,
      targetCount: targetCount, completionsToday: completionsToday, totalCompletions: 0,
      completionRate30d: 0, archived: false, weekdays: weekdays, perPeriodTarget: perPeriodTarget,
      dayOfMonth: dayOfMonth, milestone: milestone)
  }

  static func entry(_ date: String, value: Int = 1) -> HabitCompletionEntry {
    HabitCompletionEntry(
      habitID: "h1", completedDate: date, value: value, note: nil,
      createdAt: "\(date)T00:00:00Z", updatedAt: "\(date)T00:00:00Z")
  }

  static func rhythm(_ habit: LorvexHabit, _ entries: [HabitCompletionEntry]) -> HabitWeekdayRhythm? {
    HabitWeekdayRhythm.make(habit: habit, completions: entries, today: today, calendar: calendar)
  }

  static func policy(_ time: String, enabled: Bool = true) -> HabitReminderPolicy {
    HabitReminderPolicy(
      id: "p-\(time)", habitID: "h1", habitName: "Walk", reminderTime: time, enabled: enabled,
      createdAt: "2026-09-01T00:00:00Z", updatedAt: "2026-09-01T00:00:00Z")
  }
}

@Suite("HabitWeekdayRhythm")
struct HabitWeekdayRhythmTests {
  @Test("A monthly habit, or one planned on a single weekday, has no rhythm")
  func noRhythmWithoutWeekdaysToCompare() {
    #expect(Fixture.rhythm(Fixture.habit(frequencyType: "monthly", dayOfMonth: 15), [Fixture.entry("2026-09-15")]) == nil)
    #expect(Fixture.rhythm(Fixture.habit(frequencyType: "weekly", weekdays: [2]), [Fixture.entry("2026-09-23")]) == nil)
  }

  @Test("A weekly habit plans its chosen days, or every day when none are chosen")
  func scheduledWeekdays() {
    #expect(HabitWeekdayRhythm.scheduledWeekdays(for: Fixture.habit(frequencyType: "weekly", weekdays: [4, 0])) == [0, 4])
    #expect(HabitWeekdayRhythm.scheduledWeekdays(for: Fixture.habit(frequencyType: "weekly", weekdays: [])) == Set(0...6))
    #expect(HabitWeekdayRhythm.scheduledWeekdays(for: Fixture.habit(frequencyType: "times_per_week", perPeriodTarget: 3)) == Set(0...6))
    #expect(HabitWeekdayRhythm.scheduledWeekdays(for: Fixture.habit(frequencyType: "monthly", dayOfMonth: 1)) == nil)
  }

  @Test("A habit without check-ins has an empty window: planned days at zero, the rest without a share")
  func emptyHistory() throws {
    let rhythm = try #require(Fixture.rhythm(Fixture.habit(frequencyType: "weekly", weekdays: [0, 2, 4]), []))
    #expect(rhythm.windowStart == nil)
    #expect(rhythm.windowDays == 0)
    #expect(!rhythm.hasEnoughHistory)
    #expect(rhythm.days.map(\.share) == [0, nil, 0, nil, 0, nil, nil])
    #expect(rhythm.strongestDays.isEmpty)
    #expect(rhythm.weakestDays.isEmpty)
  }

  @Test("Check-ins after today, or without a count, are ignored")
  func ignoresFutureAndEmptyEntries() throws {
    let rhythm = try #require(Fixture.rhythm(
      Fixture.habit(), [Fixture.entry("2026-10-02"), Fixture.entry("2026-09-20", value: 0)]))
    #expect(rhythm.windowStart == nil)
    #expect(rhythm.windowDays == 0)
  }

  @Test("Today counts only once its plan is met")
  func todayCountsOnceMet() throws {
    // 2026-09-23 is the Wednesday a week before today.
    let open = try #require(Fixture.rhythm(Fixture.habit(), [Fixture.entry("2026-09-23")]))
    #expect(open.windowDays == 8)
    #expect(open.days[2].occurrences == 1)
    #expect(open.days[2].share == 1)

    let met = try #require(Fixture.rhythm(
      Fixture.habit(), [Fixture.entry("2026-09-23"), Fixture.entry("2026-09-30")]))
    #expect(met.days[2].occurrences == 2)
    #expect(met.days[2].daysWithCheckIns == 2)
    #expect(met.days[2].share == 1)
  }

  @Test("A day counted several times earns part of a day for part of its count, capped at one")
  func partialCredit() throws {
    let rhythm = try #require(Fixture.rhythm(Fixture.habit(targetCount: 4), [
      Fixture.entry("2026-09-28", value: 2),  // Monday: half a day.
      Fixture.entry("2026-09-29", value: 3),  // Tuesday: two entries summing
      Fixture.entry("2026-09-29", value: 3),  // to six, capped at a full day.
      Fixture.entry("2026-09-30", value: 1),  // Today, under its plan: not yet counted.
    ]))
    #expect(rhythm.days[0].share == 0.5)
    #expect(rhythm.days[0].daysWithCheckIns == 1)
    #expect(rhythm.days[1].share == 1)
    #expect(rhythm.days[2].occurrences == 0)
  }

  @Test("A habit done some times a week earns a full day for any check-in")
  func timesPerWeekCountsAnyCheckIn() throws {
    let habit = Fixture.habit(frequencyType: "times_per_week", targetCount: 3, perPeriodTarget: 3)
    let rhythm = try #require(Fixture.rhythm(habit, [Fixture.entry("2026-09-28")]))
    #expect(rhythm.days[0].share == 1)
  }

  @Test("The window starts at the first check-in, at most twelve weeks back")
  func windowIsCapped() throws {
    let recent = try #require(Fixture.rhythm(Fixture.habit(), [Fixture.entry("2026-09-17")]))
    #expect(recent.windowStart == Fixture.day("2026-09-17"))
    #expect(recent.windowDays == 14)
    #expect(recent.hasEnoughHistory)

    let old = try #require(Fixture.rhythm(Fixture.habit(), [Fixture.entry("2026-01-05")]))
    #expect(old.windowDays == HabitWeekdayRhythm.maximumWindowDays)
    #expect(old.windowStart == Fixture.day("2026-07-09"))
  }

  @Test("The strongest and weakest weekdays, with every weekday tied at an end")
  func strongestAndWeakest() throws {
    // Three weeks from Thursday 2026-09-10: that first Thursday, every
    // Monday, and one Tuesday.
    let rhythm = try #require(Fixture.rhythm(Fixture.habit(), [
      Fixture.entry("2026-09-10"),
      Fixture.entry("2026-09-14"), Fixture.entry("2026-09-15"),
      Fixture.entry("2026-09-21"), Fixture.entry("2026-09-28"),
    ]))
    #expect(rhythm.windowDays == 21)
    #expect(rhythm.days[0].share == 1)
    #expect(rhythm.days[0].occurrences == 3)
    #expect(rhythm.strongestDays == [0])
    // Wednesday, Friday, Saturday, and Sunday tie at zero.
    #expect(rhythm.weakestDays == [2, 4, 5, 6])
  }

  @Test("Weekdays with the same share tie for an end")
  func exactTie() throws {
    // Mondays 3 of 3 and Wednesdays 2 of 2 (today not yet done) tie at the
    // top; Fridays 1 of 2.
    let rhythm = try #require(Fixture.rhythm(
      Fixture.habit(frequencyType: "weekly", weekdays: [0, 2, 4]),
      [
        Fixture.entry("2026-09-14"), Fixture.entry("2026-09-16"), Fixture.entry("2026-09-18"),
        Fixture.entry("2026-09-21"), Fixture.entry("2026-09-23"), Fixture.entry("2026-09-28"),
      ]))
    #expect(rhythm.strongestDays == [0, 2])
    #expect(rhythm.weakestDays == [4])
  }

  @Test("Shares within the tie tolerance of an end tie for it")
  func nearTie() throws {
    // A count of 50 a day: Mondays met, Tuesdays at 49, every other day at 10.
    let entries = (0..<14).map { offset -> HabitCompletionEntry in
      let date = Fixture.string(daysBeforeToday: offset)
      let weekday = HabitWeekdayRhythm.mondayFirstWeekday(of: Fixture.day(date), calendar: Fixture.calendar)
      return Fixture.entry(date, value: weekday == 0 ? 50 : weekday == 1 ? 49 : 10)
    }
    let rhythm = try #require(Fixture.rhythm(Fixture.habit(targetCount: 50), entries))
    #expect(rhythm.strongestDays == [0, 1])
    #expect(rhythm.weakestDays == [2, 3, 4, 5, 6])
  }

  @Test("A habit on chosen weekdays compares only those days")
  func chosenWeekdays() throws {
    let rhythm = try #require(Fixture.rhythm(
      Fixture.habit(frequencyType: "weekly", weekdays: [0, 2, 4]),
      [
        Fixture.entry("2026-09-14"), Fixture.entry("2026-09-16"),
        Fixture.entry("2026-09-21"), Fixture.entry("2026-09-28"),
      ]))
    #expect(rhythm.days.map { $0.share == nil } == [false, true, false, true, false, true, true])
    #expect(rhythm.days[1].occurrences == 0)
    #expect(rhythm.days[0].share == 1)
    // Wednesday: 09-16 of 09-16 and 09-23, with today not yet done.
    #expect(rhythm.days[2].share == 0.5)
    #expect(rhythm.days[4].share == 0)
    #expect(rhythm.strongestDays == [0])
    #expect(rhythm.weakestDays == [4])
  }

  @Test("Shares within a tenth of each other read as an even week")
  func evenWeek() throws {
    let entries = (0..<14).map { Fixture.entry(Fixture.string(daysBeforeToday: $0)) }
    let rhythm = try #require(Fixture.rhythm(Fixture.habit(), entries))
    #expect(rhythm.hasEnoughHistory)
    #expect(rhythm.days.allSatisfy { $0.share == 1 })
    #expect(rhythm.strongestDays.isEmpty)
    #expect(rhythm.weakestDays.isEmpty)
  }

  @Test("Under two weeks of history names no strongest or weakest day")
  func shortWindowNamesNoExtremes() throws {
    let rhythm = try #require(Fixture.rhythm(
      Fixture.habit(), [Fixture.entry("2026-09-21"), Fixture.entry("2026-09-28")]))
    #expect(rhythm.windowDays == 10)
    #expect(!rhythm.hasEnoughHistory)
    #expect(rhythm.strongestDays.isEmpty)
    #expect(rhythm.weakestDays.isEmpty)
  }
}

@Suite("HabitGoalChoices")
struct HabitGoalChoicesTests {
  @Test("A goal counts days for a daily habit, weeks for a weekly one, and completions otherwise")
  func unitFollowsTheMilestoneMetric() {
    #expect(HabitGoalChoices.unit(for: Fixture.habit()) == .days)
    #expect(HabitGoalChoices.unit(for: Fixture.habit(frequencyType: "weekly", weekdays: [0, 2])) == .weeks)
    #expect(HabitGoalChoices.unit(for: Fixture.habit(frequencyType: "times_per_week", perPeriodTarget: 3)) == .completions)
    #expect(HabitGoalChoices.unit(for: Fixture.habit(frequencyType: "monthly", dayOfMonth: 1)) == .completions)
    // The stored milestone's metric wins over the cadence's.
    let counted = Fixture.habit(milestone: HabitMilestoneInfo(
      metric: "count", value: 3, currentMilestone: nil, nextMilestone: 10, progressToNext: 0.3))
    #expect(HabitGoalChoices.unit(for: counted) == .completions)
  }

  @Test("Each unit offers ascending presets, the first being the first goal")
  func presets() {
    for unit in [HabitGoalChoices.Unit.days, .weeks, .completions] {
      let presets = HabitGoalChoices.presets(for: unit)
      #expect(!presets.isEmpty)
      #expect(presets == presets.sorted() && Set(presets).count == presets.count)
      #expect(presets.allSatisfy { (1...HabitGoalChoices.maximum).contains($0) })
      #expect(HabitGoalChoices.firstGoal(for: unit) == presets[0])
    }
  }

  @Test("Stepping snaps to a grid that widens as the goal grows")
  func steppingSnaps() {
    let up: [(Int, Int)] = [
      (1, 2), (9, 10), (10, 15), (12, 15), (49, 50), (50, 60), (66, 70), (199, 200), (200, 250),
      (HabitGoalChoices.maximum, HabitGoalChoices.maximum),
    ]
    for (value, next) in up {
      #expect(HabitGoalChoices.increment(value) == next, "increment(\(value))")
    }
    let down: [(Int, Int)] = [
      (1, 1), (2, 1), (10, 9), (11, 10), (12, 10), (15, 10), (50, 45), (51, 50), (66, 60),
      (200, 190), (201, 200), (250, 200),
    ]
    for (value, previous) in down {
      #expect(HabitGoalChoices.decrement(value) == previous, "decrement(\(value))")
    }
  }

  @Test("A step always moves the goal, and stays between one and the maximum")
  func steppingStaysInRange() {
    for value in 1...2_000 {
      let up = HabitGoalChoices.increment(value)
      let down = HabitGoalChoices.decrement(value)
      #expect(up > value && up <= HabitGoalChoices.maximum)
      #expect(value == 1 ? down == 1 : (down < value && down >= 1))
    }
  }
}

@Suite("HabitRingAction")
struct HabitRingActionTests {
  @Test("A habit counted several times a day adds one until the day is met")
  func multiCount() {
    let habit = Fixture.habit(targetCount: 3, completionsToday: 1)
    #expect(HabitRingAction.action(habit: habit, progress: .init(completed: 1, required: 3)) == .addOne)
    #expect(HabitRingAction.action(habit: habit, progress: .init(completed: 3, required: 3)) == .none)
  }

  @Test("A habit checked in once checks in, clears today's check-in, or does nothing once earlier days met the period")
  func singleCount() {
    #expect(HabitRingAction.action(habit: Fixture.habit(), progress: .init(completed: 0, required: 1)) == .checkIn)
    #expect(
      HabitRingAction.action(habit: Fixture.habit(completionsToday: 1), progress: .init(completed: 1, required: 1))
        == .undoToday)
    let weekly = Fixture.habit(frequencyType: "times_per_week", perPeriodTarget: 2)
    #expect(HabitRingAction.action(habit: weekly, progress: .init(completed: 2, required: 2)) == .none)
  }

  @Test("Each action has its own card identifier")
  func identifiers() {
    let ids = [HabitRingAction.addOne, .checkIn, .undoToday, .none].map(\.cardIdentifier)
    #expect(Set(ids).count == 4)
  }
}

@MainActor
@Suite("HabitHistoryGridLayout")
struct HabitHistoryGridLayoutTests {
  @Test("The grid shows the newest weeks its width fits at the smallest cell, then widens the cells to fill the row")
  func metricsFillTheWidth() {
    // 264pt less the 12pt weekday labels and a 3pt gap leaves 249pt: 19
    // columns of 10pt with 18 gaps of 3pt fit, and widen to 195/19pt.
    let fitted = HabitHistoryGridLayout.metrics(columns: 53, width: 264, labelWidth: 12)
    #expect(fitted.shown == 19)
    #expect(abs(fitted.cell - 195.0 / 19.0) < 0.0001)
    // A few weeks of history grow only to the largest cell.
    let sparse = HabitHistoryGridLayout.metrics(columns: 5, width: 264, labelWidth: 12)
    #expect(sparse.shown == 5)
    #expect(sparse.cell == HabitHistoryGridLayout.maximumCell)
    #expect(HabitHistoryGridLayout.metrics(columns: 0, width: 264, labelWidth: 12).shown == 0)
  }

  @Test("A panel too narrow for one column at the smallest cell still shows the newest week")
  func narrowShowsOneWeek() {
    #expect(HabitHistoryGridLayout.metrics(columns: 53, width: 20, labelWidth: 12).shown == 1)
  }

  @Test("The grid is the month row and seven rows of cells tall")
  func heightFollowsTheCell() {
    // The 14pt month row, a 3pt gap, seven 10pt cells, and six 3pt gaps.
    #expect(HabitHistoryGridLayout.height(cell: 10) == CGFloat(14 + 3 + 70 + 18))
  }
}

@Suite("Habit inspector copy")
struct HabitInspectorCopyTests {
  @Test("The Repeat row reads the habit's rhythm")
  func repeatSummary() {
    #expect(HabitDisplayText.repeatSummary(Fixture.habit()) == "Daily")
    #expect(HabitDisplayText.repeatSummary(Fixture.habit(targetCount: 6)) == "6 times a day")
    #expect(HabitDisplayText.repeatSummary(Fixture.habit(frequencyType: "times_per_week", perPeriodTarget: 3)) == "3 times a week")
    #expect(HabitDisplayText.repeatSummary(Fixture.habit(frequencyType: "monthly", dayOfMonth: 15)) == "Monthly on day 15")
    let monWedFri = LorvexRecurrenceWeekdays.summary(["MO", "WE", "FR"])
    #expect(HabitDisplayText.repeatSummary(Fixture.habit(frequencyType: "weekly", weekdays: [4, 0, 2])) == monWedFri)
    #expect(
      HabitDisplayText.repeatSummary(Fixture.habit(frequencyType: "weekly", targetCount: 2, weekdays: [0, 2, 4]))
        == "\(monWedFri) · 2 times a day")
    // Every day, or no day, reads as daily.
    #expect(HabitDisplayText.repeatSummary(Fixture.habit(frequencyType: "weekly", weekdays: Array(0...6))) == "Daily")
    #expect(HabitDisplayText.repeatSummary(Fixture.habit(frequencyType: "weekly", weekdays: [])) == "Daily")
  }

  @Test("The period's standing reads in the habit's own period")
  func periodLabels() {
    #expect(HabitDisplayText.periodCountLabel(completed: 3, required: 8, period: .day) == "3 of 8 today")
    #expect(HabitDisplayText.periodCountLabel(completed: 1, required: 3, period: .week) == "1 of 3 this week")
    #expect(HabitDisplayText.periodNotYetLabel(.month) == "Not done yet this month")
    #expect(HabitDisplayText.periodDoneLabel(.week) == "Done this week")
  }

  @Test("The Reminder row lists up to three enabled times in order, a count and span beyond that, and Off when all are off")
  func reminderValue() {
    let display = HabitReminderTime.display
    #expect(HabitDetailFieldCopy.reminderValue([]) == nil)
    #expect(HabitDetailFieldCopy.reminderValue([Fixture.policy("08:00", enabled: false)]) == "Off")
    #expect(
      HabitDetailFieldCopy.reminderValue([
        Fixture.policy("21:00"), Fixture.policy("12:00", enabled: false), Fixture.policy("08:00"),
      ]) == "\(display("08:00")) · \(display("21:00"))")
    let many = ["13:00", "07:00", "11:00", "09:00"].map { Fixture.policy($0) }
    #expect(HabitDetailFieldCopy.reminderValue(many) == "4 times, \(display("07:00"))–\(display("13:00"))")
  }

  @Test("The Goal row reads the goal in the habit's milestone unit")
  func goalValue() {
    #expect(HabitDetailFieldCopy.goalValue(30, habit: Fixture.habit()) == "30-day streak")
    #expect(
      HabitDetailFieldCopy.goalValue(8, habit: Fixture.habit(frequencyType: "weekly", weekdays: [0, 3]))
        == "8-week streak")
    #expect(
      HabitDetailFieldCopy.goalValue(50, habit: Fixture.habit(frequencyType: "times_per_week", perPeriodTarget: 3))
        == "50 completions")
    #expect(
      HabitDetailFieldCopy.goalValue(25, habit: Fixture.habit(frequencyType: "monthly", dayOfMonth: 1))
        == "25 completions")
  }
}
