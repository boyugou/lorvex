import Foundation
import Testing

@testable import LorvexApple
@testable import LorvexCore

// MARK: - Snooze action → available_from write path

@MainActor
@Test
func snoozeTaskWritesAvailableFromWithoutTouchingPlannedDate() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  let task = try await core.createTask(title: "Hide me until later", notes: "")
  let until = try #require(store.deferStorageDate(daysFromNow: 30))

  await store.snoozeTask(id: task.id, until: until)

  let reloaded = try await core.loadTask(id: task.id)
  #expect(reloaded.availableFrom == until)
  // Snooze owns available_from; defer owns planned_date. Snoozing must not
  // silently push a planned work day the way a defer would.
  #expect(reloaded.plannedDate == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func snoozeSelectedTaskWritesAvailableFrom() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  let task = try await core.createTask(title: "Snooze the selected task", notes: "")
  store.selectedTaskID = task.id
  await store.loadSelectedTaskDetail()
  let until = try #require(store.deferStorageDate(daysFromNow: 14))

  await store.snoozeSelectedTask(until: until)

  #expect(try await core.loadTask(id: task.id).availableFrom == until)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func snoozeIsInertForResolvedTasks() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  let task = try await core.createTask(title: "Already done", notes: "")
  _ = try await core.completeTask(id: task.id)
  let until = try #require(store.deferStorageDate(daysFromNow: 7))

  await store.snoozeTask(id: task.id, until: until)

  #expect(try await core.loadTask(id: task.id).availableFrom == nil)
}

// MARK: - Scheduled section (defer-until / hidden lane)

@MainActor
@Test
func scheduledSectionListsHiddenTasksAndKeepsThemOutOfOpen() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  let hidden = try await core.createTask(title: "Hidden until next month", notes: "")
  let visible = try await core.createTask(title: "Plain open task", notes: "")
  let until = try #require(store.deferStorageDate(daysFromNow: 30))
  await store.snoozeTask(id: hidden.id, until: until)

  await store.loadTaskWorkspace()

  #expect(store.taskWorkspaceScheduledTasks.map(\.id).contains(hidden.id))
  // A hidden task surfaces only under Scheduled, never doubled into open.
  #expect(!store.taskWorkspaceOpenTasks.map(\.id).contains(hidden.id))
  #expect(store.taskWorkspaceOpenTasks.map(\.id).contains(visible.id))
  #expect(!store.taskWorkspaceScheduledTasks.map(\.id).contains(visible.id))
}

@MainActor
@Test
func getHiddenScheduledTasksExcludesOverdueTasksOverdueWins() async throws {
  let core = try await makeSeededInMemoryCore()
  // available_from is in the future, but the deadline has already passed —
  // overdue-wins keeps the task in the day surfaces, never in the hidden lane.
  let overdueYesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
  let futureAvailable = Calendar.current.date(byAdding: .day, value: 10, to: Date()) ?? Date()
  let task = try await core.createTask(title: "Overdue but hidden", notes: "")
  _ = try await core.updateTask(
    id: task.id, title: task.title, notes: task.notes, priority: task.priority,
    estimatedMinutes: nil,
    dueDate: PlannedDayBridge.storageDate(forLocalInstant: overdueYesterday),
    plannedDate: nil,
    availableFrom: PlannedDayBridge.storageDate(forLocalInstant: futureAvailable),
    tags: [], dependsOn: [])

  let page = try await core.getHiddenScheduledTasks(limit: 100, offset: 0)

  #expect(!page.tasks.map(\.id).contains(task.id))
}

// MARK: - Inspector "Available from" row → save path

@MainActor
@Test
func inspectorAvailableFromRowSavesAndClearsAvailableFrom() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  let task = try await core.createTask(title: "Inspector defer-until", notes: "")
  store.selectedTaskID = task.id
  await store.loadSelectedTaskDetail()
  #expect(store.taskDetailHasAvailableFrom == false)

  let picker = Calendar.current.date(byAdding: .day, value: 20, to: Date()) ?? Date()
  store.setTaskDetailHasAvailableFrom(true)
  store.taskDetailAvailableFromPickerDate = picker
  #expect(store.selectedTaskCanSave)

  await store.saveSelectedTaskDraft()

  #expect(try await core.loadTask(id: task.id).availableFrom != nil)
  // The saved value round-trips back into the draft on re-sync.
  #expect(store.taskDetailHasAvailableFrom)

  store.setTaskDetailHasAvailableFrom(false)
  #expect(store.selectedTaskCanSave)
  await store.saveSelectedTaskDraft()

  #expect(try await core.loadTask(id: task.id).availableFrom == nil)
  #expect(store.errorMessage == nil)
}

