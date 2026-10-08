import Foundation
import UserNotifications

/// Schedules and replaces UNUserNotificationCenter-based task reminders.
public protocol TaskReminderScheduling: Sendable {
  /// Build the schedulable reminder candidates for `tasks` — future, non-terminal
  /// reminders — using the scheduler's localized fallback body.
  ///
  /// `includeNotes` gates whether a task's freeform `notes` may become the
  /// notification body (lock screen / banner) in place of the fallback; the
  /// caller passes the live `notification_show_task_notes` preference so notes
  /// only ever render when the user opted in on this device.
  func candidates(for tasks: [LorvexTask], includeNotes: Bool) -> [ScheduledTaskReminder]

  /// Replace every pending task-reminder notification with exactly `reminders`
  /// (reap the prefix, then arm the given set). The cross-scheduler budgeter uses
  /// this to arm only the earliest-due subset that fits the shared OS cap.
  func scheduleReminders(_ reminders: [ScheduledTaskReminder]) async -> TaskReminderScheduleReport

  /// Task IDs that currently have a pending one-shot snooze notification.
  /// `scheduleReminders` deliberately leaves snoozes alone (they are not stored
  /// reminders), so ``cancelSnoozesOfResolvedTasks(core:)`` reads these to find
  /// the snoozes whose task has resolved. Default: none.
  func pendingSnoozeTaskIDs() async -> Set<LorvexTask.ID>

  /// Cancel the pending one-shot snooze for each task in `taskIDs`. The set is
  /// an explicit drop-set, so a snooze added concurrently for another task is
  /// never swept. Default: no-op.
  func cancelSnoozes(forResolvedTaskIDs taskIDs: Set<LorvexTask.ID>) async

  /// Cancel every pending one-shot snooze, for a reset that removes every
  /// task. Default: no-op.
  func cancelAllSnoozes() async
}

extension TaskReminderScheduling {
  /// Default candidate builder using the generic fallback body; the live
  /// scheduler overrides it to inject its localized copy.
  public func candidates(for tasks: [LorvexTask], includeNotes: Bool) -> [ScheduledTaskReminder] {
    ScheduledTaskReminder.reminders(for: tasks, includeNotes: includeNotes)
  }

  /// Default: no scheduler-managed notifications, so no pending snoozes.
  public func pendingSnoozeTaskIDs() async -> Set<LorvexTask.ID> { [] }

  /// Default no-op; the live scheduler overrides it.
  public func cancelSnoozes(forResolvedTaskIDs taskIDs: Set<LorvexTask.ID>) async {}

  /// Default no-op: preview/test/no-op schedulers manage no real notifications.
  /// The live `UserNotificationTaskReminderScheduler` overrides this.
  public func cancelAllSnoozes() async {}

  /// Cancel the pending one-shot snoozes whose task no longer wants one: a task
  /// that is not actionable (completed, cancelled, or parked as someday), one
  /// in the Trash, or one deleted outright, here or on another device.
  ///
  /// Only the tasks that have a pending snooze are read, one at a time, so the
  /// cost follows the (usually zero) number of snoozes rather than the size of
  /// the task list, and no task is judged by its absence from a capped page. A
  /// read that fails for any reason other than a missing task (for example
  /// SQLITE_BUSY under a concurrent sync write) keeps that snooze for the next
  /// pass instead of cancelling a reminder the user still wants.
  public func cancelSnoozesOfResolvedTasks(core: any LorvexTaskServicing) async {
    let snoozeTaskIDs = await pendingSnoozeTaskIDs()
    guard !snoozeTaskIDs.isEmpty else { return }
    var resolved: Set<LorvexTask.ID> = []
    for id in snoozeTaskIDs {
      do {
        let task = try await core.loadTask(id: id)
        if !task.status.isActionable || task.archivedAt != nil { resolved.insert(id) }
      } catch LorvexCoreError.taskNotFound {
        resolved.insert(id)
      } catch {
        continue
      }
    }
    await cancelSnoozes(forResolvedTaskIDs: resolved)
  }
}

