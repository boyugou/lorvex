import GRDB
import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexCore

/// Per-field canonical-escaped byte budgets keep every locally-authored task
/// payload provably under the sync byte cap. Pre-budget, two individually
/// codepoint-legal fields (emoji body + emoji ai_notes) composed past the
/// 256 KiB whole-payload cap and failed at outbound canonicalization with an
/// internal error attributed to whichever write came second; the budgets now
/// reject the offending FIELD at ITS OWN write with a typed validation error,
/// and both fields at their budget maxima commit and enqueue cleanly.
final class SwiftLorvexCoreServicePayloadBudgetTests: XCTestCase {

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // LorvexCoreServiceTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return SwiftLorvexCoreService(store: store)
  }

  /// 4 escaped bytes per emoji, so counts convert exactly to escaped bytes.
  private func emoji(_ count: Int) -> String {
    String(repeating: "😀", count: count)
  }

  func testOversizedBodyRejectsTypedAtItsOwnWrite() async throws {
    let service = try makeService()
    // 49,900 emoji = 199,600 escaped bytes — codepoint-legal, byte-illegal.
    do {
      _ = try await service.createTask(title: "T", notes: emoji(49_900))
      XCTFail("an over-budget body must reject at create")
    } catch {
      let text = "\(error)"
      XCTAssertTrue(text.contains("body"), "the error must name the offending field: \(text)")
      XCTAssertFalse(
        text.contains("canonicalization"),
        "the rejection must be a write-time validation, not an outbound canonicalization error")
    }
  }

  func testOversizedAiNotesRejectsTypedWithoutBlamingThePriorWrite() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "T", notes: emoji(25_000))
    do {
      _ = try await service.setTaskAINotes(taskID: task.id, notes: emoji(49_900))
      XCTFail("over-budget ai_notes must reject at their own write")
    } catch {
      let text = "\(error)"
      XCTAssertTrue(text.contains("ai_notes"), "the error must name ai_notes: \(text)")
      XCTAssertFalse(text.contains("canonicalization"), "must be a typed validation: \(text)")
    }
    let unchanged = try await service.loadTask(id: task.id)
    XCTAssertNil(unchanged.aiNotes, "a rejected ai_notes write must not land")
  }

  func testReviewTextBudgetRejectsOverAndAcceptsAtTheBound() async throws {
    let service = try makeService()
    // reviewTextEscapedBytes = 40,000; 10,000 emoji = exactly at the budget.
    // A nil date resolves to today, inside the interactive staleness window.
    _ = try await service.upsertDailyReview(
      date: nil, summary: emoji(10_000), mood: nil, energyLevel: nil,
      wins: nil, blockers: nil, learnings: nil, linkedTaskIDs: [], linkedListIDs: [])

    do {
      _ = try await service.upsertDailyReview(
        date: nil, summary: emoji(10_001), mood: nil, energyLevel: nil,
        wins: nil, blockers: nil, learnings: nil, linkedTaskIDs: [], linkedListIDs: [])
      XCTFail("an over-budget review summary must reject")
    } catch {
      XCTAssertTrue("\(error)".contains("summary"), "must name the field: \(error)")
    }
  }

  func testRecurrenceExceptionAddPathRejectsPastTheCap() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Recurring", notes: "")
    _ = try await service.setTaskRecurrence(
      taskID: task.id, rule: TaskRecurrenceRule(freq: .daily, interval: 1))

    // Seed exactly the cap directly (setup only; the caps under test guard the
    // service write paths, not raw SQL).
    try service.write { db in
      for day in 1...PayloadByteBudget.maxRecurrenceExceptions {
        let unique = String(
          format: "%04d-%02d-%02d", 2027 + day / 336, (day / 28) % 12 + 1, day % 28 + 1)
        try db.execute(
          sql: "INSERT OR IGNORE INTO task_recurrence_exceptions (task_id, exception_date) VALUES (?, ?)",
          arguments: [task.id, unique])
      }
    }
    let seeded = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM task_recurrence_exceptions WHERE task_id = ?",
        arguments: [task.id]) ?? 0
    }
    XCTAssertEqual(
      seeded, PayloadByteBudget.maxRecurrenceExceptions, "seeding must land exactly at the cap")

    do {
      _ = try await service.addTaskRecurrenceException(
        taskID: task.id, exceptionDate: "2031-06-15")
      XCTFail("the add path must reject once the cap is reached")
    } catch {
      XCTAssertTrue("\(error)".contains("at most"), "must state the cap: \(error)")
    }
  }

  func testBothFieldsAtBudgetMaximaCommitAndEnqueue() async throws {
    let service = try makeService()
    // body: 30,000 emoji = exactly longTextEscapedBytes (120,000).
    // ai_notes: 20,000 emoji = exactly aiNotesEscapedBytes (80,000).
    let task = try await service.createTask(title: "T", notes: emoji(30_000))
    _ = try await service.setTaskAINotes(taskID: task.id, notes: emoji(20_000))

    let outboxRows = try service.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?",
        arguments: [task.id]) ?? 0
    }
    XCTAssertGreaterThan(
      outboxRows, 0,
      "both fields at their budget maxima must commit AND enqueue without payloadTooLarge")
  }
}
