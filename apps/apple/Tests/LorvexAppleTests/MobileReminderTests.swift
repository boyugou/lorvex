import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

@MainActor
@Test
func mobileStoreAddsAndRemovesRemindersThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let task = try #require(store.snapshot.openTasks.first)
  let reminderDate = Date(timeIntervalSince1970: 1_779_494_400)

  let added = await store.addReminder(taskID: task.id, date: reminderDate)
  let reminder = try #require(store.snapshot.today.tasks.first { $0.id == task.id }?.reminders.first)

  #expect(added)
  // Stored reminder instants carry millisecond precision; compare instants.
  let parser = ISO8601DateFormatter()
  parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  #expect(parser.date(from: reminder.reminderAt) == reminderDate)

  let removed = await store.removeReminder(taskID: task.id, reminder: reminder)

  #expect(removed)
  #expect(store.snapshot.today.tasks.first { $0.id == task.id }?.reminders.isEmpty == true)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreReminderMutationsDoNotReloadPlanningSnapshots() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let listLoads = core.loadListsCallCount
  let habitLoads = core.loadHabitsCallCount
  let calendarLoads = core.loadCalendarTimelineCallCount
  let task = try #require(store.snapshot.openTasks.first)
  let reminderDate = Date(timeIntervalSince1970: 1_779_494_400)

  let added = await store.addReminder(taskID: task.id, date: reminderDate)

  #expect(added)
  #expect(core.loadListsCallCount == listLoads)
  #expect(core.loadHabitsCallCount == habitLoads)
  #expect(core.loadCalendarTimelineCallCount == calendarLoads)
  let storedReminderAt = try #require(store.selectedTask?.reminders.first?.reminderAt)
  let reminderParser = ISO8601DateFormatter()
  reminderParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  #expect(reminderParser.date(from: storedReminderAt) == reminderDate)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreSchedulesTaskRemindersOutsideStaleTodaySnapshot() async throws {
  let scheduler = RecordingTaskReminderScheduler()
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(
    core: core,
    taskReminderScheduler: scheduler
  )

  await store.refresh()
  let created = try await core.createTask(title: "Mobile scheduled stale outside task", notes: "")
  let reminderAt = LorvexDateFormatters.iso8601.string(from: Date(timeIntervalSinceNow: 3600))
  _ = try await core.setTaskReminders(taskID: created.id, reminderAts: [reminderAt])
  #expect(store.snapshot.today.tasks.contains { $0.id == created.id } == false)

  await store.rescheduleReminders()

  #expect(await scheduler.lastScheduledIDs().contains(created.id))
}

@MainActor
@Test
func mobileStoreReminderSchedulingUsesReminderBoundedTaskQuery() async throws {
  let scheduler = RecordingTaskReminderScheduler()
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(
    core: core,
    taskReminderScheduler: scheduler
  )

  await store.refresh()
  let created = try await core.preview.createTask(title: "Mobile reminder bounded query", notes: "")
  let reminderAt = LorvexDateFormatters.iso8601.string(from: Date(timeIntervalSinceNow: 3600))
  _ = try await core.preview.setTaskReminders(taskID: created.id, reminderAts: [reminderAt])
  core.listTasksCallCount = 0
  core.upcomingReminderTaskCallCount = 0

  await store.rescheduleReminders()

  #expect(core.upcomingReminderTaskCallCount == 1)
  #expect(core.listTasksCallCount == 0)
  #expect(await scheduler.lastScheduledIDs().contains(created.id))
}

@MainActor
@Test
func mobileStoreBadgeCountsTasksOutsideStaleTodaySnapshot() async throws {
  let recorder = RecordingBadgeSetter()
  let core = try await makeSeededInMemoryCore()
  let logicalDay = try #require(try await core.loadToday().logicalDay)
  let store = MobileStore(
    core: core,
    setBadge: { count in await recorder.set(count) },
    todayString: { logicalDay }
  )

  await store.refresh()
  var created = try await core.createTask(title: "Mobile badge stale outside task", notes: "")
  let today = try #require(PlannedDayBridge.storageDate(forLogicalDay: logicalDay))
  created = try await core.updateTask(
    id: created.id,
    title: created.title,
    notes: created.notes,
    priority: created.priority,
    estimatedMinutes: created.estimatedMinutes,
    plannedDate: today,
    tags: created.tags,
    dependsOn: created.dependsOn)
  #expect(store.snapshot.today.tasks.contains { $0.id == created.id } == false)

  await store.updateBadge()

  let scheduledTasks = try await core.getScheduledTasks(
    from: "0001-01-01", to: logicalDay, limit: 500)
  #expect(await recorder.lastCount() == BadgeCoordinator.badgeCount(
    tasks: scheduledTasks,
    today: logicalDay))
  #expect((await recorder.lastCount() ?? 0) > BadgeCoordinator.badgeCount(
    tasks: store.snapshot.today.tasks,
    today: logicalDay))
}

@MainActor
@Test
func mobileStorePostMutationBadgeUsesCanonicalUncappedCount() async throws {
  let recorder = RecordingBadgeSetter()
  let core = try makeInMemoryCore()
  let store = MobileStore(
    core: core,
    setBadge: { count in await recorder.set(count) },
    todayString: { "2026-05-23" }
  )

  // Seed 12 tasks planned today — more than the 10-task dashboard cap, so the
  // canonical badge source (the uncapped scheduled/overdue query) reports more
  // than the ≤10 `snapshot.today.tasks` pool would.
  let today = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(
    timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 5, day: 23)))
  var ids: [LorvexTask.ID] = []
  for index in 0..<12 {
    let created = try await core.createTask(title: "Badge task \(index)", notes: "")
    let planned = try await core.updateTask(
      id: created.id,
      title: created.title,
      notes: created.notes,
      priority: created.priority,
      estimatedMinutes: created.estimatedMinutes,
      plannedDate: today,
      tags: created.tags,
      dependsOn: created.dependsOn)
    ids.append(planned.id)
  }

  await store.refresh()
  #expect(store.snapshot.today.tasks.count == 10)  // dashboard pool is capped

  // Complete one task through the mutation path (`mutateTaskReturningToday`),
  // whose post-mutation badge update now routes through the canonical source.
  #expect(await store.completeTask(ids[0]))

  let scheduled = try await core.getScheduledTasks(
    from: "0001-01-01", to: "2026-05-23", limit: 500)
  let canonical = BadgeCoordinator.badgeCount(tasks: scheduled, today: "2026-05-23")
  let capped = BadgeCoordinator.badgeCount(
    tasks: store.snapshot.today.tasks, today: "2026-05-23")
  #expect(canonical == 11)  // 12 planned today, one now completed
  #expect(canonical > capped)  // capped is 10 — the dashboard slice
  #expect(await recorder.lastCount() == canonical)
}
