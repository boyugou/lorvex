import Foundation
import GRDB
import LorvexDomain

/// Store-layer identity of one strictly validated Watch command.
public struct WatchCommandLedgerCommand: Sendable, Equatable {
  public let sourceInstallID: String
  public let workspaceInstanceID: String
  public let sequence: Int64
  public let commandID: String
  public let payloadChecksum: String
  public let createdAt: String

  public init(
    sourceInstallID: String,
    workspaceInstanceID: String,
    sequence: Int64,
    commandID: String,
    payloadChecksum: String,
    createdAt: String
  ) {
    self.sourceInstallID = sourceInstallID
    self.workspaceInstanceID = workspaceInstanceID
    self.sequence = sequence
    self.commandID = commandID
    self.payloadChecksum = payloadChecksum
    self.createdAt = createdAt
  }
}

public enum WatchCommandTerminalOutcome: String, Sendable, Equatable {
  case applied
  case rejected
}

/// An indefinite local receipt. No timestamp-based eviction is permitted.
public struct WatchCommandTerminalReceipt: Sendable, Equatable {
  public let outcome: WatchCommandTerminalOutcome
  public let code: String?
  public let message: String?

  public init(outcome: WatchCommandTerminalOutcome, code: String?, message: String?) {
    self.outcome = outcome
    self.code = code
    self.message = message
  }
}

/// Transaction-start decision made before any domain mutation or HLC mint.
public enum WatchCommandLedgerGate: Sendable, Equatable {
  case apply
  case replay(WatchCommandTerminalReceipt)
  case retryable(code: String, message: String?)
  /// The command is the next sequence but is protocol-invalid. The service
  /// must persist this rejection and advance high-water before ACKing it.
  case rejectAndRecord(code: String, message: String?)
  case rejected(code: String, message: String?)
}

public enum WatchCommandLedgerError: Error, Sendable, Equatable {
  case invalidDatabaseInstanceID
  case gateChanged(WatchCommandLedgerGate)
  case invalidTerminalReceipt
}

/// Local-only Watch command receipt and per-stream sequence high-water access.
public enum WatchCommandLedger {
  public static let workspaceReplacedCode = "workspace_replaced"
  public static let commandIDCollisionCode = "command_id_collision"
  public static let sequenceReuseCode = "sequence_reuse"
  public static let sequenceGapCode = "sequence_gap"

  /// Canonical lowercase UUID for the physical database owning `db`.
  public static func currentWorkspaceInstanceID(_ db: Database) throws -> String {
    let raw = try SyncCheckpoints.getOrCreateDatabaseInstanceId(db)
    let canonical = raw.lowercased()
    guard case .success(let parsed) = EntityID.parseIDWithSentinel(
      canonical, field: "workspace_instance_id", sentinel: nil), parsed == canonical
    else { throw WatchCommandLedgerError.invalidDatabaseInstanceID }
    return canonical
  }

  /// Must run as the first protocol operation inside `BEGIN IMMEDIATE`.
  public static func preflight(
    _ db: Database,
    command: WatchCommandLedgerCommand
  ) throws -> WatchCommandLedgerGate {
    let currentWorkspace = try currentWorkspaceInstanceID(db)
    guard command.workspaceInstanceID == currentWorkspace else {
      return .rejected(
        code: workspaceReplacedCode,
        message: "The phone workspace was replaced. Refresh the Watch replica.")
    }

    if let receipt = try receiptForSequence(db, command: command) {
      guard receipt.commandID == command.commandID else {
        return .rejected(
          code: sequenceReuseCode,
          message: "The command sequence was already used by another command.")
      }
      guard receipt.payloadChecksum == command.payloadChecksum else {
        return .rejected(
          code: commandIDCollisionCode,
          message: "The command identifier was already used for different content.")
      }
      return .replay(receipt.terminal)
    }

    guard let highWater = try highWater(db, command: command) else {
      // A new workspace stream may begin at any positive sequence. This lets a
      // Watch keep its monotonic install-wide counter across a database reset.
      return .apply
    }
    guard highWater < Int64.max else {
      return .rejected(
        code: sequenceReuseCode,
        message: "The command sequence is behind the terminal high-water mark.")
    }
    let expectedSequence = highWater + 1
    if command.sequence > expectedSequence {
      return .retryable(
        code: sequenceGapCode,
        message: "An earlier Watch command must be delivered first.")
    }
    if command.sequence < expectedSequence {
      return .rejected(
        code: sequenceReuseCode,
        message: "The command sequence is behind the terminal high-water mark.")
    }
    // Reaching this point means `sequence == highWater + 1`.
    if try commandIDExists(db, command: command) {
      return .rejectAndRecord(
        code: commandIDCollisionCode,
        message: "The command identifier was already used for different content.")
    }
    return .apply
  }

  /// Writes the terminal receipt and advances the stream high-water atomically
  /// in the caller's already-open immediate transaction.
  @discardableResult
  public static func recordTerminal(
    _ db: Database,
    command: WatchCommandLedgerCommand,
    receipt: WatchCommandTerminalReceipt,
    recordedAt: String = SyncTimestamp.now().asString
  ) throws -> WatchCommandTerminalReceipt {
    try validate(receipt)
    let gate = try preflight(db, command: command)
    switch gate {
    case .apply:
      break
    case .replay(let existing):
      return existing
    case .retryable, .rejectAndRecord, .rejected:
      throw WatchCommandLedgerError.gateChanged(gate)
    }

    return try insertTerminal(
      db, command: command, receipt: receipt, recordedAt: recordedAt)
  }

