import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// What the Mac's Copy as Text and Share put on the clipboard and in the share
/// sheet for a task: the shared layout, worded from the Mac catalog, with the
/// list named from the sidebar's lists.
@MainActor
@Suite("Mac task share text")
struct AppStoreTaskShareTextTests {
  private func makeStore() async throws -> AppStore {
    let suiteName = "AppStoreTaskShareTextTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
    await store.refresh()
    return store
  }

  @Test("The text names the task's list, its fields, and its checklist in the Mac's words")
  func macShareTextNamesTheListAndFields() async throws {
    let store = try await makeStore()
    let list = try #require(store.orderedLists.first)
    let task = LorvexTask(
      id: "t", title: "Ship the release", notes: "Coordinate with QA.", aiNotes: "Blocked on review.",
      priority: .p1, status: .open, dueDate: LorvexDateFormatters.ymdUTC.date(from: "2026-09-29"),
      estimatedMinutes: 45, tags: ["work"],
      checklistItems: [TaskChecklistItem(id: "c", taskID: "t", position: 0, text: "Ask QA", completedAt: nil)],
      listID: list.id)

    let text = store.shareText(for: task)

    #expect(text.hasPrefix("Ship the release\n\nCoordinate with QA.\n\n"))
    #expect(text.contains("How long: 45 min\nDue: Tue, Sep 29, 2026\nList: \(list.displayName)\nPriority: High\nTags: work"))
    #expect(text.hasSuffix("Assistant Context\nBlocked on review.\n\nChecklist\n- [ ] Ask QA"))
  }

  @Test("A task with no list has no List line, and one with nothing set is its title alone")
  func macShareTextOfABareTask() async throws {
    let store = try await makeStore()
    let task = LorvexTask(
      id: "t", title: "Water the plants", notes: "", priority: .p2, status: .open, dueDate: nil,
      estimatedMinutes: nil, tags: [])
    #expect(store.shareText(for: task) == "Water the plants")
  }

  @Test("Several tasks follow one another with a rule between them, in the order given")
  func macShareTextOfSeveralTasks() async throws {
    let store = try await makeStore()
    func task(_ id: String, _ title: String) -> LorvexTask {
      LorvexTask(
        id: id, title: title, notes: "", priority: .p2, status: .open, dueDate: nil,
        estimatedMinutes: nil, tags: [])
    }
    let tasks = [task("a", "First"), task("b", "Second"), task("c", "Third")]
    #expect(store.shareText(for: tasks) == "First\n\n---\n\nSecond\n\n---\n\nThird")
    #expect(store.shareText(for: [tasks[1]]) == "Second")
    #expect(store.shareText(for: []) == "")
  }

  @Test("⌘C copies the highlighted tasks from every task list that ⌫ cancels from")
  func everyTaskListCopiesItsSelection() throws {
    let views = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "Sources/LorvexApple/Views")
    for (file, surface) in [
      ("TodayView.swift", ".today"), ("TasksWorkspaceView.swift", ".taskWorkspace"),
      ("TasksTableWorkspaceView.swift", ".taskWorkspace"), ("ListDetailPane.swift", ".selectedList"),
    ] {
      let source = try String(contentsOf: views.appending(path: file), encoding: .utf8)
      let cancel = try #require(source.range(of: ".cancelSelectedTaskOnDelete(store, on: \(surface))"), "\(file)")
      let copy = try #require(source.range(of: ".copySelectedTasksAsText(store, on: \(surface))"), "\(file)")
      #expect(cancel.upperBound <= copy.lowerBound, "\(file)")
    }
    let modifier = try String(
      contentsOf: views.appending(path: "CopySelectedTasksAsText.swift"), encoding: .utf8)
    #expect(modifier.contains("onCopyCommand"))
    #expect(modifier.contains("store.shareText(for: tasks)"))
  }

  @Test("The task context menu offers Copy as Text and Share, built from the shared text")
  func contextMenuOffersCopyAndShare() throws {
    let sources = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "Sources/LorvexApple")
    let menu = try String(contentsOf: sources.appending(path: "Views/WorkspaceTaskViews.swift"), encoding: .utf8)
    #expect(menu.contains("store.copyShareText(of: task)"))
    #expect(menu.contains("ShareLink(item: store.shareText(for: task))"))
    #expect(menu.contains("\"task.action.copy_as_text\""))
    // Both sit with the other non-status actions, before the destructive pair.
    let copy = try #require(menu.range(of: "store.copyShareText(of: task)"))
    let cancel = try #require(menu.range(of: "store.requestCancel(task, undoManager: undoManager)"))
    #expect(copy.upperBound <= cancel.lowerBound)
  }
}
