import LorvexCore

extension MobileStore {
  /// Re-plans this device's task and habit reminder notifications under one
  /// shared budget (``ReminderReplan``) and keeps the reports for Settings ›
  /// Diagnostics. A failed read leaves the pending notifications as they were;
  /// a pass that stopped before habits keeps the previous habit report, which
  /// still describes them.
  func rescheduleReminders() async {
    let signpost = LorvexSignpost.begin(.notificationsReplace)
    defer { LorvexSignpost.end(signpost) }
    let outcome = await ReminderReplan.run(
      core: core, taskScheduler: taskReminderScheduler, habitScheduler: habitReminderScheduler,
      includeTaskNotes: await loadShowTaskNotesInNotificationsPreference(),
      setupCompleted: isSetupCompleted,
      authorizationStatus: notificationAuthorizationStatusProvider, now: now,
      diagnosticSource: "ios.reminders.schedule")
    lastTaskReminderScheduleReport = outcome.taskReport
    if let habitReport = outcome.habitReport {
      lastHabitReminderScheduleReport = habitReport
    }
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

  /// The tasks the badge counts from: every actionable task the day surfaces
  /// show, read uncapped so the count stays exact however many tasks rank
  /// ahead of an overdue one. Falls back to the Today snapshot, which holds the
  /// day's due and overdue tasks, when the read fails.
  private func mobileBadgeTasks() async -> [LorvexTask] {
    if let source = try? await core.loadWidgetStatsSource() {
      return source.actionableTasks
    }
    return snapshot.today.tasks
  }
}
