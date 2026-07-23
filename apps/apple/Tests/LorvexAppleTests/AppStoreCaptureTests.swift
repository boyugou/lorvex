import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexApple

@MainActor
@Test
func appStoreCreatesTaskThroughSharedCapturePath() async throws {
  let suiteName = "appStoreCreatesTaskThroughSharedCapturePath.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

  await store.refresh()
  store.draftTitle = "Captured from native quick capture"
  store.draftNotes = "Shared by window, toolbar, and menu bar."
  await store.createDraftTask()

  #expect(store.selectedTask?.title == "Captured from native quick capture")
  #expect(store.selectedTask?.notes == "Shared by window, toolbar, and menu bar.")
  // Today keeps the canonical sort (priority first), so the new P2 capture
  // lands in the pool but not necessarily at the top.
  #expect(store.today.tasks.contains { $0.id == store.selectedTaskID })
  #expect(store.selection == .today)
  #expect(store.draftTitle == "")
  #expect(store.draftNotes == "")
  #expect(store.errorMessage == nil)
}

@Test
func captureTitleParserKeepsOnlyTrimmedNonEmptyLines() {
  #expect(
    CaptureTitleParser.titles(from: " first task \n\n\tsecond task\n ") == [
      "first task",
      "second task",
    ]
  )
}

@MainActor
@Test
func appStoreCreatesMultipleTasksFromMultilineQuickCapture() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  store.draftTitle = " First native batch task \n\nSecond native batch task "
  store.draftNotes = "Captured from one quick-capture brain dump."
  await store.createDraftTask()

  let first = try #require(store.today.tasks.first { $0.title == "First native batch task" })
  let second = try #require(store.today.tasks.first { $0.title == "Second native batch task" })
  #expect(first.notes == "Captured from one quick-capture brain dump.")
  #expect(second.notes == "Captured from one quick-capture brain dump.")
  #expect(store.selectedTaskID == first.id)
  #expect(store.draftTitle == "")
  #expect(store.draftNotes == "")
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func createTaskInInboxStaysOnCurrentSurfaceForInlineAdd() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  store.selection = .tasks
  store.selectedTaskID = nil
  let selectionBefore = store.selectedTaskID

  await store.createTaskInInbox(title: "  Inline all-tasks add  ")

  let created = store.today.tasks.first { $0.title == "Inline all-tasks add" }
  // The inline all-tasks quick-add lands the task but stays in place: unlike
  // the global capture it must not navigate to Today or select the new task,
  // so consecutive Returns keep adding without yanking the view.
  #expect(created != nil)
  #expect(store.selection == .tasks)
  #expect(store.selectedTaskID == selectionBefore)
  #expect(store.selectedTaskID != created?.id)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func requestQuickAddFocusBumpsTokenMonotonically() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  let start = store.quickAddFocusToken

  store.requestQuickAddFocus()
  store.requestQuickAddFocus()

  #expect(store.quickAddFocusToken == start + 2)
}
