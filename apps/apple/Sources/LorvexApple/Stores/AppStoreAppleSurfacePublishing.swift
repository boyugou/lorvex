import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import UserNotifications
import LorvexCloudSync

extension AppStore {
  static let calendarSpotlightPastHorizonDays = 183
  static let calendarSpotlightFutureHorizonDays = 365
  static let taskReminderSchedulingHorizonHours = 24 * 365

  /// Days of habit reminders pre-scheduled per re-plan. The OS fires each
  /// one-shot trigger once; the refresh fan-out re-plans frequently enough that
  /// a rolling two-week window stays well ahead of the user without crowding the
  /// 64-pending-notification ceiling.
  static let habitReminderHorizonDays = 14

  /// Replaces the Spotlight task index with every non-cancelled task, so any task
  /// — not just today's — is findable and deep-links back. Reads live data through
  /// the core `listTasks(status:)` query path; the index work runs off the main
  /// actor inside the indexer. Skips the replace when the bulk read fails so a
  /// transient query error keeps the existing index rather than shrinking it.
  func reindexTasksForSpotlight() async {
    guard let tasks = await appleSurfaceTasks() else { return }
    await reindexTasksForSpotlight(tasks: tasks)
  }

  func reindexTasksForSpotlight(tasks: [LorvexTask]) async {
    let signpost = LorvexSignpost.begin(.spotlightReplace)
    defer { LorvexSignpost.end(signpost) }
    let searchableTasks = tasks.filter { $0.status != .cancelled }
    do {
      try await taskSearchIndexer.replaceIndexedTasks(searchableTasks)
      lastSpotlightIndexedTaskCount = searchableTasks.count
      lastSpotlightTaskIndexErrorMessage = nil
    } catch {
      lastSpotlightTaskIndexErrorMessage = error.localizedDescription
    }
  }

  func reindexContentForSpotlight() async {
    let signpost = LorvexSignpost.begin(.spotlightReplace)
    defer { LorvexSignpost.end(signpost) }
    let allLists = lists?.lists ?? []
    do {
      try await contentSearchIndexer.replaceIndexedLists(allLists)
      let allHabits = (habits?.habits ?? []).filter { !$0.archived }
      try await contentSearchIndexer.replaceIndexedHabits(allHabits)
      try await contentSearchIndexer.replaceIndexedDailyReview(dailyReview)
      let calendarEvents = try await calendarEventsForSpotlight()
      try await contentSearchIndexer.replaceIndexedCalendarEvents(calendarEvents)
      lastSpotlightIndexedCalendarEventCount = calendarEvents.count
      lastSpotlightContentIndexErrorMessage = nil
    } catch {
      lastSpotlightContentIndexErrorMessage = error.localizedDescription
    }
  }

  func calendarEventsForSpotlight() async throws -> [CalendarTimelineEvent] {
    let anchor = now()
    let from = Self.dateString(days: -Self.calendarSpotlightPastHorizonDays, from: anchor)
    let to = Self.dateString(days: Self.calendarSpotlightFutureHorizonDays, from: anchor)
    let events = try await core.loadCalendarTimeline(from: from, to: to).events
    let representatives = CalendarTimelineEvent.stableSourceRepresentatives(in: events)
    var hydrated: [CalendarTimelineEvent] = []
    hydrated.reserveCapacity(representatives.count)
    for representative in representatives {
      if representative.editable,
        let event = try await core.getCalendarEvent(id: representative.eventID)
      {
        hydrated.append(event)
      } else {
        // Provider rows are device-local and have no canonical row lookup.
        hydrated.append(representative)
      }
    }
    return hydrated
  }

  // The task and habit reminder schedulers share the OS 64-pending-notification
  // cap, so both entry points funnel through `rescheduleReminders`, which budgets
  // the earliest-due requests across BOTH kinds before arming them. Calling the
  // two separately (or in parallel) would let each fill the cap independently and
  // race the same notification center; routing through one pass avoids both.
  func rescheduleTodayTaskReminders() async {
    await rescheduleReminders()
  }

  func rescheduleHabitReminders() async {
    await rescheduleReminders()
  }

