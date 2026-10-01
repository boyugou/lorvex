import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// Saving a time from the macOS task detail: the time is written with the
// planned day, kept when the day moves, and cleared when the day is turned
// off.

/// 2026-05-23 and 2026-05-24 at UTC midnight, the storage frame of planned days.
private let storageDay = Date(timeIntervalSince1970: 1_779_494_400)
private let storageNextDay = Date(timeIntervalSince1970: 1_779_580_800)

/// A store over a seeded core with the first task on Today selected and timed
/// 10:00–11:00 on `storageDay` through the detail.
@MainActor
private func makeStoreWithTimedSelection() async throws -> (AppStore, LorvexTask.ID) {
  let suiteName = "AppStoreTaskDetailTimeTests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  await store.refresh()
  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = task.id
  store.syncSelectedTaskDraft()
  store.taskDetailHasPlannedDate = true
  store.taskDetailPlannedDate = PlannedDayBridge.displayDate(forStorageDate: storageDay)
  store.taskDetailPlannedTime = 600..<660
  #expect(store.selectedTaskCanSave)
  await store.saveSelectedTaskDraft()
  return (store, task.id)
}

@MainActor
@Test
func taskDetailSavesATimeOnThePlannedDay() async throws {
  let (store, id) = try await makeStoreWithTimedSelection()

  let saved = try await store.core.loadTask(id: id)
  #expect(saved.plannedDate == storageDay)
  #expect(saved.plannedTime == 600..<660)
  #expect(store.taskDetailPlannedTime == 600..<660)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func taskDetailMovingTheDayKeepsTheTime() async throws {
  let (store, id) = try await makeStoreWithTimedSelection()

  store.taskDetailPlannedDate = PlannedDayBridge.displayDate(forStorageDate: storageNextDay)
  await store.saveSelectedTaskDraft()

  let moved = try await store.core.loadTask(id: id)
  #expect(moved.plannedDate == storageNextDay)
  #expect(moved.plannedTime == 600..<660)
}

@MainActor
@Test
func taskDetailTurningTheDayOffClearsTheTime() async throws {
  let (store, id) = try await makeStoreWithTimedSelection()

  store.taskDetailHasPlannedDate = false
  await store.saveSelectedTaskDraft()

  let cleared = try await store.core.loadTask(id: id)
  #expect(cleared.plannedDate == nil)
  #expect(cleared.plannedTime == nil)
}