/// A scheduler that performs no work. Used as the default in non-production contexts.
public struct NoopTaskReminderScheduler: TaskReminderScheduling {
  public init() {}
  public func scheduleReminders(_ reminders: [ScheduledTaskReminder]) async
    -> TaskReminderScheduleReport
  {
    .disabled
  }
}

/// Summary of a reminder scheduling operation.
public struct TaskReminderScheduleReport: Equatable, Sendable {
  public enum Status: String, Sendable {
    case disabled = "Disabled"
    case scheduled = "Scheduled"
    case permissionDenied = "Permission Denied"
    case failed = "Failed"
  }

  public var status: Status
  public var scheduledCount: Int
  public var requestedCount: Int
  public var errorMessage: String?

  public init(
    status: Status,
    scheduledCount: Int,
    requestedCount: Int,
    errorMessage: String? = nil
  ) {
    self.status = status
    self.scheduledCount = scheduledCount
    self.requestedCount = requestedCount
    self.errorMessage = errorMessage
  }

  public static var disabled: TaskReminderScheduleReport {
    TaskReminderScheduleReport(status: .disabled, scheduledCount: 0, requestedCount: 0)
  }

  public static func scheduled(_ count: Int) -> TaskReminderScheduleReport {
    TaskReminderScheduleReport(status: .scheduled, scheduledCount: count, requestedCount: count)
  }

  public static func permissionDenied(requestedCount: Int) -> TaskReminderScheduleReport {
    TaskReminderScheduleReport(status: .permissionDenied, scheduledCount: 0, requestedCount: requestedCount)
  }

  public static func failed(scheduledCount: Int, requestedCount: Int, error: any Error) -> TaskReminderScheduleReport {
    TaskReminderScheduleReport(
      status: .failed,
      scheduledCount: scheduledCount,
      requestedCount: requestedCount,
      errorMessage: error.localizedDescription
    )
  }
}

/// A pending task reminder mapped to a UNNotificationRequest.
///
/// Only created for tasks that are not completed/cancelled and whose reminder
/// fire date is in the future relative to `now`.
public struct ScheduledTaskReminder: Equatable, Sendable {
  public static let identifierPrefix = "lorvex-reminder:"

  /// Identifier prefix for one-shot snooze notifications. Deliberately distinct
  /// from `identifierPrefix` so `scheduleReminders` — which reaps every pending
  /// request under `identifierPrefix` before arming the given set — never sweeps
  /// a live snooze (which is not a stored reminder and whose original fire date
  /// is already past, so it would not be re-added).
  public static let snoozeIdentifierPrefix = "lorvex-snooze:"

  public var identifier: String
  /// The bare `task_reminders.id` (the identifier without ``identifierPrefix``).
  /// Lets the reschedule pass tell the store exactly which reminder rows it
  /// armed, so their `last_armed_at` arming stamp reflects reality.
  public var reminderID: TaskReminder.ID
  public var taskID: LorvexTask.ID
  public var title: String
  public var body: String
  public var fireDate: Date

  /// - Parameter includeNotes: When `false` (the default), the body is always
  ///   `fallbackBody` — the task's freeform `notes` never render on the lock
  ///   screen / banner. When `true` and `task.notes` is non-empty, the notes
  ///   become the body instead. Callers thread in the live
  ///   `notification_show_task_notes` preference so this only ever happens
  ///   with the user's on-device opt-in.
  public init?(
    task: LorvexTask,
    reminder: TaskReminder,
    now: Date = Date(),
    fallbackBody: String = "Lorvex task reminder",
    includeNotes: Bool = false
  ) {
    guard task.status != .completed, task.status != .cancelled,
      let fireDate = Self.parseDate(reminder.reminderAt),
      fireDate > now
    else { return nil }
    identifier = Self.identifierPrefix + reminder.id
    reminderID = reminder.id
    taskID = task.id
    title = task.title
    body = (includeNotes && !task.notes.isEmpty) ? task.notes : fallbackBody
    self.fireDate = fireDate
  }