  /// Re-plan task + habit reminder notifications under a single shared budget.
  ///
  /// Both kinds compete for the OS 64-pending-notification cap, so this gathers
  /// every schedulable candidate from both, keeps the earliest-firing
  /// ``ReminderBudget/pendingNotificationLimit`` across the combined set (so a
  /// flood of far-future reminders of one kind can't crowd out near-term ones of
  /// the other), and arms that earliest-due set while deliberately skipping the
  /// rest rather than letting the OS drop them silently. The refresh fan-out
  /// re-plans after every mutation, so a completed habit / delivered reminder
  /// drops out on the next pass.
  ///
  /// `providedTasks` lets the refresh pass its already-loaded surface set for
  /// snooze cleanup. Reminder candidates still come from the delivery-aware
  /// core query: a task snapshot does not carry this device's notification
  /// receipt, so rebuilding from it could re-arm an already-delivered reminder
  /// after a timezone re-anchor. A transient read failure leaves both kinds'
  /// pending notifications untouched (never clears them on a flaky read).
  func rescheduleReminders(tasks providedTasks: [LorvexTask]? = nil) async {
    let signpost = LorvexSignpost.begin(.notificationsReplace)
    defer { LorvexSignpost.end(signpost) }
    // Mark elapsed reminders delivered before the reads, so the MCP due-queries
    // stop re-surfacing ones the OS has already shown. Only reminders that were
    // actually armed on a prior pass (their `last_armed_at` is stamped below)
    // transition to delivered; a budgeted-out / denied / add-failed reminder
    // stays pending and remains visible. Best-effort; a failure only
    // over-returns, never blocks.
    _ = try? await core.markDueTaskRemindersDelivered(asOf: now())
    try? await core.reconcileDeliveredHabitReminders(asOf: now())

    let surfaceTasks: [LorvexTask]
    if let providedTasks {
      surfaceTasks = providedTasks
    } else if let loaded = await appleSurfaceTasks() {
      surfaceTasks = loaded
    } else {
      return
    }
    guard
      let reminderTasks = try? await core.getTasksWithUpcomingReminders(
        hoursAhead: Self.taskReminderSchedulingHorizonHours, limit: 500)
    else {
      return
    }
    // Only actionable tasks arm reminders — `open` and `in_progress` (started),
    // so starting a task does NOT cancel its reminder. This matches the
    // due/upcoming/mark-delivered core queries, which filter the actionable
    // status list. A `someday` task is parked, so filtering on `.isActionable`
    // (rather than `.isActive`, which includes `someday`) also drops parked
    // tasks' one-shot snoozes below, so a parked task never fires anything.
    let schedulableTasks = reminderTasks.filter { $0.status.isActionable }
    let showTaskNotesInNotifications = await loadShowTaskNotesInNotificationsPreference()
    let taskCandidates = taskReminderScheduler.candidates(
      for: schedulableTasks, includeNotes: showTaskNotesInNotifications)

    // If the occurrence read fails the pending set can't be reconciled, so we
    // clear habit notifications rather than leave stale ones firing, and record
    // the failure instead of swallowing it.
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
    lastScheduledReminderCount = taskReport.scheduledCount

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

    let habitReport = await habitReminderScheduler.replaceScheduledHabitReminders(
      for: gated.habits)
    lastHabitReminderScheduleReport =
      habitReadError.map { .failed(scheduledCount: 0, requestedCount: 0, error: $0) } ?? habitReport

    // Same contract for habits: record "armed through" per policy from the
    // accepted prefix (the scheduler adds requests in array order and stops on
    // the first failure) and clear every other policy's stamp. On a habit
    // occurrence-read failure the replace above already cleared all pending
    // habit notifications, so the empty map correctly clears the armed record
    // with them. The delivered reconciler only records occurrences at or
    // before this stamp, so a never-armed nudge keeps surfacing as due.
    var armedThroughByPolicyID: [String: Date] = [:]
    for occurrence in gated.habits.prefix(habitReport.scheduledCount) {
      let policyID = occurrence.policy.id
      armedThroughByPolicyID[policyID] = max(
        armedThroughByPolicyID[policyID] ?? .distantPast, occurrence.fireDate)
    }
    try? await core.replaceArmedHabitReminders(
      armedThroughByPolicyID: armedThroughByPolicyID, asOf: now())

    // Drop one-shot snoozes for tasks that are no longer active (completed/
    // cancelled here or via sync) so a snoozed reminder doesn't fire for a task
    // that's already done. The reminder reap above ignores the snooze prefix.
    await taskReminderScheduler.cancelSnoozes(
      keepingActiveTaskIDs: Set(
        surfaceTasks.filter { $0.status.isActionable }.map(\.id)))
  }

  func updateBadge() async {
    guard let tasks = await appleSurfaceTasks() else { return }
    await updateBadge(tasks: tasks)
  }

  func updateBadge(tasks: [LorvexTask]) async {
    let today = logicalTodayDateString
    // The true due-today/overdue count (independent of whether the dock badge is
    // enabled) drives the menu-bar attention chip + glyph, keeping it in step
    // with the badge instead of a separate, 10-capped, timezone-skewed count.
    menuBarAttentionCount = BadgeCoordinator.badgeCount(tasks: tasks, today: today)
    let coordinator = BadgeCoordinator(
      badgeEnabled: badgeEnabled,
      today: today,
      setBadge: setBadge
    )
    await coordinator.update(tasks: tasks)
  }

