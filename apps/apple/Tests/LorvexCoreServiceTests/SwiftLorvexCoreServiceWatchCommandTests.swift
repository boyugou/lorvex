import Dispatch
import Foundation
import GRDB
import LorvexStore
import XCTest

@testable import LorvexCore

final class SwiftLorvexCoreServiceWatchCommandTests: XCTestCase {
  private let source = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

  func testCrashRestartReplayForCaptureDeferAndHabitIsSingleEffect() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    var service: SwiftLorvexCoreService? = fixture.open()
    let task = try await service!.createTask(title: "Defer once", notes: "")
    let habit = try await service!.createHabit(
      name: "Complete once", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: .daily)
    let workspace = try await service!.currentWatchWorkspaceInstanceID()

    let capture = try command(
      workspace: workspace, sequence: 50,
      id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      mutation: .captureTask(title: "Captured exactly once"))
    let captureFirst = await service!.applyWatchCommand(capture)
    XCTAssertEqual(captureFirst.outcome, .applied)
    service = nil
    service = fixture.open()
    let captureReplay = await service!.applyWatchCommand(capture)
    XCTAssertEqual(captureReplay.outcome, .applied)
    XCTAssertEqual(try taskCount(service!, title: "Captured exactly once"), 1)

    let deferCommand = try command(
      workspace: workspace, sequence: 51,
      id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
      mutation: .deferTaskToTomorrow(id: task.id, plannedDate: "2026-07-17"))
    let deferFirst = await service!.applyWatchCommand(deferCommand)
    XCTAssertEqual(deferFirst.outcome, .applied)
    service = nil
    service = fixture.open()
    let deferReplay = await service!.applyWatchCommand(deferCommand)
    XCTAssertEqual(deferReplay.outcome, .applied)
    let deferredTask = try await service!.loadTask(id: task.id)
    XCTAssertEqual(deferredTask.deferCount, 1)

