import Foundation
import UserNotifications

/// Schedules habit-reminder notifications from concrete due occurrences. Mirrors
/// the task-reminder contract: every re-plan replaces all previously scheduled
/// habit reminders (prefix-identified), so policy edits, disables, habit
/// completions, and deletions converge without per-policy bookkeeping. The
/// scheduler consumes ``DueHabitReminderOccurrence`` values — already filtered to
/// scheduled, not-yet-met, future firings by the core's
/// `getDueHabitReminderOccurrences` query — and arms one one-shot trigger each.
public protocol HabitReminderScheduling: Sendable {
  func replaceScheduledHabitReminders(
    for occurrences: [DueHabitReminderOccurrence]
  ) async -> TaskReminderScheduleReport
}

/// A scheduler that performs no work. Used as the default in non-production contexts.
public struct NoopHabitReminderScheduler: HabitReminderScheduling {
  public init() {}
  public func replaceScheduledHabitReminders(
    for occurrences: [DueHabitReminderOccurrence]
  ) async -> TaskReminderScheduleReport {
    .disabled
  }
}

/// A single due habit reminder mapped to a `UNNotificationRequest`.
///
/// One per ``DueHabitReminderOccurrence``: a `repeats: false` calendar trigger at
/// the occurrence's exact instant, identified by
/// `identifierPrefix + policyID + ":" + fireInstantKey` so several reminder
/// times for one habit on different days each get a distinct, stable id that a
/// prefix sweep reaps on the next re-plan.
public struct ScheduledHabitReminder: Equatable, Sendable {
  public var identifier: String
  public var habitID: String
  public var title: String
  public var body: String
  public var fireDate: Date

  public init(occurrence: DueHabitReminderOccurrence, body: String) {
    let key = Self.fireInstantKey(occurrence.fireDate)
    identifier = UserNotificationHabitReminderScheduler.identifierPrefix
      + occurrence.policy.id + ":" + key
    habitID = occurrence.policy.habitID
    title = occurrence.policy.habitName
    self.body = body
    fireDate = occurrence.fireDate
  }

  public var notificationRequest: UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    // A habit reminder fires at a user-chosen moment, so mark it time-sensitive to
    // break through Focus / Do Not Disturb. Without the Time Sensitive entitlement
    // the system downgrades it to `.active`, so this is safe and forward-compatible.
    content.interruptionLevel = .timeSensitive
    content.userInfo = [
      LorvexNotificationRoute.deepLinkUserInfoKey: LorvexDeepLinkRoute.habit(habitID).url
        .absoluteString
    ]
    let components = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: fireDate)
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
  }

  /// Stable per-instant identifier suffix (`yyyyMMddHHmmss`, UTC) so the same
  /// occurrence re-plans to the same id (idempotent re-add) while distinct
  /// instants stay distinct.
  static func fireInstantKey(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMddHHmmss"
    return formatter.string(from: date)
  }
}

/// UNUserNotificationCenter-backed habit reminders: one one-shot calendar-trigger
/// notification per due occurrence. The occurrence list is pre-gated by the core
/// query (scheduled day, period below target, future instant), so a completed or
/// met habit simply contributes no occurrence on the next re-plan and its pending
/// notification is reaped here.
public struct UserNotificationHabitReminderScheduler: HabitReminderScheduling {
  public static let identifierPrefix = "lorvex-habit-reminder-"

  /// Localized notification body; `LorvexCore` carries no string catalog, so
  /// each host injects its copy. The notification title is the habit's name.
  let body: String

  public init(body: String = "Time for your habit") {
    self.body = body
  }

  public func replaceScheduledHabitReminders(
    for occurrences: [DueHabitReminderOccurrence]
  ) async -> TaskReminderScheduleReport {
    let center = UNUserNotificationCenter.current()
    let reminders = occurrences.map { ScheduledHabitReminder(occurrence: $0, body: body) }
    // Removal needs no authorization; do it first so disabling, completing, or
    // deleting the last habit reminder still clears its pending notification.
    // With nothing to schedule, never request authorization — a user with zero
    // habit reminders must not see a permission prompt on app refresh.
    let pending = await center.pendingNotificationRequests()
    let existingIDs = pending.map(\.identifier).filter {
      $0.hasPrefix(Self.identifierPrefix)
    }
    center.removePendingNotificationRequests(withIdentifiers: existingIDs)
    guard !reminders.isEmpty else { return .scheduled(0) }
    do {
      let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
      guard granted else {
        return .permissionDenied(requestedCount: reminders.count)
      }
    } catch {
      return .failed(scheduledCount: 0, requestedCount: reminders.count, error: error)
    }
    var scheduledCount = 0
    for reminder in reminders {
      do {
        try await center.add(reminder.notificationRequest)
        scheduledCount += 1
      } catch {
        return .failed(
          scheduledCount: scheduledCount, requestedCount: reminders.count, error: error)
      }
    }
    return .scheduled(scheduledCount)
  }
}
