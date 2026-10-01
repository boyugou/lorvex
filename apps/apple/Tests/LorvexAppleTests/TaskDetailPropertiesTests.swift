import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// The macOS task detail's property rows, built from the store's draft: one
/// row per set field in planning order, an addition for every unset one.
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
}
