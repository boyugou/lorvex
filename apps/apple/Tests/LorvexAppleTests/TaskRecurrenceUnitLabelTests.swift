import LorvexCore
import Testing

@testable import LorvexApple

/// The repeat editors read "Every 1 week" and "Every 2 weeks": the interval's
/// unit agrees with its count.
@Suite("Repeat interval unit")
struct TaskRecurrenceUnitLabelTests {
  @Test("An interval of 1 takes the singular unit, any other the plural")
  func agreesWithCount() {
    let weekly = TaskRecurrenceRule.Frequency.weekly
    #expect(weekly.localizedIntervalUnit(count: 1) != weekly.localizedIntervalUnit(count: 2))
    #expect(weekly.localizedIntervalUnit(count: 2) == weekly.localizedIntervalUnit(count: 5))
  }
}
