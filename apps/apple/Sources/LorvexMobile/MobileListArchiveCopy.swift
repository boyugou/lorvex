import Foundation

/// The words the Lists screen and a list's own screen use for archiving a list
/// and restoring it.
enum MobileListArchiveCopy {
  /// The swipe action and context-menu item on a list row.
  static var archive: String {
    String(localized: "lists.row.archive", defaultValue: "Archive", table: "Localizable", bundle: MobileL10n.bundle)
  }

  /// The item in a list's own List Actions menu.
  static var archiveList: String {
    String(
      localized: "list_detail.archive_list", defaultValue: "Archive List", table: "Localizable",
      bundle: MobileL10n.bundle)
  }

  /// The button that returns an archived list to the active lists.
  static var restore: String {
    String(localized: "lists.row.restore", defaultValue: "Restore", table: "Localizable", bundle: MobileL10n.bundle)
  }

  /// The header of the section that holds the archived lists.
  static var sectionTitle: String {
    String(
      localized: "lists.archived.section", defaultValue: "Archived", table: "Localizable",
      bundle: MobileL10n.bundle)
  }
}
