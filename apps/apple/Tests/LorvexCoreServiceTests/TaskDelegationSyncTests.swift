import GRDB
import XCTest

@testable import LorvexCore

/// A task's hand-off to the assistant travels between the person's devices as
/// its own synced edge: the hand-over, the assistant's return, and taking the
/// task back each reach the other device, and two devices that change it apart
/// end in the same state.
final class TaskDelegationSyncTests: XCTestCase {
  /// Delivers everything `source` has queued to `target`.
  private func ship(
    from source: SwiftLorvexCoreService, to target: SwiftLorvexCoreService,
    file: StaticString = #filePath, line: UInt = #line
  ) throws {
    for _ in 0..<50 {
      let page = try source.pendingOutbound()
      if page.isEmpty { return }
      let report = try target.applyInbound(page.map(\.envelope), undecodable: 0)
      XCTAssertEqual(report.undecodable, 0, file: file, line: line)
      XCTAssertEqual(report.deferred, 0, file: file, line: line)
      try source.markOutboundSynced(outboxIds: page.map(\.outboxId))
    }
    XCTFail("the outbox did not drain", file: file, line: line)
  }

  private func delegationRows(_ service: SwiftLorvexCoreService) throws -> [String] {
    try service.read { db in
      try Row.fetchAll(
        db, sql: "SELECT task_id, assignee, state, request FROM task_delegations ORDER BY task_id"
      ).map { row in
        let request: String? = row["request"]
        return "\(row["task_id"] as String)|\(row["assignee"] as String)|"
          + "\(row["state"] as String)|\(request ?? "-")"
      }
    }
  }

  func testHandOverReturnAndTakeBackReachTheOtherDevice() async throws {
    let mac = try SwiftLorvexCoreService.inMemory()
    let phone = try SwiftLorvexCoreService.inMemory()
    let task = try await mac.createTask(title: "Book the dentist", notes: "")
    try ship(from: mac, to: phone)

    // Handed over on the phone.
    _ = try await phone.delegateTask(id: task.id, request: "Find a morning slot")
    try ship(from: phone, to: mac)
    let onMac = try await mac.loadTask(id: task.id)
    XCTAssertEqual(onMac.delegation?.state, .assistant)
    XCTAssertEqual(onMac.delegation?.request, "Find a morning slot")

    // The assistant, working through the Mac, hands it back.
    _ = try await mac.returnDelegatedTask(id: task.id, result: "Tuesday 9:00 is free.")
    try ship(from: mac, to: phone)
    let onPhone = try await phone.loadTask(id: task.id)
    XCTAssertEqual(onPhone.delegation?.state, .returned)
    XCTAssertEqual(onPhone.aiNotes, "Tuesday 9:00 is free.")

    // Taken back on the phone.
    _ = try await phone.clearTaskDelegation(id: task.id)
    try ship(from: phone, to: mac)
    XCTAssertEqual(try delegationRows(mac), [])
    XCTAssertEqual(try delegationRows(phone), [])
    let cleared = try await mac.loadTask(id: task.id)
    XCTAssertNil(cleared.delegation)
  }

  func testChangesMadeApartConverge() async throws {
    let mac = try SwiftLorvexCoreService.inMemory()
    let phone = try SwiftLorvexCoreService.inMemory()
    let task = try await mac.createTask(title: "Draft the reply", notes: "")
    _ = try await mac.delegateTask(id: task.id, request: nil)
    try ship(from: mac, to: phone)

    // While apart: the assistant returns the task on the Mac, and the person
    // takes it back on the phone.
    _ = try await mac.returnDelegatedTask(id: task.id, result: "Draft is in the notes.")
    _ = try await phone.clearTaskDelegation(id: task.id)
    try ship(from: mac, to: phone)
    try ship(from: phone, to: mac)

    XCTAssertEqual(try delegationRows(mac), try delegationRows(phone))
    let macNotes = try await mac.loadTask(id: task.id).aiNotes
    let phoneNotes = try await phone.loadTask(id: task.id).aiNotes
    XCTAssertEqual(macNotes, "Draft is in the notes.")
    XCTAssertEqual(phoneNotes, "Draft is in the notes.")
  }

  func testDeletingTheTaskRemovesItsDelegationOnTheOtherDevice() async throws {
    let mac = try SwiftLorvexCoreService.inMemory()
    let phone = try SwiftLorvexCoreService.inMemory()
    let task = try await mac.createTask(title: "Cancel the trial", notes: "")
    _ = try await mac.delegateTask(id: task.id, request: nil)
    try ship(from: mac, to: phone)
    XCTAssertEqual(try delegationRows(phone).count, 1)

    _ = try await mac.permanentlyDeleteTask(id: task.id)
    try ship(from: mac, to: phone)

    XCTAssertEqual(try delegationRows(phone), [])
  }
}
