import Testing

@testable import LorvexCore

/// Which habits a day's lists show. The open list drops a weekday-pinned habit
/// on its rest days, a monthly habit before its day of the month or once the
/// month's check-in is in, and a times-per-week habit once the week's quota is
/// met; a check-in made that day always keeps a habit on it. A review counts
/// the habits that were due that day or checked in that day.
@Suite("Habit schedule")
struct HabitScheduleTests {
  /// 2026-04-06 is a Monday; the week runs to Sunday 2026-04-12.
  private static let week = [
    "2026-04-06", "2026-04-07", "2026-04-08", "2026-04-09", "2026-04-10", "2026-04-11",
    "2026-04-12",
  ]

  private func makeHabit(
    _ frequencyType: String, weekdays: [Int]? = nil, perPeriodTarget: Int? = nil,
    dayOfMonth: Int? = nil, completionsToday: Int = 0, periodMetDays: Int = 0
  ) -> LorvexHabit {
    LorvexHabit(
      id: "habit", name: "Habit", icon: nil, color: nil, cue: nil, frequencyType: frequencyType,
      targetCount: 1, completionsToday: completionsToday, totalCompletions: 0,
      completionRate30d: 0, archived: false, weekdays: weekdays, perPeriodTarget: perPeriodTarget,
      dayOfMonth: dayOfMonth, periodMetDays: periodMetDays)
  }

