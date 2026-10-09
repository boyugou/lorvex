import SwiftUI

/// Shared SF Symbol + tint mapping for a task's status, so the icon/color
/// contract lives in one place and macOS, iOS, and iPadOS can't drift when a
/// status is added or a color is tweaked. A status shown on its own (a section
/// header, the table's status column) draws `statusSymbolName` in `statusTint`;
/// a task row's leading circle draws ``LorvexTask/statusCircleGlyph`` in
/// ``LorvexTask/statusCircleStyle``, which also carry the task's priority.
extension LorvexTask.Status {
  /// SF Symbol name for the status indicator.
  ///
  /// `inProgress` shares `open`'s hollow circle: the leading indicator stays a
  /// tap-to-complete affordance regardless of the started marker. The
  /// "in progress" signal is carried by the separate row badge, not by
  /// reshaping the completion circle.
  public var statusSymbolName: String {
    switch self {
    case .open: "circle"
    case .inProgress: "circle"
    case .completed: "checkmark.circle.fill"
    case .cancelled: "xmark.circle"
    case .someday: "tray"
    }
  }

  /// Tint for the status indicator.
  public var statusTint: Color {
    switch self {
    case .open: LorvexDesign.Palette.neutral
    case .inProgress: LorvexDesign.Palette.neutral
    case .completed: LorvexDesign.Palette.done
    case .cancelled: LorvexDesign.Palette.cancelled
    case .someday: LorvexDesign.Palette.someday
    }
  }
}

/// A task row's leading status circle, derived from the task's status and
/// priority. Every task row on macOS, iOS, and iPadOS draws it through
/// ``LorvexTaskStatusCircle``, as do the tappable completion circles and the
/// rows listing the tasks a task waits on, so each shows the same symbol and
/// tint for every state.
extension LorvexTask {
  /// SF Symbol for the leading status circle: a filled check when completed, an
  /// × for cancelled, a moon for someday, a hollow circle for anything still
  /// open. Every state is circle-shaped, so a column of mixed states stays even.
  public var statusCircleGlyph: String {
    switch status {
    case .completed: "checkmark.circle.fill"
    case .cancelled: "xmark.circle"
    case .someday: "moon.circle"
    case .open, .inProgress: "circle"
    }
  }

  /// The leading status circle's glyph, with an open task's priority marked
  /// inside the ring when `differentiatingPriority` is true (the person has
  /// turned on Differentiate Without Color; see
  /// ``LorvexTask/Priority/circleGlyph(differentiating:)``). A completed,
  /// cancelled, or someday task keeps ``statusCircleGlyph`` either way: its
  /// state is already told by its shape, and its priority no longer orders it.
  public func statusCircleGlyph(differentiatingPriority: Bool) -> String {
    guard status.isActionable else { return statusCircleGlyph }
    return priority.circleGlyph(differentiating: differentiatingPriority)
  }

  /// Foreground style for the leading status circle: the done color when
  /// completed, the quiet tertiary gray when cancelled, the someday gray when
  /// parked, otherwise the priority tint.
  ///
  /// The someday gray is the ``LorvexDesign/Palette/someday`` color, not the
  /// hierarchical `.secondary` style: a hierarchical style takes its level from
  /// the tint of the control around the circle, so inside a tappable circle it
  /// would draw accent blue at half strength instead of gray.
  public var statusCircleStyle: AnyShapeStyle {
    switch status {
    case .completed: AnyShapeStyle(LorvexDesign.Palette.done)
    case .cancelled: AnyShapeStyle(.tertiary)
    case .someday: AnyShapeStyle(LorvexDesign.Palette.someday)
    case .open, .inProgress: AnyShapeStyle(priority.priorityTint)
    }
  }
}
