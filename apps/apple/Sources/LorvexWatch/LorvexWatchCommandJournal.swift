import Foundation
import LorvexCore

enum LorvexWatchCommandJournalError: LocalizedError, Equatable {
  case corrupt
  case unsupportedVersion(Int)
  case invalidInvariant
  case sequenceExhausted
  case acknowledgementMismatch
  case acknowledgementOutOfOrder

  var errorDescription: String? {
    switch self {
    case .corrupt:
      return "The saved watch action journal is damaged."
    case .unsupportedVersion:
      return "The saved watch action journal was created by an unsupported app version."
    case .invalidInvariant:
      return "The saved watch action journal is internally inconsistent."
    case .sequenceExhausted:
      return "The watch action sequence is exhausted."
    case .acknowledgementMismatch:
      return "The phone acknowledgement does not match this watch installation."
    case .acknowledgementOutOfOrder:
      return "The phone acknowledgement arrived out of order."
    }
  }
}

/// Durable representation of one watch-originated mutation. The platform wire
/// command is derived from this record immediately before transport, keeping the
/// journal independent of WatchConnectivity while preserving the same identity.
struct LorvexWatchJournalCommand: Codable, Equatable, Sendable, Identifiable {
  let installID: String
  let sequence: Int64
  let workspaceInstanceID: String
  let commandID: String
  let createdAt: String
  let mutation: LorvexWatchMutation

  var id: String { commandID }

  func wireCommand() throws -> LorvexWatchCommand {
    try LorvexWatchCommand(
      sourceInstallID: installID,
      workspaceInstanceID: workspaceInstanceID,
      sequence: sequence,
      commandID: commandID,
      createdAt: createdAt,
      mutation: mutation)
  }
}

struct LorvexWatchJournalEntry: Codable, Equatable, Sendable {
  enum Disposition: String, Codable, Equatable, Sendable {
    case pending
    case rejected
  }

  let command: LorvexWatchJournalCommand
  var disposition: Disposition
  var attemptCount: Int
  var nextAttemptAt: Date?
  var rejectionCode: String?
}

enum LorvexWatchAcknowledgementResolution: Equatable, Sendable {
  case applied
  case retryable
  case rejected
  case duplicate
}