  @Test("a weekly habit pinned to weekdays is due only on them")
  func pinnedWeeklyHabitRestsOnTheOtherDays() {
    let gym = makeHabit("weekly", weekdays: [0, 2, 4])

    #expect(
      Self.week.map { gym.isDue(on: $0) }
        == [true, false, true, false, true, false, false])
  }

  @Test("a daily habit and a weekly habit with no pinned weekdays are due every day")
  func dailyAndUnpinnedWeeklyAreDueEveryDay() {
    let habits = [makeHabit("daily"), makeHabit("weekly"), makeHabit("weekly", weekdays: [])]

    for habit in habits {
      #expect(Self.week.allSatisfy { habit.isDue(on: $0) }, "\(habit.frequencyType)")
    }
  }

  @Test("a monthly habit is due on its day of the month and a times-per-week habit on none")
  func monthlyIsDueOnItsDayAndTimesPerWeekOnNone() {
    let rent = makeHabit("monthly", dayOfMonth: 8)
    let run = makeHabit("times_per_week", perPeriodTarget: 3)

    #expect(
      Self.week.map { rent.isDue(on: $0) }
        == [false, false, true, false, false, false, false])
    #expect(Self.week.allSatisfy { !run.isDue(on: $0) })
  }

  @Test("a monthly habit's day clamps to the month's last day and falls back to the 1st")
  func monthlyDayClampsToTheLastDayOfTheMonth() {
    let bills = makeHabit("monthly", dayOfMonth: 31)
    let unset = makeHabit("monthly")

    #expect(bills.isDue(on: "2026-04-30"))
    #expect(!bills.isDue(on: "2026-04-29"))
    #expect(bills.isDue(on: "2026-02-28"))
    #expect(bills.isDue(on: "2026-01-31"))
    #expect(unset.isDue(on: "2026-04-01"))
    #expect(!unset.isDue(on: "2026-04-02"))
  }

  @Test("a habit that cannot be read, or a day that is not a date, never hides the habit")
  func unreadableInputsNeverHideTheHabit() {
    let unknown = makeHabit("fortnightly")
    let pinned = makeHabit("weekly", weekdays: [1])
    // A weekday outside 0...6 is dropped, which leaves the habit unpinned.
    let outOfRange = makeHabit("weekly", weekdays: [9])

    let cases = [(unknown, "2026-04-07"), (pinned, "not-a-day"), (outOfRange, "2026-04-07")]
    for (habit, day) in cases {
      #expect(habit.isDue(on: day))
      #expect(habit.isListed(on: day))
      #expect(habit.isReviewed(on: day))
    }
  }

  @Test("a check-in made on a rest day keeps the habit on that day's list")
  func restDayCheckInStaysListed() {
    let notCheckedIn = makeHabit("weekly", weekdays: [0])
    let checkedIn = makeHabit("weekly", weekdays: [0], completionsToday: 1)

    #expect(!notCheckedIn.isListed(on: "2026-04-07"))
    #expect(checkedIn.isListed(on: "2026-04-07"))
    #expect(notCheckedIn.isListed(on: "2026-04-06"))
  }

  @Test("a monthly habit is listed from its day until the month has a met day")
  func monthlyHabitIsListedFromItsDayUntilItIsDoneThatMonth() {
    let open = makeHabit("monthly", dayOfMonth: 15)
    let done = makeHabit("monthly", dayOfMonth: 15, periodMetDays: 1)
    let doneToday = makeHabit(
      "monthly", dayOfMonth: 15, completionsToday: 1, periodMetDays: 1)

    #expect(!open.isListed(on: "2026-04-14"))
    #expect(open.isListed(on: "2026-04-15"))
    #expect(open.isListed(on: "2026-04-30"))
    // Done earlier in the month, even before its day: nothing is left to do.
    #expect(!done.isListed(on: "2026-04-14"))
    #expect(!done.isListed(on: "2026-04-16"))
    // The day it is checked in it stays, so it can be undone there.
    #expect(doneToday.isListed(on: "2026-04-16"))
  }

  @Test("a times-per-week habit is listed until the week's quota is met")
  func timesPerWeekHabitIsListedUntilTheQuotaIsMet() {
    func run(met: Int, today: Int = 0) -> LorvexHabit {
      makeHabit("times_per_week", perPeriodTarget: 3, completionsToday: today, periodMetDays: met)
    }

    #expect(run(met: 0).isListed(on: "2026-04-08"))
    #expect(run(met: 2).isListed(on: "2026-04-12"))
    #expect(!run(met: 3).isListed(on: "2026-04-12"))
    // The day the quota is met by a check-in, the habit stays to show it done.
    #expect(run(met: 3, today: 1).isListed(on: "2026-04-12"))
  }

  @Test("a review counts the habits due that day or checked in that day")
  func reviewCountsTheHabitsDueOrCheckedIn() {
    let gym = makeHabit("weekly", weekdays: [0])
    let gymChecked = makeHabit("weekly", weekdays: [0], completionsToday: 1)
    let rent = makeHabit("monthly", dayOfMonth: 15)
    let rentChecked = makeHabit("monthly", dayOfMonth: 15, completionsToday: 1)
    let run = makeHabit("times_per_week", perPeriodTarget: 3)
    let runChecked = makeHabit("times_per_week", perPeriodTarget: 3, completionsToday: 1)

    #expect(makeHabit("daily").isReviewed(on: "2026-04-07"))
    #expect(gym.isReviewed(on: "2026-04-06"))
    #expect(!gym.isReviewed(on: "2026-04-07"))
    #expect(gymChecked.isReviewed(on: "2026-04-07"))
    #expect(rent.isReviewed(on: "2026-04-15"))
    #expect(!rent.isReviewed(on: "2026-04-16"))
    #expect(rentChecked.isReviewed(on: "2026-04-16"))
    #expect(!run.isReviewed(on: "2026-04-07"))
    #expect(runChecked.isReviewed(on: "2026-04-07"))
  }

  @Test("listed(on:) and reviewed(on:) drop the habits that are off and keep the order")
  func filtersKeepTheOrderOfTheHabitsThatAreOn() {
    var water = makeHabit("daily")
    water.id = "water"
    var gym = makeHabit("weekly", weekdays: [0, 2, 4])
    gym.id = "gym"
    var plan = makeHabit("weekly", weekdays: [1])
    plan.id = "plan"
    var stretch = makeHabit("weekly", weekdays: [0], completionsToday: 1)
    stretch.id = "stretch"
    var rent = makeHabit("monthly", dayOfMonth: 7, periodMetDays: 1)
    rent.id = "rent"
    var run = makeHabit("times_per_week", perPeriodTarget: 2)
    run.id = "run"

    let habits = [water, gym, plan, stretch, rent, run]

    // Tuesday the 7th: gym rests, rent is done for the month, run is open.
    #expect(habits.listed(on: "2026-04-07").map(\.id) == ["water", "plan", "stretch", "run"])
    #expect(habits.listed(on: "2026-04-06").map(\.id) == ["water", "gym", "stretch", "run"])
    // The review counts rent on its day and run only when checked in.
    #expect(habits.reviewed(on: "2026-04-07").map(\.id) == ["water", "plan", "stretch", "rent"])
    #expect(habits.reviewed(on: "2026-04-06").map(\.id) == ["water", "gym", "stretch"])
  }
}