  /// Persist the protocol-terminal rejection returned as `rejectAndRecord`.
  /// This is intentionally a separate maintenance transaction before the domain
  /// write, so the rejection commits while no HLC/domain effect can begin.
  @discardableResult
  public static func recordPreflightRejection(
    _ db: Database,
    command: WatchCommandLedgerCommand,
    code: String,
    message: String?,
    recordedAt: String = SyncTimestamp.now().asString
  ) throws -> WatchCommandTerminalReceipt {
    let gate = try preflight(db, command: command)
    guard case .rejectAndRecord(let expectedCode, let expectedMessage) = gate,
      code == expectedCode, message == expectedMessage
    else { throw WatchCommandLedgerError.gateChanged(gate) }
    let receipt = WatchCommandTerminalReceipt(
      outcome: .rejected, code: code, message: message)
    try validate(receipt)
    return try insertTerminal(
      db, command: command, receipt: receipt, recordedAt: recordedAt)
  }

  private static func insertTerminal(
    _ db: Database,
    command: WatchCommandLedgerCommand,
    receipt: WatchCommandTerminalReceipt,
    recordedAt: String
  ) throws -> WatchCommandTerminalReceipt {

    try db.execute(
      sql: """
        INSERT INTO local_watch_command_streams (
          source_install_id, workspace_instance_id, last_terminal_sequence, updated_at
        ) VALUES (?, ?, ?, ?)
        ON CONFLICT(source_install_id, workspace_instance_id) DO UPDATE SET
          last_terminal_sequence = excluded.last_terminal_sequence,
          updated_at = excluded.updated_at
        """,
      arguments: [
        command.sourceInstallID, command.workspaceInstanceID, command.sequence, recordedAt,
      ])
    try db.execute(
      sql: """
        INSERT INTO local_watch_command_receipts (
          source_install_id, workspace_instance_id, command_id, sequence,
          payload_checksum, outcome, code, message, command_created_at, recorded_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
      arguments: [
        command.sourceInstallID, command.workspaceInstanceID, command.commandID,
        command.sequence, command.payloadChecksum, receipt.outcome.rawValue,
        receipt.code, receipt.message, command.createdAt, recordedAt,
      ])
    return receipt
  }

  private struct StoredReceipt {
    let commandID: String
    let payloadChecksum: String
    let terminal: WatchCommandTerminalReceipt
  }

  private static func receiptForSequence(
    _ db: Database,
    command: WatchCommandLedgerCommand
  ) throws -> StoredReceipt? {
    guard let row = try Row.fetchOne(
      db,
      sql: """
        SELECT command_id, payload_checksum, outcome, code, message
        FROM local_watch_command_receipts
        WHERE source_install_id = ? AND workspace_instance_id = ? AND sequence = ?
        """,
      arguments: [command.sourceInstallID, command.workspaceInstanceID, command.sequence])
    else { return nil }
    guard let outcome = WatchCommandTerminalOutcome(rawValue: row["outcome"]) else {
      throw WatchCommandLedgerError.invalidTerminalReceipt
    }
    let terminal = WatchCommandTerminalReceipt(
      outcome: outcome, code: row["code"], message: row["message"])
    try validate(terminal)
    return StoredReceipt(
      commandID: row["command_id"], payloadChecksum: row["payload_checksum"], terminal: terminal)
  }

  private static func commandIDExists(
    _ db: Database,
    command: WatchCommandLedgerCommand
  ) throws -> Bool {
    try Bool.fetchOne(
      db,
      sql: """
        SELECT EXISTS(
          SELECT 1 FROM local_watch_command_receipts
          WHERE source_install_id = ? AND workspace_instance_id = ? AND command_id = ?
        )
        """,
      arguments: [command.sourceInstallID, command.workspaceInstanceID, command.commandID]) ?? false
  }

  private static func highWater(
    _ db: Database,
    command: WatchCommandLedgerCommand
  ) throws -> Int64? {
    try Int64.fetchOne(
      db,
      sql: """
        SELECT last_terminal_sequence FROM local_watch_command_streams
        WHERE source_install_id = ? AND workspace_instance_id = ?
        """,
      arguments: [command.sourceInstallID, command.workspaceInstanceID])
  }

  private static func validate(_ receipt: WatchCommandTerminalReceipt) throws {
    switch receipt.outcome {
    case .applied:
      guard receipt.code == nil, receipt.message == nil else {
        throw WatchCommandLedgerError.invalidTerminalReceipt
      }
    case .rejected:
      guard let code = receipt.code, !code.isEmpty, code.utf8.count <= 64,
        code.utf8.allSatisfy({
          ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 95 || $0 == 46
        }),
        receipt.message.map({ !$0.isEmpty && $0.utf8.count <= 2_048 }) ?? true
      else {
        throw WatchCommandLedgerError.invalidTerminalReceipt
      }
    }
  }
}
