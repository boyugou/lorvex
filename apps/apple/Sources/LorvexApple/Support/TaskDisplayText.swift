import Foundation
import LorvexCore

public enum TaskDisplayText {
  /// The priority as one word ("High", "Normal", "Low"), for a filter item or
  /// a table cell; the storage codes P1–P3 never reach the screen.
  public static func compactPriority(_ priority: LorvexTask.Priority) -> String {
    switch priority {
    case .p1: String(localized: "task_detail.priority_value.high", defaultValue: "High", table: "Localizable", bundle: LorvexL10n.bundle)
    case .p2: String(localized: "task_detail.priority_value.normal", defaultValue: "Normal", table: "Localizable", bundle: LorvexL10n.bundle)
    case .p3: String(localized: "task_detail.priority_value.low", defaultValue: "Low", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  /// The priority as a phrase ("High priority"), for a filter summary or
  /// VoiceOver.
  public static func priority(_ priority: LorvexTask.Priority) -> String {
    switch priority {
    case .p1:
      String(localized: "task_detail.sentence.priority_phrase.high", defaultValue: "High priority", table: "Localizable", bundle: LorvexL10n.bundle)
    case .p2:
      String(localized: "task_detail.sentence.priority_phrase.normal", defaultValue: "Normal priority", table: "Localizable", bundle: LorvexL10n.bundle)
    case .p3:
      String(localized: "task_detail.sentence.priority_phrase.low", defaultValue: "Low priority", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }

  /// The word on the badge of a task whose dependencies are still open.
  public static var blocked: String {
    String(localized: "task.status.blocked", defaultValue: "Blocked", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// What a task's completion circle does: Complete for an open task, Reopen
  /// for a done one. Rows show it as the circle's tooltip and offer it to
  /// VoiceOver as a named action.
  public static func completionToggle(isDone: Bool) -> String {
    isDone
      ? String(localized: "common.reopen", defaultValue: "Reopen", table: "Localizable", bundle: LorvexL10n.bundle)
      : String(localized: "common.complete", defaultValue: "Complete", table: "Localizable", bundle: LorvexL10n.bundle)
  }

  /// "Hidden until Oct 3": the day a task set aside until then comes back
  /// into view, given as a short label.
  public static func hiddenUntil(_ day: String) -> String {
    String(
      format: String(localized: "task.row.hidden_until", defaultValue: "Hidden until %@", table: "Localizable", bundle: LorvexL10n.bundle),
      day)
  }

  public static func status(_ status: LorvexTask.Status) -> String {
    switch status {
    case .open:
      String(localized: "task.status.open", defaultValue: "Open", table: "Localizable", bundle: LorvexL10n.bundle)
    case .inProgress:
      String(localized: "task.status.in_progress", defaultValue: "In Progress", table: "Localizable", bundle: LorvexL10n.bundle)
    case .completed:
      String(localized: "task.status.completed", defaultValue: "Completed", table: "Localizable", bundle: LorvexL10n.bundle)
    case .cancelled:
      String(localized: "task.status.cancelled", defaultValue: "Cancelled", table: "Localizable", bundle: LorvexL10n.bundle)
    case .someday:
      String(localized: "task.status.someday", defaultValue: "Someday", table: "Localizable", bundle: LorvexL10n.bundle)
    }
  }
}
