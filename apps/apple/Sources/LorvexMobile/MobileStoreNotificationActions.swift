import LorvexCore
import UserNotifications

extension MobileStore {
  private static let reminderSchedulingHorizonHours = 24 * 365

  /// Days of habit reminders pre-scheduled per re-plan; mirrors the macOS shell.
  /// The OS fires each one-shot trigger once, and the refresh fan-out re-plans
  /// frequently enough that a rolling two-week window stays ahead of the user.
  private static let habitReminderHorizonDays = 14

  /// Re-plan task + habit reminder notifications under one shared budget so a
  /// flood of one kind can't crowd the other out of the OS cap (the OS otherwise
  /// silently drops the excess). Marks elapsed reminders delivered first — but
  /// only those actually armed on a prior pass (see the `last_armed_at` stamp
  /// below), so a budgeted-out / denied / add-failed reminder stays pending and
  /// keeps re-surfacing in MCP due-queries instead of recording a phantom
  /// delivery. Gathers both kinds' candidates, keeps the earliest-firing across
  /// the combined set, and arms each subset. On a habit occurrence-read failure
  /// the habit reap is skipped entirely so the last-good pending habit
  /// notifications keep firing rather than being cleared by a transient error;
  /// the failure is recorded on ``lastHabitReminderScheduleReport`` and in the
  /// diagnostics ring instead of being swallowed. Both schedule reports are
  /// retained on the store, and a `.failed`/`.permissionDenied` outcome for
  /// either kind is logged so a silent reap-and-fail is observable. The task read
  /// falls back to the loaded Today snapshot and never fails.
  func rescheduleReminders() async {
    let signpost = LorvexSignpost.begin(.notificationsReplace)
    defer { LorvexSignpost.end(signpost) }
    _ = try? await core.markDueTaskRemindersDelivered(asOf: now())
    try? await core.reconcileDeliveredHabitReminders(asOf: now())

    // Only actionable tasks arm reminders — `open` and `in_progress` (started),
    // so starting a task keeps its reminder. Filtering on `.isActionable`
    // (not `.isActive`, which includes `someday`) means a parked task never
    // notifies, matching macOS and the core reminder queries.
    let schedulableTasks = await mobileReminderTasks().filter { $0.status.isActionable }
    let showTaskNotesInNotifications = await loadShowTaskNotesInNotificationsPreference()
    let taskCandidates = taskReminderScheduler.candidates(
      for: schedulableTasks, includeNotes: showTaskNotesInNotifications)

    var occurrences: [DueHabitReminderOccurrence] = []
    var habitReadError: (any Error)?
    do {
      occurrences = try await core.getDueHabitReminderOccurrences(
        now: now(), horizonDays: Self.habitReminderHorizonDays)
    } catch {
      habitReadError = error
    }

    let budgeted = ReminderBudget.budget(
      taskCandidates: taskCandidates, habitOccurrences: occurrences)
    // Defer arming brand-new reminders while the setup wizard's own
    // Notifications row hasn't yet had its chance to request authorization —
    // see `ReminderOnboardingGate`. The live authorization read is skipped
    // once setup is complete: the gate ignores it in that case anyway, and
    // skipping avoids touching `UNUserNotificationCenter` (unavailable in the
    // SwiftPM test-runner process) on the overwhelmingly common path.
    let authorizationStatus: UNAuthorizationStatus =
      isSetupCompleted ? .authorized : await notificationAuthorizationStatusProvider()
    let gated = ReminderOnboardingGate.gate(
      tasks: budgeted.tasks, habits: budgeted.habits,
      setupCompleted: isSetupCompleted,
      authorizationStatus: authorizationStatus)
    let taskReport = await taskReminderScheduler.scheduleReminders(gated.tasks)
    lastTaskReminderScheduleReport = taskReport

    // Replace the armed record with exactly the reminders the OS accepted —
    // the armed earliest-due prefix (`scheduledCount` is 0 for a denied/
    // disabled report). Reminders outside the prefix had their OS requests
    // dropped by this replace pass, so their stale armed stamps are cleared:
    // the stamp mirrors the currently pending request set, a budgeted-out /
    // denied / add-failed reminder stays pending and remains visible to MCP
    // due queries instead of being recorded as a phantom delivery.
    // Best-effort: a failure only over-returns.
    let armedReminderIDs = gated.tasks.prefix(taskReport.scheduledCount).map(\.reminderID)
    try? await core.replaceArmedTaskReminders(reminderIDs: armedReminderIDs, asOf: now())

    // On a habit occurrence-read failure, skip the reap entirely: the scheduler
    // reaps every pending habit request before arming, so re-planning with an
    // empty set on a transient read failure would clear all pending habit
    // notifications with no trace. Keep the last-good armed set and record the
    // failure instead; a successful read reaps and re-arms as usual.
    if let habitReadError {
      lastHabitReminderScheduleReport = .failed(
        scheduledCount: 0, requestedCount: 0, error: habitReadError)
    } else {
      lastHabitReminderScheduleReport = await habitReminderScheduler.replaceScheduledHabitReminders(
        for: gated.habits)

      // Same contract for habits: record "armed through" per policy from the
      // accepted prefix (the scheduler adds requests in array order and stops
      // on the first failure) and clear every other policy's stamp. Guarded by
      // the read-failure skip above so the armed record moves only when the
      // pending request set actually did. The delivered reconciler only
      // records occurrences at or before this stamp, so a never-armed nudge
      // keeps surfacing as due.
      var armedThroughByPolicyID: [String: Date] = [:]
      for occurrence in gated.habits.prefix(lastHabitReminderScheduleReport.scheduledCount) {
        let policyID = occurrence.policy.id
        armedThroughByPolicyID[policyID] = max(
          armedThroughByPolicyID[policyID] ?? .distantPast, occurrence.fireDate)
      }
      try? await core.replaceArmedHabitReminders(
        armedThroughByPolicyID: armedThroughByPolicyID, asOf: now())
    }

    // Drop one-shot snoozes for tasks no longer active (completed/cancelled here
    // or via sync); the reminder reap above leaves the snooze prefix untouched.
    await taskReminderScheduler.cancelSnoozes(
      keepingActiveTaskIDs: Set(schedulableTasks.map(\.id)))

    // Surface a failed/denied schedule into the diagnostics ring so a silent
    // reap-and-fail (or a permission loss) leaves an observable trace.
    await recordReminderScheduleDiagnostic(lastTaskReminderScheduleReport, kind: "Task")
    await recordReminderScheduleDiagnostic(lastHabitReminderScheduleReport, kind: "Habit")
  }

