import UserNotifications

/// Withholds arming brand-new task/habit reminders while the first-run setup
/// wizard hasn't finished AND the OS has never been asked about notifications.
///
/// Both `UserNotificationTaskReminderScheduler` and
/// `UserNotificationHabitReminderScheduler` call `requestAuthorization` the
/// moment they're handed a non-empty reminder set — the first such call with a
/// `.notDetermined` status is what pops the system's one-time permission
/// dialog. The setup wizard has its own explicit "Allow" row for this; a
/// background reminder re-plan (running concurrently with the wizard on first
/// launch, e.g. for reminders created by an MCP client before the app was ever
/// opened) must not be the one to trigger that dialog out of context — it
/// would surface mid-wizard, unrelated to whatever step the user is actually
/// looking at.
///
/// `gate(...)` is the pure decision: given the candidates a re-plan would
/// otherwise arm, whether onboarding is done, and the current OS authorization
/// status, it returns either the candidates unchanged or an empty set. Once
/// authorization has been decided by ANY means — the wizard's own tap, System
/// Settings, or a prior session — or the wizard completes, arming proceeds
/// immediately; the hold only ever closes the first-launch race, never delays
/// an already-resolved permission.
public enum ReminderOnboardingGate {
  public static func gate(
    tasks: [ScheduledTaskReminder],
    habits: [DueHabitReminderOccurrence],
    setupCompleted: Bool,
    authorizationStatus: UNAuthorizationStatus
  ) -> (tasks: [ScheduledTaskReminder], habits: [DueHabitReminderOccurrence]) {
    guard !setupCompleted, authorizationStatus == .notDetermined else {
      return (tasks, habits)
    }
    return ([], [])
  }
}
