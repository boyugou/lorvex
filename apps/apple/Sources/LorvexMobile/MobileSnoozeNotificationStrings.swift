import LorvexCore

extension SnoozeNotificationScheduler.Strings {
  /// Snooze notification copy localized against the LorvexMobile catalog.
  public static var mobileLocalized: Self {
    Self(
      titleFallback: String(
        localized: "notification.snooze.title_fallback", defaultValue: "Task Reminder",
        table: "Localizable", bundle: MobileL10n.bundle),
      body: String(
        localized: "notification.snooze.body", defaultValue: "Snoozed reminder",
        table: "Localizable", bundle: MobileL10n.bundle)
    )
  }
}
