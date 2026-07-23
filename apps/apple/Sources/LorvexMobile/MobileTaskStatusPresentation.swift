import LorvexCore
import SwiftUI

/// The leading status circle's glyph and fill, derived from a task's status —
/// shared by the read-only row content and the tappable completion circle so
/// both draw the same symbol and tint for every state.
extension LorvexTask {
  /// SF Symbol for the leading status circle: a filled check when completed, an
  /// × for cancelled, a moon for someday, a hollow circle for anything still
  /// open.
  var statusCircleGlyph: String {
    switch status {
    case .completed: return "checkmark.circle.fill"
    case .cancelled: return "xmark.circle"
    case .someday: return "moon.circle"
    default: return "circle"
    }
  }

  /// Foreground style for the leading status circle: the done color when
  /// completed, quiet tertiary / secondary for cancelled / someday, otherwise
  /// the priority tint.
  var statusCircleStyle: AnyShapeStyle {
    switch status {
    case .completed: return AnyShapeStyle(LorvexDesign.Palette.done)
    case .cancelled: return AnyShapeStyle(.tertiary)
    case .someday: return AnyShapeStyle(.secondary)
    default: return AnyShapeStyle(priority.priorityTint)
    }
  }
}