    let habitCommand = try command(
      workspace: workspace, sequence: 52,
      id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
      mutation: .completeHabit(id: habit.id, date: "2026-07-16"))
    let habitFirst = await service!.applyWatchCommand(habitCommand)
    XCTAssertEqual(habitFirst.outcome, .applied)
    service = nil
    service = fixture.open()
    let habitReplay = await service!.applyWatchCommand(habitCommand)
    XCTAssertEqual(habitReplay.outcome, .applied)
    let value: Int = try service!.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT value FROM habit_completions WHERE habit_id = ? AND completed_date = ?",
        arguments: [habit.id, "2026-07-16"]) ?? 0
    }
    XCTAssertEqual(value, 1)
  }

  func testGapRetryThenMissingSequenceUnblocksWithoutAReceiptForRetry() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let service = fixture.open()
    let workspace = try await service.currentWatchWorkspaceInstanceID()
    let first = try command(
      workspace: workspace, sequence: 7,
      id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      mutation: .captureTask(title: "First"))
    let gap = try command(
      workspace: workspace, sequence: 9,
      id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
      mutation: .captureTask(title: "After gap"))
    let missing = try command(
      workspace: workspace, sequence: 8,
      id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
      mutation: .captureTask(title: "Missing"))

    let firstAck = await service.applyWatchCommand(first)
    XCTAssertEqual(firstAck.outcome, .applied)
    let retry = await service.applyWatchCommand(gap)
    XCTAssertEqual(retry.outcome, .retryable)
    XCTAssertEqual(retry.code, WatchCommandLedger.sequenceGapCode)
    XCTAssertEqual(try receiptCount(service), 1)
    let missingAck = await service.applyWatchCommand(missing)
    XCTAssertEqual(missingAck.outcome, .applied)
    let gapAck = await service.applyWatchCommand(gap)
    XCTAssertEqual(gapAck.outcome, .applied)
    XCTAssertEqual(try receiptCount(service), 3)
  }

  func testConcurrentSameCommandProducesOneCapture() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let service = fixture.open()
    let workspace = try await service.currentWatchWorkspaceInstanceID()
    let command = try command(
      workspace: workspace, sequence: 100,
      id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      mutation: .captureTask(title: "Concurrent once"))

    async let first = service.applyWatchCommand(command)
    async let second = service.applyWatchCommand(command)
    let outcomes = await [first.outcome, second.outcome]

    XCTAssertEqual(outcomes, [.applied, .applied])
    XCTAssertEqual(try taskCount(service, title: "Concurrent once"), 1)
    XCTAssertEqual(try receiptCount(service), 1)
  }

  func testDeterministicRejectionIsDurableAndAdvancesSequence() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    var service: SwiftLorvexCoreService? = fixture.open()
    let workspace = try await service!.currentWatchWorkspaceInstanceID()
    let missing = try command(
      workspace: workspace, sequence: 30,
      id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      mutation: .completeTask(id: "ffffffff-ffff-4fff-8fff-ffffffffffff"))
    let next = try command(
      workspace: workspace, sequence: 31,
      id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
      mutation: .captureTask(title: "After rejection"))

    let rejection = await service!.applyWatchCommand(missing)
    XCTAssertEqual(rejection.outcome, .rejected)
    XCTAssertEqual(rejection.code, "not_found")
    service = nil
    service = fixture.open()
    let rejectionReplay = await service!.applyWatchCommand(missing)
    XCTAssertEqual(rejectionReplay, rejection)
    let nextAck = await service!.applyWatchCommand(next)
    XCTAssertEqual(nextAck.outcome, .applied)
    XCTAssertEqual(try taskCount(service!, title: "After rejection"), 1)
  }

  func testCorruptStoredReceiptReturnsRetryableInsteadOfCrashing() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let service = fixture.open()
    let workspace = try await service.currentWatchWorkspaceInstanceID()
    let command = try command(
      workspace: workspace, sequence: 1,
      id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      mutation: .completeTask(id: "ffffffff-ffff-4fff-8fff-ffffffffffff"))
    let rejection = await service.applyWatchCommand(command)
    XCTAssertEqual(rejection.outcome, .rejected)

    try service.write { db in
      try db.execute(sql: "PRAGMA ignore_check_constraints = ON")
      try db.execute(
        sql: "UPDATE local_watch_command_receipts SET code = 'INVALID CODE!' WHERE sequence = 1")
      try db.execute(sql: "PRAGMA ignore_check_constraints = OFF")
    }

    let ack = await service.applyWatchCommand(command)
    XCTAssertEqual(ack.outcome, .retryable)
    XCTAssertEqual(ack.code, "receipt_corrupt")
  }

  func testExpectedNextCommandIDCollisionIsTerminalAndDoesNotBlockFollowingCommand() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let service = fixture.open()
    let workspace = try await service.currentWatchWorkspaceInstanceID()
    let reusedID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    let first = try command(
      workspace: workspace, sequence: 4, id: reusedID,
      mutation: .captureTask(title: "Original id"))
    let collision = try command(
      workspace: workspace, sequence: 5, id: reusedID,
      mutation: .captureTask(title: "Must not apply"))
    let following = try command(
      workspace: workspace, sequence: 6,
      id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
      mutation: .captureTask(title: "Following command"))

    let firstAck = await service.applyWatchCommand(first)
    XCTAssertEqual(firstAck.outcome, .applied)
    let rejection = await service.applyWatchCommand(collision)
    XCTAssertEqual(rejection.outcome, .rejected)
    XCTAssertEqual(rejection.code, WatchCommandLedger.commandIDCollisionCode)
    let rejectionReplay = await service.applyWatchCommand(collision)
    XCTAssertEqual(rejectionReplay, rejection)
    let followingAck = await service.applyWatchCommand(following)
    XCTAssertEqual(followingAck.outcome, .applied)
    XCTAssertEqual(try taskCount(service, title: "Must not apply"), 0)
    XCTAssertEqual(try taskCount(service, title: "Following command"), 1)
  }

  func testFocusNoOpCheckAndAppliedReceiptShareTheWriteTransaction() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let service = fixture.open()
    let peer = fixture.open()
    let task = try await service.createTask(title: "Concurrent focus add", notes: "")
    let workspace = try await service.currentWatchWorkspaceInstanceID()
    let remove = try command(
      workspace: workspace, sequence: 1,
      id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      mutation: .removeFromFocus(id: task.id, date: "2026-07-16"))
    let enteredPreTransactionWindow = expectation(
      description: "Watch removal reached the pre-transaction window")
    let releaseCommand = DispatchSemaphore(value: 0)

    let commandTask = Task {
      await SwiftLorvexCoreService.$afterWriteStateBarrierForTesting.withValue({
        enteredPreTransactionWindow.fulfill()
        releaseCommand.wait()
      }) {
        await service.applyWatchCommand(remove)
      }
    }

    await fulfillment(of: [enteredPreTransactionWindow], timeout: 5)

    // The peer lands the task after the Watch call starts but before the Watch
    // transaction begins. The locked recheck must observe and remove it before
    // committing the applied receipt.
    _ = try await peer.addToCurrentFocus(
      date: "2026-07-16", taskIDs: [task.id], briefing: nil, timezone: "UTC")
    releaseCommand.signal()

    let acknowledgement = await commandTask.value
    XCTAssertEqual(acknowledgement.outcome, .applied)
    let focusAfterApplication = try await service.loadCurrentFocus(date: "2026-07-16")
    XCTAssertNil(focusAfterApplication)
    XCTAssertEqual(try receiptCount(service), 1)

    let replay = await service.applyWatchCommand(remove)
    XCTAssertEqual(replay, acknowledgement)
    let focusAfterReplay = try await service.loadCurrentFocus(date: "2026-07-16")
    XCTAssertNil(focusAfterReplay)
  }

  private func command(
    workspace: String,
    sequence: Int64,
    id: String,
    mutation: LorvexWatchMutation
  ) throws -> LorvexWatchCommand {
    try LorvexWatchCommand(
      sourceInstallID: source,
      workspaceInstanceID: workspace,
      sequence: sequence,
      commandID: id,
      createdAt: "2026-07-16T12:00:00.000Z",
      mutation: mutation)
  }

  private func taskCount(_ service: SwiftLorvexCoreService, title: String) throws -> Int {
    try service.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks WHERE title = ?", arguments: [title])
        ?? 0
    }
  }

  private func receiptCount(_ service: SwiftLorvexCoreService) throws -> Int {
    try service.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM local_watch_command_receipts") ?? 0
    }
  }

  private final class Fixture {
    let directory: URL
    let databaseURL: URL
    let schemaSQL: String

    init() throws {
      directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "lorvex-watch-command-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      databaseURL = directory.appendingPathComponent("lorvex.sqlite")
      let schemaURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("schema/schema.sql")
      schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    }

    func open() -> SwiftLorvexCoreService {
      SwiftLorvexCoreService(databasePath: databaseURL.path, schemaSQL: schemaSQL)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
  }
}
