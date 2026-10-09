import Testing

@testable import LorvexApple

@Suite("Habit history weekday column")
@MainActor
struct HabitHistoryLabelMetricsTests {
  @Test("one-letter initials keep the minimum column")
  func oneLetterInitialsKeepTheMinimum() {
    let width = HabitHistoryLabelMetrics.width(fitting: ["M", "", "W", "", "F", "", "S"])
    #expect(width == HabitHistoryLabelMetrics.minimumWidth)
  }

  @Test("two-letter Tamil initials widen the column to fit them")
  func twoLetterInitialsWidenTheColumn() {
    let width = HabitHistoryLabelMetrics.width(fitting: ["தி", "", "பு", "", "வெ", "", "ஞா"])
    #expect(width > HabitHistoryLabelMetrics.minimumWidth)
    #expect(width <= HabitHistoryLabelMetrics.maximumWidth)
  }

  @Test("an overlong initial is capped so the weeks keep their room")
  func overlongInitialIsCapped() {
    let width = HabitHistoryLabelMetrics.width(fitting: [String(repeating: "W", count: 8)])
    #expect(width == HabitHistoryLabelMetrics.maximumWidth)
  }

  @Test("no labels give the minimum")
  func noLabels() {
    #expect(HabitHistoryLabelMetrics.width(fitting: []) == HabitHistoryLabelMetrics.minimumWidth)
    #expect(HabitHistoryLabelMetrics.width(fitting: ["", ""]) == HabitHistoryLabelMetrics.minimumWidth)
  }
}
