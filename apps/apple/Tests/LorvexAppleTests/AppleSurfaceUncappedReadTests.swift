import Foundation
import Testing

@testable import LorvexApple
@testable import LorvexCore
@testable import LorvexMobile

// The service clamps paged task reads to 500 rows. The badges, the Spotlight
// task index, and snooze cleanup must still see every task they cover, however
// many tasks rank ahead of it in the canonical order, so each reads an
// uncapped source. The fixture holds 501 overdue tasks: one more than a page.

private let overdueTaskCount = 501

private func makeCoreWithOverdueTasksPastOnePage() async throws -> SwiftLorvexCoreService {
  let core = try makeInMemoryCore()
  let pastDay = try #require(LorvexDateFormatters.ymdUTC.date(from: "2020-01-02"))
  let drafts = (0..<overdueTaskCount).map { index in
    TaskCreateDraft(title: "Overdue \(index)", priority: .p1, dueDate: pastDay)
  }
  // One batch holds at most 500 tasks.
  _ = try await core.batchCreateTasks(Array(drafts.dropLast()))
  _ = try await core.createTask(try #require(drafts.last))
  return core
}

@MainActor
@Test("The Mac badge and menu bar count every overdue task past one page")
func macBadgeCountsEveryOverdueTaskPastOnePage() async throws {
  let core = try await makeCoreWithOverdueTasksPastOnePage()
  let recorder = RecordingBadgeSetter()
  let store = AppStore(core: core, setBadge: { await recorder.set($0) })

  await store.updateBadge()

  #expect(store.menuBarAttentionCount == overdueTaskCount)
  #expect(await recorder.lastCount() == overdueTaskCount)
}

@MainActor
@Test("The iPhone badge counts every overdue task past one page")
func phoneBadgeCountsEveryOverdueTaskPastOnePage() async throws {
  let core = try await makeCoreWithOverdueTasksPastOnePage()
  let recorder = RecordingBadgeSetter()
  let store = MobileStore(core: core, setBadge: { await recorder.set($0) })

  await store.updateBadge()

  #expect(await recorder.lastCount() == overdueTaskCount)
}

@MainActor
@Test("Spotlight indexes every task past one page, but no cancelled or trashed task")
func spotlightIndexesEveryTaskPastOnePage() async throws {
  let core = try await makeCoreWithOverdueTasksPastOnePage()
  let cancelled = try await core.createTask(title: "Dropped", notes: "")
  _ = try await core.cancelTask(id: cancelled.id)
  let trashed = try await core.createTask(title: "Trashed", notes: "")
  _ = try await core.archiveTask(id: trashed.id)
  let indexer = RecordingTaskSearchIndexer()
  let store = AppStore(core: core, taskSearchIndexer: indexer)

  await store.reindexTasksForSpotlight()

  #expect(store.lastSpotlightIndexedTaskCount == overdueTaskCount)
  let indexedIDs = Set(await indexer.lastIndexedIDs())
  #expect(indexedIDs.count == overdueTaskCount)
  #expect(!indexedIDs.contains(cancelled.id))
  #expect(!indexedIDs.contains(trashed.id))
}

// MARK: - Snooze cleanup

/// Records which snoozes the reaper cancels, over a fixed pending set.
private actor PendingSnoozeScheduler: TaskReminderScheduling {
  let pending: Set<LorvexTask.ID>
  private(set) var cancelledSets: [Set<LorvexTask.ID>] = []

  init(pending: Set<LorvexTask.ID>) {
    self.pending = pending
  }

  func scheduleReminders(_ reminders: [ScheduledTaskReminder]) async -> TaskReminderScheduleReport {
    .scheduled(reminders.count)
  }

  func pendingSnoozeTaskIDs() async -> Set<LorvexTask.ID> { pending }

  func cancelSnoozes(forResolvedTaskIDs taskIDs: Set<LorvexTask.ID>) async {
    cancelledSets.append(taskIDs)
  }
}

@Test("Snooze cleanup cancels the snoozes of done, trashed, and deleted tasks only")
func snoozeCleanupCancelsOnlyResolvedTasks() async throws {
  let core = try makeInMemoryCore()
  let open = try await core.createTask(title: "Still open", notes: "")
  let started = try await core.createTask(title: "Started", notes: "")
  _ = try await core.startTask(id: started.id)
  let done = try await core.createTask(title: "Done", notes: "")
  _ = try await core.completeTask(id: done.id)
  let trashed = try await core.createTask(title: "Trashed", notes: "")
  _ = try await core.archiveTask(id: trashed.id)
  let scheduler = PendingSnoozeScheduler(
    pending: [open.id, started.id, done.id, trashed.id, "deleted-task"])

  await scheduler.cancelSnoozesOfResolvedTasks(core: core)

  #expect(await scheduler.cancelledSets == [[done.id, trashed.id, "deleted-task"]])
}

@Test("Snooze cleanup cancels nothing while no snooze is pending")
func snoozeCleanupSkipsWithoutPendingSnoozes() async throws {
  let core = try makeInMemoryCore()
  _ = try await core.createTask(title: "Unsnoozed", notes: "")
  let scheduler = PendingSnoozeScheduler(pending: [])

  await scheduler.cancelSnoozesOfResolvedTasks(core: core)

  #expect(await scheduler.cancelledSets.isEmpty)
}
