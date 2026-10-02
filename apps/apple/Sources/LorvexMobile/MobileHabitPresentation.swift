import LorvexCore
import SwiftUI

/// Shared "today progress" presentation derived from a habit, used by every
/// mobile habit surface (catalog rows, completion ring, detail panel, milestone
/// celebration). One source of truth so the ring fill, the "N/M today" caption,
/// the complete/reset state, and the tile tint stay in lockstep everywhere.
extension LorvexHabit {
  /// Today's completion fraction, clamped to `0...1`. Zero when the habit has no
  /// positive target.
  var todayProgressValue: Double {
    guard targetCount > 0 else { return 0 }
    return min(1, Double(completionsToday) / Double(targetCount))
  }

  /// Whether today's completions have met or exceeded the target.
  var isCompleteToday: Bool {
    completionsToday >= targetCount
  }

  /// Localized "N/M today" progress caption.
  var todayProgressText: String {
    String(
      localized: "habits.progress_today", defaultValue: "\(completionsToday)/\(targetCount) today",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  /// The habit's tile / ring / icon tint: its identity color
  /// (``LorvexHabitPalette/baseColor(for:)``), the same hue the Mac shows.
  var tileTint: Color {
    LorvexHabitPalette.baseColor(for: self)
  }

  /// The habit's tile / ring symbol: its stored icon when that names a real SF
  /// Symbol, otherwise "repeat".
  var tileSymbol: String {
    LorvexSymbol.name(for: icon, fallback: "repeat")
  }

  /// Whether the milestone strip has a real reading to show — a nonzero
  /// streak / total or a user-set goal. A brand-new habit with a zero streak and
  /// no goal gets no hollow, near-empty bar.
  var showsMilestoneStrip: Bool {
    guard let milestone else { return false }
    return milestone.value > 0 || milestoneTarget != nil
  }
}
