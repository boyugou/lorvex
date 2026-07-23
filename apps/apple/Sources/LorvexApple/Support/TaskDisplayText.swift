import Foundation
import LorvexCore

public enum TaskDisplayText {
  public static func compactPriority(_ priority: LorvexTask.Priority) -> String {
    priority.rawValue
  }

  public static func priority(_ priority: LorvexTask.Priority) -> String {
    switch priority {
    case .p1:
      String(localized: "task.priority.p1", defaultValue: "Priority 1", table: "Localizable", bundle: LorvexL10n.bundle)
    case .p2:
      String(localized: "task.priority.p2", defaultValue: "Priority 2", table: "Localizable", bundle: LorvexL10n.bundle)
    case .p3:
      String(localized: "task.priority.p3", defaultValue: "Priority 3", table: "Localizable", bundle: LorvexL10n.bundle)
    }
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

  public static func priorityAndStatus(priority: LorvexTask.Priority, status: LorvexTask.Status) -> String {
    String(
      format: String(localized: "task.metadata.priority_status", defaultValue: "%@ · %@", table: "Localizable", bundle: LorvexL10n.bundle),
      Self.priority(priority),
      Self.status(status)
    )
  }

  public static func compactPriorityAndStatus(priority: LorvexTask.Priority, status: LorvexTask.Status) -> String {
    String(
      format: String(localized: "task.metadata.priority_status", defaultValue: "%@ · %@", table: "Localizable", bundle: LorvexL10n.bundle),
      compactPriority(priority),
      Self.status(status)
    )
  }
}
