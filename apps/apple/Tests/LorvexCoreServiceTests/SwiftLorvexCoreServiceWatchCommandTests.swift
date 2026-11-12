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

  func testPauseNoOpCheckAndAppliedReceiptShareTheWriteTransaction() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let service = fixture.open()
    let peer = fixture.open()
    let task = try await service.createTask(title: "Concurrent start", notes: "")
    let workspace = try await service.currentWatchWorkspaceInstanceID()
    let pause = try command(
      workspace: workspace, sequence: 1,
      id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      mutation: .pauseTask(id: task.id))
    let enteredPreTransactionWindow = expectation(
      description: "Watch pause reached the pre-transaction window")
    let releaseCommand = DispatchSemaphore(value: 0)

    let commandTask = Task {
      await SwiftLorvexCoreService.$afterWriteStateBarrierForTesting.withValue({
        enteredPreTransactionWindow.fulfill()
        releaseCommand.wait()
      }) {
        await service.applyWatchCommand(pause)
      }
    }

    await fulfillment(of: [enteredPreTransactionWindow], timeout: 5)

    // The peer starts the task after the Watch call begins but before the Watch
    // transaction does. The locked recheck must observe the start and pause the
    // task before committing the applied receipt.
    _ = try await peer.startTask(id: task.id)
    releaseCommand.signal()

    let acknowledgement = await commandTask.value
    XCTAssertEqual(acknowledgement.outcome, .applied)
    let statusAfterApplication = try await service.loadTask(id: task.id).status
    XCTAssertEqual(statusAfterApplication, .open)
    XCTAssertEqual(try receiptCount(service), 1)

    let replay = await service.applyWatchCommand(pause)
    XCTAssertEqual(replay, acknowledgement)
    let statusAfterReplay = try await service.loadTask(id: task.id).status
    XCTAssertEqual(statusAfterReplay, .open)
  }

  /// A newer watch build can send an action this phone does not know. The
  /// phone used to answer it with no ACK; the watch then rejected it locally
  /// after three tries, and the phone, whose high-water never passed it,
  /// refused every later command as a sequence gap, so the watch could never
  /// write again. A verified unreadable action is now rejected and recorded
  /// at its sequence, and the next command applies.
  func testAnUnreadableActionIsRejectedAtItsSequenceAndTheNextCommandApplies() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let service = fixture.open()
    let workspace = try await service.currentWatchWorkspaceInstanceID()
    let first = try command(
      workspace: workspace, sequence: 7,
      id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      mutation: .captureTask(title: "Before"))
    let unreadable = try unreadableActionData(
      workspace: workspace, sequence: 8, id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")
    let next = try command(
      workspace: workspace, sequence: 9,
      id: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
      mutation: .captureTask(title: "After"))

    let firstAck = await service.applyWatchCommand(first)
    XCTAssertEqual(firstAck.outcome, .applied)
    XCTAssertThrowsError(try LorvexWatchCommand.decodeWireData(unreadable))
    let identity = try XCTUnwrap(LorvexWatchCommand.identityOfUnreadableAction(in: unreadable))
    XCTAssertEqual(identity.sequence, 8)

    let rejection = await service.rejectWatchCommandWithUnreadableAction(identity)
    XCTAssertEqual(rejection.outcome, .rejected)
    XCTAssertEqual(rejection.code, LorvexWatchCommandAck.unreadableActionCode)
    XCTAssertEqual(rejection.commandID, identity.commandID)
    XCTAssertEqual(rejection.payloadChecksum, identity.payloadChecksum)
    // A retry replays the recorded rejection.
    let replay = await service.rejectWatchCommandWithUnreadableAction(identity)
    XCTAssertEqual(replay, rejection)

    let nextAck = await service.applyWatchCommand(next)
    XCTAssertEqual(nextAck.outcome, .applied)
    XCTAssertEqual(try taskCount(service, title: "After"), 1)
    XCTAssertEqual(try receiptCount(service), 3)
  }

  /// The ledger's ordering holds for an unreadable action as for any command:
  /// one that arrives ahead of an earlier command waits for it.
  func testAnUnreadableActionAheadOfAnEarlierCommandWaitsForIt() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let service = fixture.open()
    let workspace = try await service.currentWatchWorkspaceInstanceID()
    let first = try command(
      workspace: workspace, sequence: 7,
      id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      mutation: .captureTask(title: "Before"))
    let identity = try XCTUnwrap(
      LorvexWatchCommand.identityOfUnreadableAction(
        in: try unreadableActionData(
          workspace: workspace, sequence: 9, id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")))

    let firstAck = await service.applyWatchCommand(first)
    XCTAssertEqual(firstAck.outcome, .applied)
    let ack = await service.rejectWatchCommandWithUnreadableAction(identity)
    XCTAssertEqual(ack.outcome, .retryable)
    XCTAssertEqual(ack.code, WatchCommandLedger.sequenceGapCode)
    XCTAssertEqual(try receiptCount(service), 1)
  }

  func testOnlyAVerifiedCommandWithAnUnreadableActionHasAnIdentity() throws {
    let workspace = "ffffffff-ffff-4fff-8fff-ffffffffffff"
    // A command this build reads is never rejected as unreadable.
    let readable = try command(
      workspace: workspace, sequence: 3,
      id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      mutation: .captureTask(title: "Readable"))
    XCTAssertNil(LorvexWatchCommand.identityOfUnreadableAction(in: try readable.wireData()))

    // A known action with a field this build does not know is unreadable too.
    let extraField = try unreadableActionData(
      workspace: workspace, sequence: 3, id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      mutation: ["type": "capture_task", "title": "With a list", "list_id": "inbox"])
    XCTAssertNotNil(LorvexWatchCommand.identityOfUnreadableAction(in: extraField))

    // Bytes that do not match their checksum have no trustworthy identity.
    let valid = try unreadableActionData(
      workspace: workspace, sequence: 3, id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
    object["sequence"] = 4
    let tampered = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    XCTAssertNil(LorvexWatchCommand.identityOfUnreadableAction(in: tampered))
  }

  /// An error that a retry of the same command cannot change must end the
  /// command, or it holds every later command from the watch behind it.
  func testDeterministicStoreErrorsRejectAndTransientOnesRetry() {
    XCTAssertEqual(
      SwiftLorvexCoreService.deterministicWatchRejection(for: StoreError.invariant("x"))?.code,
      "invalid_state")
    XCTAssertEqual(
      SwiftLorvexCoreService.deterministicWatchRejection(for: StoreError.serialization("x"))?
        .outcome, .rejected)
    XCTAssertNil(
      SwiftLorvexCoreService.deterministicWatchRejection(
        for: StoreError.staleVersion(entity: "task", id: "t")))
    XCTAssertNil(
      SwiftLorvexCoreService.deterministicWatchRejection(
        for: DatabaseError(resultCode: .SQLITE_BUSY)))
  }

  /// Wire data for a command whose action this build cannot read, with a
  /// valid identity and checksum, as a newer watch build would send it.
  private func unreadableActionData(
    workspace: String, sequence: Int64, id: String,
    mutation: [String: Any] = ["type": "snooze_task", "minutes": 10]
  ) throws -> Data {
    var object: [String: Any] = [
      "protocol_version": LorvexWatchCommand.currentProtocolVersion,
      "workspace_instance_id": workspace,
      "source_install_id": source,
      "sequence": sequence,
      "command_id": id,
      "created_at": "2026-07-16T12:00:00.000Z",
      "mutation": mutation,
    ]
    object["payload_checksum"] = try LorvexWatchWire.checksum(object)
    return try LorvexWatchWire.jsonData(object)
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
