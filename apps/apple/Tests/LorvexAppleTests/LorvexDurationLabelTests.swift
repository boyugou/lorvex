import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// `lorvexHabitStreakLabel` must label each cadence's streak in its own unit:
/// days for daily, weeks for weekly / times_per_week / custom, months for
/// monthly. The streak *count* is already computed per cadence by the core, so a
/// `times_per_week` "3" means three weeks and must render in the weeks unit.
@Suite("Habit streak duration label")
struct LorvexDurationLabelTests {
  /// A `times_per_week` streak is counted in weeks by the core, so its label
  /// must match the `weekly` (weeks) form rather than falling through to the
  /// daily day-count form.
  @Test
  func timesPerWeekStreakReadsInWeeksNotDays() {
    let weekly = lorvexHabitStreakLabel(3, frequencyType: "weekly")
    let timesPerWeek = lorvexHabitStreakLabel(3, frequencyType: "times_per_week")
    let daily = lorvexHabitStreakLabel(3, frequencyType: "daily")

    #expect(timesPerWeek == weekly)
    #expect(timesPerWeek != daily)
  }

  /// The label spells the unit out rather than abbreviating it.
  @Test
  func spellsTheUnitOut() {
    #expect(lorvexHabitStreakLabel(12, frequencyType: "daily").contains("12"))
    #expect(lorvexHabitStreakLabel(12, frequencyType: "daily") != "12d")
  }

  /// One period reads in the singular, any other count in the plural.
  @Test
  func pluralizesByCount() {
    #expect(lorvexHabitStreakLabel(1, frequencyType: "daily") == "1 day")
    #expect(lorvexHabitStreakLabel(12, frequencyType: "daily") == "12 days")
    #expect(lorvexHabitStreakLabel(3, frequencyType: "weekly") == "3 weeks")
    #expect(lorvexHabitStreakLabel(1, frequencyType: "monthly") == "1 month")
  }
}
