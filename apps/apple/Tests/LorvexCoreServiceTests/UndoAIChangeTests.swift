import GRDB
import XCTest

@testable import LorvexCore

/// Undoing an assistant's update to a task puts back the fields that change moved, as long as they
/// still hold what the change set; a field edited since is left alone. Only an assistant's update
/// with a whole before-and-after can be undone.
final class UndoAIChangeTests: XCTestCase {
  private func assistantUpdate(
    _ service: SwiftLorvexCoreService, _ draft: TaskUpdateDraft
  ) async throws {
    _ = try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.assistant
    ) {
      try await service.updateTask(draft)
    }
  }

  private func latestUpdateID(_ service: SwiftLorvexCoreService, task: String) throws -> String {
    try XCTUnwrap(
      try service.read { db in
        try String.fetchOne(
          db,
          sql: """
            SELECT id FROM ai_changelog
            WHERE entity_id = ? AND operation = 'update' ORDER BY timestamp DESC, id DESC LIMIT 1
            """,
          arguments: [task])
      })
  }

  /// A planned or due day as the store keeps it, a calendar day at midnight UTC, written
  /// `YYYY-MM-DD`.
  private func ymd(_ date: Date?) -> String? {
    guard let date else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
  }

  private func changelogCount(_ service: SwiftLorvexCoreService) throws -> Int {
    try service.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? -1 }
  }

  func testUndoPutsBackEveryFieldTheChangeMoved() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let task = try await service.createTask(title: "Write report", notes: "Draft first")
    try await assistantUpdate(
      service,
      TaskUpdateDraft(
        id: task.id, title: "Write the Q3 report", notes: "Draft, then review", priority: .p1,
        estimatedMinutes: .set(45), tags: ["work"]))
    let id = try latestUpdateID(service, task: task.id)
    let before = try changelogCount(service)

    let result = try await service.undoAIChange(changelogID: id)

    let restored = try XCTUnwrap(result.task)
    XCTAssertEqual(Set(result.reverted), ["title", "notes", "priority", "estimated_minutes", "tags"])
    XCTAssertTrue(result.kept.isEmpty)
    XCTAssertEqual(restored.title, "Write report")
    XCTAssertEqual(restored.notes, "Draft first")
    XCTAssertNil(restored.estimatedMinutes)
    XCTAssertTrue(restored.tags.isEmpty)
    let stored = try await service.loadTask(id: task.id)
    XCTAssertEqual(stored.title, "Write report")
    XCTAssertEqual(try changelogCount(service), before + 1, "the undo is itself a logged change")
  }

  func testAFieldEditedSinceIsKeptAndTheRestIsPutBack() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let task = try await service.createTask(title: "Write report", notes: "Draft first")
    try await assistantUpdate(
      service, TaskUpdateDraft(id: task.id, title: "Write the Q3 report", notes: "Draft, then review"))
    let id = try latestUpdateID(service, task: task.id)
    // A person edits the notes afterwards.
    _ = try await service.updateTask(TaskUpdateDraft(id: task.id, notes: "My own notes"))

    let result = try await service.undoAIChange(changelogID: id)

    let restored = try XCTUnwrap(result.task)
    XCTAssertEqual(result.reverted, ["title"])
    XCTAssertEqual(result.kept, ["notes"])
    XCTAssertEqual(restored.title, "Write report")
    XCTAssertEqual(restored.notes, "My own notes", "a later edit is never overwritten")
  }

  func testUndoingTwiceChangesNothingTheSecondTime() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let task = try await service.createTask(title: "Write report", notes: "")
    try await assistantUpdate(service, TaskUpdateDraft(id: task.id, title: "Write the Q3 report"))
    let id = try latestUpdateID(service, task: task.id)
    _ = try await service.undoAIChange(changelogID: id)
    let afterFirst = try changelogCount(service)

    let second = try await service.undoAIChange(changelogID: id)

    XCTAssertTrue(second.reverted.isEmpty)
    XCTAssertEqual(second.task?.title, "Write report")
    XCTAssertEqual(try changelogCount(service), afterFirst, "nothing was written")
  }

  func testOnlyAnAssistantsTaskUpdateWithAWholeSnapshotCanBeUndone() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let task = try await service.createTask(title: "Write report", notes: "")
    func refusal(_ id: String) async -> String? {
      do {
        _ = try await service.undoAIChange(changelogID: id)
        return nil
      } catch let LorvexCoreError.validation(field, message) {
        XCTAssertEqual(field, "changelog_id")
        return message
      } catch {
        return "unexpected \(error)"
      }
    }

    let unknown = await refusal("no-such-change")
    XCTAssertEqual(unknown?.contains("No change with that id"), true)

    // A person's update.
    _ = try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.user
    ) {
      try await service.updateTask(TaskUpdateDraft(id: task.id, title: "Mine"))
    }
    let humanID = try latestUpdateID(service, task: task.id)
    let human = await refusal(humanID)
    XCTAssertEqual(human?.contains("not made by an assistant"), true)

    // Rows an assistant wrote that cannot be undone: another operation, no snapshot, a truncated one.
    func insert(_ id: String, operation: String, before: String?, after: String?) throws {
      try service.withWrite { db, _, _ in
        try db.execute(
          sql: """
            INSERT INTO ai_changelog
              (id, timestamp, operation, entity_type, entity_id, summary, initiated_by, before_json, after_json)
            VALUES (?, '2026-10-13T00:00:00.000Z', ?, 'task', ?, 'x', 'assistant', ?, ?)
            """,
          arguments: [id, operation, task.id, before, after])
      }
    }
    try insert("00000000-0000-4000-8000-000000000001", operation: "complete", before: "{}", after: "{}")
    try insert("00000000-0000-4000-8000-000000000002", operation: "update", before: nil, after: nil)
    try insert(
      "00000000-0000-4000-8000-000000000003", operation: "update",
      before: "{\"_lorvex_truncated\":true}", after: "{\"title\":\"x\"}")
    let other = await refusal("00000000-0000-4000-8000-000000000001")
    XCTAssertEqual(other?.contains("Only an update to a task or a calendar event"), true)
    let none = await refusal("00000000-0000-4000-8000-000000000002")
    XCTAssertEqual(none?.contains("no before-and-after"), true)
    let truncated = await refusal("00000000-0000-4000-8000-000000000003")
    XCTAssertEqual(truncated?.contains("too large"), true)
  }

  func testTagsAndDependenciesGoBackAsSets() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let blocker = try await service.createTask(title: "Gather documents", notes: "")
    let task = try await service.createTask(title: "File taxes", notes: "")
    _ = try await service.updateTask(TaskUpdateDraft(id: task.id, tags: ["money", "home"]))
    try await assistantUpdate(
      service, TaskUpdateDraft(id: task.id, tags: ["money"], dependsOn: [blocker.id]))
    let id = try latestUpdateID(service, task: task.id)

    let result = try await service.undoAIChange(changelogID: id)

    let restored = try XCTUnwrap(result.task)
    XCTAssertEqual(Set(result.reverted), ["tags", "depends_on"])
    XCTAssertEqual(Set(restored.tags), ["money", "home"])
    XCTAssertTrue(restored.dependsOn.isEmpty)
  }

  /// The planned day and its times are one value: moving the day clears the time, so a time
  /// edited since keeps the day with it, and a day cleared since leaves the whole slot alone
  /// (restoring only the time would be refused for want of a day).
  func testThePlannedDayAndItsTimesGoBackOrStayTogether() async throws {
    let day = { (number: Int) in
      Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: number, hour: 12))!
    }
    let service = try SwiftLorvexCoreService.inMemory()
    let task = try await service.createTask(title: "Plan trip", notes: "")
    _ = try await service.updateTask(
      TaskUpdateDraft(id: task.id, plannedDate: .set(day(10)), plannedTime: .set(600..<630)))
    try await assistantUpdate(
      service,
      TaskUpdateDraft(id: task.id, plannedDate: .set(day(12)), plannedTime: .set(540..<570)))
    let id = try latestUpdateID(service, task: task.id)

    // A person moves the time afterwards: the day stays with it.
    _ = try await service.updateTask(TaskUpdateDraft(id: task.id, plannedTime: .set(480..<540)))
    let edited = try await service.undoAIChange(changelogID: id)
    XCTAssertTrue(edited.reverted.isEmpty)
    XCTAssertEqual(edited.kept, ["planned_date"])
    XCTAssertEqual(edited.task?.plannedTime, 480..<540)
    XCTAssertEqual(ymd(edited.task?.plannedDate), "2026-11-12")

    // A person clears the day instead: nothing is restored, and nothing is refused.
    _ = try await service.updateTask(TaskUpdateDraft(id: task.id, plannedDate: .clear))
    let cleared = try await service.undoAIChange(changelogID: id)
    XCTAssertTrue(cleared.reverted.isEmpty)
    XCTAssertNil(cleared.task?.plannedDate)
    XCTAssertNil(cleared.task?.plannedTime)
  }

  func testAnUntouchedPlannedSlotGoesBackWhole() async throws {
    let day = { (number: Int) in
      Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: number, hour: 12))!
    }
    let service = try SwiftLorvexCoreService.inMemory()
    let task = try await service.createTask(title: "Plan trip", notes: "")
    _ = try await service.updateTask(
      TaskUpdateDraft(id: task.id, plannedDate: .set(day(10)), plannedTime: .set(600..<630)))
    try await assistantUpdate(service, TaskUpdateDraft(id: task.id, plannedDate: .set(day(12))))
    let id = try latestUpdateID(service, task: task.id)

    let result = try await service.undoAIChange(changelogID: id)

    XCTAssertEqual(result.reverted, ["planned_date"])
    XCTAssertEqual(ymd(result.task?.plannedDate), "2026-11-10")
    XCTAssertEqual(result.task?.plannedTime, 600..<630, "the time the move cleared comes back")
  }
}
