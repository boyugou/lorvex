import Foundation
import UserNotifications

/// A pending notification request reduced to what ``ReminderWithdrawal``
/// decides on.
public struct PendingReminderRequest: Equatable, Sendable {
  public var identifier: String
  /// The task a task reminder or snooze belongs to (its
  /// `LorvexNotificationRoute.taskIDUserInfoKey`), nil for any other request.
  public var taskID: String?
  /// When the request next fires, nil when its trigger cannot say.
  public var nextFireDate: Date?

  public init(identifier: String, taskID: String? = nil, nextFireDate: Date? = nil) {
    self.identifier = identifier
    self.taskID = taskID
    self.nextFireDate = nextFireDate
  }
}

/// Takes back the pending reminder notifications of one task or habit that a
/// write made outside the app shell has resolved.
///
/// The app re-plans every reminder after its own writes (``ReminderReplan``),
/// but an interactive widget's intent runs in the widget extension, and an
/// iPhone app stays suspended through it: without this, a task completed from a
/// widget still fires its reminder, and a habit met from one still nudges later
/// that day. This only removes requests. It arms nothing, writes nothing to the
/// store, and never constructs the app's schedulers, whose setup registers the
/// notification actions in the app's language; the app's next pass arms what
/// the write added, such as a repeat's next occurrence.
///
/// Every step is best effort: a read that fails withdraws nothing, which keeps
/// a reminder rather than losing one the user still wants.
public struct ReminderWithdrawal: Sendable {
  private let pending: @Sendable () async -> [PendingReminderRequest]
  private let remove: @Sendable ([String]) -> Void
  private let now: @Sendable () -> Date

  public init(
    pending: @escaping @Sendable () async -> [PendingReminderRequest],
    remove: @escaping @Sendable ([String]) -> Void,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.pending = pending
    self.remove = remove
    self.now = now
  }

  /// The device's notification center, which an app shares with its
  /// extensions. Built on use: the center is unavailable to a process without
  /// an app bundle, such as the test runner.
  public static var live: ReminderWithdrawal {
    ReminderWithdrawal(
      pending: {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map { request in
          let trigger = request.trigger
          let nextFireDate =
            (trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            ?? (trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
          return PendingReminderRequest(
            identifier: request.identifier,
            taskID: request.content.userInfo[LorvexNotificationRoute.taskIDUserInfoKey] as? String,
            nextFireDate: nextFireDate)
        }
      },
      remove: { identifiers in
        UNUserNotificationCenter.current().removePendingNotificationRequests(
          withIdentifiers: identifiers)
      })
  }

  /// Withdraws every pending reminder and snooze of `taskID`. Call it only
  /// after a write that left the task unable to want one (completed or
  /// cancelled); a repeat's next occurrence is a task of its own and keeps
  /// its reminders.
  public func withdrawTaskReminders(taskID: LorvexTask.ID) async {
    let snoozeID = ScheduledTaskReminder.snoozeIdentifierPrefix + taskID
    let withdrawn = await pending().filter { request in
      request.identifier == snoozeID
        || (request.identifier.hasPrefix(ScheduledTaskReminder.identifierPrefix)
          && request.taskID == taskID)
    }
    guard !withdrawn.isEmpty else { return }
    remove(withdrawn.map(\.identifier))
  }

  /// Withdraws the pending reminders of `habitID` that the habit no longer
  /// wants: each one still to fire that the core's due-occurrence query, read
  /// at the same instant, no longer returns, as when the period's target has
  /// just been met. Other habits' reminders, and ones at or before now, are
  /// left alone.
  public func withdrawHabitReminders(
    habitID: LorvexHabit.ID, core: any LorvexHabitServicing
  ) async {
    await withdrawHabitReminders(
      habitID: habitID,
      policies: { try await core.getHabitReminderPolicies(id: habitID) },
      dueOccurrences: { now in
        try await core.getDueHabitReminderOccurrences(
          now: now, horizonDays: ReminderReplan.habitHorizonDays)
      })
  }

  /// ``withdrawHabitReminders(habitID:core:)`` over explicit reads: the
  /// habit's reminder policies, and the due occurrences at an instant.
  func withdrawHabitReminders(
    habitID: LorvexHabit.ID,
    policies: () async throws -> [HabitReminderPolicy],
    dueOccurrences: (Date) async throws -> [DueHabitReminderOccurrence]
  ) async {
    let now = now()
    guard let policies = try? await policies(), !policies.isEmpty,
      let occurrences = try? await dueOccurrences(now)
    else { return }
    let prefixes = policies.map {
      UserNotificationHabitReminderScheduler.identifierPrefix + $0.id + ":"
    }
    let wanted = Set(
      occurrences
        .filter { $0.policy.habitID == habitID }
        .map { ScheduledHabitReminder(occurrence: $0, body: "").identifier })
    let withdrawn = await pending().filter { request in
      guard let fireDate = request.nextFireDate, fireDate > now else { return false }
      return prefixes.contains { request.identifier.hasPrefix($0) }
        && !wanted.contains(request.identifier)
    }
    guard !withdrawn.isEmpty else { return }
    remove(withdrawn.map(\.identifier))
  }
}
