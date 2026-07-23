import LorvexCore
import SwiftUI
import Testing

@testable import LorvexApple

@Test
func lorvexWindowIDsMatchRegisteredSceneIdentifiers() {
  #expect(LorvexWindowID.main.rawValue == "main")
  #expect(LorvexWindowID.taskDetail.rawValue == "task-detail")
  // Quick Capture is retired: capture happens inline, so no popup window scene.
  #expect(!LorvexWindowID.allCases.map(\.rawValue).contains("quick-capture"))
  #expect(Set(LorvexWindowID.allCases.map(\.rawValue)).count == LorvexWindowID.allCases.count)
}

@Test
func lorvexWindowIDsProvideNativeEntrypointMetadata() {
  #expect(LorvexWindowID.main.title == "Lorvex")
  #expect(LorvexWindowID.today.windowMenuTitle == "Today Window")
  #expect(LorvexWindowID.calendar.title == "Calendar")
  #expect(LorvexWindowID.calendar.windowMenuTitle == "Calendar Window")
  #expect(LorvexWindowID.taskDetail.windowMenuTitle == "Task Detail Window")
  #expect(LorvexWindowID.detachedListTitle == "Lorvex List")
  #expect(LorvexWindowID.stickyTaskTitle == "Lorvex Sticky")
  #expect(LorvexWindowID.main.systemImage == "checklist.checked")
  #expect(LorvexWindowID.calendar.systemImage == "calendar")
  #expect(LorvexWindowID.taskDetail.systemImage == "sidebar.right")
}

@Test
func lorvexWindowIDsOwnMinimumContentSizes() {
  #expect(LorvexWindowID.main.minimumContentSize.width == 1000)
  #expect(LorvexWindowID.main.minimumContentSize.height == 600)
  #expect(LorvexWindowID.tasks.minimumContentSize.width == 660)
  #expect(LorvexWindowID.lists.minimumContentSize.width == 660)
  #expect(LorvexWindowID.reviews.minimumContentSize.width == 700)
  #expect(LorvexWindowID.taskDetail.minimumContentSize.width == 480)

  for windowID in LorvexWindowID.allCases {
    #expect(windowID.minimumContentSize.width >= 320)
    #expect(windowID.minimumContentSize.height >= 160)
  }
}

@Test
func lorvexWorkspaceWindowsCoverDedicatedWorkspaceScenes() {
  #expect(
    LorvexWindowID.workspaceWindows == [
      .today,
      .calendar,
      .tasks,
      .lists,
      .habits,
      .reviews,
    ])
  #expect(!LorvexWindowID.workspaceWindows.contains(.main))
  #expect(!LorvexWindowID.workspaceWindows.contains(.taskDetail))
  // Each workspace window has a ⇧⌘1-6 accelerator matching its menu position.
  #expect(LorvexWindowID.today.keyboardShortcut == "1")
  #expect(LorvexWindowID.calendar.keyboardShortcut == "2")
  #expect(LorvexWindowID.tasks.keyboardShortcut == "3")
  #expect(LorvexWindowID.lists.keyboardShortcut == "4")
  #expect(LorvexWindowID.habits.keyboardShortcut == "5")
  #expect(LorvexWindowID.reviews.keyboardShortcut == "6")
  #expect(LorvexWindowID.main.keyboardShortcut == nil)
  #expect(LorvexWindowID.taskDetail.keyboardShortcut == nil)
}

@Test
func lorvexRefreshOnOpenWindowsCoverDataBackedScenes() {
  #expect(
    LorvexWindowID.refreshOnOpenWindows == [
      .today,
      .calendar,
      .tasks,
      .lists,
      .habits,
      .reviews,
      .taskDetail,
    ])
  #expect(!LorvexWindowID.refreshOnOpenWindows.contains(.main))
}

@MainActor
@Test
func lorvexWorkspaceWindowViewAcceptsEveryRefreshOnOpenWindow() async throws {
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    taskSearchIndexer: NoopTaskSearchIndexer(),
    widgetSnapshotPublisher: NoopWidgetSnapshotPublisher()
  )

  for windowID in LorvexWindowID.refreshOnOpenWindows {
    _ = LorvexWorkspaceWindowView(windowID: windowID, store: store)
  }
}

@MainActor
@Test
func lorvexSystemSurfaceViewsAcceptStoreAndSettings() async throws {
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    taskSearchIndexer: NoopTaskSearchIndexer(),
    widgetSnapshotPublisher: NoopWidgetSnapshotPublisher()
  )
  let suiteName = "LorvexWindowIDTests.systemSurface.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let settings = AppSettingsStore(defaults: defaults)

  _ = LorvexMenuBarExtraView(store: store)
  _ = LorvexSettingsWindowView(settings: settings, store: store)
}

@MainActor
@Test
func lorvexSceneSizingModifiersComposeOnWindowGroups() {
  _ = WindowGroup("Sizing Test") {
    Text("Sizing")
  }
  .lorvexDefaultWindowPosition()

  _ = Window("Main Sizing Test", id: "main-sizing-test") {
    Text("Main Sizing")
  }
  .lorvexDefaultWindowPosition()
  .lorvexMainWindowSizing()
}

@MainActor
@Test
func lorvexWorkspaceScenesAcceptStore() async throws {
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    taskSearchIndexer: NoopTaskSearchIndexer(),
    widgetSnapshotPublisher: NoopWidgetSnapshotPublisher()
  )

  _ = lorvexWorkspaceScenes(store: store)
}

@MainActor
@Test
func lorvexDetachedScenesAcceptStore() async throws {
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    taskSearchIndexer: NoopTaskSearchIndexer(),
    widgetSnapshotPublisher: NoopWidgetSnapshotPublisher()
  )

  _ = lorvexDetachedScenes(store: store)
}

@MainActor
@Test
func lorvexPrimaryAndSystemScenesAcceptStoreAndSettings() async throws {
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    taskSearchIndexer: NoopTaskSearchIndexer(),
    widgetSnapshotPublisher: NoopWidgetSnapshotPublisher()
  )
  let suiteName = "LorvexWindowIDTests.scenes.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let settings = AppSettingsStore(defaults: defaults)

  _ = lorvexPrimaryScenes(store: store, settings: settings) {}
  _ = lorvexSystemScenes(store: store, settings: settings)
}
