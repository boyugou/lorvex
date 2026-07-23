import Foundation
import GRDB
import LorvexDomain
import LorvexStore

extension SwiftLorvexCoreService: LorvexWatchCommandServicing {
  /// Resolve the physical-database identity through the same cutover-guarded
  /// transaction used for Watch ledger maintenance, then expose its canonical
  /// lowercase UUID wire form.
  public func currentWatchWorkspaceInstanceID() async throws -> String {
    try withWatchCommandMaintenanceWrite { db in
      try WatchCommandLedger.currentWorkspaceInstanceID(db)
    }
  }

  public func applyWatchCommand(
    _ command: LorvexWatchCommand
  ) async -> LorvexWatchCommandAck {
    do {
      let terminal = try await Self.$currentWatchCommand.withValue(command) {
        try await applyWatchMutation(command.mutation)
        // Every command passes through one ordinary write transaction, which
        // commits this receipt atomically with its domain effect or no-op check.
        return WatchCommandTerminalReceipt(outcome: .applied, code: nil, message: nil)
      }
      return makeWatchAck(command: command, terminal: terminal)
    } catch let signal as WatchCommandGateSignal {
      if case .rejectAndRecord(let code, let message) = signal.gate {
        do {
          let terminal = try ensureWatchTerminal(
            command,
            desired: WatchCommandTerminalReceipt(
              outcome: .rejected, code: code, message: message))
          return makeWatchAck(command: command, terminal: terminal)
        } catch let nested as WatchCommandGateSignal {
          return makeWatchAck(command: command, gate: nested.gate)
        } catch {
          return makeWatchAck(
            command: command,
            gate: .retryable(code: "receipt_write_failed", message: nil))
        }
      }
      return makeWatchAck(command: command, gate: signal.gate)
    } catch WatchCommandLedgerError.invalidTerminalReceipt {
      return LorvexWatchCommandAck(trustedReceiptCorruptFor: command)
    } catch {
      if let rejection = deterministicWatchRejection(for: error) {
        do {
          let terminal = try ensureWatchTerminal(command, desired: rejection)
          return makeWatchAck(command: command, terminal: terminal)
        } catch let signal as WatchCommandGateSignal {
          return makeWatchAck(command: command, gate: signal.gate)
        } catch {
          return makeWatchAck(
            command: command,
            gate: .retryable(code: "receipt_write_failed", message: nil))
        }
      }
      return makeWatchAck(
        command: command,
        gate: .retryable(code: "temporary_failure", message: nil))
    }
  }

  // MARK: - Write-funnel hooks

  func preflightCurrentWatchCommand(_ db: Database) throws {
    guard let command = Self.currentWatchCommand else { return }
    let gate = try WatchCommandLedger.preflight(db, command: ledgerCommand(command))
    guard gate == .apply else { throw WatchCommandGateSignal(gate: gate) }
  }

  func recordCurrentWatchCommandApplied(_ db: Database) throws {
    guard let command = Self.currentWatchCommand else { return }
    _ = try WatchCommandLedger.recordTerminal(
      db,
      command: ledgerCommand(command),
      receipt: WatchCommandTerminalReceipt(outcome: .applied, code: nil, message: nil))
  }

  // MARK: - Domain routing

  private func applyWatchMutation(_ mutation: LorvexWatchMutation) async throws {
    switch mutation {
    case .completeTask(let id):
      _ = try await completeTask(id: id)
    case .cancelTask(let id):
      _ = try await cancelTask(id: id)
    case .deferTaskToTomorrow(let id, let plannedDate):
      guard let ymd = IsoDate.parse(plannedDate) else {
        throw LorvexCoreError.validation(
          field: "planned_date", message: "The planned date is invalid.")
      }
      _ = try await deferTask(
        id: id, until: IsoDate.ymdToDate(ymd), reason: nil, note: nil)
    case .removeFromFocus(let id, let date):
      _ = try await removeFromCurrentFocus(date: date, taskID: id)
    case .captureTask(let title):
      _ = try await createTask(title: title, notes: "")
    case .completeHabit(let id, let date):
      _ = try await completeHabit(id: id, date: date)
    }
  }

