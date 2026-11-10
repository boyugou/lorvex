import SwiftUI

/// Shared tint + SF Symbol mapping for a task's priority, parallel to
/// `LorvexTask.Status`'s presentation. Priority is the primary canonical sort
/// key, so every task-row surface shows it identically: high priority is red,
/// normal priority (the default) is the neutral ring, and low priority is the
/// same ring, quieter. Centralised so macOS, iOS, and iPadOS can't drift.
extension LorvexTask.Priority {
  /// Tint for the priority indicator. Only high priority takes a hue: a task
  /// at the default priority is neutral, so a colored circle on a row always
  /// says that the task was marked important.
  public var priorityTint: Color {
    switch self {
    case .p1: LorvexDesign.Palette.priorityHigh
    case .p2: LorvexDesign.Palette.priorityNormal
    case .p3: LorvexDesign.Palette.priorityLow
    }
  }

  /// SF Symbol for a priority indicator: the exclamation mark the task
  /// detail gives its Priority field, apart from the flag that marks a due date.
  public var prioritySymbolName: String {
    "exclamationmark.circle.fill"
  }

  /// SF Symbol of an open task's circle. With `differentiating` true (the person
  /// has turned on Differentiate Without Color) a mark inside the ring carries
  /// the priority, so the tint is not its only carrier: an exclamation mark for
  /// P1, an arrow pointing down for P3, and the plain ring for P2, whose mark
  /// would only repeat what normal priority leaves unsaid (VoiceOver does not
  /// read it either). Every symbol is an outlined circle of the same size, so a
  /// column of mixed priorities stays even.
  public func circleGlyph(differentiating: Bool) -> String {
    guard differentiating else { return "circle" }
    switch self {
    case .p1: return "exclamationmark.circle"
    case .p2: return "circle"
    case .p3: return "arrow.down.circle"
    }
  }
}
