import Foundation

/// The phone's durable application result for one exact Watch command.
public struct LorvexWatchCommandAck: Sendable, Equatable {
  public enum Outcome: String, Sendable {
    case applied
    case retryable
    case rejected
  }

  public let protocolVersion: Int
  public let workspaceInstanceID: String
  public let sourceInstallID: String
  public let sequence: Int64
  public let commandID: String
  public let payloadChecksum: String
  public let outcome: Outcome
  public let code: String?
  public let message: String?

  public init(
    command: LorvexWatchCommand,
    outcome: Outcome,
    code: String? = nil,
    message: String? = nil
  ) throws {
    try Self.validate(outcome: outcome, code: code, message: message)
    protocolVersion = command.protocolVersion
    workspaceInstanceID = command.workspaceInstanceID
    sourceInstallID = command.sourceInstallID
    sequence = command.sequence
    commandID = command.commandID
    payloadChecksum = command.payloadChecksum
    self.outcome = outcome
    self.code = code
    self.message = message
  }

  /// Nonthrowing fail-safe used only when a locally stored receipt cannot be
  /// represented by the validated public initializer. It deliberately carries
  /// no data from that corrupt receipt.
  init(trustedReceiptCorruptFor command: LorvexWatchCommand) {
    protocolVersion = command.protocolVersion
    workspaceInstanceID = command.workspaceInstanceID
    sourceInstallID = command.sourceInstallID
    sequence = command.sequence
    commandID = command.commandID
    payloadChecksum = command.payloadChecksum
    outcome = .retryable
    code = "receipt_corrupt"
    message = nil
  }

  public func matches(_ command: LorvexWatchCommand) -> Bool {
    protocolVersion == command.protocolVersion
      && workspaceInstanceID == command.workspaceInstanceID
      && sourceInstallID == command.sourceInstallID
      && sequence == command.sequence
      && commandID == command.commandID
      && payloadChecksum == command.payloadChecksum
  }

  public func wireData() throws -> Data {
    try Self.validate(outcome: outcome, code: code, message: message)
    return try LorvexWatchWire.jsonData(object)
  }

  public static func decodeWireData(_ data: Data) throws -> Self {
    let object = try LorvexWatchWire.object(from: data, name: "ack")
    try LorvexWatchWire.requireExactKeys(
      object,
      [
        "protocol_version", "workspace_instance_id", "source_install_id", "sequence",
        "command_id", "payload_checksum", "outcome", "code", "message",
      ],
      name: "ack")
    let protocolVersion = Int(try LorvexWatchWire.integer(object, "protocol_version"))
    guard protocolVersion == LorvexWatchCommand.currentProtocolVersion else {
      throw LorvexWatchWireError.unsupportedProtocolVersion(protocolVersion)
    }
    let outcomeRaw = try LorvexWatchWire.string(object, "outcome")
    guard let outcome = Outcome(rawValue: outcomeRaw) else {
      throw LorvexWatchWireError.missingOrInvalidField("outcome")
    }
    let code = try LorvexWatchWire.optionalString(object, "code")
    let message = try LorvexWatchWire.optionalString(object, "message")
    try validate(outcome: outcome, code: code, message: message)
    let checksum = try LorvexWatchWire.string(object, "payload_checksum")
    try LorvexWatchWire.requireChecksumShape(checksum)
    return Self(
      protocolVersion: protocolVersion,
      workspaceInstanceID: try LorvexWatchWire.canonicalUUID(
        try LorvexWatchWire.string(object, "workspace_instance_id"),
        field: "workspace_instance_id"),
      sourceInstallID: try LorvexWatchWire.canonicalUUID(
        try LorvexWatchWire.string(object, "source_install_id"), field: "source_install_id"),
      sequence: try positiveSequence(object),
      commandID: try LorvexWatchWire.canonicalUUID(
        try LorvexWatchWire.string(object, "command_id"), field: "command_id"),
      payloadChecksum: checksum,
      outcome: outcome,
      code: code,
      message: message)
  }

  private init(
    protocolVersion: Int,
    workspaceInstanceID: String,
    sourceInstallID: String,
    sequence: Int64,
    commandID: String,
    payloadChecksum: String,
    outcome: Outcome,
    code: String?,
    message: String?
  ) {
    self.protocolVersion = protocolVersion
    self.workspaceInstanceID = workspaceInstanceID
    self.sourceInstallID = sourceInstallID
    self.sequence = sequence
    self.commandID = commandID
    self.payloadChecksum = payloadChecksum
    self.outcome = outcome
    self.code = code
    self.message = message
  }

  private var object: [String: Any] {
    [
      "protocol_version": protocolVersion,
      "workspace_instance_id": workspaceInstanceID,
      "source_install_id": sourceInstallID,
      "sequence": sequence,
      "command_id": commandID,
      "payload_checksum": payloadChecksum,
      "outcome": outcome.rawValue,
      "code": code.map { $0 as Any } ?? NSNull(),
      "message": message.map { $0 as Any } ?? NSNull(),
    ]
  }

  private static func positiveSequence(_ object: [String: Any]) throws -> Int64 {
    let value = try LorvexWatchWire.integer(object, "sequence")
    guard value > 0 else { throw LorvexWatchWireError.missingOrInvalidField("sequence") }
    return value
  }

  private static func validate(outcome: Outcome, code: String?, message: String?) throws {
    switch outcome {
    case .applied:
      guard code == nil, message == nil else {
        throw LorvexWatchWireError.missingOrInvalidField("applied_result")
      }
    case .retryable, .rejected:
      guard let code, code.utf8.count <= 64, !code.isEmpty,
        code.utf8.allSatisfy({
          ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 95 || $0 == 46
        })
      else { throw LorvexWatchWireError.missingOrInvalidField("code") }
      if let message {
        guard !message.isEmpty, message.utf8.count <= 2_048 else {
          throw LorvexWatchWireError.missingOrInvalidField("message")
        }
      }
    }
  }
}
