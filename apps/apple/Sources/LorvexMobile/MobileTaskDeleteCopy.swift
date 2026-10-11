import Foundation
import LorvexCore

/// The words of a task's permanent delete: the row that starts it and the
/// confirmation that follows.
enum MobileTaskDeleteCopy {
  /// The row at the end of a task's detail.
  static var action: String {
    String(
      localized: "task.permanent_delete.action", defaultValue: "Delete Permanently…",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  /// The question, naming the task.
  static func title(for task: LorvexTask) -> String {
    String(
      format: String(
        localized: "task.permanent_delete.title", defaultValue: "Delete “%@” permanently?",
        table: "Localizable", bundle: MobileL10n.bundle),
      task.title)
  }

  /// What a delete takes with it, and the way to keep the record instead.
  static var message: String {
    String(
      localized: "task.permanent_delete.message",
      defaultValue:
        "This task and all its checklist items, reminders, and links are removed for good. This can’t be undone — use Cancel to keep the record instead.",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  /// The confirm button.
  static var confirm: String {
    String(
      localized: "task.permanent_delete.confirm", defaultValue: "Delete Permanently",
      table: "Localizable", bundle: MobileL10n.bundle)
  }
}