// MARK: - LorvexTask hidden-until helpers

@Test
func hiddenUntilHelpersTrackFutureAvailableFromAndOverdueWins() throws {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let future = Calendar.current.date(byAdding: .day, value: 5, to: now) ?? now
  let past = Calendar.current.date(byAdding: .day, value: -5, to: now) ?? now

  let hidden = LorvexTask(
    id: "t1", title: "Hidden", notes: "",
    priority: .p2, status: .open, dueDate: nil,
    availableFrom: PlannedDayBridge.storageDate(forLocalInstant: future),
    estimatedMinutes: nil, tags: [])
  #expect(hidden.isHiddenUntilFuture(now: now))
  #expect(hidden.hiddenUntilShortLabel(now: now) != nil)

  let overdueHidden = LorvexTask(
    id: "t2", title: "Overdue", notes: "",
    priority: .p2, status: .open,
    dueDate: PlannedDayBridge.storageDate(forLocalInstant: past),
    availableFrom: PlannedDayBridge.storageDate(forLocalInstant: future),
    estimatedMinutes: nil, tags: [])
  // Overdue-wins: an overdue task never reads as hidden.
  #expect(!overdueHidden.isHiddenUntilFuture(now: now))
  #expect(overdueHidden.hiddenUntilShortLabel(now: now) == nil)

  let plain = LorvexTask(
    id: "t3", title: "Plain", notes: "",
    priority: .p2, status: .open, dueDate: nil,
    estimatedMinutes: nil, tags: [])
  #expect(!plain.isHiddenUntilFuture(now: now))
}

// MARK: - Source lock-ins for the macOS available_from UI wiring

private func availableFromSource(_ relativePath: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(contentsOf: root.appending(path: relativePath), encoding: .utf8)
}

@Test
func inspectorSchedulingPanelHasAvailableFromRow() throws {
  let source = try availableFromSource("Sources/LorvexApple/Views/TaskDetailMetadataSection.swift")
  #expect(source.contains(#".accessibilityIdentifier("task.detail.availableFrom")"#))
  #expect(source.contains(#"systemImage: "eye.slash""#))
  #expect(source.contains("store.taskDetailHasAvailableFrom"))
  #expect(source.contains("store.setTaskDetailHasAvailableFrom(true)"))
  #expect(source.contains("store.taskDetailAvailableFromPickerDate"))
  #expect(source.contains(#""task_detail.metadata.available_from""#))
}

@Test
func snoozeMenuIsWiredIntoContextAndDetailMenus() throws {
  let menu = try availableFromSource("Sources/LorvexApple/Views/TaskSnoozeMenu.swift")
  #expect(menu.contains("struct TaskSnoozeMenu"))
  #expect(menu.contains("let onSnooze: (Date) -> Void"))
  #expect(menu.contains("LorvexDateChip("))
  #expect(menu.contains("PlannedDayBridge.storageDate(forLocalInstant: selected)"))
  #expect(menu.contains(#".accessibilityIdentifier("task.snooze.custom.chip")"#))

  let context = try availableFromSource("Sources/LorvexApple/Views/WorkspaceTaskViews.swift")
  #expect(context.contains("TaskSnoozeMenu(store: store, onSnooze:"))
  #expect(context.contains("store.snoozeTask(id: task.id, until: date)"))

  let detail = try availableFromSource("Sources/LorvexApple/Views/TaskDetailActionsSection.swift")
  #expect(detail.contains("TaskSnoozeMenu(store: store, onSnooze:"))
  #expect(detail.contains("store.snoozeSelectedTask(until: date)"))
  #expect(detail.contains(#".accessibilityIdentifier("task.detail.snooze")"#))
}

@Test
func laterDisclosureRendersScheduledSubsection() throws {
  let components = try availableFromSource("Sources/LorvexApple/Views/TasksWorkspaceComponents.swift")
  #expect(components.contains(#""tasks.section.scheduled""#))
  #expect(components.contains("status: .scheduled"))
  #expect(components.contains("tasks: scheduledTasks"))

  let view = try availableFromSource("Sources/LorvexApple/Views/TasksWorkspaceView.swift")
  #expect(view.contains("scheduledTasks: visibleScheduledTasks"))
}

@Test
func listRowRendersHiddenUntilBadge() throws {
  let row = try availableFromSource("Sources/LorvexApple/Views/LorvexTaskRow.swift")
  #expect(row.contains("task.hiddenUntilShortLabel()"))
  #expect(row.contains(#"Image(systemName: "eye.slash")"#))
  #expect(row.contains(#""task.row.hidden_until""#))
}
