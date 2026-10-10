import LorvexCore

/// Copy shared by the habit delete confirmations: the detail page, the Habits
/// rows, the archived section, and the batch bar.
enum MobileHabitDeleteCopy {
  /// The question for deleting one habit, naming it.
  static func title(for habit: LorvexHabit) -> String {
    String(
      format: String(
        localized: "habits.row.delete_confirm.title", defaultValue: "Delete habit “%@”?",
        table: "Localizable", bundle: MobileL10n.bundle),
      habit.name)
  }

  /// The question for deleting the selected habits.
  static var batchTitle: String {
    String(
      localized: "habits.batch.delete_confirm.title", defaultValue: "Delete selected habits?",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  /// What a deletion takes with it, under either question.
  static var message: String {
    String(
      localized: "habits.row.delete_confirm.message",
      defaultValue: "This removes its completion history.", table: "Localizable",
      bundle: MobileL10n.bundle)
  }
}
