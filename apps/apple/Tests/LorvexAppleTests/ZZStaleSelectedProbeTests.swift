import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// Scratch probe (git-excluded): which selected-task actions leave the
// inspector's copy of the task stale?

@MainActor
@Test
func zzStaleSelectedProbe() async throws {
  guard ProcessInfo.processInfo.environment["STALE_PROBE"] != nil else { return }
  func fresh() async throws -> (AppStore, SwiftLorvexCoreService, LorvexTask) {
    let core = try await makeSeededInMemoryCore()
    let store = AppStore(core: core)
    await store.refresh()
    let task = try #require(store.today.tasks.first { $0.status == .open && $0.plannedDate == nil })
    store.selectOnlyTodayTask(task.id)
    store.syncSelectedTaskDraft()
    await store.loadSelectedTaskDetail()
    return (store, core, task)
  }
  func report(_ name: String, _ store: AppStore, _ core: SwiftLorvexCoreService, _ id: String) async throws {
    try await report(name, store, core, id, refreshed: false)
    await store.refresh()
    await store.loadDoneTodayCount()
    try await report(name, store, core, id, refreshed: true)
  }
  func report(_ name: String, _ store: AppStore, _ core: SwiftLorvexCoreService, _ id: String, refreshed: Bool) async throws {
    let stored = try await core.loadTask(id: id)
    let shown = store.selectedTask
    let stale = shown.map { $0.status != stored.status || $0.plannedDate != stored.plannedDate || $0.listID != stored.listID }
    print("STALE \(name)\(refreshed ? " [after refresh]" : ""): shown=\(shown.map { "\($0.status.rawValue) plan=\($0.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:)) ?? "-")" } ?? "nil") core=\(stored.status.rawValue) plan=\(stored.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:)) ?? "-") stale=\(String(describing: stale)) canReopen=\(store.selectedTaskCanReopen) canComplete=\(store.selectedTaskCanComplete) selectedID=\(store.selectedTaskID.map { String($0.prefix(6)) } ?? "nil")")
  }

  do {
    let (store, core, task) = try await fresh()
    await store.completeSelectedTask()
    try await report("completeSelectedTask", store, core, task.id)
  }
  do {
    let (store, core, task) = try await fresh()
    await store.deferSelectedTask()
    try await report("deferSelectedTask", store, core, task.id)
  }
  do {
    let (store, core, task) = try await fresh()
    await store.deferTaskFromRow(task, until: Date().addingTimeInterval(86_400))
    try await report("deferTaskFromRow", store, core, task.id)
  }
  do {
    let (store, core, task) = try await fresh()
    await store.toggleTaskCompletion(task)
    try await report("toggleTaskCompletion", store, core, task.id)
  }
  do {
    let (store, core, task) = try await fresh()
    await store.completeTodaySelection()
    try await report("completeTodaySelection", store, core, task.id)
  }
  do {
    let (store, core, task) = try await fresh()
    await store.deferTodaySelection()
    try await report("deferTodaySelection", store, core, task.id)
  }
  do {
    let (store, core, task) = try await fresh()
    await store.markTodaySelectionSomeday()
    try await report("markTodaySelectionSomeday", store, core, task.id)
  }
  do {
    let (store, core, task) = try await fresh()
    await store.cancelTodaySelection()
    try await report("cancelTodaySelection", store, core, task.id)
  }
  do {
    let (store, core, task) = try await fresh()
    await store.planTasks(ids: [task.id], daysFromToday: 3)
    try await report("planTasks(+3d)", store, core, task.id)
  }
  do {
    let (store, core, task) = try await fresh()
    let other = try #require(try await core.loadLists().lists.first { $0.id != task.listID }?.id)
    await store.moveTasks(ids: [task.id], toListID: other)
    try await report("moveTasks", store, core, task.id)
  }
  do {
    let (store, core, task) = try await fresh()
    await store.completeTask(id: task.id)
    try await report("completeTask(id:)", store, core, task.id)
  }
}

@MainActor
@Test
func zzReopenRecurringProbe() async throws {
  guard ProcessInfo.processInfo.environment["REOPEN_PROBE"] != nil else { return }
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  let weekly = try #require(store.today.tasks.first { $0.title == "Send the weekly status update" })
  print("REOPEN weekly id=\(weekly.id.prefix(6)) recurrence=\(String(describing: weekly.recurrence)) status=\(weekly.status.rawValue)")
  _ = try await core.completeTask(id: weekly.id)
  let all = try await core.listTasks(status: "all", listID: nil, priority: nil, text: "weekly status", limit: 50, offset: 0).tasks
  print("REOPEN after first completion: \(all.map { "\($0.id.prefix(6)):\($0.status.rawValue) plan=\($0.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:)) ?? "-") due=\($0.dueDate.map(LorvexDateFormatters.ymdUTC.string(from:)) ?? "-")" })")
  // 1. Reopen the first occurrence while the successor is still active.
  do {
    _ = try await core.reopenTask(id: weekly.id)
    print("REOPEN step1 reopen(first) with active successor: ok")
    let tasks = try await core.listTasks(status: "all", listID: nil, priority: nil, text: "weekly status", limit: 50, offset: 0).tasks
    print("REOPEN after reopen: \(tasks.map { "\($0.id.prefix(6)):\($0.status.rawValue)" })")
    _ = try await core.completeTask(id: weekly.id)
  } catch { print("REOPEN step1 error: \(error)") }
  // 2. Complete the successor, then reopen the first occurrence.
  let current = try await core.listTasks(status: "open", listID: nil, priority: nil, text: "weekly status", limit: 50, offset: 0).tasks
  print("REOPEN open now: \(current.map { "\($0.id.prefix(6)):\($0.status.rawValue)" })")
  if let next = current.first(where: { $0.id != weekly.id }) {
    _ = try await core.completeTask(id: next.id)
    do {
      _ = try await core.reopenTask(id: weekly.id)
      print("REOPEN step2 reopen(first) with completed successor: ok")
    } catch {
      print("REOPEN step2 error: \(error)")
      let classified = UserFacingError.classify(error)
      print("REOPEN step2 classified: \(classified)")
    }
  }
}
