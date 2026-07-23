import Foundation
import LorvexCore
import Testing

@Test
func previewSetTaskRecurrenceStoresRule() async throws {
  let service = try await makeSeededInMemoryCore()
  let rule = TaskRecurrenceRule(freq: .weekly, interval: 2, byDay: ["MO", "WE"])
  let task = try await service.setTaskRecurrence(
    taskID: LorvexPreviewSeedID.agendaTask, rule: rule)
  #expect(task.id == LorvexPreviewSeedID.agendaTask)
  #expect(task.recurrence == rule)
  #expect(task.recurrenceExceptions.isEmpty)
}

@Test
func previewRemoveTaskRecurrenceClearsRuleAndExceptions() async throws {
  let service = try await makeSeededInMemoryCore()
  _ = try await service.setTaskRecurrence(
    taskID: LorvexPreviewSeedID.agendaTask,
    rule: TaskRecurrenceRule(freq: .weekly, interval: 2)
  )
  _ = try await service.addTaskRecurrenceException(
    taskID: LorvexPreviewSeedID.agendaTask,
    exceptionDate: "2026-06-01"
  )

  let task = try await service.removeTaskRecurrence(taskID: LorvexPreviewSeedID.agendaTask)

  #expect(task.id == LorvexPreviewSeedID.agendaTask)
  #expect(task.recurrence == nil)
  #expect(task.recurrenceExceptions.isEmpty)
}

@Test
func previewAddAndRemoveTaskRecurrenceException() async throws {
  let service = try await makeSeededInMemoryCore()
  _ = try await service.setTaskRecurrence(
    taskID: LorvexPreviewSeedID.venueTask,
    rule: TaskRecurrenceRule(freq: .daily)
  )
  let afterAdd = try await service.addTaskRecurrenceException(
    taskID: LorvexPreviewSeedID.venueTask, exceptionDate: "2026-06-01")
  #expect(afterAdd.id == LorvexPreviewSeedID.venueTask)
  // The store normalizes the default interval to an explicit 1.
  #expect(afterAdd.recurrence == TaskRecurrenceRule(freq: .daily, interval: 1))
  #expect(afterAdd.recurrenceExceptions == ["2026-06-01"])
  let afterRemove = try await service.removeTaskRecurrenceException(
    taskID: LorvexPreviewSeedID.venueTask, exceptionDate: "2026-06-01")
  #expect(afterRemove.id == LorvexPreviewSeedID.venueTask)
  #expect(afterRemove.recurrence == TaskRecurrenceRule(freq: .daily, interval: 1))
  #expect(afterRemove.recurrenceExceptions.isEmpty)
}

@Test
func previewAddTaskRecurrenceExceptionRequiresRule() async throws {
  let service = try await makeSeededInMemoryCore()
  // The agenda task carries no recurrence rule (the seeded status-update task
  // does, so an exception on it would succeed).
  await #expect(throws: (any Error).self) {
    _ = try await service.addTaskRecurrenceException(
      taskID: LorvexPreviewSeedID.agendaTask, exceptionDate: "2026-06-02")
  }
}

@Test
func previewBatchCompleteTasksMarksAllCompleted() async throws {
  let service = try await makeSeededInMemoryCore()
  // The completed tasks travel on the result's in-transaction capture; the
  // Today snapshot carries only open tasks.
  let result = try await service.batchCompleteTasks(
    ids: [LorvexPreviewSeedID.agendaTask, LorvexPreviewSeedID.venueTask]
  )
  #expect(result.changedTasks.count == 2)
  #expect(result.changedTasks.allSatisfy { $0.status == .completed })
  #expect(!result.snapshot.tasks.contains {
    [LorvexPreviewSeedID.agendaTask, LorvexPreviewSeedID.venueTask].contains($0.id)
  })
}

