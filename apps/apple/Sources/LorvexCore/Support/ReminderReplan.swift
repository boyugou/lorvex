import Foundation
import UserNotifications

/// One re-plan of this device's task and habit reminder notifications: the
/// pass the macOS and iOS app shells run on launch, on foreground, and after
/// every refresh.
///
/// Task and habit reminders share the OS cap on pending notifications, so one
/// pass plans both kinds together:
///
/// 1. Elapsed reminders are marked delivered, so the assistant's due-reminder
///    queries stop returning ones the OS has already shown. Only reminders
///    armed on an earlier pass become delivered; one that was never armed
///    (over budget, permission denied, refused by the OS) stays pending and
///    keeps surfacing as due.
/// 2. Candidates come from the delivery-aware core queries: actionable tasks
///    (open or started, never parked) with a reminder in the next
///    ``taskHorizonHours``, and habit reminder occurrences in the next
///    ``habitHorizonDays``. A task snapshot cannot stand in for the task
///    query: it lacks this device's delivery receipts, so rebuilding from it
///    could re-arm a reminder that already fired, and every reminder of a task
///    it leaves out would be cancelled by the replace below.
/// 3. The earliest-firing ``ReminderBudget/pendingNotificationLimit``
///    candidates across both kinds are kept, and ``ReminderOnboardingGate``
///    holds brand-new reminders back while first-run setup has not yet asked
///    for notification permission.
/// 4. Each scheduler replaces its kind's pending notifications with its share,
///    and the core records which reminders the OS accepted: `last_armed_at`
///    per task reminder, an armed-through instant per habit reminder policy.
/// 5. Pending snoozes of tasks that have since resolved are cancelled.
///
/// A failed read never clears notifications. When the task read fails, the
/// pass stops before replacing either kind, because the shared budget cannot
/// be computed without it. When the habit read fails, task reminders are
/// re-planned and the pending habit notifications stay as they were. Either
/// failure comes back as a `.failed` report and is written to the diagnostics
/// log, as is a scheduler that fails to arm its share.
public enum ReminderReplan {
  /// How far ahead task reminders are read: a year, so a reminder set months
  /// out is armed as soon as it ranks among the earliest under the budget.
  public static let taskHorizonHours = 24 * 365

  /// The most tasks one pass reads; far above the notification budget, which
  /// keeps only the earliest-firing reminders anyway.
  public static let taskReadLimit = 500

  /// Days of habit reminder occurrences armed per pass. Each occurrence is a
  /// one-shot trigger, and passes run often enough that a rolling two weeks
  /// stays ahead of the user.
  public static let habitHorizonDays = 14

  /// What one pass did to each kind's pending notifications.
  public struct Outcome: Sendable {
    /// The task scheduler's report, or `.failed` when the task read failed
    /// and the pass stopped without touching any notification.
    public var taskReport: TaskReminderScheduleReport
    /// The habit scheduler's report, `.failed` when the habit read failed and
    /// the pending habit notifications were kept, or `nil` when the pass
    /// stopped before habits, so the previous habit report still describes
    /// the pending habit notifications.
    public var habitReport: TaskReminderScheduleReport?
  }

