import Foundation
import LorvexCore

public enum MobileTaskDisplayText {
  public static func compactEstimateMinutes(_ minutes: Int) -> String {
    String(
      localized: "task.estimate.compact_minutes", defaultValue: "\(minutes) min",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  /// The priority as one word ("High", "Normal", "Low"), the way the task
  /// detail's Priority row names it; the storage codes P1–P3 never reach the
  /// screen.
  public static func priority(_ priority: LorvexTask.Priority) -> String {
    MobileTaskPropertyCopy.priorityValue(priority)
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

  /// The word on the badge of a task whose dependencies are still open.
  public static var blocked: String {
    String(
      localized: "task.status.blocked", defaultValue: "Blocked", table: "Localizable",
      bundle: MobileL10n.bundle)
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

  private static func titleCased(_ rawValue: String) -> String {
    rawValue
      .split(separator: "_")
      .map { $0.prefix(1).uppercased() + $0.dropFirst() }
      .joined(separator: " ")
  }
}
