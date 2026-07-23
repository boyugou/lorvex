import Foundation

/// Localized strings for habit-reminder notifications, exposed to the mobile
/// app targets (which cannot reach the internal `MobileL10n`).
public enum MobileHabitReminderStrings {
  /// Notification body; the title is the habit's name.
  public static var body: String {
    String(localized: "habit.reminder.notification.body", defaultValue: "Time for your habit", table: "Localizable", bundle: MobileL10n.bundle)
  }
}
