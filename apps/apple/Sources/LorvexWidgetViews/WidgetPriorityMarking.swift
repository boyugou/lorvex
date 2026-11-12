import LorvexCore
import SwiftUI
import WidgetKit

/// How a widget's task circle carries the task's priority.
///
/// In full color a High task's circle is red and the others neutral
/// (``LorvexTask/Priority/priorityTint``). Every other rendering mode drops
/// that color: the Mac desktop renders its widgets desaturated whenever a
/// window is in front, as the tinted iPhone Home Screen and StandBy at night
/// do. There, as with Differentiate Without Color, the circle carries the
/// priority's mark instead (``LorvexTask/Priority/circleGlyph(differentiating:)``),
/// so High still reads as High.
enum WidgetPriorityMarking {
  /// A task with no recorded priority is Normal, as everywhere else.
  static let defaultPriority = LorvexTask.Priority.p2

  static func marksInShape(
    differentiateWithoutColor: Bool, renderingMode: WidgetRenderingMode
  ) -> Bool {
    differentiateWithoutColor || renderingMode != .fullColor
  }

  static func circleGlyph(
    _ priority: LorvexTask.Priority?, differentiateWithoutColor: Bool,
    renderingMode: WidgetRenderingMode
  ) -> String {
    (priority ?? defaultPriority).circleGlyph(
      differentiating: marksInShape(
        differentiateWithoutColor: differentiateWithoutColor, renderingMode: renderingMode))
  }

  static func tint(_ priority: LorvexTask.Priority?) -> Color {
    (priority ?? defaultPriority).priorityTint
  }
}