  private func ensureWatchTerminal(
    _ command: LorvexWatchCommand,
    desired: WatchCommandTerminalReceipt
  ) throws -> WatchCommandTerminalReceipt {
    try withWatchCommandMaintenanceWrite { db in
      let ledgerCommand = ledgerCommand(command)
      let gate = try WatchCommandLedger.preflight(db, command: ledgerCommand)
      switch gate {
      case .apply:
        return try WatchCommandLedger.recordTerminal(
          db, command: ledgerCommand, receipt: desired)
      case .replay(let receipt):
        return receipt
      case .rejectAndRecord(let code, let message):
        return try WatchCommandLedger.recordPreflightRejection(
          db, command: ledgerCommand, code: code, message: message)
      case .retryable, .rejected:
        throw WatchCommandGateSignal(gate: gate)
      }
    }
  }

  private func ledgerCommand(_ command: LorvexWatchCommand) -> WatchCommandLedgerCommand {
    WatchCommandLedgerCommand(
      sourceInstallID: command.sourceInstallID,
      workspaceInstanceID: command.workspaceInstanceID,
      sequence: command.sequence,
      commandID: command.commandID,
      payloadChecksum: command.payloadChecksum,
      createdAt: command.createdAt)
  }

  // MARK: - Outcome mapping

  private func deterministicWatchRejection(
    for error: Error
  ) -> WatchCommandTerminalReceipt? {
    let code: String
    let message: String
    switch error {
    case LorvexCoreError.taskNotFound:
      (code, message) = ("not_found", "The task no longer exists.")
    case LorvexCoreError.emptyTitle:
      (code, message) = ("invalid_title", "The task title is invalid.")
    case LorvexCoreError.notFound:
      (code, message) = ("not_found", "The target no longer exists.")
    case LorvexCoreError.validation:
      (code, message) = ("validation_failed", "The command is no longer valid.")
    case LorvexCoreError.conflict:
      (code, message) = ("conflict", "The command conflicts with current data.")
    case is ValidationError:
      (code, message) = ("validation_failed", "The command is no longer valid.")
    case StoreError.notFound:
      (code, message) = ("not_found", "The target no longer exists.")
    case StoreError.validation:
      (code, message) = ("validation_failed", "The command is no longer valid.")
    default:
      return nil
    }
    return WatchCommandTerminalReceipt(outcome: .rejected, code: code, message: message)
  }

  private func makeWatchAck(
    command: LorvexWatchCommand,
    terminal: WatchCommandTerminalReceipt
  ) -> LorvexWatchCommandAck {
    switch terminal.outcome {
    case .applied:
      return validatedWatchAck(command: command, outcome: .applied)
    case .rejected:
      return validatedWatchAck(
        command: command, outcome: .rejected,
        code: terminal.code ?? "rejected", message: terminal.message)
    }
  }

  private func makeWatchAck(
    command: LorvexWatchCommand,
    gate: WatchCommandLedgerGate
  ) -> LorvexWatchCommandAck {
    switch gate {
    case .apply:
      return validatedWatchAck(
        command: command, outcome: .retryable, code: "temporary_failure")
    case .replay(let receipt):
      return makeWatchAck(command: command, terminal: receipt)
    case .retryable(let code, let message):
      return validatedWatchAck(
        command: command, outcome: .retryable, code: code, message: message)
    case .rejectAndRecord(let code, let message):
      return validatedWatchAck(
        command: command, outcome: .rejected, code: code, message: message)
    case .rejected(let code, let message):
      return validatedWatchAck(
        command: command, outcome: .rejected, code: code, message: message)
    }
  }

  private func validatedWatchAck(
    command: LorvexWatchCommand,
    outcome: LorvexWatchCommandAck.Outcome,
    code: String? = nil,
    message: String? = nil
  ) -> LorvexWatchCommandAck {
    do {
      return try LorvexWatchCommandAck(
        command: command, outcome: outcome, code: code, message: message)
    } catch {
      // Never bypass validation with receipt-controlled fields. A corrupt local
      // row yields one fixed retryable ACK and remains available for diagnosis.
      return LorvexWatchCommandAck(trustedReceiptCorruptFor: command)
    }
  }
}

/// Escapes a write transaction before any mutation for replay/retry/rejection.
struct WatchCommandGateSignal: Error {
  let gate: WatchCommandLedgerGate
}