@Test
func previewBatchReopenTasksResetsStatus() async throws {
  let service = try await makeSeededInMemoryCore()
  _ = try await service.completeTask(id: LorvexPreviewSeedID.agendaTask)
  let snapshot = try await service.batchReopenTasks(ids: [LorvexPreviewSeedID.agendaTask]).snapshot
  let reopened = snapshot.tasks.first { $0.id == LorvexPreviewSeedID.agendaTask }
  #expect(reopened?.status == .open)
}

@Test
func previewBatchCreateTasksCreatesListScopedPriorityTasks() async throws {
  let service = try await makeSeededInMemoryCore()
  let created = try await service.batchCreateTasks([
    TaskCreateDraft(
      title: "Batch create preview one",
      notes: "Created together.",
      listID: LorvexPreviewSeedID.appleNativeList,
      priority: .p1
    ),
    TaskCreateDraft(title: "Batch create preview two", listID: LorvexPreviewSeedID.appleNativeList, priority: .p3),
  ])
  let detail = try await service.loadListDetail(id: LorvexPreviewSeedID.appleNativeList, limit: 100, offset: 0)

  #expect(created.map(\.title) == ["Batch create preview one", "Batch create preview two"])
  #expect(created.first?.priority == .p1)
  #expect(detail.tasks.map(\.id).contains(created[1].id))
}

@Test
func previewBatchCreateTasksRejectsInvalidBatchWithoutPartialCreate() async throws {
  let service = try await makeSeededInMemoryCore()
  let before = try await service.loadToday().tasks

  await #expect(throws: LorvexCoreError.self) {
    _ = try await service.batchCreateTasks([
      TaskCreateDraft(title: "Should not be created"),
      TaskCreateDraft(title: "   "),
    ])
  }

  let after = try await service.loadToday().tasks
  #expect(after.map(\.id) == before.map(\.id))
  #expect(!after.contains { $0.title == "Should not be created" })
}

@Test
func previewBatchMoveTasksReturnsMovedTasks() async throws {
  let service = try await makeSeededInMemoryCore()
  let moved = try await service.batchMoveTasks(
    ids: [LorvexPreviewSeedID.venueTask], toListID: LorvexPreviewSeedID.appleNativeList
  ).moved
  #expect(moved.map(\.id) == [LorvexPreviewSeedID.venueTask])
}

@Test
func previewBatchDeferTasksUpdatesPlannedDate() async throws {
  let service = try await makeSeededInMemoryCore()
  let target = Date(timeIntervalSince1970: 1_780_000_000)
  let snapshot = try await service.batchDeferTasks(
    ids: [LorvexPreviewSeedID.statusUpdateTask], until: target
  )
  let deferred = snapshot.tasks.first { $0.id == LorvexPreviewSeedID.statusUpdateTask }
  // Deferral pushes planned_date forward and keeps status open. Planned dates
  // are day-granular in storage: the target instant's day.
  #expect(deferred?.status == .open)
  #expect(
    deferred?.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:))
      == LorvexDateFormatters.ymdUTC.string(from: target))
}

@Test
func previewAppendToTaskBodyAddsSeparator() async throws {
  let service = try await makeSeededInMemoryCore()
  let task = try await service.appendToTaskBody(
    taskID: LorvexPreviewSeedID.agendaTask,
    additionalNotes: "Add Swift MCP host wiring."
  )
  #expect(task.notes.contains("Add Swift MCP host wiring."))
  #expect(task.notes.contains("\n\n"))
}

@Test
func previewSetTaskRemindersReplacesAll() async throws {
  let service = try await makeSeededInMemoryCore()
  _ = try await service.addTaskReminder(
    taskID: LorvexPreviewSeedID.venueTask, reminderAt: "2026-06-01T09:00:00Z"
  )
  let task = try await service.setTaskReminders(
    taskID: LorvexPreviewSeedID.venueTask,
    reminderAts: ["2026-06-02T10:00:00Z", "2026-06-03T11:00:00Z"]
  )
  #expect(task.reminders.count == 2)
  // Stored reminder instants carry millisecond precision.
  #expect(
    task.reminders.map(\.reminderAt).sorted()
      == ["2026-06-02T10:00:00.000Z", "2026-06-03T11:00:00.000Z"])
}