  /// Runs one pass.
  ///
  /// - Parameters:
  ///   - core: the store the reminders are read from and armed stamps written to.
  ///   - taskScheduler: replaces the pending task-reminder notifications.
  ///   - habitScheduler: replaces the pending habit-reminder notifications.
  ///   - includeTaskNotes: whether a task's notes may become its notification
  ///     body, the device's `notification_show_task_notes` preference.
  ///   - setupCompleted: whether first-run setup has finished; while it has
  ///     not, `authorizationStatus` is read for the onboarding gate.
  ///   - authorizationStatus: the OS notification authorization status.
  ///   - now: the clock each step reads.
  ///   - diagnosticSource: the diagnostics-log source failures are written
  ///     under, such as `ios.reminders.schedule`.
  public static func run(
    core: any LorvexCoreServicing,
    taskScheduler: any TaskReminderScheduling,
    habitScheduler: any HabitReminderScheduling,
    includeTaskNotes: Bool,
    setupCompleted: Bool,
    authorizationStatus: @Sendable () async -> UNAuthorizationStatus,
    now: @Sendable () -> Date,
    diagnosticSource: String
  ) async -> Outcome {
    // Best-effort: a failure only over-returns due reminders, never blocks.
    _ = try? await core.markDueTaskRemindersDelivered(asOf: now())
    try? await core.reconcileDeliveredHabitReminders(asOf: now())

    let reminderTasks: [LorvexTask]
    do {
      reminderTasks = try await core.getTasksWithUpcomingReminders(
        hoursAhead: taskHorizonHours, limit: taskReadLimit)
    } catch {
      await log(
        "Couldn't read task reminders; pending reminder notifications kept.", error: error,
        core: core, source: diagnosticSource)
      return Outcome(
        taskReport: .failed(scheduledCount: 0, requestedCount: 0, error: error), habitReport: nil)
    }
    let taskCandidates = taskScheduler.candidates(
      for: reminderTasks.filter { $0.status.isActionable }, includeNotes: includeTaskNotes)

    var occurrences: [DueHabitReminderOccurrence] = []
    var habitReadError: (any Error)?
    do {
      occurrences = try await core.getDueHabitReminderOccurrences(
        now: now(), horizonDays: habitHorizonDays)
    } catch {
      habitReadError = error
    }

    let budgeted = ReminderBudget.budget(taskCandidates: taskCandidates, habitOccurrences: occurrences)
    // Once setup is complete the gate ignores the status, so it is not read:
    // `UNUserNotificationCenter` is unavailable in the SwiftPM test runner.
    let status: UNAuthorizationStatus = setupCompleted ? .authorized : await authorizationStatus()
    let gated = ReminderOnboardingGate.gate(
      tasks: budgeted.tasks, habits: budgeted.habits, setupCompleted: setupCompleted,
      authorizationStatus: status)

    let taskReport = await taskScheduler.scheduleReminders(gated.tasks)
    // The scheduler arms in order and stops at the first refusal, so the
    // accepted reminders are the prefix it reports (none when denied or
    // disabled). Stamps outside it are cleared, so the armed record mirrors
    // the pending request set. Best-effort: a failure only over-returns.
    let armedReminderIDs = gated.tasks.prefix(taskReport.scheduledCount).map(\.reminderID)
    try? await core.replaceArmedTaskReminders(reminderIDs: armedReminderIDs, asOf: now())

    let habitReport: TaskReminderScheduleReport
    if let habitReadError {
      habitReport = .failed(scheduledCount: 0, requestedCount: 0, error: habitReadError)
      await log(
        "Couldn't read habit reminders; pending habit notifications kept.", error: habitReadError,
        core: core, source: diagnosticSource)
    } else {
      habitReport = await habitScheduler.replaceScheduledHabitReminders(for: gated.habits)
      // The same accepted-prefix rule per habit reminder policy. The delivered
      // reconciler only records occurrences at or before a policy's stamp, so
      // a nudge that was never armed keeps surfacing as due.
      var armedThroughByPolicyID: [String: Date] = [:]
      for occurrence in gated.habits.prefix(habitReport.scheduledCount) {
        let policyID = occurrence.policy.id
        armedThroughByPolicyID[policyID] = max(
          armedThroughByPolicyID[policyID] ?? .distantPast, occurrence.fireDate)
      }
      try? await core.replaceArmedHabitReminders(
        armedThroughByPolicyID: armedThroughByPolicyID, asOf: now())
    }

    // The replace above leaves snoozes alone; drop the ones whose task resolved
    // (done, parked, trashed, or deleted, here or through sync).
    await taskScheduler.cancelSnoozesOfResolvedTasks(core: core)

    if taskReport.status == .failed {
      await log(
        "Task reminder scheduling failed.", message: taskReport.errorMessage, core: core,
        source: diagnosticSource)
    }
    if habitReadError == nil, habitReport.status == .failed {
      await log(
        "Habit reminder scheduling failed.", message: habitReport.errorMessage, core: core,
        source: diagnosticSource)
    }
    return Outcome(taskReport: taskReport, habitReport: habitReport)
  }

  private static func log(
    _ summary: String, error: any Error, core: any LorvexCoreServicing, source: String
  ) async {
    await log(summary, message: error.localizedDescription, core: core, source: source)
  }

  private static func log(
    _ summary: String, message: String?, core: any LorvexCoreServicing, source: String
  ) async {
    try? await core.appendDiagnosticLog(
      source: source, level: "error", message: summary, details: message)
  }
}
