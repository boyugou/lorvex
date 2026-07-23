import Foundation
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
}
