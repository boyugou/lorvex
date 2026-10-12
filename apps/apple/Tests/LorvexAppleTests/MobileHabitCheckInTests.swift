import LorvexCore
import Testing

@testable import LorvexMobile

/// How the Habits screens judge a habit: by its period, as the Mac's cards do,
/// so a habit kept three times a week that met its week reads done on the
/// iPhone too, and offers no check-in that would only over-log the week.
@Suite("Mobile habit check-in")
struct MobileHabitCheckInTests {
  private static func habit(
    freq: String = "daily", perPeriodTarget: Int? = nil, target: Int = 1, today: Int = 0,
    met: Int = 0, isSkipped: Bool = false
  ) -> LorvexHabit {
    LorvexHabit(
      id: "h", name: "Run", icon: nil, color: nil, cue: nil, frequencyType: freq,
      targetCount: target, completionsToday: today, totalCompletions: 0, completionRate30d: 0,
      archived: false, perPeriodTarget: perPeriodTarget, periodMetDays: met, isSkipped: isSkipped)
  }

  @Test("A daily habit offers Complete Today until it is checked in, then Reset Today")
  func dailyHabit() {
    let open = Self.habit()
    let done = Self.habit(today: 1)
    #expect(open.offersCompleteToday && !open.offersResetToday)
    #expect(!done.offersCompleteToday && done.offersResetToday)
    #expect(open.periodProgressValue == 0 && !open.isCompleteForPeriod)
    #expect(done.periodProgressValue == 1 && done.isCompleteForPeriod)
  }

  @Test("A habit kept three times a week reads its week's progress, not today's")
  func timesPerWeekReadsTheWeek() {
    let oneOfThree = Self.habit(freq: "times_per_week", perPeriodTarget: 3, met: 1)
    #expect(abs(oneOfThree.periodProgressValue - 1.0 / 3.0) < 0.0001)
    #expect(!oneOfThree.isCompleteForPeriod)
    #expect(oneOfThree.offersCompleteToday && !oneOfThree.offersResetToday)

    let checkedInToday = Self.habit(freq: "times_per_week", perPeriodTarget: 3, today: 1, met: 1)
    #expect(!checkedInToday.isCompleteForPeriod, "today's check-in is one of the three, not the week")
    #expect(!checkedInToday.offersCompleteToday && checkedInToday.offersResetToday)
  }

  @Test("A habit whose week earlier days met offers no check-in, and reads done")
  func metWeekOffersNothing() {
    let met = Self.habit(freq: "times_per_week", perPeriodTarget: 3, met: 3)
    #expect(met.isCompleteForPeriod)
    #expect(met.periodProgressValue == 1)
    #expect(!met.offersCompleteToday && !met.offersResetToday)
    #expect(!met.isCompleteToday, "judged by today alone it would read open")

    let monthly = Self.habit(freq: "monthly", met: 1)
    #expect(monthly.isCompleteForPeriod && !monthly.offersCompleteToday && !monthly.offersResetToday)
  }

  @Test("A habit counted several times a day adds one until met, and offers a reset while it holds any")
  func multiCountHabit() {
    let partial = Self.habit(target: 3, today: 1)
    #expect(partial.offersCompleteToday && partial.offersResetToday)
    let met = Self.habit(target: 3, today: 3)
    #expect(!met.offersCompleteToday && met.offersResetToday)
    #expect(met.isCompleteForPeriod)
  }

  @Test("The ring speaks the command a tap runs, or the habit's name when a tap does nothing")
  func ringLabel() {
    let habit = Self.habit()
    #expect(MobileHabitCheckInCopy.ringLabel(for: habit, action: .complete) == "Complete Run")
    #expect(MobileHabitCheckInCopy.ringLabel(for: habit, action: .addOne) == "Complete Run")
    #expect(MobileHabitCheckInCopy.ringLabel(for: habit, action: .uncomplete) == "Reset Run")
    #expect(MobileHabitCheckInCopy.ringLabel(for: habit, action: LorvexHabitCheckIn.none) == "Run")
  }

  @Test("On the period basis the ring's value is the period's standing or its count so far")
  func ringValueOnThePeriodBasis() {
    func value(_ habit: LorvexHabit) -> String {
      MobileHabitCheckInCopy.ringValue(for: habit, basis: .period)
    }
    #expect(value(Self.habit(freq: "times_per_week", perPeriodTarget: 3, met: 1)) == "1 of 3 this week")
    #expect(value(Self.habit(freq: "times_per_week", perPeriodTarget: 3, met: 3)) == "Done this week")
    #expect(value(Self.habit(freq: "monthly", met: 1)) == "Done this month")
    #expect(value(Self.habit(freq: "daily", today: 1)) == "Done today")
    #expect(value(Self.habit(target: 3, today: 1)) == "1/3 today")
    #expect(value(Self.habit(freq: "times_per_week", perPeriodTarget: 3, met: 1, isSkipped: true)) == "Skipped today")
  }

  @Test("On the day basis the ring's value stays today's count")
  func ringValueOnTheDayBasis() {
    let met = Self.habit(freq: "times_per_week", perPeriodTarget: 3, met: 3)
    #expect(MobileHabitCheckInCopy.ringValue(for: met, basis: .day) == "0/1 today")
  }

  @Test("The period's done label names the day, the week, or the month")
  func periodDoneLabels() {
    #expect(MobileHabitCheckInCopy.periodDone(.day) == "Done today")
    #expect(MobileHabitCheckInCopy.periodDone(.week) == "Done this week")
    #expect(MobileHabitCheckInCopy.periodDone(.month) == "Done this month")
  }
}
