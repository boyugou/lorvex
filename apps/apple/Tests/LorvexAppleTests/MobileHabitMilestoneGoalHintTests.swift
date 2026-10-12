import Testing

@testable import LorvexMobile

/// The milestone-goal hint names the unit the habit's milestone counts, as the
/// Mac's editor does.
@Suite("Mobile milestone goal hint")
struct MobileHabitMilestoneGoalHintTests {
  @Test("A daily habit's goal is a streak in days, a weekday habit's in weeks, the others' a completion count")
  func hintNamesTheUnit() {
    #expect(
      MobileHabitDisplayText.milestoneGoalHint(frequencyType: "daily")
        == "Streak length in days, like 30. The habit keeps going.")
    #expect(
      MobileHabitDisplayText.milestoneGoalHint(frequencyType: "weekly")
        == "Streak length in weeks, like 8. The habit keeps going.")
    for frequencyType in ["times_per_week", "monthly"] {
      #expect(
        MobileHabitDisplayText.milestoneGoalHint(frequencyType: frequencyType)
          == "Total completions, like 50. The habit keeps going.")
    }
  }
}
