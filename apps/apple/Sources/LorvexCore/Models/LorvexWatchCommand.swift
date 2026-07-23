import Foundation
import LorvexDomain

/// A crash-stable Watch command. Its checksum covers every field except the
/// checksum itself, including the physical-database generation fence.
public struct LorvexWatchCommand: Sendable, Equatable {
  public static let currentProtocolVersion = 1

  public let protocolVersion: Int
  public let workspaceInstanceID: String
  public let sourceInstallID: String
  public let sequence: Int64
  public let commandID: String
  public let createdAt: String
  public let mutation: LorvexWatchMutation
  public let payloadChecksum: String

  public init(
    sourceInstallID: String,
    workspaceInstanceID: String,
    sequence: Int64,
    commandID: String,
    createdAt: String,
    mutation: LorvexWatchMutation
  ) throws {
    let fields = try Self.validatedFields(
      protocolVersion: Self.currentProtocolVersion,
      workspaceInstanceID: workspaceInstanceID,
      sourceInstallID: sourceInstallID,
      sequence: sequence,
      commandID: commandID,
      createdAt: createdAt,
      mutation: mutation)
    protocolVersion = fields.protocolVersion
    self.workspaceInstanceID = fields.workspaceInstanceID
    self.sourceInstallID = fields.sourceInstallID
    self.sequence = fields.sequence
    self.commandID = fields.commandID
    self.createdAt = fields.createdAt
    self.mutation = fields.mutation
    payloadChecksum = try LorvexWatchWire.checksum(Self.payloadObject(fields))
  }

  public func wireData() throws -> Data {
    var object = Self.payloadObject(Self.Fields(self))
    object["payload_checksum"] = payloadChecksum
    return try LorvexWatchWire.jsonData(object)
  }

  public static func decodeWireData(_ data: Data) throws -> Self {
    let object = try LorvexWatchWire.object(from: data, name: "command")
    try LorvexWatchWire.requireExactKeys(
      object,
      [
        "protocol_version", "workspace_instance_id", "source_install_id", "sequence",
        "command_id", "created_at", "mutation", "payload_checksum",
      ],
      name: "command")
    let mutation = try decodeMutation(object["mutation"])
    let fields = try validatedFields(
      protocolVersion: Int(try LorvexWatchWire.integer(object, "protocol_version")),
      workspaceInstanceID: try LorvexWatchWire.string(object, "workspace_instance_id"),
      sourceInstallID: try LorvexWatchWire.string(object, "source_install_id"),
      sequence: try LorvexWatchWire.integer(object, "sequence"),
      commandID: try LorvexWatchWire.string(object, "command_id"),
      createdAt: try LorvexWatchWire.string(object, "created_at"),
      mutation: mutation)
    let supplied = try LorvexWatchWire.string(object, "payload_checksum")
    try LorvexWatchWire.requireChecksumShape(supplied)
    guard supplied == (try LorvexWatchWire.checksum(payloadObject(fields))) else {
      throw LorvexWatchWireError.checksumMismatch
    }
    return Self(fields: fields, payloadChecksum: supplied)
  }

  private struct Fields {
    let protocolVersion: Int
    let workspaceInstanceID: String
    let sourceInstallID: String
    let sequence: Int64
    let commandID: String
    let createdAt: String
    let mutation: LorvexWatchMutation

    init(
      protocolVersion: Int,
      workspaceInstanceID: String,
      sourceInstallID: String,
      sequence: Int64,
      commandID: String,
      createdAt: String,
      mutation: LorvexWatchMutation
    ) {
      self.protocolVersion = protocolVersion
      self.workspaceInstanceID = workspaceInstanceID
      self.sourceInstallID = sourceInstallID
      self.sequence = sequence
      self.commandID = commandID
      self.createdAt = createdAt
      self.mutation = mutation
    }

    init(_ command: LorvexWatchCommand) {
      protocolVersion = command.protocolVersion
      workspaceInstanceID = command.workspaceInstanceID
      sourceInstallID = command.sourceInstallID
      sequence = command.sequence
      commandID = command.commandID
      createdAt = command.createdAt
      mutation = command.mutation
    }
  }

  private init(fields: Fields, payloadChecksum: String) {
    protocolVersion = fields.protocolVersion
    workspaceInstanceID = fields.workspaceInstanceID
    sourceInstallID = fields.sourceInstallID
    sequence = fields.sequence
    commandID = fields.commandID
    createdAt = fields.createdAt
    mutation = fields.mutation
    self.payloadChecksum = payloadChecksum
  }

