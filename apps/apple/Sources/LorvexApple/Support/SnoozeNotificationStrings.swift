import LorvexCore
import SwiftUI

extension SnoozeNotificationScheduler.Strings {
  /// Snooze notification copy localized against the LorvexApple catalog.
  static var lorvexLocalized: Self {
    Self(
      titleFallback: String(
        localized: "notification.snooze.title_fallback", defaultValue: "Task Reminder",
        table: "Localizable",
        bundle: LorvexL10n.bundle),
      body: String(
        localized: "notification.snooze.body", defaultValue: "Snoozed reminder",
        table: "Localizable",
        bundle: LorvexL10n.bundle)
    )
  }
}
