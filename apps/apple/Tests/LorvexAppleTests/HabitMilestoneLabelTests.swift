import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

@Test("A zero milestone reading names the absence, on both platforms")
func habitMilestoneZeroReadingNamesTheAbsence() {
  #expect(
    MobileHabitDisplayText.milestoneValueLabel(metric: "streak", value: 0, frequencyType: "daily")
      == "No streak yet")
  #expect(
    MobileHabitDisplayText.milestoneValueLabel(metric: "count", value: 0, frequencyType: "daily")
      == "No completions yet")
  #expect(
    HabitDisplayText.milestoneValueLabel(metric: "streak", value: 0, frequencyType: "weekly")
      == "No streak yet")
  #expect(
    HabitDisplayText.milestoneValueLabel(metric: "count", value: 0, frequencyType: "daily")
      == "No completions yet")
  // A nonzero reading, and a rung, keep the unit phrase.
  #expect(
    MobileHabitDisplayText.milestoneValueLabel(metric: "streak", value: 3, frequencyType: "daily")
      == "3-day streak")
  #expect(
    HabitDisplayText.milestoneValueLabel(metric: "streak", value: 14, frequencyType: "daily")
      == "14-day streak")
}

@Test("A habit row's next milestone carries the reading's unit")
func habitMilestoneNextLabelCarriesTheUnit() {
  #expect(
    MobileHabitDisplayText.milestoneNextLabel(metric: "streak", next: 7, frequencyType: "daily")
      == "Next at 7 days")
  #expect(
    MobileHabitDisplayText.milestoneNextLabel(metric: "streak", next: 1, frequencyType: "daily")
      == "Next at 1 day")
  #expect(
    MobileHabitDisplayText.milestoneNextLabel(metric: "streak", next: 4, frequencyType: "weekly")
      == "Next at 4 weeks")
  #expect(
    MobileHabitDisplayText.milestoneNextLabel(metric: "streak", next: 3, frequencyType: "monthly")
      == "Next at 3 months")
  #expect(
    MobileHabitDisplayText.milestoneNextLabel(metric: "count", next: 50, frequencyType: "daily")
      == "Next at 50 completions")
}
