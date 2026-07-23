import Foundation

/// A phone snapshot bound to the physical database generation that produced it.
public struct LorvexWatchReplicaEnvelope: Sendable, Equatable {
  public static let currentProtocolVersion = 1
  public static let maximumSnapshotBytes = 45 * 1024

  public let protocolVersion: Int
  public let workspaceInstanceID: String
  public let snapshotData: Data
  public let payloadChecksum: String

  public init(workspaceInstanceID: String, snapshotData: Data) throws {
    guard !snapshotData.isEmpty, snapshotData.count <= Self.maximumSnapshotBytes else {
      throw LorvexWatchWireError.missingOrInvalidField("snapshot_data")
    }
    let workspaceInstanceID = try LorvexWatchWire.canonicalUUID(
      workspaceInstanceID, field: "workspace_instance_id")
    protocolVersion = Self.currentProtocolVersion
    self.workspaceInstanceID = workspaceInstanceID
    self.snapshotData = snapshotData
    payloadChecksum = try LorvexWatchWire.checksum([
      "protocol_version": Self.currentProtocolVersion,
      "workspace_instance_id": workspaceInstanceID,
      "snapshot_data": snapshotData.base64EncodedString(),
    ])
  }

  public func wireData() throws -> Data {
    var object = payloadObject
    object["payload_checksum"] = payloadChecksum
    return try LorvexWatchWire.jsonData(object)
  }

  public static func decodeWireData(_ data: Data) throws -> Self {
    let object = try LorvexWatchWire.object(from: data, name: "replica")
    try LorvexWatchWire.requireExactKeys(
      object,
      ["protocol_version", "workspace_instance_id", "snapshot_data", "payload_checksum"],
      name: "replica")
    let protocolVersion = Int(try LorvexWatchWire.integer(object, "protocol_version"))
    guard protocolVersion == currentProtocolVersion else {
      throw LorvexWatchWireError.unsupportedProtocolVersion(protocolVersion)
    }
    let encoded = try LorvexWatchWire.string(object, "snapshot_data")
    guard let snapshotData = Data(base64Encoded: encoded),
      snapshotData.base64EncodedString() == encoded,
      !snapshotData.isEmpty,
      snapshotData.count <= maximumSnapshotBytes
    else { throw LorvexWatchWireError.missingOrInvalidField("snapshot_data") }
    let decoded = try Self(
      workspaceInstanceID: try LorvexWatchWire.string(object, "workspace_instance_id"),
      snapshotData: snapshotData)
    let supplied = try LorvexWatchWire.string(object, "payload_checksum")
    try LorvexWatchWire.requireChecksumShape(supplied)
    guard decoded.payloadChecksum == supplied else {
      throw LorvexWatchWireError.checksumMismatch
    }
    return decoded
  }

  private var payloadObject: [String: Any] {
    [
      "protocol_version": protocolVersion,
      "workspace_instance_id": workspaceInstanceID,
      "snapshot_data": snapshotData.base64EncodedString(),
    ]
  }
}
