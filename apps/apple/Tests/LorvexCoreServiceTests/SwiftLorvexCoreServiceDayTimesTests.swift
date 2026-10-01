import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexCore

/// A day's times and briefing through the on-disk service: `saveDayTimes`
/// replaces the times of a day's unfinished tasks in one write, and the
/// assistant's briefing is one trimmed row per day that a blank write deletes.
final class SwiftLorvexCoreServiceDayTimesTests: XCTestCase {
  private let day = "2026-07-16"

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(store: try LorvexStore.openInMemory(
      schemaSQL: schemaSQL, migrations: try SwiftLorvexCoreService.resolveSchemaMigrations()))
  }

  /// The stored planned date and time of a task, read from its row.
  private func planned(_ service: SwiftLorvexCoreService, _ id: String) throws
    -> (date: String?, start: Int?, end: Int?)
  {
    try service.read { db in
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT planned_date, planned_start_minutes, planned_end_minutes
            FROM tasks WHERE id = ?
            """,
          arguments: [id]))
      return (row["planned_date"], row["planned_start_minutes"], row["planned_end_minutes"])
    }
  }

  private func changelogCount(_ service: SwiftLorvexCoreService, entityType: String) throws -> Int {
    try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE entity_type = ?",
        arguments: [entityType]) ?? 0
    }
  }

  // MARK: - Saving a day's times

  func testSaveDayTimesPlansListedTasksAndTakesTheTimeFromTheRest() async throws {
    let service = try makeService()
    let first = try await service.createTask(title: "Write the draft", notes: "")
    let second = try await service.createTask(title: "Review the draft", notes: "")
    let third = try await service.createTask(title: "Send the draft", notes: "")
    _ = try await service.saveDayTimes(
      date: day,
      times: [
        LorvexTaskTime(taskID: first.id, time: 540..<600),
        LorvexTaskTime(taskID: second.id, time: 600..<660),
      ])

    let receipt = try await service.saveDayTimesForMcp(
      date: day, times: [LorvexTaskTime(taskID: third.id, time: 555..<585)])

    XCTAssertEqual(receipt.timedTasks.map(\.id), [third.id])
    XCTAssertEqual(receipt.timedTasks.first?.plannedTime, 555..<585)
    XCTAssertEqual(receipt.clearedTasks.map(\.id), [first.id, second.id])
    let firstState = try planned(service, first.id)
    XCTAssertEqual(firstState.date, day, "a task that loses its time keeps its day")
    XCTAssertNil(firstState.start)
    XCTAssertNil(firstState.end)
    let thirdState = try planned(service, third.id)
    XCTAssertEqual(thirdState.date, day)
    XCTAssertEqual(thirdState.start, 555)
    XCTAssertEqual(thirdState.end, 585)
  }

  func testSaveDayTimesLeavesFinishedTasksTheirTimes() async throws {
    let service = try makeService()
    let done = try await service.createTask(title: "Morning run", notes: "")
    let open = try await service.createTask(title: "Answer mail", notes: "")
    _ = try await service.saveDayTimes(
      date: day,
      times: [
        LorvexTaskTime(taskID: done.id, time: 420..<480),
        LorvexTaskTime(taskID: open.id, time: 540..<570),
      ])
    _ = try await service.completeTask(id: done.id)

    let timed = try await service.saveDayTimes(date: day, times: [])

    XCTAssertEqual(timed.map(\.id), [done.id], "a finished task keeps its time as the day's record")
    let openState = try planned(service, open.id)
    XCTAssertEqual(openState.date, day)
    XCTAssertNil(openState.start)
  }

  func testArchivedTaskLeavesTheDayAndCannotTakeATime() async throws {
    let service = try makeService()
    let keep = try await service.createTask(title: "Keep timed", notes: "")
    let archived = try await service.createTask(title: "Archive while timed", notes: "")
    _ = try await service.saveDayTimes(
      date: day,
      times: [
        LorvexTaskTime(taskID: archived.id, time: 540..<600),
        LorvexTaskTime(taskID: keep.id, time: 600..<660),
      ])

    _ = try await service.archiveTask(id: archived.id)

    let timed = try await service.loadTimedTasks(from: day, through: day)
    XCTAssertEqual(timed.map(\.id), [keep.id])
    do {
      _ = try await service.saveDayTimes(
        date: "2026-07-17", times: [LorvexTaskTime(taskID: archived.id, time: 540..<600)])
      XCTFail("an archived task must not take a time")
    } catch LorvexCoreError.validation(let field, _) {
      XCTAssertEqual(field, "times")
    }
    let nextDay = try await service.loadTimedTasks(from: "2026-07-17", through: "2026-07-17")
    XCTAssertTrue(nextDay.isEmpty)
  }

  func testSaveDayTimesRejectsARepeatedTaskAndATimeOutsideTheDay() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Plan the week", notes: "")

    do {
      _ = try await service.saveDayTimes(
        date: day,
        times: [
          LorvexTaskTime(taskID: task.id, time: 540..<600),
          LorvexTaskTime(taskID: task.id, time: 660..<720),
        ])
      XCTFail("a task listed twice must be rejected")
    } catch LorvexCoreError.validation(let field, _) {
      XCTAssertEqual(field, "times")
    }
    do {
      _ = try await service.saveDayTimes(
        date: day, times: [LorvexTaskTime(taskID: task.id, time: 1400..<1500)])
      XCTFail("a time past midnight must be rejected")
    } catch LorvexCoreError.validation(let field, _) {
      XCTAssertEqual(field, "times")
    }
    let state = try planned(service, task.id)
    XCTAssertNil(state.date, "a rejected save changes nothing")
    XCTAssertNil(state.start)
  }

  func testSaveDayTimesRecordsOneChangelogRowWithBothStatesAndSkipsNoOps() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Deep work", notes: "")
    let times = [LorvexTaskTime(taskID: task.id, time: 540..<630)]

    _ = try await service.saveDayTimes(date: day, times: times)
    _ = try await service.saveDayTimes(date: day, times: times)

    XCTAssertEqual(
      try changelogCount(service, entityType: EntityName.dailySchedule), 1,
      "saving the times already stored writes no second row")
    let states = try service.read { db in
      try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT entity_id, before_json, after_json FROM ai_changelog
            WHERE entity_type = ?
            """,
          arguments: [EntityName.dailySchedule]))
    }
    XCTAssertEqual(states["entity_id"] as String, day)
    let before = try JSONSerialization.jsonObject(
      with: Data((states["before_json"] as String).utf8)) as? [String: Any]
    let after = try JSONSerialization.jsonObject(
      with: Data((states["after_json"] as String).utf8)) as? [String: Any]
    let beforeTask = try XCTUnwrap((before?["tasks"] as? [[String: Any]])?.first)
    let afterTask = try XCTUnwrap((after?["tasks"] as? [[String: Any]])?.first)
    XCTAssertEqual(beforeTask["id"] as? String, task.id)
    XCTAssertTrue(beforeTask["planned_date"] is NSNull)
    XCTAssertTrue(beforeTask["planned_start_minutes"] is NSNull)
    XCTAssertEqual(afterTask["planned_date"] as? String, day)
    XCTAssertEqual(afterTask["planned_start_minutes"] as? Int, 540)
    XCTAssertEqual(afterTask["planned_end_minutes"] as? Int, 630)
  }

  func testClearingEveryTimeRecordsADeleteRowWithThePreviousTimes() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Deep work", notes: "")
    _ = try await service.saveDayTimes(
      date: day, times: [LorvexTaskTime(taskID: task.id, time: 540..<630)])

    try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.assistant
    ) {
      _ = try await service.saveDayTimes(date: day, times: [])
    }

    let cleared = try planned(service, task.id)
    XCTAssertEqual(cleared.date, day, "clearing a time keeps the task on its day")
    XCTAssertNil(cleared.start)
    let operations = try service.read { db in
      try String.fetchAll(
        db,
        sql: "SELECT operation FROM ai_changelog WHERE entity_type = ? ORDER BY rowid",
        arguments: [EntityName.dailySchedule])
    }
    XCTAssertEqual(operations, [SyncNaming.opUpsert, SyncNaming.opDelete])

    let log = try await service.loadAIChangelog(
      limit: 10, offset: nil, entityType: EntityName.dailySchedule,
      operation: SyncNaming.opDelete, entityID: day, since: nil)
    let entry = try XCTUnwrap(log.entries.first)
    XCTAssertTrue(entry.hasBefore, "the delete row records the times it cleared")
  }

  // MARK: - The day's briefing

  func testDailyBriefingIsTrimmedReplacedAndClearedWithoutNoOpWrites() async throws {
    let service = try makeService()
    let loadedDay = try await service.loadToday().logicalDay
    let today = try XCTUnwrap(loadedDay)

    let first = try await service.setDailyBriefingForMcp(
      date: today, briefing: "  Ship the draft first.  ")
    XCTAssertEqual(first.briefing, "Ship the draft first.")
    XCTAssertNil(first.previous)
    XCTAssertTrue(first.changed)
    let shown = try await service.loadToday().briefing
    XCTAssertEqual(shown, "Ship the draft first.")

    let repeated = try await service.setDailyBriefingForMcp(
      date: today, briefing: "Ship the draft first.")
    XCTAssertFalse(repeated.changed)
    XCTAssertEqual(try changelogCount(service, entityType: EntityName.dailyBriefing), 1)

    let cleared = try await service.setDailyBriefingForMcp(date: today, briefing: "   ")
    XCTAssertNil(cleared.briefing)
    XCTAssertEqual(cleared.previous, "Ship the draft first.")
    let afterClear = try await service.loadToday().briefing
    XCTAssertNil(afterClear)
    let rows = try service.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM daily_briefings") ?? 0
    }
    XCTAssertEqual(rows, 0, "a cleared briefing deletes the day's row")
    XCTAssertEqual(try changelogCount(service, entityType: EntityName.dailyBriefing), 2)

    _ = try await service.setDailyBriefingForMcp(date: today, briefing: "Ship the draft first.")
    let rewritten = try await service.loadToday().briefing
    XCTAssertEqual(rewritten, "Ship the draft first.")
  }
}
