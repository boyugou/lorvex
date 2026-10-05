import LorvexCore
import SwiftUI
import Testing

/// "What moved forward" lists a capped slice of the finished tasks that the
/// review's sentence counts, so the page says how many the list leaves out.
@Suite("Review moved list")
@MainActor
struct ReviewMovedListTests {
  private static func tasks(_ count: Int) -> [ReviewTaskSummary] {
    (0..<count).map {
      ReviewTaskSummary(id: "task-\($0)", title: "Finished task \($0)", status: "completed", deferCount: 0)
    }
  }

  private static func day(completed: Int, listed: Int) -> DayReviewSummary {
    DayReviewSummary(
      date: "2026-09-22", completedCount: completed, topCompleted: tasks(listed), createdCount: 0,
      dueOpenCount: 0, habitsCompleted: 0, habitsTotal: 0, eventCount: 0)
  }

  private static func week(completed: Int, listed: Int) -> WeeklyReviewSnapshot {
    WeeklyReviewSnapshot(
      windowTitle: "2026-09-21 - 2026-09-27", completedThisWeek: completed, createdThisWeek: 0,
      overdueOpen: 0, deferredOpen: 0, someday: 0, estimateCoverageRatio: nil,
      topCompleted: tasks(listed), frequentlyDeferred: [], topSomeday: [])
  }

  /// The rendered height of `view` laid out at a fixed width, in points.
  private static func height<V: View>(of view: V) -> Int? {
    let renderer = ImageRenderer(content: view.frame(width: 420).fixedSize(horizontal: false, vertical: true))
    renderer.scale = 1
    return renderer.cgImage?.height
  }

  private static func list(hidden: Int) -> LorvexReviewMovedList {
    LorvexReviewMovedList(
      label: "What moved forward", tasks: tasks(5), hiddenCount: hidden, moreLine: { "\($0) more" },
      identifier: "test.moved")
  }

  @Test("a day's hidden count is what the capped list leaves out of its finished count")
  func dayHiddenCount() {
    #expect(Self.day(completed: 6, listed: 5).hiddenCompletedCount == 1)
    #expect(Self.day(completed: 40, listed: 5).hiddenCompletedCount == 35)
    #expect(Self.day(completed: 5, listed: 5).hiddenCompletedCount == 0)
    #expect(Self.day(completed: 0, listed: 0).hiddenCompletedCount == 0)
    #expect(Self.day(completed: 3, listed: 5).hiddenCompletedCount == 0)
  }

  @Test("a week's hidden count is what the capped list leaves out of its finished count")
  func weekHiddenCount() {
    #expect(Self.week(completed: 6, listed: 5).hiddenCompletedCount == 1)
    #expect(Self.week(completed: 65, listed: 5).hiddenCompletedCount == 60)
    #expect(Self.week(completed: 5, listed: 5).hiddenCompletedCount == 0)
    #expect(Self.week(completed: 3, listed: 5).hiddenCompletedCount == 0)
  }

  @Test("the count line adds a row under a capped list and nothing under a complete one")
  func countLineAddsARow() throws {
    let complete = try #require(Self.height(of: Self.list(hidden: 0)))
    let capped = try #require(Self.height(of: Self.list(hidden: 1)))
    #expect(capped > complete)
    #expect(try #require(Self.height(of: Self.list(hidden: -2))) == complete)
  }
}
