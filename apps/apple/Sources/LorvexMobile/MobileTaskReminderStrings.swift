import Foundation
import LorvexCore

/// Localized strings for task-reminder notifications, exposed to the mobile
/// app targets (which cannot reach the internal `MobileL10n`).
public enum MobileTaskReminderStrings {
  /// Notification body used when a reminder's task has no notes.
  public static var fallbackBody: String {
    String(
      localized: "task.reminder.notification.fallback_body", defaultValue: "Lorvex task reminder",
      table: "Localizable", bundle: MobileL10n.bundle)
  }

  /// Localized titles for the reminder notification's action buttons.
  public static var actionTitles: LorvexNotificationActionTitles {
    LorvexNotificationActionTitles(
      complete: String(
        localized: "notification.action.complete", defaultValue: "Complete", table: "Localizable",
        bundle: MobileL10n.bundle),
      deferToTomorrow: String(
        localized: "notification.action.defer_tomorrow", defaultValue: "Defer to Tomorrow",
        table: "Localizable", bundle: MobileL10n.bundle),
      snooze: String(
        localized: "notification.action.snooze_hour", defaultValue: "Snooze 1 Hour",
        table: "Localizable", bundle: MobileL10n.bundle))
  }
}
