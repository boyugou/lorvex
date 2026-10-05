import Testing

@testable import LorvexApple

@Suite("Inspector property label column")
@MainActor
struct InspectorPropertyMetricsTests {
  @Test("English field names keep the minimum column")
  func englishNamesKeepTheMinimum() {
    let width = InspectorPropertyMetrics.labelWidth(
      fitting: ["Priority", "Due", "Planned", "List", "Duration", "Tags"])
    #expect(width == InspectorPropertyMetrics.minimumLabelWidth)
  }

  @Test("a wider translated name widens the column to fit it")
  func widerNameWidensTheColumn() {
    let width = InspectorPropertyMetrics.labelWidth(fitting: ["Προτεραιότητα", "Λίστα"])
    #expect(width > InspectorPropertyMetrics.minimumLabelWidth)
    #expect(width <= InspectorPropertyMetrics.maximumLabelWidth)
  }

  @Test("a name wider than the maximum is capped so the value keeps its room")
  func overlongNameIsCapped() {
    let width = InspectorPropertyMetrics.labelWidth(
      fitting: [String(repeating: "Wiederholungsregel ", count: 3)])
    #expect(width == InspectorPropertyMetrics.maximumLabelWidth)
  }

  @Test("no labels give the minimum")
  func noLabels() {
    #expect(InspectorPropertyMetrics.labelWidth(fitting: []) == InspectorPropertyMetrics.minimumLabelWidth)
  }
}
