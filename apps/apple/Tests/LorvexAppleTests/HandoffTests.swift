import Foundation
import LorvexCore
import SwiftUI
import Testing

@testable import LorvexApple

// MARK: - Activity type registry

@Test
func handoffActivityTypeSetContainsAllTypes() {
  #expect(LorvexActivityType.all.count == 3)
  #expect(LorvexActivityType.all.contains("com.lorvex.apple.openTask"))
  #expect(LorvexActivityType.all.contains("com.lorvex.apple.openDestination"))
  #expect(LorvexActivityType.all.contains("com.lorvex.apple.openList"))
}

// MARK: - Round-trip: openTask

@Test
func openTaskActivityRoundTrip() {
  let taskID = "task-abc-123"
  let activity = makeOpenTaskActivity(taskID: taskID)
  let parsed = parseOpenTaskActivity(activity)
  #expect(parsed == taskID)
}

@Test
func openTaskActivityRejectsWrongType() {
  let activity = NSUserActivity(activityType: "com.lorvex.apple.openDestination")
  activity.addUserInfoEntries(from: ["taskID": "task-xyz"])
  #expect(parseOpenTaskActivity(activity) == nil)
}

@Test
func openTaskActivityRejectsEmptyID() {
  let activity = NSUserActivity(activityType: LorvexActivityType.openTask)
  activity.addUserInfoEntries(from: ["taskID": ""])
  #expect(parseOpenTaskActivity(activity) == nil)
}

// MARK: - Round-trip: openDestination

@Test
func openDestinationActivityRoundTrip() {
  for selection in SidebarSelection.allCases {
    let activity = makeOpenDestinationActivity(selection: selection)
    let parsed = parseOpenDestinationActivity(activity)
    #expect(parsed == selection)
  }
}

@Test
func openDestinationActivityRejectsUnknownRawValue() {
  let activity = NSUserActivity(activityType: LorvexActivityType.openDestination)
  activity.addUserInfoEntries(from: ["destination": "nonexistent-destination"])
  #expect(parseOpenDestinationActivity(activity) == nil)
}

// MARK: - Round-trip: openList

@Test
func openListActivityRoundTrip() {
  let listID = "list-def-456"
  let activity = makeOpenListActivity(listID: listID)
  let parsed = parseOpenListActivity(activity)
  #expect(parsed == listID)
}

@Test
func openListActivityRejectsEmptyID() {
  let activity = NSUserActivity(activityType: LorvexActivityType.openList)
  activity.addUserInfoEntries(from: ["listID": ""])
  #expect(parseOpenListActivity(activity) == nil)
}

// MARK: - Routing: an openTask activity sets selectedTaskID

@MainActor
@Test
func handoffContinueOpenTaskSetsSelectedTaskID() async throws {
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    taskSearchIndexer: NoopTaskSearchIndexer(),
    widgetSnapshotPublisher: NoopWidgetSnapshotPublisher()
  )

  await store.refresh()
  let taskID = store.today.tasks.first?.id ?? "task-handoff-test"

  let activity = makeOpenTaskActivity(taskID: taskID)
  store.continueActivity(activity)

  #expect(store.selectedTaskID == taskID)
  #expect(store.selection == .tasks)
}

// MARK: - Routing: an openDestination activity sets sidebar selection

@MainActor
@Test
func handoffContinueOpenDestinationUpdatesSidebarSelection() async throws {
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    taskSearchIndexer: NoopTaskSearchIndexer(),
    widgetSnapshotPublisher: NoopWidgetSnapshotPublisher()
  )

  let activity = makeOpenDestinationActivity(selection: .lists)
  store.continueActivity(activity)

  #expect(store.selection == .lists)
}

@MainActor
@Test
func handoffContinueOpenDestinationIgnoresMalformedActivity() async throws {
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    taskSearchIndexer: NoopTaskSearchIndexer(),
    widgetSnapshotPublisher: NoopWidgetSnapshotPublisher()
  )
  store.selection = .habits

  let activity = NSUserActivity(activityType: LorvexActivityType.openDestination)
  // No userInfo set — parser should return nil and store should remain unchanged.
  store.continueActivity(activity)

  #expect(store.selection == .habits)
}

@MainActor
@Test
func mainWindowLifecycleModifierAcceptsOpenMainWindowCallback() async throws {
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    taskSearchIndexer: NoopTaskSearchIndexer(),
    widgetSnapshotPublisher: NoopWidgetSnapshotPublisher()
  )

  _ = Text("main").lorvexMainWindowLifecycle(store) {}
}

@MainActor
@Test
func mainWindowViewAcceptsStoreSettingsAndOpenMainWindowCallback() async throws {
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    taskSearchIndexer: NoopTaskSearchIndexer(),
    widgetSnapshotPublisher: NoopWidgetSnapshotPublisher()
  )
  let suiteName = "HandoffTests.mainWindow.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let settings = AppSettingsStore(defaults: defaults)

  _ = LorvexMainWindowView(store: store, settings: settings) {}
}
