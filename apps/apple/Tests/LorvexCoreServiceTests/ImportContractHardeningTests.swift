import Foundation
import GRDB
import LorvexStore
import XCTest

@testable import LorvexCore

final class ImportContractHardeningTests: XCTestCase {
  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(store: try LorvexStore.openInMemory(schemaSQL: schemaSQL))
  }

  private func uuid() -> String { UUID().uuidString.lowercased() }

  func testParentOwnedImportRejectsMalformedSoftReferenceIDsBeforeWriting() async throws {
    let service = try makeService()

    do {
      try await service.importCurrentFocus(
        ExportCurrentFocus(date: "2026-07-17", taskIDs: ["not-a-canonical-task-id"]))
      XCTFail("A malformed current-focus child identity must be rejected.")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("canonical task identity"))
    }

    do {
      _ = try await service.importDailyReview(
        date: "2026-07-17", summary: "Review", mood: nil, energyLevel: nil,
        wins: nil, blockers: nil, learnings: nil,
        linkedTaskIDs: [], linkedListIDs: ["not-a-canonical-list-id"])
      XCTFail("A malformed daily-review child identity must be rejected.")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("canonical list identity"))
    }

    let counts = try service.read { db -> (Int, Int, Int) in
      (
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM current_focus") ?? -1,
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM daily_reviews") ?? -1,
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox") ?? -1
      )
    }
    XCTAssertEqual(counts.0, 0)
    XCTAssertEqual(counts.1, 0)
    XCTAssertEqual(counts.2, 0)
  }

  func testHabitImportRejectsCadenceValuesThatWouldOtherwiseBeNormalized() async throws {
    let service = try makeService()
    let invalidCadences: [(String, [Int], Int?, Int?)] = [
      ("weekly", [0, 9], nil, nil),
      ("weekly", [1, 1], nil, nil),
      ("monthly", [], nil, 32),
      ("times_per_week", [], nil, nil),
      ("daily", [0], nil, nil),
    ]

    for (frequency, weekdays, target, day) in invalidCadences {
      do {
        _ = try await service.importHabit(
          id: uuid(), name: "Invalid cadence", cue: nil,
          frequencyType: frequency, weekdays: weekdays,
          perPeriodTarget: target, dayOfMonth: day, targetCount: 1)
        XCTFail("Invalid cadence \(frequency) should not be normalized into storage.")
      } catch {
        // Expected: each malformed record fails at the import trust boundary.
      }
    }

    XCTAssertEqual(
      try service.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM habits") },
      0)
  }

  func testInvalidRecurrenceAnchorRollsBackTheWholeTaskRecord() async throws {
    let service = try makeService()
    let taskID = uuid()
    var recurrence = ExportRecurrenceRule(
      from: TaskRecurrenceRule(freq: .weekly, interval: 1, byDay: ["MO"]))
    recurrence.anchor = "silently-wrong"
    let task = ExportTask(
      id: taskID, title: "Invalid recurrence", priority: "P2", status: "open",
      dueDate: nil, estimatedMinutes: nil, recurrence: recurrence)
    let payload = LorvexDataExportPayload(tasks: [task])

    let summary = await LorvexDataImporter.apply(
      plan: LorvexDataImporter.plan(for: payload), payload: payload, using: service)

    XCTAssertEqual(summary.totalImported, 0)
    XCTAssertTrue(summary.errors.contains { $0.recordRef == taskID })
    XCTAssertEqual(
      try service.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks") },
      0)
  }

  func testPortableRestorePreservesStartedTaskWithUnresolvedDependency() async throws {
    let service = try makeService()
    let startedID = uuid()
    let blockerID = uuid()
    let payload = LorvexDataExportPayload(
      tasks: [
        ExportTask(
          id: startedID, title: "Already underway", priority: "P1",
          status: "in_progress", dueDate: nil, estimatedMinutes: 30,
          dependsOn: [blockerID]),
        ExportTask(
          id: blockerID, title: "Blocker added later", priority: "P2",
          status: "open", dueDate: nil, estimatedMinutes: 15),
      ])

    let summary = await LorvexDataImporter.apply(
      plan: LorvexDataImporter.plan(for: payload), payload: payload, using: service)

    XCTAssertTrue(summary.errors.isEmpty, "Exact lifecycle restore failed: \(summary.errors)")
    let restored = try await service.loadTask(id: startedID)
    XCTAssertEqual(restored.status, .inProgress)
    XCTAssertEqual(restored.dependsOn, [blockerID])
  }

  func testCurrentV1DTOsDoNotInventRequiredFields() throws {
    let incompleteHabit = Data(#"{"id":"00000000-0000-4000-8000-000000000001","name":"Missing wire fields"}"#.utf8)
    XCTAssertThrowsError(try JSONDecoder().decode(ExportHabit.self, from: incompleteHabit))

    let incompleteReview = Data(#"{"date":"2026-07-17","summary":"Missing arrays"}"#.utf8)
    XCTAssertThrowsError(try JSONDecoder().decode(ExportDailyReview.self, from: incompleteReview))

    let incompleteList = Data(#"{"id":"00000000-0000-4000-8000-000000000002","name":"No position"}"#.utf8)
    XCTAssertThrowsError(try JSONDecoder().decode(ExportList.self, from: incompleteList))

    let incompleteEvent = Data(
      #"{"id":"00000000-0000-4000-8000-000000000003","title":"No defaults","startDate":"2026-07-17"}"#.utf8)
    XCTAssertThrowsError(try JSONDecoder().decode(ExportCalendarEvent.self, from: incompleteEvent))
  }
}