  /// Append a diagnostics-ring row when a reminder schedule failed or was denied,
  /// so the otherwise in-memory-only report is also observable via the
  /// `error_logs` feed. A `.disabled`/`.scheduled` outcome is a no-op.
  private func recordReminderScheduleDiagnostic(
    _ report: TaskReminderScheduleReport, kind: String
  ) async {
    guard report.status == .failed || report.status == .permissionDenied else { return }
    try? await core.appendDiagnosticLog(
      source: "ios.reminders.schedule",
      level: report.status == .permissionDenied ? "warn" : "error",
      message: "\(kind) reminder scheduling \(report.status.rawValue).",
      details: report.errorMessage)
  }

  /// Refill the rolling reminder window and reconcile fired cycles from the
  /// current DB, then refresh the badge — the lightweight entry point to call on
  /// app launch, on foreground, and from a background refresh task.
  ///
  /// Only the earliest ``ReminderBudget/pendingNotificationLimit`` reminders and
  /// a bounded habit horizon are armed at once; the OS frees a pending slot when
  /// each one-shot request fires, but nothing re-arms the next batch (or cancels
  /// an already-fired habit cadence's remaining same-cycle requests) unless a
  /// re-plan runs. `rescheduleReminders` re-selects the earliest-due set and
  /// reconciles fired habit cycles on every pass, so calling this as the app
  /// wakes keeps requests 61+ and later habit days from starving and stops a
  /// consumed weekly cadence from re-notifying.
  public func replenishReminderWindow() async {
    await rescheduleReminders()
    await updateBadge()
  }

  /// Updates the app-icon badge to reflect the current due/overdue task count.
  ///
  /// Clears the badge when `badgeEnabled` is false.
  func updateBadge() async {
    await updateBadge(tasks: await mobileBadgeTasks())
  }

  func updateBadge(tasks: [LorvexTask]) async {
    let coordinator = BadgeCoordinator(
      badgeEnabled: badgeEnabled,
      today: logicalTodayString,
      setBadge: setBadge
    )
    await coordinator.update(tasks: tasks)
  }

  func mobileReminderTasks() async -> [LorvexTask] {
    if let tasks = try? await core.getTasksWithUpcomingReminders(
      hoursAhead: Self.reminderSchedulingHorizonHours,
      limit: 500)
    {
      return tasks
    }
    return snapshot.today.tasks
  }

  private func mobileBadgeTasks() async -> [LorvexTask] {
    if let tasks = try? await core.getScheduledTasks(
      from: "0001-01-01",
      to: logicalTodayString,
      limit: 500)
    {
      return tasks
    }
    return snapshot.today.tasks
  }
}
