import SwiftUI

/// Shared tint + SF Symbol mapping for a task's priority, parallel to
/// `LorvexTask.Status`'s presentation. Priority is the primary canonical sort
/// key, so every task-row surface color-codes it identically: P1 reads as
/// urgent (red), P2 as elevated (orange), and P3 recedes (secondary). Centralised
/// so macOS, iOS, and iPadOS can't drift.
extension LorvexTask.Priority {
  /// Tint for the priority indicator. P3 uses `.secondary` so low-priority work
  /// stays visually quiet rather than competing with P1/P2.
  public var priorityTint: Color {
    switch self {
    case .p1: LorvexDesign.Palette.priorityHigh
    case .p2: LorvexDesign.Palette.priorityMedium
    case .p3: LorvexDesign.Palette.priorityLow
    }
  }

  /// SF Symbol for a priority indicator dot/flag.
  public var prioritySymbolName: String {
    "flag.fill"
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
