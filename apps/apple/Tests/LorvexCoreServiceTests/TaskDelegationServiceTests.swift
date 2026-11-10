import GRDB
import XCTest

@testable import LorvexCore

/// A task can be handed to the person's assistant, handed back with a result,
/// and taken back. Each real change writes one sync envelope for the
/// `task_delegation` edge and one changelog row; a restated one writes nothing.
final class TaskDelegationServiceTests: XCTestCase {
  private func counts(_ service: SwiftLorvexCoreService) throws
    -> (rows: Int, outbox: Int, changelog: Int)
  {
    try service.read { db in
      (
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM task_delegations") ?? -1,
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'task_delegation'") ?? -1,
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM ai_changelog
            WHERE operation IN ('delegate_task', 'return_task', 'clear_task_delegation')
            """) ?? -1
      )
    }
  }

  func testHandOverReturnAndTakeBack() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let task = try await service.createTask(title: "Book the dentist", notes: "")
    XCTAssertNil(task.delegation)

    let handed = try await service.delegateTask(id: task.id, request: "  Find a morning slot  ")
    XCTAssertEqual(handed.delegation?.state, .assistant)
    XCTAssertEqual(handed.delegation?.request, "Find a morning slot")
    XCTAssertNotNil(handed.delegation?.since)
    let waiting = try await service.delegatedTaskCount(state: .assistant)
    let back = try await service.delegatedTaskCount(state: .returned)
    XCTAssertEqual(waiting, 1)
    XCTAssertEqual(back, 0)
    let afterHandOver = try counts(service)
    XCTAssertEqual(afterHandOver.rows, 1)
    XCTAssertEqual(afterHandOver.changelog, 1)

    // The same hand-over again writes nothing.
    _ = try await service.delegateTask(id: task.id, request: "Find a morning slot")
    let restated = try counts(service)
    XCTAssertEqual(restated.outbox, afterHandOver.outbox)
    XCTAssertEqual(restated.changelog, afterHandOver.changelog)

    // The assistant hands it back; the result becomes the task's AI notes.
    let returned = try await service.returnDelegatedTask(
      id: task.id, result: "Tuesday 9:00 is free. Call to confirm.")
    XCTAssertEqual(returned.delegation?.state, .returned)
    XCTAssertEqual(returned.delegation?.request, "Find a morning slot")
    XCTAssertEqual(returned.aiNotes, "Tuesday 9:00 is free. Call to confirm.")
    XCTAssertEqual(returned.status, .open, "the assistant does not complete the task")
    let waitingAfterReturn = try await service.delegatedTaskCount(state: .assistant)
    let backAfterReturn = try await service.delegatedTaskCount(state: .returned)
    XCTAssertEqual(waitingAfterReturn, 0)
    XCTAssertEqual(backAfterReturn, 1)
    let afterReturn = try counts(service)
    XCTAssertEqual(afterReturn.changelog, 2)

    // Returning it again with the same result writes nothing.
    _ = try await service.returnDelegatedTask(
      id: task.id, result: "Tuesday 9:00 is free. Call to confirm.")
    XCTAssertEqual(try counts(service).changelog, 2)

    // The person takes it back: the row goes, and a delete is queued.
    let cleared = try await service.clearTaskDelegation(id: task.id)
    XCTAssertNil(cleared.delegation)
    XCTAssertEqual(cleared.aiNotes, "Tuesday 9:00 is free. Call to confirm.")
    let afterClear = try counts(service)
    XCTAssertEqual(afterClear.rows, 0)
    XCTAssertEqual(afterClear.changelog, 3)
    let deletes = try service.read { db in
      try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM sync_outbox
          WHERE entity_type = 'task_delegation' AND operation = 'delete'
          """) ?? -1
    }
    XCTAssertEqual(deletes, 1)

    // Taking back a task that is not handed over changes nothing.
    _ = try await service.clearTaskDelegation(id: task.id)
    XCTAssertEqual(try counts(service).changelog, 3)
  }

  func testATaskHandedOverAgainStartsOver() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let task = try await service.createTask(title: "Draft the reply", notes: "")
    _ = try await service.delegateTask(id: task.id, request: nil)
    _ = try await service.returnDelegatedTask(id: task.id, result: "Draft is in the notes.")

    let again = try await service.delegateTask(id: task.id, request: "Shorter, please")
    XCTAssertEqual(again.delegation?.state, .assistant)
    XCTAssertEqual(again.delegation?.request, "Shorter, please")
    XCTAssertEqual(try counts(service).rows, 1)
  }

  func testOnlyAnOpenTaskCanBeHandedOverAndOnlyAHandedOverTaskReturned() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let task = try await service.createTask(title: "Send the form", notes: "")

    do {
      _ = try await service.returnDelegatedTask(id: task.id, result: "Done")
      XCTFail("a task that was never handed over was returned")
    } catch LorvexCoreError.validation(let field, _) {
      XCTAssertEqual(field, "id")
    }

    _ = try await service.completeTask(id: task.id)
    do {
      _ = try await service.delegateTask(id: task.id, request: nil)
      XCTFail("a completed task was handed over")
    } catch LorvexCoreError.validation(let field, _) {
      XCTAssertEqual(field, "id")
    }

    do {
      _ = try await service.delegateTask(
        id: task.id, request: String(repeating: "x", count: 2001))
      XCTFail("a request over the limit was accepted")
    } catch LorvexCoreError.validation(let field, _) {
      XCTAssertEqual(field, "request")
    }
  }

  func testDeletingATaskTombstonesItsDelegation() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let task = try await service.createTask(title: "Cancel the trial", notes: "")
    _ = try await service.delegateTask(id: task.id, request: nil)

    _ = try await service.permanentlyDeleteTask(id: task.id)

    let (rows, deletes) = try service.read { db in
      (
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM task_delegations") ?? -1,
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE entity_type = 'task_delegation' AND operation = 'delete'
            """) ?? -1
      )
    }
    XCTAssertEqual(rows, 0)
    XCTAssertEqual(deletes, 1)
  }
}