  private static func validatedFields(
    protocolVersion: Int,
    workspaceInstanceID: String,
    sourceInstallID: String,
    sequence: Int64,
    commandID: String,
    createdAt: String,
    mutation: LorvexWatchMutation
  ) throws -> Fields {
    guard protocolVersion == currentProtocolVersion else {
      throw LorvexWatchWireError.unsupportedProtocolVersion(protocolVersion)
    }
    guard sequence > 0 else {
      throw LorvexWatchWireError.missingOrInvalidField("sequence")
    }
    return Fields(
      protocolVersion: protocolVersion,
      workspaceInstanceID: try LorvexWatchWire.canonicalUUID(
        workspaceInstanceID, field: "workspace_instance_id"),
      sourceInstallID: try LorvexWatchWire.canonicalUUID(
        sourceInstallID, field: "source_install_id"),
      sequence: sequence,
      commandID: try LorvexWatchWire.canonicalUUID(commandID, field: "command_id"),
      createdAt: try LorvexWatchWire.canonicalTimestamp(createdAt, field: "created_at"),
      mutation: try validatedMutation(mutation))
  }

  private static func payloadObject(_ fields: Fields) -> [String: Any] {
    [
      "protocol_version": fields.protocolVersion,
      "workspace_instance_id": fields.workspaceInstanceID,
      "source_install_id": fields.sourceInstallID,
      "sequence": fields.sequence,
      "command_id": fields.commandID,
      "created_at": fields.createdAt,
      "mutation": mutationObject(fields.mutation),
    ]
  }

  private static func mutationObject(_ mutation: LorvexWatchMutation) -> [String: Any] {
    switch mutation {
    case .completeTask(let id):
      return ["type": "complete_task", "id": id]
    case .cancelTask(let id):
      return ["type": "cancel_task", "id": id]
    case .deferTaskToTomorrow(let id, let plannedDate):
      return ["type": "defer_task_to_tomorrow", "id": id, "date": plannedDate]
    case .removeFromFocus(let id, let date):
      return ["type": "remove_from_focus", "id": id, "date": date]
    case .captureTask(let title):
      return ["type": "capture_task", "title": title]
    case .completeHabit(let id, let date):
      return ["type": "complete_habit", "id": id, "date": date]
    }
  }

  private static func decodeMutation(_ raw: Any?) throws -> LorvexWatchMutation {
    guard let object = raw as? [String: Any] else {
      throw LorvexWatchWireError.invalidObject("mutation")
    }
    let type = try LorvexWatchWire.string(object, "type")
    let keys: Set<String>
    let mutation: LorvexWatchMutation
    switch type {
    case "complete_task":
      keys = ["type", "id"]
      mutation = .completeTask(id: try LorvexWatchWire.string(object, "id"))
    case "cancel_task":
      keys = ["type", "id"]
      mutation = .cancelTask(id: try LorvexWatchWire.string(object, "id"))
    case "defer_task_to_tomorrow":
      keys = ["type", "id", "date"]
      mutation = .deferTaskToTomorrow(
        id: try LorvexWatchWire.string(object, "id"),
        plannedDate: try LorvexWatchWire.string(object, "date"))
    case "remove_from_focus":
      keys = ["type", "id", "date"]
      mutation = .removeFromFocus(
        id: try LorvexWatchWire.string(object, "id"),
        date: try LorvexWatchWire.string(object, "date"))
    case "capture_task":
      keys = ["type", "title"]
      mutation = .captureTask(title: try LorvexWatchWire.string(object, "title"))
    case "complete_habit":
      keys = ["type", "id", "date"]
      mutation = .completeHabit(
        id: try LorvexWatchWire.string(object, "id"),
        date: try LorvexWatchWire.string(object, "date"))
    default:
      throw LorvexWatchWireError.missingOrInvalidField("mutation.type")
    }
    try LorvexWatchWire.requireExactKeys(object, keys, name: "mutation")
    return try validatedMutation(mutation)
  }

  private static func validatedMutation(
    _ mutation: LorvexWatchMutation
  ) throws -> LorvexWatchMutation {
    switch mutation {
    case .completeTask(let id):
      return .completeTask(
        id: try LorvexWatchWire.canonicalUUID(id, field: "mutation.id"))
    case .cancelTask(let id):
      return .cancelTask(
        id: try LorvexWatchWire.canonicalUUID(id, field: "mutation.id"))
    case .deferTaskToTomorrow(let id, let plannedDate):
      return .deferTaskToTomorrow(
        id: try LorvexWatchWire.canonicalUUID(id, field: "mutation.id"),
        plannedDate: try LorvexWatchWire.canonicalDate(
          plannedDate, field: "mutation.date"))
    case .removeFromFocus(let id, let date):
      return .removeFromFocus(
        id: try LorvexWatchWire.canonicalUUID(id, field: "mutation.id"),
        date: try LorvexWatchWire.canonicalDate(date, field: "mutation.date"))
    case .captureTask(let title):
      guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        title.count <= ValidationLimits.maxTitleLength
      else { throw LorvexWatchWireError.missingOrInvalidField("mutation.title") }
      return .captureTask(title: title)
    case .completeHabit(let id, let date):
      return .completeHabit(
        id: try LorvexWatchWire.canonicalUUID(id, field: "mutation.id"),
        date: try LorvexWatchWire.canonicalDate(date, field: "mutation.date"))
    }
  }
}
