import Foundation

enum MenuBarStatusCopy {
  /// Count of tasks due today or overdue, for the attention stat pill.
  static func dueText(_ count: Int) -> String {
    String(
      format: String(localized: "menubar.due_count", defaultValue: "%lld due", table: "Localizable", bundle: LorvexL10n.bundle),
      count)
  }
}