  func publishWidgetSnapshot() async throws {
    // Widgets read only the App-Group sidecar. Capture every projected surface
    // (including uncapped stats and the storage generation) from one SQLite
    // transaction instead of mixing independently refreshed in-memory views.
    guard let sourceCore = core as? any LorvexWidgetSnapshotSourceServicing else {
      throw WidgetSnapshotPublisherError.atomicSourceUnavailable
    }
    let source = try await sourceCore.loadWidgetSnapshotSource(date: nil)
    lastPublishedWidgetSnapshot = try await widgetSnapshotPublisher.publish(source: source)
  }

  func publishAppleSyncSurfaces() async {
    // Widget publication is a derived, best-effort surface. A missing/corrupt
    // App-Group sidecar or a transient file-lock failure must not prevent the
    // independent CloudKit owner from draining the canonical SQLite outbox.
    // Each subsystem records/reconciles its own state; neither is a commit
    // prerequisite for the other.
    try? await publishWidgetSnapshot()
    // A refresh follows every local mutation, so this is the debounced
    // post-write sync trigger: drain the outbox and pull remote changes. Errors
    // are recorded in the cycle's status fields, not propagated — sync is
    // invisible and best-effort.
    await runCloudSyncCycle()
  }

  /// Run local retention under the App's retained CloudSync operation gate,
  /// best-effort. A no-op for a non-envelope backend (previews) and swallowed
  /// on failure — retention GC must never surface an error or block the refresh.
  /// A coordinator-less test/preview shell keeps the direct off-actor fallback.
  func runLocalRetentionMaintenance() async {
    guard let sync = core as? any EnvelopeSyncServicing else { return }
    if let coordinator = cloudDataMaintenanceCoordinator ?? cloudSyncCoordinator {
      try? await coordinator.runLocalRetentionMaintenance(
        sync: sync,
        activeOutboxCapPolicy: { @MainActor [weak self] in
          self?.shouldIncludeActiveOutboxCap ?? false
        })
      return
    }
    let includeActiveOutboxCap = shouldIncludeActiveOutboxCap
    try? await Task.detached(priority: .utility) {
      try sync.runLocalRetentionMaintenance(
        includeActiveOutboxCap: includeActiveOutboxCap)
    }.value
  }

  /// Re-plan reminders and the badge from the current DB after an inbound sync
  /// drained remote changes outside a refresh fan-out.
  ///
  /// The sync cycle ran the reminder reschedule and badge on the pre-pull state,
  /// so a task completed, cancelled, deferred, or re-timed on another device
  /// would otherwise leave its local notification armed — it fires on this Mac
  /// (often while backgrounded) until an unrelated trigger reschedules. Reads
  /// the schedulable pool once and feeds both surfaces. `runCloudSyncCycle`
  /// calls this only when it fetched inbound records while no refresh was in
  /// flight (the post-local-mutation outbox drain); an inbound arrival during a
  /// refresh instead sets `refreshPending`, so the trailing single-flight re-run
  /// re-reads the UI, republishes the widget, and re-plans reminders/badge in one
  /// pass rather than recomputing them here and reloading again.
  func republishSurfacesAfterInboundSync() async {
    guard let tasks = await appleSurfaceTasks() else { return }
    await rescheduleReminders(tasks: tasks)
    await updateBadge(tasks: tasks)
  }

  /// Re-plan reminders, the badge, and the widget snapshot from the current DB
  /// after any local in-app task or habit mutation, then kick the sync outbox.
  ///
  /// Local mutations write to the DB but don't automatically update the reminder
  /// schedule or the dock badge, so a completed/cancelled/deferred task's
  /// notification stays armed (and can fire on this Mac while the app is still
  /// open) and the badge stays wrong until the next refresh. This mirrors
  /// `republishSurfacesAfterInboundSync` for the local-mutation path: reads the
  /// schedulable pool once and feeds reminders, badge, widget snapshot, and the
  /// cloud sync cycle in a single pass. The snapshot write is best-effort so a
  /// transient App-Group write failure doesn't surface a modal or skip the sync
  /// outbox drain on an otherwise-successful mutation.
  func republishSurfacesAfterLocalMutation() async {
    await runLocalRetentionMaintenance()
    guard let tasks = await appleSurfaceTasks() else { return }
    await rescheduleReminders(tasks: tasks)
    await updateBadge(tasks: tasks)
    try? await publishWidgetSnapshot()
    await runCloudSyncCycle()
  }

  /// Every non-cancelled task for the Apple read surfaces (Spotlight index,
  /// reminders, badge). Returns `nil` when the bulk read fails so callers keep
  /// their existing surface rather than replacing it with a shrunken today-only
  /// set; the hard 5000-task limit is the known ceiling for these surfaces.
  func appleSurfaceTasks() async -> [LorvexTask]? {
    guard
      let page = try? await core.listTasks(
        status: "all", listID: nil, priority: nil, text: nil, limit: 5000, offset: 0)
    else {
      return nil
    }
    return page.tasks
  }
}
