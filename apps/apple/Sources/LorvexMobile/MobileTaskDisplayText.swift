import Foundation
import LorvexCore

public enum MobileTaskDisplayText {
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
