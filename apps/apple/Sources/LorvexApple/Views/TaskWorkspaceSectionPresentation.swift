import LorvexCore
import SwiftUI

extension TaskWorkspaceSection {
  /// SF Symbol for the section header. Mirrors the per-status presentation; the
  /// `deferred` lane uses the clock the old deferred status carried, and the
  /// `scheduled` (defer-until / hidden) lane uses the `eye.slash` glyph that
  /// marks hidden-until state across the inspector row, badge, and Snooze menu.
  var sectionSymbolName: String {
    switch self {
    case .deferred: "clock"
    case .scheduled: "eye.slash"
    default: taskStatus?.statusSymbolName ?? "clock"
    }
  }

  /// Tint for the section header. The `deferred` lane keeps the orange the old
  /// deferred status used; the `scheduled` lane reads teal to sit apart from the
  /// deferred orange while staying calm.
  var sectionTint: Color {
    switch self {
    case .deferred: .orange
    case .scheduled: .teal
    default: taskStatus?.statusTint ?? .secondary
    }
  }
}
