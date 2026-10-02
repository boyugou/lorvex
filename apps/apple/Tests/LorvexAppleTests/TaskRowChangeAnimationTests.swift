import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// Which changes to task rows animate: a refresh that moves a few rows does; a
/// first load, a new search, and a change over many rows replace the rows at
/// once.
struct TaskRowChangeAnimationTests {
  private static func tasks(_ numbers: Range<Int>) -> [LorvexTask] {
    numbers.map { number in
      LorvexTask(
        id: "task-\(number)",
        title: "Task \(number)",
        notes: "",
        priority: .p2,
        status: .open,
        dueDate: nil,
        estimatedMinutes: nil,
        tags: []
      )
    }
  }

  @Test("A task moving from the open section to the completed one animates")
  func oneMovedTaskAnimates() {
    let before = [Self.tasks(0..<5), [], [], [], [], []]
    let after = [Self.tasks(1..<5), [], [], Self.tasks(0..<1), [], []]
    #expect(TaskRowChangeAnimation.animates(from: before, to: after))
  }

  @Test("Rows that only reorder within their section count as no change")
  func reorderingAnimates() {
    let rows = Self.tasks(0..<100)
    #expect(TaskRowChangeAnimation.animates(from: [rows], to: [Array(rows.reversed())]))
  }

  @Test("Twenty added or removed rows animate, twenty-one apply at once")
  func rowLimit() {
    let before = [Self.tasks(0..<200)]
    #expect(TaskRowChangeAnimation.animates(from: before, to: [Self.tasks(0..<180)]))
    #expect(!TaskRowChangeAnimation.animates(from: before, to: [Self.tasks(0..<179)]))
  }

  @Test("A batch over ten tasks animates, a batch over eleven applies at once")
  func batchLimit() {
    #expect(TaskRowChangeAnimation.animates(batchOf: 10))
    #expect(!TaskRowChangeAnimation.animates(batchOf: 11))
  }

  @Test("Only a refresh of the loaded search animates the workspace's sections")
  func onlyARefreshOfTheLoadedSearchAnimates() {
    var storage = AppStoreTaskWorkspaceStorage()
    storage.openTasks = Self.tasks(0..<5)
    let refreshed = [Self.tasks(1..<5), [], [], Self.tasks(0..<1), [], []]

    // The first load has nothing to settle from.
    #expect(!storage.animatesReplacingSections(with: refreshed, query: ""))

    storage.hasLoaded = true
    storage.loadedQuery = ""
    #expect(storage.animatesReplacingSections(with: refreshed, query: ""))
    // New search results replace the old ones at once.
    #expect(!storage.animatesReplacingSections(with: refreshed, query: "offsite"))
  }
}
