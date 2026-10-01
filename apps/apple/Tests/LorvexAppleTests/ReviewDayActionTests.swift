import Foundation
import LorvexCore
import Testing

/// The rules behind the day review's row actions: what checking a habit in
/// does, and which still-open tasks still have a move to tomorrow to make.
@Suite("Day review actions")
struct ReviewDayActionTests {
  private static func habit(target: Int, done: Int) -> LorvexHabit {
    LorvexHabit(
      id: "h", name: "Stretch", icon: nil, color: nil, cue: nil, frequencyType: "daily",
      targetCount: target, completionsToday: done, totalCompletions: done, completionRate30d: 0,
      archived: false, position: 0)
  }

  @Test("A once-a-day habit toggles; a counted one adds one until met, then does nothing")
  func checkInRule() {
    #expect(LorvexHabitCheckIn.action(for: Self.habit(target: 1, done: 0)) == .complete)
    #expect(LorvexHabitCheckIn.action(for: Self.habit(target: 1, done: 1)) == .uncomplete)
    #expect(LorvexHabitCheckIn.action(for: Self.habit(target: 3, done: 1)) == .addOne)
    #expect(LorvexHabitCheckIn.action(for: Self.habit(target: 3, done: 3)) == LorvexHabitCheckIn.none)
    #expect(LorvexHabitCheckIn.action(for: Self.habit(target: 0, done: 0)) == .complete)
  }

  @Test("Only tasks not yet planned for tomorrow or later can move")
  func movableTasks() {
    let deferral = LorvexReviewTaskList.Deferral(
      tomorrowKey: "2026-04-06", sectionLabel: { _ in "" }, rowLabel: "") { _ in }
    func task(planned: String?) -> ReviewTaskSummary {
      ReviewTaskSummary(id: "t", title: "T", status: "open", deferCount: 0, plannedDate: planned)
    }
    #expect(deferral.canMove(task(planned: nil)))
    #expect(deferral.canMove(task(planned: "2026-04-05")))
    #expect(!deferral.canMove(task(planned: "2026-04-06")))
    #expect(!deferral.canMove(task(planned: "2026-04-09")))
  }
}
