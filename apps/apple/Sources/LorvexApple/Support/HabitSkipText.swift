import LorvexCore

/// Copy shared by the Mac habit skip surfaces: the card's context menu, the
/// inspector's chip and menu, the status line on the card and in the
/// inspector, the ring's VoiceOver value, and the history grid's legend and
/// help tags.
enum HabitSkipText {
  /// The command that sets today aside for a habit.
  static var skipToday: String {
    String(
      localized: "habits.row.skip_today", defaultValue: "Skip Today", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  /// The command that takes a skip back.
  static var undoSkip: String {
    String(
      localized: "habits.row.undo_skip", defaultValue: "Undo Skip", table: "Localizable",
      bundle: LorvexL10n.bundle)
  }

  /// The state of a habit set aside for today.
  static var skippedToday: String {
    String(
      localized: "habits.row.skipped_today", defaultValue: "Skipped today", table: "Localizable",
      bundle: LorvexL10n.bundle)
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
