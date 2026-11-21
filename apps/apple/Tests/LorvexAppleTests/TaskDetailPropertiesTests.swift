import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// The macOS task detail's property rows, built from the store's draft: active tasks lead
/// with When. Remaining fields appear in planning order or in Add Detail.
@MainActor
@Suite("Task detail properties")
struct TaskDetailPropertiesTests {
  private func makeStore() async throws -> AppStore {
    let suiteName = "TaskDetailPropertiesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  }

  @Test("Set fields are rows in planning order; unset fields are additions")
  func setFieldsAreRowsInPlanningOrder() async throws {
    let store = try await makeStore()
    await store.refresh()
    let task = try #require(store.today.tasks.first)
    store.selectedTaskID = task.id
    store.syncSelectedTaskDraft()
    store.setTaskDetailHasPlannedDate(true)
    store.taskDetailEstimatedMinutesText = "45"
    store.setTaskDetailHasDueDate(true)
    store.taskDetailDueDatePickerDate = store.taskDetailPlannedDatePickerDate

    let content = TaskDetailView(store: store).propertyContent(task: task)
    let rowIDs = content.rows.map(\.id)

    #expect(Array(rowIDs.prefix(3)) == ["doOn", "estimate", "due"])
    #expect(Set(rowIDs).isDisjoint(with: content.additions.map(\.id)))
    // A deadline on the planned day names its own day: the row stands alone.
    #expect(content.rows.first { $0.id == "due" }?.value != "The same day")
    #expect(content.rows.first { $0.id == "estimate" }?.value.contains("45") == true)
  }

  @Test("Normal priority is not a row; it stays offered as an addition")
  func normalPriorityIsAnAddition() async throws {
    let store = try await makeStore()
    await store.refresh()
    let task = try #require(store.today.tasks.first { $0.priority == .p2 })
    store.selectedTaskID = task.id
    store.syncSelectedTaskDraft()

    let content = TaskDetailView(store: store).propertyContent(task: task)

    #expect(!content.rows.contains { $0.id == "priority" })
    #expect(content.additions.contains { $0.id == "priority" })
  }

  @Test("An active undated task can be planned from its first row without changing its deadline")
  func planFromFirstRowPreservesDeadline() async throws {
    let store = try await makeStore()
    let inbox = LorvexListNaming.inboxID
    let created = try await store.core.createTask(title: "Reserve a reading room", notes: "")
    _ = try await store.core.moveTask(id: created.id, toListID: inbox)
    await store.refresh()
    store.openTaskListScope(inbox)
    await store.loadTaskWorkspace()
    let task = try #require(store.taskWorkspaceOpenTasks.first { $0.id == created.id })
    store.selectedTaskID = task.id
    store.syncSelectedTaskDraft()
    store.setTaskDetailHasPlannedDate(false)
    store.setTaskDetailHasDueDate(true)
    await store.saveSelectedTaskDraftIfNeeded()
    let before = try await store.core.loadTask(id: task.id)
    #expect(before.plannedDate == nil)
    #expect(before.dueDate != nil)
    let content = TaskDetailView(store: store).propertyContent(task: before)
    #expect(content.rows.first?.id == "doOn")
    #expect(!content.additions.contains { $0.id == "doOn" })
    store.setTaskDetailHasPlannedDate(true)
    store.taskDetailPlannedDatePickerDate = try #require(
      PlannedDayBridge.displayDate(forLogicalDay: "2026-12-10"))
    await store.saveSelectedTaskDraftIfNeeded()
    let saved = try await store.core.loadTask(id: task.id)
    #expect(saved.plannedDate == LorvexDateFormatters.ymdUTC.date(from: "2026-12-10"))
    #expect(saved.dueDate == before.dueDate)
    store.selectedTaskID = nil
    await store.loadTaskWorkspace()
    #expect(store.selection == .tasks)
    #expect(store.taskWorkspaceListScopeID == inbox)
    #expect(store.taskWorkspaceOpenTasks.contains { $0.id == task.id })
  }
}
