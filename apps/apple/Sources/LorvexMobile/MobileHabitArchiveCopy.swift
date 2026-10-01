import Foundation

/// Copy shared by the habit archive surfaces: the row actions, the detail
/// page, and the archived section.
enum MobileHabitArchiveCopy {
  static var archive: String {
    String(localized: "habits.row.archive", defaultValue: "Archive", table: "Localizable", bundle: MobileL10n.bundle)
  }

  static var archiveHabit: String {
    String(
      localized: "habits.detail.archive_habit", defaultValue: "Archive Habit", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  static var restore: String {
    String(localized: "habits.row.restore", defaultValue: "Restore", table: "Localizable", bundle: MobileL10n.bundle)
  }

  static var sectionTitle: String {
    String(
      localized: "habits.archived.section", defaultValue: "Archived", table: "Localizable",
      bundle: MobileL10n.bundle)
  }
}