/// An atomic, append-only-until-acknowledged command journal.
///
/// The actor never evicts an unacknowledged command. Every mutation works on a
/// copy and replaces in-memory state only after the JSON file has been atomically
/// replaced, so an I/O failure cannot create a false durable success in this
/// process. Existing but undecodable state is never overwritten.
actor LorvexWatchCommandJournal {
  private struct Document: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var installID: String
    var nextSequence: Int64
    var entries: [LorvexWatchJournalEntry]
  }

  private static let maximumJournalBytes = 4 * 1024 * 1024

  private let fileURL: URL
  private var document: Document

  init(
    fileURL: URL,
    newInstallID: @autoclosure () -> String = UUID().uuidString.lowercased()
  ) throws {
    self.fileURL = fileURL
    if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
      size > Self.maximumJournalBytes
    {
      throw LorvexWatchCommandJournalError.corrupt
    }

    do {
      let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
      guard data.count <= Self.maximumJournalBytes else {
        throw LorvexWatchCommandJournalError.corrupt
      }
      let loaded = try Self.decoder().decode(Document.self, from: data)
      try Self.validate(loaded)
      document = loaded
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      let fresh = Document(
        version: Document.currentVersion,
        installID: newInstallID(),
        nextSequence: 1,
        entries: [])
      try Self.validate(fresh)
      try Self.write(fresh, to: fileURL)
      document = fresh
    } catch let error as LorvexWatchCommandJournalError {
      throw error
    } catch {
      throw LorvexWatchCommandJournalError.corrupt
    }
  }

  func enqueue(
    mutation: LorvexWatchMutation,
    workspaceInstanceID: String,
    commandID: String = UUID().uuidString.lowercased(),
    createdAt: String
  ) throws -> LorvexWatchJournalCommand {
    guard Self.isCanonicalUUID(workspaceInstanceID),
      Self.isCanonicalUUID(commandID),
      Self.isCanonicalTimestamp(createdAt)
    else {
      throw LorvexWatchCommandJournalError.invalidInvariant
    }
    return try persistMutation { document in
      guard document.nextSequence < Int64.max else {
        throw LorvexWatchCommandJournalError.sequenceExhausted
      }
      let command = LorvexWatchJournalCommand(
        installID: document.installID,
        sequence: document.nextSequence,
        workspaceInstanceID: workspaceInstanceID,
        commandID: commandID,
        createdAt: createdAt,
        mutation: mutation)
      _ = try command.wireCommand()
      document.entries.append(
        LorvexWatchJournalEntry(
          command: command,
          disposition: .pending,
          attemptCount: 0,
          nextAttemptAt: nil,
          rejectionCode: nil))
      document.nextSequence += 1
      return command
    }
  }

  func deliveryStatus() -> LorvexWatchDeliveryStatus {
    let pending = document.entries.compactMap { entry -> LorvexWatchPendingCommand? in
      guard entry.disposition == .pending else { return nil }
      return LorvexWatchPendingCommand(
        id: entry.command.id,
        sequence: entry.command.sequence,
        mutation: entry.command.mutation)
    }
    let rejected = document.entries.compactMap { entry -> LorvexWatchRejectedCommand? in
      guard entry.disposition == .rejected, let code = entry.rejectionCode else { return nil }
      return LorvexWatchRejectedCommand(
        id: entry.command.id,
        sequence: entry.command.sequence,
        mutation: entry.command.mutation,
        code: code,
        reason: LorvexWatchDeliveryRejectionText.localizedMessage(for: code))
    }
    return LorvexWatchDeliveryStatus(
      pendingCommands: pending,
      rejectedCommands: rejected)
  }

  /// The strict FIFO head when its retry deadline has arrived. An earlier
  /// retryable command blocks all later pending commands; terminal rejected
  /// entries do not.
  func nextDeliverable(at now: Date) -> LorvexWatchJournalEntry? {
    guard let head = firstPendingEntry() else { return nil }
    if let nextAttemptAt = head.nextAttemptAt, nextAttemptAt > now { return nil }
    return head
  }

  func nextPendingRetryDate() -> Date? {
    firstPendingEntry()?.nextAttemptAt
  }

  func markAttemptStarted(commandID: String) throws {
    try persistMutation { document in
      let index = try Self.requirePendingHead(commandID: commandID, in: document)
      document.entries[index].attemptCount += 1
    }
  }

  func markWaitingForAcknowledgement(
    commandID: String,
    retryAt: Date
  ) throws {
    try persistMutation { document in
      let index = try Self.requirePendingHead(commandID: commandID, in: document)
      document.entries[index].nextAttemptAt = retryAt
    }
  }

  func markRetryable(
    commandID: String,
    retryAt: Date
  ) throws {
    try persistMutation { document in
      let index = try Self.requirePendingHead(commandID: commandID, in: document)
      document.entries[index].nextAttemptAt = retryAt
    }
  }

  /// Applies a strictly decoded, checksum-bound application ACK to the FIFO
  /// head. Identity is checked with `LorvexWatchCommandAck.matches`, so an ACK
  /// that merely reuses an install id or sequence can never consume a command.
  func applyAcknowledgement(
    _ acknowledgement: LorvexWatchCommandAck,
    retryAt: Date
  ) throws -> LorvexWatchAcknowledgementResolution {
    try persistMutation { document in
      guard acknowledgement.sourceInstallID == document.installID else {
        throw LorvexWatchCommandJournalError.acknowledgementMismatch
      }
      guard let matchingIndex = document.entries.firstIndex(where: {
        $0.command.commandID == acknowledgement.commandID
      }) else {
        if acknowledgement.sequence < document.nextSequence { return .duplicate }
        throw LorvexWatchCommandJournalError.acknowledgementOutOfOrder
      }
      guard document.entries[matchingIndex].disposition == .pending else {
        return .duplicate
      }
      guard matchingIndex == document.entries.firstIndex(where: { $0.disposition == .pending }) else {
        throw LorvexWatchCommandJournalError.acknowledgementOutOfOrder
      }
      let command = try document.entries[matchingIndex].command.wireCommand()
      guard acknowledgement.matches(command) else {
        throw LorvexWatchCommandJournalError.acknowledgementMismatch
      }

      switch acknowledgement.outcome {
      case .applied:
        document.entries.remove(at: matchingIndex)
        return .applied
      case .retryable:
        document.entries[matchingIndex].nextAttemptAt = retryAt
        return .retryable
      case .rejected:
        document.entries[matchingIndex].disposition = .rejected
        document.entries[matchingIndex].nextAttemptAt = nil
        document.entries[matchingIndex].rejectionCode = acknowledgement.code
        return .rejected
      }
    }
  }

  /// Marks old-workspace pending commands terminal before any transport is
  /// attempted against a replacement/reset database. The retained entries make
  /// the non-application visible and explicitly dismissible.
  @discardableResult
  func rejectCommandsOutsideWorkspace(
    _ workspaceInstanceID: String,
    code: String
  ) throws -> Bool {
    try persistMutation { document in
      var changed = false
      for index in document.entries.indices
      where document.entries[index].disposition == .pending
        && document.entries[index].command.workspaceInstanceID != workspaceInstanceID
      {
        document.entries[index].disposition = .rejected
        document.entries[index].nextAttemptAt = nil
        document.entries[index].rejectionCode = code
        changed = true
      }
      return changed
    }
  }

  @discardableResult
  func dismissRejected(commandID: String) throws -> Bool {
    try persistMutation { document in
      guard let index = document.entries.firstIndex(where: {
        $0.command.id == commandID && $0.disposition == .rejected
      }) else { return false }
      document.entries.remove(at: index)
      return true
    }
  }

  // Test-only visibility through `@testable import LorvexWatch`.
  func allEntries() -> [LorvexWatchJournalEntry] { document.entries }
  func installID() -> String { document.installID }
  func nextSequence() -> Int64 { document.nextSequence }

  private func firstPendingEntry() -> LorvexWatchJournalEntry? {
    document.entries.first { $0.disposition == .pending }
  }

  private func persistMutation<T>(
    _ mutation: (inout Document) throws -> T
  ) throws -> T {
    var candidate = document
    let result = try mutation(&candidate)
    try Self.validate(candidate)
    try Self.write(candidate, to: fileURL)
    document = candidate
    return result
  }

  private static func requirePendingHead(
    commandID: String,
    in document: Document
  ) throws -> Int {
    guard let head = document.entries.firstIndex(where: { $0.disposition == .pending }) else {
      throw LorvexWatchCommandJournalError.acknowledgementMismatch
    }
    guard document.entries[head].command.id == commandID else {
      throw LorvexWatchCommandJournalError.acknowledgementOutOfOrder
    }
    return head
  }

  private static func validate(_ document: Document) throws {
    guard document.version == Document.currentVersion else {
      throw LorvexWatchCommandJournalError.unsupportedVersion(document.version)
    }
    guard isCanonicalUUID(document.installID), document.nextSequence > 0 else {
      throw LorvexWatchCommandJournalError.invalidInvariant
    }
    var priorSequence: Int64 = 0
    var commandIDs = Set<String>()
    for entry in document.entries {
      guard entry.command.installID == document.installID,
        isCanonicalUUID(entry.command.workspaceInstanceID),
        isCanonicalUUID(entry.command.commandID),
        isCanonicalTimestamp(entry.command.createdAt),
        commandIDs.insert(entry.command.commandID).inserted,
        entry.command.sequence > priorSequence,
        entry.command.sequence < document.nextSequence,
        entry.attemptCount >= 0
      else {
        throw LorvexWatchCommandJournalError.invalidInvariant
      }
      do {
        _ = try entry.command.wireCommand()
      } catch {
        throw LorvexWatchCommandJournalError.invalidInvariant
      }
      switch entry.disposition {
      case .pending:
        guard entry.rejectionCode == nil else {
          throw LorvexWatchCommandJournalError.invalidInvariant
        }
      case .rejected:
        guard entry.rejectionCode?.isEmpty == false,
          entry.nextAttemptAt == nil
        else {
          throw LorvexWatchCommandJournalError.invalidInvariant
        }
      }
      priorSequence = entry.command.sequence
    }
  }

  private static func write(_ document: Document, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true)
    let data = try encoder().encode(document)
    guard data.count <= maximumJournalBytes else {
      throw LorvexWatchCommandJournalError.corrupt
    }
    try data.write(to: url, options: [.atomic])
  }

  private static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  private static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  private static func isCanonicalUUID(_ value: String) -> Bool {
    LorvexWatchWire.isCanonicalUUID(value)
  }

  private static func isCanonicalTimestamp(_ value: String) -> Bool {
    guard let parsed = LorvexDateFormatters.iso8601Fractional.date(from: value) else {
      return false
    }
    return LorvexDateFormatters.iso8601Fractional.string(from: parsed) == value
  }
}
