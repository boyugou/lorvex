import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func sidebarSelectionKeepsSettingsOutOfMainWorkspace() {
  #expect(
    SidebarSelection.allCases.map(\.rawValue) == [
      "today",
      "tasks",
      "lists",
      "calendar",
      "habits",
      "reviews",
      "memory",
    ])
}

@Test
func openIntentDestinationsCoverMainWorkspaces() {
  let destinations: [LorvexIntentDestination] = [
    .today, .tasks, .lists, .calendar, .habits, .reviews, .memory,
  ]
  #expect(destinations.map(\.sidebarSelection) == [
    .today, .tasks, .lists, .calendar, .habits, .reviews, .memory,
  ])
  #expect(Set(destinations.map(\.rawValue)).count == destinations.count)
}

@MainActor
@Test
func appStoreAppliesPendingIntentDestinationHandoff() async throws {
  let defaultsSuiteName = "appStoreAppliesPendingIntentDestinationHandoff.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: defaultsSuiteName)!
  defaults.removePersistentDomain(forName: defaultsSuiteName)
  defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
  let suiteName = "AppStoreDestinationHandoffTests.\(UUID().uuidString)"
  defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
  let seededCore = try await makeSeededInMemoryCore()
  await LorvexIntentHandoffStore.withMainActorScopedSuiteName(suiteName) {
    let store = AppStore(core: seededCore, defaults: defaults)
    let handoffStore = LorvexIntentHandoffStore()

    await store.refresh()
    handoffStore.clear()
    defer { handoffStore.clear() }
    LorvexIntentHandoff.storeDestination(.calendar)
    store.applyPendingIntentHandoff()

    #expect(store.selection == .calendar)

    store.selection = .today
    store.applyPendingIntentHandoff()
    #expect(store.selection == .today)
  }
}

@MainActor
@Test
func appStoreAppliesPendingIntentTaskHandoff() async throws {
  let defaultsSuiteName = "appStoreAppliesPendingIntentTaskHandoff.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: defaultsSuiteName)!
  defaults.removePersistentDomain(forName: defaultsSuiteName)
  defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
  let suiteName = "AppStoreTaskHandoffTests.\(UUID().uuidString)"
  defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
  let seededCore = try await makeSeededInMemoryCore()
  try await LorvexIntentHandoffStore.withMainActorScopedSuiteName(suiteName) {
    let store = AppStore(core: seededCore, defaults: defaults)
    let handoffStore = LorvexIntentHandoffStore()

    await store.refresh()
    let task = try #require(store.today.tasks.first)
    handoffStore.clear()
    defer { handoffStore.clear() }
    LorvexIntentHandoff.storeTask(task.id)
    store.applyPendingIntentHandoff()

    #expect(store.selection == .tasks)
    #expect(store.selectedTaskID == task.id)
    #expect(store.selectedTask?.id == task.id)
  }
}
