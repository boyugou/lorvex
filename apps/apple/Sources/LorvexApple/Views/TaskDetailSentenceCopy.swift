import Foundation
import LorvexCore

/// The names of the task detail's fields (each row's label and each dashed
/// addition's), the priority values, and the two phrases quick add's preview
/// shares with the detail ("Due …", "High priority").
enum TaskDetailSentenceCopy {
  static var dueLead: String {
    String(localized: "task_detail.sentence.due_lead", defaultValue: "Due ", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// The priority as a phrase that opens a clause ("High priority").
  static func priorityPhrase(_ priority: LorvexTask.Priority) -> String {
    switch priority {
    case .p1: String(localized: "task_detail.sentence.priority_phrase.high", defaultValue: "High priority", table: "Localizable", bundle: LorvexL10n.bundle)
    case .p2: String(localized: "task_detail.sentence.priority_phrase.normal", defaultValue: "Normal priority", table: "Localizable", bundle: LorvexL10n.bundle)
    case .p3: String(localized: "task_detail.sentence.priority_phrase.low", defaultValue: "Low priority", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  /// The priority as a row value and a menu choice ("High").
  static func priorityValue(_ priority: LorvexTask.Priority) -> String {
    switch priority {
    case .p1: String(localized: "task_detail.priority_value.high", defaultValue: "High", table: "Localizable", bundle: LorvexL10n.bundle)
    case .p2: String(localized: "task_detail.priority_value.normal", defaultValue: "Normal", table: "Localizable", bundle: LorvexL10n.bundle)
    case .p3: String(localized: "task_detail.priority_value.low", defaultValue: "Low", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

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
