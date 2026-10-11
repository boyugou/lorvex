import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// ⌘A on a focused Mac task list highlights every row the list shows.
@MainActor
@Suite("Select All on the Mac task lists")
struct TaskListSelectAllCommandTests {
  @Test("Select All highlights every row of Today in the column's order and leaves none out")
  func selectAllHighlightsEveryTodayRow() async throws {
    let suiteName = "TaskListSelectAllCommandTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let core = try makeInMemoryCore()
    let store = AppStore(core: core, defaults: defaults)
    let today = try #require(LorvexDateFormatters.ymdUTC.date(from: store.logicalTodayDateString))
    for title in ["First", "Second", "Third"] {
      _ = try await core.createTask(TaskCreateDraft(title: title, dueDate: today))
    }
    await store.refresh()

    let ordered = store.orderedTaskIDs(on: .today)
    #expect(ordered.count >= 3)
    #expect(store.taskSelectionCount(on: .today) <= 1)

    store.selectAllTasks(on: .today)

    #expect(store.taskSelectionCount(on: .today) == ordered.count)
    #expect(
      Set(AppStoreBatchCancelSurface.today.selectedTasks(store).map(\.id)) == Set(ordered),
      "every row the column draws is highlighted")
  }

  @Test("Select All on a list with no rows changes nothing")
  func selectAllOnAnEmptyListIsANoOp() async throws {
    let suiteName = "TaskListSelectAllCommandTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = AppStore(core: try makeInMemoryCore(), defaults: defaults)
    await store.refresh()
    #expect(store.orderedTaskIDs(on: .selectedList).isEmpty)

    store.selectAllTasks(on: .selectedList)

    #expect(store.taskSelectionCount(on: .selectedList) == 0)
  }

  @Test("⌘A is wired on the lists that draw their own rows, and not on the table that answers it itself")
  func selectAllIsWiredOnTheCustomLists() throws {
    let views = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "Sources/LorvexApple/Views")
    for (file, surface) in [
      ("TodayView.swift", ".today"), ("TasksWorkspaceView.swift", ".taskWorkspace"),
      ("ListDetailPane.swift", ".selectedList"),
    ] {
      let source = try String(contentsOf: views.appending(path: file), encoding: .utf8)
      #expect(source.contains(".selectAllTasksOnCommand(store, on: \(surface))"), "\(file)")
    }
    let table = try String(
      contentsOf: views.appending(path: "TasksTableWorkspaceView.swift"), encoding: .utf8)
    #expect(!table.contains("selectAllTasksOnCommand"))
    let modifier = try String(
      contentsOf: views.appending(path: "SelectAllTasksOnCommand.swift"), encoding: .utf8)
    #expect(modifier.contains("onCommand(#selector(NSResponder.selectAll(_:)))"))
    #expect(modifier.contains("store.selectAllTasks(on: selectionSurface)"))
  }
}
