import Foundation
import LorvexCore
import Testing

// MARK: - getDependencyGraph

@Test
func previewGetDependencyGraphReturnsAllActiveByDefault() async throws {
  let service = try await makeSeededInMemoryCore()
  let graph = try await service.getDependencyGraph(
    rootTaskID: nil, listID: nil, includeInactive: false)
  // All preview tasks are open/someday — graph should include all of them.
  #expect(!graph.nodes.isEmpty)
  #expect(graph.truncated == false)
}

@Test
func previewGetDependencyGraphIncludesInactiveWhenRequested() async throws {
  let service = try await makeSeededInMemoryCore()
  let withActive = try await service.getDependencyGraph(
    rootTaskID: nil, listID: nil, includeInactive: false)
  let withAll = try await service.getDependencyGraph(
    rootTaskID: nil, listID: nil, includeInactive: true)
  // At minimum should have at least as many nodes when inactive included.
  #expect(withAll.nodes.count >= withActive.nodes.count)
}

@Test
func previewGetDependencyGraphRootedAtMissingIDReturnsEmpty() async throws {
  let service = try await makeSeededInMemoryCore()
  let graph = try await service.getDependencyGraph(
    rootTaskID: "task-does-not-exist", listID: nil, includeInactive: false)
  #expect(graph.nodes.isEmpty)
  #expect(graph.edges.isEmpty)
}

@Test
func previewGetDependencyGraphEdgesReflectDependsOn() async throws {
  let service = try await makeSeededInMemoryCore()
  // Update one task to depend on another.
  _ = try await service.updateTask(
    id: LorvexPreviewSeedID.venueTask,
    title: "Validate Swift MCP stdio host",
    notes: "",
    priority: .p1,
    estimatedMinutes: nil,
    plannedDate: nil,
    tags: [],
    dependsOn: [LorvexPreviewSeedID.statusUpdateTask]
  )
  let graph = try await service.getDependencyGraph(
    rootTaskID: nil, listID: nil, includeInactive: false)
  let edge = graph.edges.first { $0.from == LorvexPreviewSeedID.venueTask && $0.to == LorvexPreviewSeedID.statusUpdateTask }
  #expect(edge != nil)
}

@Test
func previewGetDependencyGraphListScopeKeepsCrossListBlockersVisible() async throws {
  let service = try await makeSeededInMemoryCore()
  // The seed already has venueTask -> agendaTask; pointing agendaTask back at
  // venueTask would be a (rejected) cycle, so the cross-list blocker is a
  // fresh inbox task.
  let blocker = try await service.createTask(title: "Cross-list blocker", notes: "")
  _ = try await service.updateTask(
    id: LorvexPreviewSeedID.agendaTask,
    title: "Define Apple-native Lorvex architecture",
    notes: "",
    priority: .p1,
    estimatedMinutes: nil,
    plannedDate: nil,
    tags: [],
    dependsOn: [blocker.id]
  )
  let graph = try await service.getDependencyGraph(
    rootTaskID: LorvexPreviewSeedID.agendaTask, listID: LorvexPreviewSeedID.appleNativeList, includeInactive: false)
  // The rooted graph walks both directions: the blocker (dependency) and the
  // seeded venue task, which itself depends on the agenda task.
  #expect(
    Set(graph.nodes.map(\.id))
      == [LorvexPreviewSeedID.agendaTask, LorvexPreviewSeedID.venueTask, blocker.id])
  #expect(graph.nodes.first(where: { $0.id == LorvexPreviewSeedID.agendaTask })?.listID == LorvexPreviewSeedID.appleNativeList)
  #expect(graph.nodes.first(where: { $0.id == blocker.id })?.listID == "inbox")
}

// MARK: - getUpcomingTasks

@Test
func previewGetUpcomingTasksReturnsEmptyWithNodueDates() async throws {
  let service = try await makeSeededInMemoryCore()
  // Default preview tasks have no due dates, so upcoming returns empty.
  let tasks = try await service.getUpcomingTasks(daysAhead: 7, limit: 100)
  #expect(tasks.isEmpty)
}

@Test
func previewGetUpcomingTasksReturnsTasksWithDueDateInWindow() async throws {
  let service = try await makeSeededInMemoryCore()
  let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
  _ = try await service.updateTask(
    id: LorvexPreviewSeedID.agendaTask,
    title: "Define Apple-native Lorvex architecture",
    notes: "",
    priority: .p1,
    estimatedMinutes: nil,
    plannedDate: tomorrow,
    tags: [],
    dependsOn: []
  )
  let tasks = try await service.getUpcomingTasks(daysAhead: 7, limit: 100)
  #expect(tasks.contains { $0.id == LorvexPreviewSeedID.agendaTask })
}

@Test
func previewGetUpcomingTasksExcludesTasksBeyondWindow() async throws {
  let service = try await makeSeededInMemoryCore()
  let farFuture = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
  _ = try await service.updateTask(
    id: LorvexPreviewSeedID.venueTask,
    title: "Validate Swift MCP stdio host",
    notes: "",
    priority: .p1,
    estimatedMinutes: nil,
    plannedDate: farFuture,
    tags: [],
    dependsOn: []
  )
  let tasks = try await service.getUpcomingTasks(daysAhead: 7, limit: 100)
  #expect(!tasks.contains { $0.id == LorvexPreviewSeedID.venueTask })
}

