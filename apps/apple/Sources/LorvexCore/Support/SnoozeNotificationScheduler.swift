import Foundation
import UserNotifications

/// Schedules a one-shot snooze reminder 1 hour (configurable) from now.
public struct SnoozeNotificationScheduler {
  public static let defaultInterval: TimeInterval = 3600

  /// Lock-screen copy for a snoozed reminder. `LorvexCore` carries no string
  /// catalog, so each host injects its localized copy; `.english` keeps the
  /// scheduler self-contained for tests.
  public struct Strings: Sendable {
    /// Notification title used when the task's own title is unavailable.
    public var titleFallback: String
    /// Notification body.
    public var body: String

    public init(titleFallback: String, body: String) {
      self.titleFallback = titleFallback
      self.body = body
    }

    public static let english = Strings(titleFallback: "Task Reminder", body: "Snoozed reminder")
  }

  public static func schedule(
    taskID: LorvexTask.ID,
    interval: TimeInterval = defaultInterval,
    title: String? = nil,
    strings: Strings = .english,
    center: UNUserNotificationCenter = .current()
  ) async -> TaskReminderScheduleReport {
    let request = notificationRequest(
      taskID: taskID, interval: interval, title: title, strings: strings)
    do {
      try await center.add(request)
      return .scheduled(1)
    } catch {
      return .failed(scheduledCount: 0, requestedCount: 1, error: error)
    }
  }

  public static func notificationRequest(
    taskID: LorvexTask.ID,
    interval: TimeInterval = defaultInterval,
    title: String? = nil,
    strings: Strings = .english
  ) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = title ?? strings.titleFallback
    content.body = strings.body
    // A user-requested "remind me later" follow-up should be audible like the
    // original reminder, not a silent notification that's easy to miss.
    content.sound = .default
    // A snoozed "remind me later" fires at a user-chosen moment, so mark it
    // time-sensitive to break through Focus / Do Not Disturb like the original
    // reminder. Without the Time Sensitive entitlement it downgrades to `.active`.
    content.interruptionLevel = .timeSensitive
    content.categoryIdentifier = LorvexNotificationCategory.taskReminder
    content.userInfo = [
      LorvexNotificationRoute.taskIDUserInfoKey: taskID,
      LorvexNotificationRoute.deepLinkUserInfoKey: LorvexDeepLinkRoute.task(taskID).url
        .absoluteString,
    ]
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
    return UNNotificationRequest(
      identifier: ScheduledTaskReminder.snoozeIdentifierPrefix + "\(taskID)",
      content: content,
      trigger: trigger
    )
  }

  /// From `pendingIdentifiers`, the snooze identifiers whose task is no longer
  /// active — completed, cancelled, or deleted, i.e. absent from
  /// `activeTaskIDs`. A snooze is a one-shot "remind me in 1h"; once its task is
  /// done it must be cancelled rather than fire for a finished task. Pure so it
  /// can be unit-tested without `UNUserNotificationCenter`; the live scheduler's
  /// `cancelSnoozes` feeds it the center's pending identifiers.
  public static func staleSnoozeIdentifiers(
    pendingIdentifiers: [String],
    activeTaskIDs: Set<LorvexTask.ID>
  ) -> [String] {
    let prefix = ScheduledTaskReminder.snoozeIdentifierPrefix
    return pendingIdentifiers
      .filter { $0.hasPrefix(prefix) }
      .filter { !activeTaskIDs.contains(String($0.dropFirst(prefix.count))) }
  }
}