  public var notificationRequest: UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    // Audible like habit reminders — the app requests `.sound` authorization and
    // presents `.sound` in the foreground, so a silent task reminder is easy to miss.
    content.sound = .default
    // A task reminder fires at a user-chosen moment, so mark it time-sensitive to
    // break through Focus / Do Not Disturb. Without the Time Sensitive entitlement
    // the system downgrades it to `.active`, so this is safe and forward-compatible.
    content.interruptionLevel = .timeSensitive
    content.categoryIdentifier = LorvexNotificationCategory.taskReminder
    content.userInfo = [
      LorvexNotificationRoute.taskIDUserInfoKey: taskID,
      LorvexNotificationRoute.deepLinkUserInfoKey: LorvexDeepLinkRoute.task(taskID).url
        .absoluteString,
    ]
    let trigger = UNCalendarNotificationTrigger.oneShot(at: fireDate)
    return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
  }

  public static func reminders(
    for tasks: [LorvexTask],
    now: Date = Date(),
    fallbackBody: String = "Lorvex task reminder",
    includeNotes: Bool = false
  ) -> [ScheduledTaskReminder] {
    tasks.flatMap { task in
      task.reminders.compactMap { reminder in
        ScheduledTaskReminder(
          task: task, reminder: reminder, now: now, fallbackBody: fallbackBody,
          includeNotes: includeNotes)
      }
    }
  }

  private static func parseDate(_ text: String) -> Date? {
    if let date = LorvexDateFormatters.iso8601Fractional.date(from: text) {
      return date
    }
    return LorvexDateFormatters.iso8601.date(from: text)
  }
}

/// Live implementation that schedules task reminders via UNUserNotificationCenter.
///
/// Requests authorization on first call. Returns `.permissionDenied` without
/// scheduling when the user has denied notifications.
public struct UserNotificationTaskReminderScheduler: TaskReminderScheduling {
  /// Notification body used when a reminder's task has no notes. `LorvexCore`
  /// carries no string catalog, so each host injects its localized copy.
  let fallbackBody: String

  public init(
    fallbackBody: String = "Lorvex task reminder",
    actionTitles: LorvexNotificationActionTitles = LorvexNotificationActionTitles()
  ) {
    self.fallbackBody = fallbackBody
    registerLorvexNotificationCategories(UNUserNotificationCenter.current(), titles: actionTitles)
  }

  public func candidates(for tasks: [LorvexTask], includeNotes: Bool) -> [ScheduledTaskReminder] {
    ScheduledTaskReminder.reminders(for: tasks, fallbackBody: fallbackBody, includeNotes: includeNotes)
  }

  public func scheduleReminders(_ reminders: [ScheduledTaskReminder]) async
    -> TaskReminderScheduleReport
  {
    let center = UNUserNotificationCenter.current()
    // Removal needs no authorization; do it first so clearing the last
    // reminder still removes its pending notification. With nothing to
    // schedule, never request authorization — the re-plan runs inside every
    // refresh, and a user with zero reminders must not see a permission
    // prompt (least of all racing the setup wizard's own permission step).
    let pending = await center.pendingNotificationRequests()
    let existingIDs = pending.map(\.identifier).filter {
      $0.hasPrefix(ScheduledTaskReminder.identifierPrefix)
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
        return .failed(scheduledCount: scheduledCount, requestedCount: reminders.count, error: error)
      }
    }
    return .scheduled(scheduledCount)
  }

  public func pendingSnoozeTaskIDs() async -> Set<LorvexTask.ID> {
    let center = UNUserNotificationCenter.current()
    let pending = await center.pendingNotificationRequests()
    let prefix = ScheduledTaskReminder.snoozeIdentifierPrefix
    return Set(
      pending.map(\.identifier)
        .filter { $0.hasPrefix(prefix) }
        .map { String($0.dropFirst(prefix.count)) })
  }

  public func cancelSnoozes(forResolvedTaskIDs taskIDs: Set<LorvexTask.ID>) async {
    guard !taskIDs.isEmpty else { return }
    let center = UNUserNotificationCenter.current()
    let prefix = ScheduledTaskReminder.snoozeIdentifierPrefix
    center.removePendingNotificationRequests(
      withIdentifiers: taskIDs.map { prefix + $0 })
  }

  public func cancelAllSnoozes() async {
    await cancelSnoozes(forResolvedTaskIDs: pendingSnoozeTaskIDs())
  }
}
