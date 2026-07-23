import Foundation
import GRDB
import Testing

@testable import LorvexApple
@testable import LorvexCore

// Task-reminder scheduling and the Dock badge read the full schedulable task
// pool (`appleSurfaceTasks`), not the possibly-stale Today snapshot, so a task
// created or scheduled after the last refresh still gets a reminder and is
// counted in the badge.

@MainActor
@Test
func appStoreSchedulesTaskRemindersOutsideStaleTodaySnapshot() async throws {
  let scheduler = RecordingTaskReminderScheduler()
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(
    core: core,
    taskReminderScheduler: scheduler
  )

  await store.refresh()
  let created = try await core.createTask(title: "Scheduled stale outside task", notes: "")
  let reminderAt = LorvexDateFormatters.iso8601.string(from: Date(timeIntervalSinceNow: 3600))
  _ = try await core.setTaskReminders(taskID: created.id, reminderAts: [reminderAt])
  #expect(store.today.tasks.contains { $0.id == created.id } == false)

  await store.rescheduleTodayTaskReminders()

  #expect(await scheduler.lastScheduledIDs().contains(created.id))
}

@MainActor
@Test
func appStoreDoesNotRearmDeliveredReminderAfterTimezoneReanchor() async throws {
  let scheduler = RecordingTaskReminderScheduler()
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core, taskReminderScheduler: scheduler)

  let task = try await core.createTask(title: "Already delivered", notes: "")
  let reminderAt = LorvexDateFormatters.iso8601.string(
    from: Date(timeIntervalSinceNow: 3600))
  let updated = try await core.setTaskReminders(
    taskID: task.id, reminderAts: [reminderAt])
  let reminder = try #require(updated.reminders.first)
  try core.write { db in
    try db.execute(
      sql: """
        INSERT INTO task_reminder_delivery_state
          (reminder_id, last_delivered_at, last_armed_at, delivery_state, updated_at)
        VALUES (?, ?, ?, 'delivered', ?)
        """,
      arguments: [
        reminder.id, reminderAt, reminderAt, reminderAt,
      ])
  }

  await store.rescheduleTodayTaskReminders()

  #expect(await scheduler.lastScheduledReminderIDs().contains(reminder.id) == false)
}

@MainActor
@Test
func appStoreBadgeCountsTasksOutsideStaleTodaySnapshot() async throws {
  let recorder = RecordingBadgeSetter()
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(
    core: core,
    setBadge: { count in await recorder.set(count) }
  )

  await store.refresh()
  var created = try await core.createTask(title: "Badge stale outside task", notes: "")
  created = try await core.updateTask(
    id: created.id,
    title: created.title,
    notes: created.notes,
    priority: created.priority,
    estimatedMinutes: created.estimatedMinutes,
    plannedDate: PlannedDayBridge.storageDate(forLocalInstant: Date()),
    tags: created.tags,
    dependsOn: created.dependsOn)
  #expect(store.today.tasks.contains { $0.id == created.id } == false)

  await store.updateBadge()

  #expect(await recorder.lastCount() == BadgeCoordinator.badgeCount(
    tasks: await store.appleSurfaceTasks() ?? [],
    today: AppStore.todayDateString()))
  #expect((await recorder.lastCount() ?? 0) > BadgeCoordinator.badgeCount(
    tasks: store.today.tasks,
    today: AppStore.todayDateString()))
}

