import GRDB
import XCTest

@testable import LorvexCore

/// A completion-anchored repeat spawns its next occurrence INTERVAL units after
/// the completion day. Completing the occurrence that was just spawned, on the
/// same day, used to compute that same date again and fail on the series' unique
/// occurrence key with a raw SQLite error; the next occurrence now moves on by
/// another interval.
final class CompletionAnchoredSuccessorTests: XCTestCase {
  func testCompletingTheJustSpawnedOccurrenceTheSameDayAdvancesAnotherInterval() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let snapshot = try await service.loadToday()
    let today = try XCTUnwrap(snapshot.logicalDay)
    let task = try await service.createTask(title: "Water the plants", notes: "")
    _ = try await service.setTaskRecurrence(
      taskID: task.id,
      rule: TaskRecurrenceRule(freq: .weekly, interval: 4, anchor: .completion))

    _ = try await service.completeTask(id: task.id)
    let successorID = try XCTUnwrap(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT id FROM tasks WHERE title = 'Water the plants' AND id != ?",
          arguments: [task.id])
      })
    let firstDue = try XCTUnwrap(
      try service.read { db in
        try String.fetchOne(db, sql: "SELECT due_date FROM tasks WHERE id = ?", arguments: [successorID])
      })

    // The same day: completing the occurrence just spawned.
    _ = try await service.completeTask(id: successorID)
    let secondDue = try XCTUnwrap(
      try service.read { db in
        try String.fetchOne(
          db,
          sql: "SELECT due_date FROM tasks WHERE title = 'Water the plants' AND status = 'open'")
      })
    XCTAssertGreaterThan(secondDue, firstDue, "the next occurrence is after the one just completed")
    XCTAssertGreaterThan(firstDue, today)
  }
}

/// An earlier occurrence keeps its occurrence key after it is completed, so a
/// daily completion-anchored repeat finished ahead of time and again the same day
/// can measure back to a date that key still names.
final class CompletionAnchoredEarlierKeyTests: XCTestCase {
  func testCompletingTwoOccurrencesInOneDayNeverReusesAnEarlierOccurrenceKey() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let task = try await service.createTask(title: "Stretch", notes: "")
    _ = try await service.setTaskRecurrence(
      taskID: task.id, rule: TaskRecurrenceRule(freq: .daily, interval: 1, anchor: .completion))

    // Each completion spawns the next occurrence; five in a row, all the same day.
    var currentID = task.id
    for _ in 0..<5 {
      _ = try await service.completeTask(id: currentID)
      let nextID = try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT id FROM tasks WHERE title = 'Stretch' AND status = 'open'")
      }
      currentID = try XCTUnwrap(nextID)
    }
    let keys = try service.read { db in
      try String.fetchAll(
        db, sql: "SELECT recurrence_instance_key FROM tasks WHERE recurrence_instance_key IS NOT NULL")
    }
    XCTAssertEqual(Set(keys).count, keys.count, "every occurrence has its own key")
  }
}

/// A repeat pinned to a day (of the month, the year, or the week), moved to
/// another day, repeats on the new day from then on.
final class RepeatRescheduleTests: XCTestCase {
  /// Pins `rule` to `from`, moves the due date to `to`, completes, and returns the
  /// next occurrence's due date.
  private func nextDue(rule: TaskRecurrenceRule, from: String, to: String) async throws -> String {
    let service = try SwiftLorvexCoreService.inMemory()
    let task = try await service.createTask(title: "Pinned", notes: "")
    func date(_ key: String) throws -> Date {
      try XCTUnwrap(LorvexDateFormatters.ymd.date(from: key))
    }
    func setDue(_ key: String) async throws {
      _ = try await service.updateTask(
        id: task.id, title: "Pinned", notes: "", priority: task.priority, estimatedMinutes: nil,
        dueDate: try date(key), plannedDate: nil, availableFrom: nil, tags: [], dependsOn: [])
    }
    try await setDue(from)
    _ = try await service.setTaskRecurrence(taskID: task.id, rule: rule)
    try await setDue(to)
    _ = try await service.completeTask(id: task.id)
    return try XCTUnwrap(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT due_date FROM tasks WHERE title = 'Pinned' AND status = 'open'")
      })
  }

  func testMonthlyDayRuleFollowsTheNewDay() async throws {
    let next = try await nextDue(
      rule: TaskRecurrenceRule(freq: .monthly, interval: 1, byMonthDay: [6]),
      from: "2031-03-06", to: "2031-03-15")
    XCTAssertEqual(next, "2031-04-15")
  }

  func testWeeklyDayRuleFollowsTheNewWeekday() async throws {
    // 2031-03-03 is a Monday, 2031-03-06 a Thursday.
    let next = try await nextDue(
      rule: TaskRecurrenceRule(freq: .weekly, interval: 1, byDay: ["MO"]),
      from: "2031-03-03", to: "2031-03-06")
    XCTAssertEqual(next, "2031-03-13")
  }

  func testYearlyRuleFollowsTheNewDate() async throws {
    let next = try await nextDue(
      rule: TaskRecurrenceRule(freq: .yearly, interval: 1, byMonth: [3], byMonthDay: [6]),
      from: "2031-03-06", to: "2031-05-20")
    XCTAssertEqual(next, "2032-05-20")
  }
}
