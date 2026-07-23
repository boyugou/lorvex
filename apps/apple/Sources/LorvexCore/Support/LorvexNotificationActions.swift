import UserNotifications

/// Stable identifiers and registration helpers for Lorvex notification rich actions.
public enum LorvexNotificationCategory {
  /// Category identifier attached to all task reminder notifications.
  public static let taskReminder = "lorvex.category.taskReminder"
}

/// Stable action identifiers for notification action buttons.
public enum LorvexNotificationActionID {
  public static let completeTask = "lorvex.action.completeTask"
  public static let deferTask = "lorvex.action.deferTask"
  public static let snoozeTask = "lorvex.action.snoozeTask"
}

/// Localized titles for the task-reminder notification action buttons.
///
/// `LorvexCore` carries no string catalog, so each host injects its localized
/// copy (mirroring `UserNotificationTaskReminderScheduler`'s `fallbackBody`).
/// The English defaults are the source strings for the hosts' catalogs.
public struct LorvexNotificationActionTitles: Sendable {
  public let complete: String
  public let deferToTomorrow: String
  public let snooze: String

  public init(
    complete: String = "Complete",
    deferToTomorrow: String = "Defer to Tomorrow",
    snooze: String = "Snooze 1 Hour"
  ) {
    self.complete = complete
    self.deferToTomorrow = deferToTomorrow
    self.snooze = snooze
  }
}

/// Builds the full set of Lorvex notification categories without touching a notification center.
///
/// Returns the category set that `registerLorvexNotificationCategories` would register.
/// Useful in tests where `UNUserNotificationCenter.current()` is unavailable.
public func lorvexNotificationCategories(
  titles: LorvexNotificationActionTitles = LorvexNotificationActionTitles()
) -> Set<UNNotificationCategory> {
  let completeAction = UNNotificationAction(
    identifier: LorvexNotificationActionID.completeTask,
    title: titles.complete,
    options: [.authenticationRequired]
  )

  let deferAction = UNNotificationAction(
    identifier: LorvexNotificationActionID.deferTask,
    title: titles.deferToTomorrow,
    options: [.foreground]
  )

  let snoozeAction = UNNotificationAction(
    identifier: LorvexNotificationActionID.snoozeTask,
    title: titles.snooze,
    options: []
  )

  let taskReminderCategory = UNNotificationCategory(
    identifier: LorvexNotificationCategory.taskReminder,
    actions: [completeAction, deferAction, snoozeAction],
    intentIdentifiers: [],
    options: []
  )

  return [taskReminderCategory]
}

/// Registers Lorvex notification categories with the given notification center.
///
/// Call once during app initialisation. Safe to call multiple times — subsequent calls
/// replace the previously registered set with an identical one.
public func registerLorvexNotificationCategories(
  _ center: UNUserNotificationCenter,
  titles: LorvexNotificationActionTitles = LorvexNotificationActionTitles()
) {
  center.setNotificationCategories(lorvexNotificationCategories(titles: titles))
}