// After an inbound CloudKit cycle applies remote changes, the reminder/badge
// surfaces must be re-planned from the post-apply DB. Otherwise a task completed
// (or cancelled/deferred) on another device keeps its local notification armed
// and fires on this Mac. `republishSurfacesAfterInboundSync` is the recompute
// the cycle runs when it fetched records; this exercises that recompute drops a
// now-inactive task's reminder.
@MainActor
@Test
func appStoreRepublishAfterInboundDropsRemindersForRemotelyCompletedTask() async throws {
  let scheduler = RecordingTaskReminderScheduler()
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(
    core: core,
    taskReminderScheduler: scheduler
  )
  await store.refresh()

  let task = try await core.createTask(title: "Remote-completed task", notes: "")
  let reminderAt = LorvexDateFormatters.iso8601.string(from: Date(timeIntervalSinceNow: 3600))
  _ = try await core.setTaskReminders(taskID: task.id, reminderAts: [reminderAt])
  await store.republishSurfacesAfterInboundSync()
  #expect(await scheduler.lastScheduledIDs().contains(task.id))

  // Simulate the post-inbound state: the task was completed on another device.
  _ = try await core.completeTask(id: task.id)
  await store.republishSurfacesAfterInboundSync()
  #expect(await scheduler.lastScheduledIDs().contains(task.id) == false)
}

// After a local in-app task mutation (complete/cancel/defer), the reminder/badge
// surfaces must be re-planned from the post-mutation DB. Without this, a completed
// task's local notification stays armed and can fire on the Mac while the app is
// still in the foreground. `republishSurfacesAfterLocalMutation` is the recompute
// every mutation tail routes through; this exercises that it drops a now-inactive
// task's reminder.
@MainActor
@Test
func appStoreRepublishAfterLocalMutationDropsReminderForCompletedTask() async throws {
  let scheduler = RecordingTaskReminderScheduler()
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(
    core: core,
    taskReminderScheduler: scheduler
  )
  await store.refresh()

  let task = try await core.createTask(title: "Locally completed task", notes: "")
  let reminderAt = LorvexDateFormatters.iso8601.string(from: Date(timeIntervalSinceNow: 3600))
  _ = try await core.setTaskReminders(taskID: task.id, reminderAts: [reminderAt])
  await store.republishSurfacesAfterLocalMutation()
  #expect(await scheduler.lastScheduledIDs().contains(task.id))

  // Simulate in-app completion: the task is completed locally in the DB.
  _ = try await core.completeTask(id: task.id)
  await store.republishSurfacesAfterLocalMutation()
  #expect(await scheduler.lastScheduledIDs().contains(task.id) == false)
}

// M1: a task parked as `someday` is not armed on macOS and drops out of the
// upcoming-reminder query, matching iOS and the due/upcoming/mark-delivered
// queries (all `status = 'open'`). macOS previously armed `someday` reminders
// via an `.isActive` schedulable filter, firing notifications for parked tasks.
// The reminder row is not deleted — it re-arms when the task reopens.
@MainActor
@Test
func appStoreDoesNotArmRemindersForSomedayTask() async throws {
  let scheduler = RecordingTaskReminderScheduler()
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(
    core: core,
    taskReminderScheduler: scheduler
  )
  await store.refresh()

  let task = try await core.createTask(title: "Someday-parked task", notes: "")
  let reminderAt = LorvexDateFormatters.iso8601.string(from: Date(timeIntervalSinceNow: 3600))
  _ = try await core.setTaskReminders(taskID: task.id, reminderAts: [reminderAt])
  await store.republishSurfacesAfterLocalMutation()
  #expect(await scheduler.lastScheduledIDs().contains(task.id))
  #expect(
    try await core.getUpcomingTaskReminders(hoursAhead: 48, limit: 50)
      .contains { $0.taskID == task.id })

  // Park the task as someday: it drops out of both the armed set and the
  // upcoming-reminder query.
  _ = try await core.markTaskSomeday(id: task.id)
  await store.republishSurfacesAfterLocalMutation()
  #expect(await scheduler.lastScheduledIDs().contains(task.id) == false)
  #expect(
    try await core.getUpcomingTaskReminders(hoursAhead: 48, limit: 50)
      .contains { $0.taskID == task.id } == false)

  // Reopening the task re-arms the still-present reminder row.
  _ = try await core.reopenTask(id: task.id)
  await store.republishSurfacesAfterLocalMutation()
  #expect(await scheduler.lastScheduledIDs().contains(task.id))
}
