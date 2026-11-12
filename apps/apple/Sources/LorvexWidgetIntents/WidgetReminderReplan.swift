import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import UserNotifications

/// Re-plans this device's task and habit reminders after a widget's write,
/// with the pass the app runs after its own (``ReminderReplan``).
///
/// A widget's Complete runs in the widget extension while the app is
/// suspended or not running. Without this pass, a repeating task completed
/// from a widget had no reminder for its next occurrence, and a later reminder
/// held back by the shared budget stayed unarmed, until the app next ran. The
/// pass is the app's own: one budget across both kinds, the armed and
/// delivered stamps, and the snoozes of resolved tasks.
///
/// It runs only when the person has allowed notifications. Before they have
/// answered, the schedulers would ask for permission, which the app's first-run
/// setup asks at a moment of its own; after a refusal there is nothing to arm.
/// The app's next pass covers both.
public struct WidgetReminderReplan: Sendable {
  /// The diagnostics-log source a failed pass is written under.
  public static let diagnosticSource = "widget.reminders.schedule"

  private let authorizationStatus: @Sendable () async -> UNAuthorizationStatus
  private let makeTaskScheduler: @Sendable () -> any TaskReminderScheduling
  private let makeHabitScheduler: @Sendable () -> any HabitReminderScheduling
  private let now: @Sendable () -> Date

  /// - Parameters:
  ///   - authorizationStatus: the OS notification authorization status.
  ///   - taskScheduler: builds the task scheduler, only once the pass runs.
  ///   - habitScheduler: builds the habit scheduler, only once the pass runs.
  ///   - now: the clock the pass reads.
  public init(
    authorizationStatus: @escaping @Sendable () async -> UNAuthorizationStatus,
    taskScheduler: @escaping @Sendable () -> any TaskReminderScheduling,
    habitScheduler: @escaping @Sendable () -> any HabitReminderScheduling,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.authorizationStatus = authorizationStatus
    self.makeTaskScheduler = taskScheduler
    self.makeHabitScheduler = habitScheduler
    self.now = now
  }

  /// The device's notification center, with the reminder copy in the
  /// person's language. The task scheduler leaves the notification categories
  /// as the app registered them (``UserNotificationTaskReminderScheduler/outsideTheApp(fallbackBody:)``).
  /// Built on use: the center is unavailable to a process without an app
  /// bundle, such as the test runner.
  public static var live: WidgetReminderReplan {
    WidgetReminderReplan(
      authorizationStatus: {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
      },
      taskScheduler: {
        UserNotificationTaskReminderScheduler.outsideTheApp(
          fallbackBody: String(
            localized: "task.reminder.notification.fallback_body",
            defaultValue: "Lorvex task reminder", table: "Localizable",
            bundle: WidgetSupportL10n.bundle))
      },
      habitScheduler: {
        UserNotificationHabitReminderScheduler(
          body: String(
            localized: "habit.reminder.notification.body", defaultValue: "Time for your habit",
            table: "Localizable", bundle: WidgetSupportL10n.bundle))
      })
  }

  /// Runs one pass over `core`, or returns nil without touching a
  /// notification when the person has not allowed notifications.
  @discardableResult
  public func run(core: any LorvexCoreServicing) async -> ReminderReplan.Outcome? {
    let status = await authorizationStatus()
    guard Self.allowsArming(status) else { return nil }
    return await ReminderReplan.run(
      core: core, taskScheduler: makeTaskScheduler(), habitScheduler: makeHabitScheduler(),
      includeTaskNotes: await ReminderReplan.includesTaskNotes(core: core),
      // The status is settled, so the onboarding gate has nothing to hold.
      setupCompleted: true, authorizationStatus: { status }, now: now,
      diagnosticSource: Self.diagnosticSource)
  }

  /// Whether a pass may arm reminders under `status`: the person allowed
  /// notifications, outright or quietly.
  static func allowsArming(_ status: UNAuthorizationStatus) -> Bool {
    status == .authorized || status == .provisional
  }
}
