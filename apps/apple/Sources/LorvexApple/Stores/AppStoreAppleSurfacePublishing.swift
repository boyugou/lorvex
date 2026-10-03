import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import LorvexCloudSync

extension AppStore {
  static let calendarSpotlightPastHorizonDays = 183
  static let calendarSpotlightFutureHorizonDays = 365

  /// Replaces the Spotlight task index with every task that is neither
  /// cancelled nor in the Trash, so any task, not just today's, is findable and
  /// deep-links back. The read (`loadSearchIndexTasks`) is uncapped; the index
  /// work runs off the main actor inside the indexer. Skips the replace when the
  /// read fails, so a transient query error keeps the existing index rather
  /// than shrinking it.
  func reindexTasksForSpotlight() async {
    guard let tasks = try? await core.loadSearchIndexTasks() else { return }
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

  /// Re-plans this Mac's task and habit reminder notifications under one
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
      diagnosticSource: "macos.reminders.schedule")
    lastTaskReminderScheduleReport = outcome.taskReport
    lastScheduledReminderCount = outcome.taskReport.scheduledCount
    if let habitReport = outcome.habitReport {
      lastHabitReminderScheduleReport = habitReport
    }
  }

  /// Recounts the Dock badge and the menu bar's attention count from every
  /// actionable task the day surfaces show, read uncapped
  /// (`loadWidgetStatsSource`), so the count stays exact however many tasks
  /// rank ahead of an overdue one. A failed read keeps the current counts.
  func updateBadge() async {
    guard let source = try? await core.loadWidgetStatsSource() else { return }
    await updateBadge(tasks: source.actionableTasks)
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

  /// Run local retention off the main actor, best-effort. A no-op for a
  /// non-envelope backend (previews) and swallowed on failure — retention GC
  /// must never surface an error or block the refresh. Retention commits in
  /// its own transactions, which SQLite serializes with sync applies.
  func runLocalRetentionMaintenance() async {
    guard let sync = core as? any EnvelopeSyncServicing else { return }
    let includeActiveOutboxCap = shouldIncludeActiveOutboxCap
    try? await Task.detached(priority: .utility) {
      try sync.runLocalRetentionMaintenance(
        includeActiveOutboxCap: includeActiveOutboxCap)
    }.value
  }

  /// Re-plan reminders, the badge, and the widget snapshot from the current DB
  /// after any local in-app task or habit mutation, then start a sync pass that
  /// sends the outbox. Advances ``taskDataGeneration`` first, so a view that
  /// reads tasks outside the published collections re-reads them.
  ///
  /// Local mutations write to the DB but don't automatically update the reminder
  /// schedule or the dock badge, so a completed/cancelled/deferred task's
  /// notification stays armed (and can fire on this Mac while the app is still
  /// open) and the badge stays wrong until the next refresh. An inbound sync
  /// re-plans the same surfaces in its selective reload
  /// (``performSelectiveInboundReload(_:)``). Each surface reads its own
  /// source, so a failed read leaves only that surface as it was, and the sync
  /// outbox drains regardless. The snapshot write is
  /// best-effort so a transient App-Group write failure doesn't surface a modal
  /// on an otherwise-successful mutation.
  ///
  /// The local work is awaited and the pass is not: a pass lasts a CloudKit
  /// round trip with no deadline, and a caller that plays feedback, registers
  /// an undo step, or holds a busy flag after this returns would otherwise
  /// wait that long. Passes started while one runs coalesce into one trailing
  /// pass (``runCloudSyncCycle()``).
  func republishSurfacesAfterLocalMutation() async {
    taskDataGeneration &+= 1
    await runLocalRetentionMaintenance()
    async let reminders: Void = rescheduleReminders()
    async let badge: Void = updateBadge()
    _ = await (reminders, badge)
    try? await publishWidgetSnapshot()
    Task { await self.runCloudSyncCycle() }
  }
}
