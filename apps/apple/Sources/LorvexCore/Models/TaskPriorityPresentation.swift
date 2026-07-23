import SwiftUI

/// Shared tint + SF Symbol mapping for a task's priority, parallel to
/// `LorvexTask.Status`'s presentation. Priority is the primary canonical sort
/// key, so every task-row surface color-codes it identically: P1 reads as
/// urgent (red), P2 as elevated (orange), and P3 recedes (secondary). Centralised
/// so macOS, iOS, iPadOS, and visionOS can't drift.
extension LorvexTask.Priority {
  /// Tint for the priority indicator. P3 uses `.secondary` so low-priority work
  /// stays visually quiet rather than competing with P1/P2.
  public var priorityTint: Color {
    switch self {
    case .p1: .red
    case .p2: .orange
    case .p3: .secondary
    }
  }

  /// SF Symbol for a priority indicator dot/flag.
  public var prioritySymbolName: String {
    "flag.fill"
  }
}