// MARK: - listTasks

@Test
func previewListTasksFiltersByStatusListPriorityAndText() async throws {
  let service = try await makeSeededInMemoryCore()

  let result = try await service.listTasks(
    status: "open",
    listID: LorvexPreviewSeedID.appleNativeList,
    priority: 1,
    text: "offsite",
    limit: 10,
    offset: 0
  )

  #expect(result.tasks.map(\.id).contains(LorvexPreviewSeedID.agendaTask))
  #expect(result.tasks.allSatisfy { $0.status == .open && $0.priority == .p1 })
}

@Test
func previewListTasksReturnsPagedResults() async throws {
  let service = try await makeSeededInMemoryCore()

  let result = try await service.listTasks(
    status: "all",
    listID: nil,
    priority: nil,
    text: nil,
    limit: 1,
    offset: 0
  )

  #expect(result.returned == 1)
  #expect(result.totalMatching > result.returned)
  #expect(result.nextOffset == 1)
  #expect(result.truncated == true)
}

// MARK: - getDeferredTasks

@Test
func previewGetDeferredTasksReturnsDeferredTasks() async throws {
  let service = try await makeSeededInMemoryCore()
  _ = try await service.deferTask(
    id: LorvexPreviewSeedID.agendaTask,
    until: Date(timeIntervalSince1970: 1_779_494_400)
  )

  let result = try await service.getDeferredTasks(listID: nil, limit: 10, offset: 0)

  #expect(result.totalMatching == 1)
  #expect(result.tasks.first?.id == LorvexPreviewSeedID.agendaTask)
  #expect(result.truncated == false)
}

@Test
func previewGetDeferredTasksSupportsListFilter() async throws {
  let service = try await makeSeededInMemoryCore()
  _ = try await service.deferTask(
    id: LorvexPreviewSeedID.agendaTask,
    until: Date(timeIntervalSince1970: 1_779_494_400)
  )

  let matching = try await service.getDeferredTasks(
    listID: LorvexPreviewSeedID.appleNativeList,
    limit: 10,
    offset: 0
  )
  let missing = try await service.getDeferredTasks(
    listID: "inbox",
    limit: 10,
    offset: 0
  )

  #expect(matching.tasks.map(\.id).contains(LorvexPreviewSeedID.agendaTask))
  #expect(missing.tasks.isEmpty)
}

// MARK: - getDueTaskReminders

@Test
func previewGetDueTaskRemindersReturnsEmptyWithNoReminders() async throws {
  let service = try await makeSeededInMemoryCore()
  let reminders = try await service.getDueTaskReminders(asOf: nil, limit: 50)
  #expect(reminders.isEmpty)
}

@Test
func previewGetDueTaskRemindersReturnsPastReminder() async throws {
  let service = try await makeSeededInMemoryCore()
  let pastTimestamp = "2020-01-01T00:00:00Z"
  _ = try await service.addTaskReminder(
    taskID: LorvexPreviewSeedID.agendaTask, reminderAt: pastTimestamp)
  let reminders = try await service.getDueTaskReminders(asOf: nil, limit: 50)
  #expect(reminders.contains { $0.taskID == LorvexPreviewSeedID.agendaTask })
}

@Test
func previewGetDueTaskRemindersFutureReminderNotIncluded() async throws {
  let service = try await makeSeededInMemoryCore()
  let futureTimestamp = "2099-12-31T23:59:59Z"
  _ = try await service.addTaskReminder(
    taskID: LorvexPreviewSeedID.venueTask, reminderAt: futureTimestamp)
  let reminders = try await service.getDueTaskReminders(asOf: nil, limit: 50)
  #expect(!reminders.contains { $0.taskID == LorvexPreviewSeedID.venueTask })
}

// MARK: - getUpcomingTaskReminders

@Test
func previewGetUpcomingTaskRemindersReturnsEmptyWithNoReminders() async throws {
  let service = try await makeSeededInMemoryCore()
  let reminders = try await service.getUpcomingTaskReminders(hoursAhead: 24, limit: 50)
  #expect(reminders.isEmpty)
}

@Test
func previewGetUpcomingTaskRemindersReturnsNearFutureReminder() async throws {
  let service = try await makeSeededInMemoryCore()
  let soon = ISO8601DateFormatter().string(
    from: Date().addingTimeInterval(3600))  // 1 hour from now
  _ = try await service.addTaskReminder(
    taskID: LorvexPreviewSeedID.statusUpdateTask, reminderAt: soon)
  let reminders = try await service.getUpcomingTaskReminders(hoursAhead: 24, limit: 50)
  #expect(reminders.contains { $0.taskID == LorvexPreviewSeedID.statusUpdateTask })
}

@Test
func previewGetUpcomingTaskRemindersExcludesPastReminder() async throws {
  let service = try await makeSeededInMemoryCore()
  let past = "2020-01-01T00:00:00Z"
  _ = try await service.addTaskReminder(
    taskID: LorvexPreviewSeedID.venueTask, reminderAt: past)
  let reminders = try await service.getUpcomingTaskReminders(hoursAhead: 24, limit: 50)
  #expect(!reminders.contains { $0.taskID == LorvexPreviewSeedID.venueTask })
}
