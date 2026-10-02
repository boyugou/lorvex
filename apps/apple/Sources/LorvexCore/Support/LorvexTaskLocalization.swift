import Foundation

extension LorvexTask.Status {
  /// The status as the interface names it ("Open", "In Progress",
  /// "Completed", "Cancelled", "Someday"), in the app's language. The storage
  /// values (`in_progress`) never reach the screen.
  public var localizedName: String {
    switch self {
    case .open:
      String(localized: "task.status.open", defaultValue: "Open", table: "Localizable", bundle: CoreL10n.bundle)
    case .inProgress:
      String(
        localized: "task.status.in_progress", defaultValue: "In Progress", table: "Localizable",
        bundle: CoreL10n.bundle)
    case .completed:
      String(
        localized: "task.status.completed", defaultValue: "Completed", table: "Localizable", bundle: CoreL10n.bundle)
    case .cancelled:
      String(
        localized: "task.status.cancelled", defaultValue: "Cancelled", table: "Localizable", bundle: CoreL10n.bundle)
    case .someday:
      String(localized: "task.status.someday", defaultValue: "Someday", table: "Localizable", bundle: CoreL10n.bundle)
    }
  }
}

extension LorvexTask.Priority {
  /// The priority as one word ("High", "Normal", "Low"): a field's value, a
  /// menu choice, a table cell. The storage codes P1–P3 never reach the screen.
  public var localizedName: String {
    switch self {
    case .p1:
      String(
        localized: "task_detail.priority_value.high", defaultValue: "High", table: "Localizable",
        bundle: CoreL10n.bundle)
    case .p2:
      String(
        localized: "task_detail.priority_value.normal", defaultValue: "Normal", table: "Localizable",
        bundle: CoreL10n.bundle)
    case .p3:
      String(
        localized: "task_detail.priority_value.low", defaultValue: "Low", table: "Localizable",
        bundle: CoreL10n.bundle)
    }
  }

  /// The priority as a phrase that stands on its own ("High priority"): a
  /// capture preview's word, a filter summary, a fact VoiceOver reads.
  public var localizedPhrase: String {
    switch self {
    case .p1:
      String(
        localized: "task_detail.sentence.priority_phrase.high", defaultValue: "High priority",
        table: "Localizable", bundle: CoreL10n.bundle)
    case .p2:
      String(
        localized: "task_detail.sentence.priority_phrase.normal", defaultValue: "Normal priority",
        table: "Localizable", bundle: CoreL10n.bundle)
    case .p3:
      String(
        localized: "task_detail.sentence.priority_phrase.low", defaultValue: "Low priority",
        table: "Localizable", bundle: CoreL10n.bundle)
    }
  }
}
