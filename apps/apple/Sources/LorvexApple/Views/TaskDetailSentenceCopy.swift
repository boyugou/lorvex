import Foundation
import LorvexCore

/// The names of the task detail's fields: each row's label and each dashed
/// addition's.
enum TaskDetailSentenceCopy {
  static var addWhen: String {
    String(localized: "task_detail.add.when", defaultValue: "When", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static var addLength: String {
    String(localized: "task_detail.add.length", defaultValue: "How long", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static var addDue: String {
    String(localized: "task_detail.add.due", defaultValue: "Due", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static var addList: String {
    String(localized: "task_detail.add.list", defaultValue: "List", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static var addPriority: String {
    String(localized: "task_detail.add.priority", defaultValue: "Priority", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static var addRepeat: String {
    String(localized: "task_detail.add.repeat", defaultValue: "Repeat", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static var addReminder: String {
    String(localized: "task_detail.add.reminder", defaultValue: "Reminder", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static var addTag: String {
    String(localized: "task_detail.add.tag", defaultValue: "Tags", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static var addWaitsOn: String {
    String(localized: "task_detail.add.waits_on", defaultValue: "Waits on", table: "Localizable", bundle: LorvexL10n.bundle)
  }
  static var addHideUntil: String {
    String(localized: "task_detail.add.hide_until", defaultValue: "Hide until", table: "Localizable", bundle: LorvexL10n.bundle)
  }
}
