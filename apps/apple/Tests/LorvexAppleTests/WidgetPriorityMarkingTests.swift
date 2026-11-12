import LorvexCore
import Testing
import WidgetKit

@testable import LorvexWidgetViews

/// A widget's High task must still read as High where the system drops the
/// widget's colors: the Mac desktop whenever a window is in front, the tinted
/// iPhone Home Screen, StandBy at night.
@Suite("Widget priority marking")
struct WidgetPriorityMarkingTests {
  @Test("full color marks priority by color alone; every other mode marks it in shape")
  func shapeMarksPriorityWithoutFullColor() {
    #expect(
      WidgetPriorityMarking.circleGlyph(
        .p1, differentiateWithoutColor: false, renderingMode: .fullColor) == "circle")
    for mode in [WidgetRenderingMode.accented, .vibrant] {
      #expect(
        WidgetPriorityMarking.circleGlyph(
          .p1, differentiateWithoutColor: false, renderingMode: mode)
          == "exclamationmark.circle")
      #expect(
        WidgetPriorityMarking.circleGlyph(
          .p3, differentiateWithoutColor: false, renderingMode: mode) == "arrow.down.circle")
    }
    #expect(
      WidgetPriorityMarking.circleGlyph(
        .p1, differentiateWithoutColor: true, renderingMode: .fullColor)
        == "exclamationmark.circle")
  }

  /// A task with no recorded priority is Normal: its circle carries no Low
  /// mark, and its tint is Normal's.
  @Test("a task without a priority reads as Normal")
  func missingPriorityIsNormal() {
    #expect(
      WidgetPriorityMarking.circleGlyph(
        nil, differentiateWithoutColor: true, renderingMode: .fullColor) == "circle")
    #expect(WidgetPriorityMarking.tint(nil) == LorvexTask.Priority.p2.priorityTint)
  }
}
