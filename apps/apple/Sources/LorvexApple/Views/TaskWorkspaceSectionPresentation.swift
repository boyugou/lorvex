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

  /// Tint for the section header. Both lanes are neutral: the lane glyphs
  /// (`sectionSymbolName`) already distinguish deferred from scheduled, so the
  /// tint does not need to carry a second signal.
  var sectionTint: Color {
    switch self {
    case .deferred: LorvexDesign.Palette.neutral
    case .scheduled: LorvexDesign.Palette.neutral
    default: taskStatus?.statusTint ?? LorvexDesign.Palette.neutral
    }
  }
}
