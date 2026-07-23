import Foundation
import LorvexCore

public enum MobileTaskDisplayText {
  public static func compactEstimateMinutes(_ minutes: Int) -> String {
    String(
      localized: "task.estimate.compact_minutes", defaultValue: "\(minutes) min",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  public static func compactPriority(_ priority: LorvexTask.Priority) -> String {
    priority.rawValue
  }

  public static func priority(_ priority: LorvexTask.Priority) -> String {
    switch priority {
    case .p1:
      String(
        localized: "task.priority.p1", defaultValue: "Priority 1", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .p2:
      String(
        localized: "task.priority.p2", defaultValue: "Priority 2", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .p3:
      String(
        localized: "task.priority.p3", defaultValue: "Priority 3", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }

  public static func status(_ status: LorvexTask.Status) -> String {
    switch status {
    case .open:
      String(
        localized: "task.status.open", defaultValue: "Open", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .inProgress:
      String(
        localized: "task.status.in_progress", defaultValue: "In Progress", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .completed:
      String(
        localized: "task.status.completed", defaultValue: "Completed", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .cancelled:
      String(
        localized: "task.status.cancelled", defaultValue: "Cancelled", table: "Localizable",
        bundle: MobileL10n.bundle)
    case .someday:
      String(
        localized: "task.status.someday", defaultValue: "Someday", table: "Localizable",
        bundle: MobileL10n.bundle)
    }
  }

  public static func compactPriorityAndStatus(
    priority: LorvexTask.Priority, status: LorvexTask.Status
  ) -> String {
    String(
      format: String(
        localized: "task.metadata.priority_status", defaultValue: "%@ · %@", table: "Localizable",
        bundle: MobileL10n.bundle),
      compactPriority(priority),
      Self.status(status)
    )
  }

  /// Localized display for a task reminder's `delivery_state` wire value
  /// (`pending` / `delivered`). Unknown values fall back to a title-cased form.
  public static func reminderStatus(_ rawStatus: String) -> String {
    switch rawStatus {
    case "pending":
      String(
        localized: "reminder.status.pending", defaultValue: "Pending", table: "Localizable",
        bundle: MobileL10n.bundle)
    case "delivered":
      String(
        localized: "reminder.status.delivered", defaultValue: "Delivered", table: "Localizable",
        bundle: MobileL10n.bundle)
    default:
      titleCased(rawStatus)
    }
  }

  /// Localized display for a task's `lateness_state` wire value. Mirrors the
  /// macOS detail header; unknown values fall back to a title-cased form.
  public static func latenessState(_ rawValue: String) -> String {
    switch rawValue {
    case "past_planned":
      String(
        localized: "task_detail.lateness.past_planned", defaultValue: "Past planned date",
        table: "Localizable", bundle: MobileL10n.bundle)
    case "overdue_unhandled":
      String(
        localized: "task_detail.lateness.overdue_unhandled", defaultValue: "Overdue",
        table: "Localizable", bundle: MobileL10n.bundle)
    case "overdue_acknowledged":
      String(
        localized: "task_detail.lateness.overdue_acknowledged",
        defaultValue: "Overdue acknowledged", table: "Localizable", bundle: MobileL10n.bundle)
    default:
      titleCased(rawValue)
    }
  }

  private static func titleCased(_ rawValue: String) -> String {
    rawValue
      .split(separator: "_")
      .map { $0.prefix(1).uppercased() + $0.dropFirst() }
      .joined(separator: " ")
  }
}
