import Foundation
import LorvexStore
import LorvexWorkflow
import Testing

@testable import LorvexCore

/// Deferring a task takes it off Today until the day it moved to, whatever
/// kept it there: a passed deadline or the started state.
@Suite("Defer leaves Today")
struct DeferLeavesTodayTests {
  private struct Fixture {
    let service: SwiftLorvexCoreService
    /// The product day the service calls today.
    let today: String

    init() throws {
      service = try SwiftLorvexCoreService.inMemory()
      today = try service.read { db in try WorkflowTimezone.todayYmdForConn(db) }
    }

    func dayKey(_ offset: Int) throws -> String {
      try #require(LorvexDateFormatters.ymdUTCAddingDays(today, days: offset))
    }

    func day(_ offset: Int) throws -> Date {
      try #require(LorvexDateFormatters.ymdUTC.date(from: try dayKey(offset)))
    }

    func task(_ title: String, due: Int? = nil, planned: Int? = nil) async throws -> LorvexTask {
      let created = try await service.createTask(title: title, notes: "")
      return try await service.updateTask(
        id: created.id, title: title, notes: "", priority: created.priority,
        estimatedMinutes: nil, dueDate: try due.map(day), plannedDate: try planned.map(day),
        availableFrom: nil, tags: [], dependsOn: [])
    }

    /// The ids on Today's list as the product day `offset` days from today
    /// reads it: the read every Today snapshot is built from.
    func todayIDs(in offset: Int = 0) throws -> [String] {
      let key = try dayKey(offset)
      return try service.read { db in
        try TaskRepo.Read.getTodayPoolTasks(db, today: key).map(\.core.id)
      }
    }
  }

  @Test("a deferred overdue task leaves Today and is back on the day it moved to")
  func overdueTaskLeavesToday() async throws {
    let fixture = try Fixture()
    let late = try await fixture.task("Reply to legal", due: -3)
    #expect(try fixture.todayIDs() == [late.id])

    let snapshot = try await fixture.service.deferTask(id: late.id, until: try fixture.day(2))

    #expect(snapshot.tasks.isEmpty)
    #expect(try fixture.todayIDs(in: 1).isEmpty)
    #expect(try fixture.todayIDs(in: 2) == [late.id])
    let upcoming = try await fixture.service.getUpcomingTasks(daysAhead: 7, limit: 20)
    #expect(upcoming.map(\.id) == [late.id])
    // The deadline is untouched: the task still reads as late wherever it is listed.
    let moved = try await fixture.service.loadTask(id: late.id)
    #expect(moved.dueDate == late.dueDate)
    #expect(moved.plannedDate == (try fixture.day(2)))
  }

  @Test("deferring a started task pauses it, so it leaves Today too")
  func startedTaskIsPaused() async throws {
    let fixture = try Fixture()
    let task = try await fixture.task("Analyze churn numbers", planned: 0)
    _ = try await fixture.service.startTask(id: task.id)
    #expect(try fixture.todayIDs() == [task.id])

    let deferred = try await fixture.service.deferTaskReturningTask(
      id: task.id, until: try fixture.day(1), reason: nil, note: nil)

    #expect(deferred.status == .open)
    #expect(deferred.plannedDate == (try fixture.day(1)))
    #expect(deferred.deferCount == 1)
    #expect(try fixture.todayIDs().isEmpty)
    #expect(try fixture.todayIDs(in: 1) == [task.id])
  }

  @Test("a started task moved to today stays started")
  func startedTaskMovedToTodayStaysStarted() async throws {
    let fixture = try Fixture()
    let task = try await fixture.task("Carry over from yesterday", planned: -1)
    _ = try await fixture.service.startTask(id: task.id)

    let moved = try await fixture.service.deferTaskReturningTask(
      id: task.id, until: try fixture.day(0), reason: nil, note: nil)

    #expect(moved.status == .inProgress)
    #expect(moved.plannedDate == (try fixture.day(0)))
    #expect(try fixture.todayIDs() == [task.id])
  }

  @Test("a batch deferral pauses the started tasks in it")
  func batchPausesStartedTasks() async throws {
    let fixture = try Fixture()
    let started = try await fixture.task("Started", planned: 0)
    let open = try await fixture.task("Open", planned: 0)
    _ = try await fixture.service.startTask(id: started.id)

    let result = try await fixture.service.batchDeferTasks(
      ids: [started.id, open.id], until: try fixture.day(1), reason: nil, note: nil)

    #expect(Set(result.changedTasks.map(\.id)) == [started.id, open.id])
    #expect(result.changedTasks.allSatisfy { $0.status == .open })
    #expect(try fixture.todayIDs().isEmpty)
  }

  @Test("a started task moved by an edit of its planned date stays on Today")
  func editingThePlannedDateKeepsAStartedTask() async throws {
    let fixture = try Fixture()
    let task = try await fixture.task("Started early", planned: 4)
    _ = try await fixture.service.startTask(id: task.id)

    #expect(try fixture.todayIDs() == [task.id])
    #expect(try await fixture.service.loadTask(id: task.id).status == .inProgress)
  }

  @Test("undoing a review move of a started task starts it again")
  func reviewUndoRestoresTheStartedState() async throws {
    let fixture = try Fixture()
    let task = try await fixture.task("Draft the plan", planned: 0)
    _ = try await fixture.service.startTask(id: task.id)
    let summary = ReviewTaskSummary(
      id: task.id, title: task.title, status: "in_progress", deferCount: 0,
      plannedDate: fixture.today)

    let changes = try await fixture.service.arrangeReviewTasks(
      [summary], reviewedOn: fixture.today, destination: .day(try fixture.dayKey(1)))
    #expect(changes.count == 1)
    #expect(try await fixture.service.loadTask(id: task.id).status == .open)

    try await fixture.service.restoreReviewTasks(changes, undo: true)

    let restored = try await fixture.service.loadTask(id: task.id)
    #expect(restored.status == .inProgress)
    #expect(restored.plannedDate == (try fixture.day(0)))
    #expect(restored.deferCount == 0)
  }

  @Test("undoing a review move restores the plan of a task that has gained a blocker")
  func reviewUndoKeepsABlockedTaskOpen() async throws {
    let fixture = try Fixture()
    let task = try await fixture.task("Draft the plan", planned: 0)
    let other = try await fixture.task("Send the invites", planned: 0)
    _ = try await fixture.service.startTask(id: task.id)
    let summaries = [task, other].map {
      ReviewTaskSummary(
        id: $0.id, title: $0.title, status: $0.id == task.id ? "in_progress" : "open",
        deferCount: 0, plannedDate: fixture.today)
    }
    let changes = try await fixture.service.arrangeReviewTasks(
      summaries, reviewedOn: fixture.today, destination: .day(try fixture.dayKey(1)))
    #expect(changes.count == 2)
    // The task cannot be started again once an unfinished task blocks it.
    let blocker = try await fixture.task("Get the budget approved")
    _ = try await fixture.service.updateTask(
      id: task.id, title: task.title, notes: "", priority: task.priority,
      estimatedMinutes: nil, dueDate: nil, plannedDate: try fixture.day(1),
      availableFrom: nil, tags: [], dependsOn: [blocker.id])

    try await fixture.service.restoreReviewTasks(changes, undo: true)

    let restored = try await fixture.service.loadTask(id: task.id)
    #expect(restored.status == .open)
    #expect(restored.plannedDate == (try fixture.day(0)))
    #expect(restored.deferCount == 0)
    #expect(try await fixture.service.loadTask(id: other.id).plannedDate == (try fixture.day(0)))
  }
}
