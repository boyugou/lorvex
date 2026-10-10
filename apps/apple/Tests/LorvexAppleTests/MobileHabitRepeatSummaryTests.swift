import LorvexCore
import Testing

@testable import LorvexMobile

private func habit(
  frequencyType: String = "daily", targetCount: Int = 1, weekdays: [Int]? = nil,
  perPeriodTarget: Int? = nil, dayOfMonth: Int? = nil
) -> LorvexHabit {
  LorvexHabit(
    id: "habit-test", name: "Test", icon: nil, color: nil, cue: nil,
    frequencyType: frequencyType, targetCount: targetCount, completionsToday: 0,
    totalCompletions: 0, completionRate30d: 0, archived: false, weekdays: weekdays,
    perPeriodTarget: perPeriodTarget, dayOfMonth: dayOfMonth)
}

@Suite("Mobile habit repeat summary")
struct MobileHabitRepeatSummaryTests {
  @Test("A habit's rhythm reads as the facts line names it")
  func repeatSummaryNamesTheRhythm() {
    #expect(MobileHabitDisplayText.repeatSummary(habit()) == "Daily")
    #expect(MobileHabitDisplayText.repeatSummary(habit(targetCount: 6)) == "6 times a day")
    #expect(
      MobileHabitDisplayText.repeatSummary(habit(frequencyType: "times_per_week", perPeriodTarget: 3))
        == "3 times a week")
    #expect(
      MobileHabitDisplayText.repeatSummary(habit(frequencyType: "monthly", dayOfMonth: 15))
        == "Monthly on day 15")
    #expect(MobileHabitDisplayText.repeatSummary(habit(frequencyType: "custom")) == "Custom")
  }

  @Test("A weekly habit names its weekdays, with the daily count after them")
  func repeatSummaryNamesWeekdays() {
    let monWedFri = LorvexRecurrenceWeekdays.summary(["MO", "WE", "FR"])
    #expect(
      MobileHabitDisplayText.repeatSummary(habit(frequencyType: "weekly", weekdays: [4, 0, 2]))
        == monWedFri)
    #expect(
      MobileHabitDisplayText.repeatSummary(
        habit(frequencyType: "weekly", targetCount: 2, weekdays: [0, 2, 4]))
        == "\(monWedFri) · 2 times a day")
  }

  @Test("Every day, or no day, of a weekly habit reads as daily")
  func repeatSummaryReadsAFullOrEmptyWeekAsDaily() {
    #expect(
      MobileHabitDisplayText.repeatSummary(habit(frequencyType: "weekly", weekdays: Array(0...6)))
        == "Daily")
    #expect(
      MobileHabitDisplayText.repeatSummary(habit(frequencyType: "weekly", weekdays: []))
        == "Daily")
    #expect(
      MobileHabitDisplayText.repeatSummary(habit(frequencyType: "weekly", weekdays: nil))
        == "Daily")
    #expect(
      MobileHabitDisplayText.repeatSummary(
        habit(frequencyType: "weekly", targetCount: 3, weekdays: Array(0...6)))
        == "3 times a day")
  }

  @Test("A weekly count falls back to the target when the habit has no per-week target")
  func repeatSummaryFallsBackToTheTarget() {
    #expect(
      MobileHabitDisplayText.repeatSummary(habit(frequencyType: "times_per_week", targetCount: 4))
        == "4 times a week")
    #expect(
      MobileHabitDisplayText.repeatSummary(habit(frequencyType: "monthly")) == "Monthly on day 1")
  }
}
