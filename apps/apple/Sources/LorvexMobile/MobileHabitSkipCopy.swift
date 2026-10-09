import Foundation
import LorvexCore

/// Copy shared by the habit skip surfaces: the row and Today menus, the swipe
/// action, the detail page, and the ring's VoiceOver value.
enum MobileHabitSkipCopy {
  /// The command that sets today aside for a habit.
  static var skipToday: String {
    String(
      localized: "habits.skip.today", defaultValue: "Skip Today", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  /// The command that takes a skip back.
  static var undoSkip: String {
    String(
      localized: "habits.skip.undo", defaultValue: "Undo Skip", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  /// The state of a habit set aside for today.
  static var skippedToday: String {
    String(
      localized: "habits.skipped_today", defaultValue: "Skipped today", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  /// The title of the command `action` names.
  static func title(for action: LorvexHabitSkip) -> String {
    switch action {
    case .skip: skipToday
    case .unskip: undoSkip
    }
  }

  /// The SF Symbol of the command `action` names.
  static func systemImage(for action: LorvexHabitSkip) -> String {
    switch action {
    case .skip: "forward"
    case .unskip: LorvexHabitSkip.undoGlyph
    }
  }
}
