import SwiftUI

/// Shared SF Symbol + tint mapping for a task's status, used by every task-row
/// surface across macOS, iOS, iPadOS, and visionOS. Centralised so the
/// icon/color contract lives in one place and the platforms can't drift when a
/// status is added or a color is tweaked.
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
    case .open: .secondary
    case .inProgress: .secondary
    case .completed: .green
    case .cancelled: .red
    case .someday: .secondary
    }
  }
}
