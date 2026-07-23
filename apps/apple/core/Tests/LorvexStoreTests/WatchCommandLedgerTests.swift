import GRDB
import XCTest

@testable import LorvexStore

final class WatchCommandLedgerTests: XCTestCase {
  private let source = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
  private let workspace = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"

  func testFirstSequenceMayStartAboveOneAndReceiptReplaysIndefinitely() throws {
    let store = try preparedStore()
    let command = makeCommand(sequence: 41, commandID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")

    try store.writer.write { db in
      XCTAssertEqual(try WatchCommandLedger.preflight(db, command: command), .apply)
      let terminal = WatchCommandTerminalReceipt(outcome: .applied, code: nil, message: nil)
      XCTAssertEqual(
        try WatchCommandLedger.recordTerminal(db, command: command, receipt: terminal), terminal)
      XCTAssertEqual(
        try WatchCommandLedger.preflight(db, command: command), .replay(terminal))
    }
  }

  func testGapIsRetryableAndCreatesNoTerminalRow() throws {
    let store = try preparedStore()
    let first = makeCommand(sequence: 8, commandID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")
    let gap = makeCommand(sequence: 10, commandID: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")

    try store.writer.write { db in
      try WatchCommandLedger.recordTerminal(
        db, command: first,
        receipt: WatchCommandTerminalReceipt(outcome: .applied, code: nil, message: nil))
      XCTAssertEqual(
        try WatchCommandLedger.preflight(db, command: gap),
        .retryable(
          code: WatchCommandLedger.sequenceGapCode,
          message: "An earlier Watch command must be delivered first."))
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM local_watch_command_receipts"), 1)
    }
  }

  func testTerminalRejectionAdvancesSequence() throws {
    let store = try preparedStore()
    let rejected = makeCommand(sequence: 20, commandID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")
    let next = makeCommand(sequence: 21, commandID: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")
    let terminal = WatchCommandTerminalReceipt(
      outcome: .rejected, code: "not_found", message: "The target no longer exists.")

    try store.writer.write { db in
      try WatchCommandLedger.recordTerminal(db, command: rejected, receipt: terminal)
      XCTAssertEqual(try WatchCommandLedger.preflight(db, command: rejected), .replay(terminal))
      XCTAssertEqual(try WatchCommandLedger.preflight(db, command: next), .apply)
    }
  }

  func testCommandIDChecksumCollisionAndSequenceReuseReject() throws {
    let store = try preparedStore()
    let first = makeCommand(sequence: 3, commandID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")
    let checksumCollision = WatchCommandLedgerCommand(
      sourceInstallID: source, workspaceInstanceID: workspace, sequence: 3,
      commandID: first.commandID, payloadChecksum: String(repeating: "1", count: 64),
      createdAt: first.createdAt)
    let sequenceReuse = makeCommand(
      sequence: 3, commandID: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")

    try store.writer.write { db in
      try WatchCommandLedger.recordTerminal(
        db, command: first,
        receipt: WatchCommandTerminalReceipt(outcome: .applied, code: nil, message: nil))
      XCTAssertEqual(
        try WatchCommandLedger.preflight(db, command: checksumCollision),
        .rejected(
          code: WatchCommandLedger.commandIDCollisionCode,
          message: "The command identifier was already used for different content."))
      XCTAssertEqual(
        try WatchCommandLedger.preflight(db, command: sequenceReuse),
        .rejected(
          code: WatchCommandLedger.sequenceReuseCode,
          message: "The command sequence was already used by another command."))
    }
  }

  func testExpectedNextCommandIDReuseIsRecordedAndAdvancesHighWater() throws {
    let store = try preparedStore()
    let first = makeCommand(sequence: 70, commandID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")
    let collision = WatchCommandLedgerCommand(
      sourceInstallID: source, workspaceInstanceID: workspace, sequence: 71,
      commandID: first.commandID, payloadChecksum: String(repeating: "1", count: 64),
      createdAt: first.createdAt)
    let next = makeCommand(sequence: 72, commandID: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")

    try store.writer.write { db in
      try WatchCommandLedger.recordTerminal(
        db, command: first,
        receipt: WatchCommandTerminalReceipt(outcome: .applied, code: nil, message: nil))
      let gate = try WatchCommandLedger.preflight(db, command: collision)
      XCTAssertEqual(
        gate,
        .rejectAndRecord(
          code: WatchCommandLedger.commandIDCollisionCode,
          message: "The command identifier was already used for different content."))
      guard case .rejectAndRecord(let code, let message) = gate else {
        return XCTFail("expected a durable protocol rejection")
      }
      let terminal = try WatchCommandLedger.recordPreflightRejection(
        db, command: collision, code: code, message: message)
      XCTAssertEqual(terminal.outcome, .rejected)
      XCTAssertEqual(try WatchCommandLedger.preflight(db, command: collision), .replay(terminal))
      XCTAssertEqual(try WatchCommandLedger.preflight(db, command: next), .apply)
    }
  }

  func testWorkspaceMismatchNeverCreatesAStreamOrReceipt() throws {
    let store = try preparedStore()
    let command = WatchCommandLedgerCommand(
      sourceInstallID: source,
      workspaceInstanceID: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
      sequence: 1,
      commandID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      payloadChecksum: String(repeating: "0", count: 64),
      createdAt: "2026-07-16T12:00:00.000Z")

    try store.writer.write { db in
      XCTAssertEqual(
        try WatchCommandLedger.preflight(db, command: command),
        .rejected(
          code: WatchCommandLedger.workspaceReplacedCode,
          message: "The phone workspace was replaced. Refresh the Watch replica."))
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM local_watch_command_streams"), 0)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM local_watch_command_receipts"), 0)
    }
  }

  func testSchemaRejectsNoncanonicalLedgerIdentityAndUnsafeCode() throws {
    let store = try preparedStore()
    try store.writer.write { db in
      XCTAssertThrowsError(
        try db.execute(
          sql: """
            INSERT INTO local_watch_command_streams (
              source_install_id, workspace_instance_id, last_terminal_sequence, updated_at
            ) VALUES (?, ?, 1, '2026-07-16T12:00:00.000Z')
            """,
          arguments: [source.uppercased(), workspace]))

      let command = makeCommand(
        sequence: 1, commandID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")
      try WatchCommandLedger.recordTerminal(
        db, command: command,
        receipt: WatchCommandTerminalReceipt(outcome: .applied, code: nil, message: nil))
      XCTAssertThrowsError(
        try db.execute(
          sql: "UPDATE local_watch_command_receipts SET outcome = 'rejected', code = 'BAD CODE'"))
    }
  }

  private func preparedStore() throws -> LorvexStore {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId, value: workspace)
    }
    return store
  }

  private func makeCommand(sequence: Int64, commandID: String) -> WatchCommandLedgerCommand {
    WatchCommandLedgerCommand(
      sourceInstallID: source,
      workspaceInstanceID: workspace,
      sequence: sequence,
      commandID: commandID,
      payloadChecksum: String(repeating: "0", count: 64),
      createdAt: "2026-07-16T12:00:00.000Z")
  }
}
