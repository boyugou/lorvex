import Foundation
import LorvexDomain
import LorvexStore

/// Canonical semantic identity for one sync mutation.
///
/// `device_id` is attribution, not business state, and is deliberately absent.
/// Every other interpretation-bearing field participates: entity identity,
/// operation, HLC, payload schema, and a canonical payload whose top-level
/// `version` is normalized to the envelope HLC. Delete handlers consume only
/// identity/version, so delete payload history is normalized away.
public enum SyncMutationSemantics {
  public struct Key: Sendable, Equatable {
    public var entityType: String
    public var entityId: String
    public var operation: SyncOperation
    public var version: String
    public var payloadSchemaVersion: UInt32
    public var canonicalPayload: String

    fileprivate var deterministicBytes: [UInt8] {
      let operationRank = operation == .delete ? "1" : "0"
      return Array(
        "\(entityType)\u{0}\(entityId)\u{0}\(operationRank)\u{0}\(version)\u{0}"
          .utf8)
        + Array(String(payloadSchemaVersion).utf8)
        + [0]
        + Array(canonicalPayload.utf8)
    }
  }

  public enum SemanticError: Error, Equatable, CustomStringConvertible {
    case payloadIsNotJSONObject(entityType: String, entityId: String)
    case payloadCanonicalization(String)

    public var description: String {
      switch self {
      case .payloadIsNotJSONObject(let entityType, let entityId):
        return "sync mutation payload must be a JSON object: \(entityType)/\(entityId)"
      case .payloadCanonicalization(let detail):
        return "sync mutation payload canonicalization failed: \(detail)"
      }
    }
  }

  /// Build the stable semantic key used for exact replay detection and the
  /// deterministic equal-HLC contender join.
  public static func key(for envelope: SyncEnvelope) throws -> Key {
    Key(
      entityType: envelope.entityType.asString,
      entityId: envelope.entityId,
      operation: envelope.operation,
      version: envelope.version.description,
      payloadSchemaVersion: envelope.payloadSchemaVersion,
      canonicalPayload: try normalizedPayload(
        envelope.payload, operation: envelope.operation,
        version: envelope.version.description,
        entityType: envelope.entityType.asString, entityId: envelope.entityId))
  }

  public static func isExactSemanticReplay(
    _ lhs: SyncEnvelope, _ rhs: SyncEnvelope
  ) throws -> Bool {
    try key(for: lhs) == key(for: rhs)
  }

  /// Deterministic max join for two equal-HLC mutations. Every clone presented
  /// with the same pair chooses the same contender even if arrival order is
  /// reversed or both clones still share an HLC device suffix.
  public static func deterministicWinner(
    _ lhs: SyncEnvelope, _ rhs: SyncEnvelope
  ) throws -> SyncEnvelope {
    let left = try key(for: lhs)
    let right = try key(for: rhs)
    if left == right { return lhs }
    return left.deterministicBytes.lexicographicallyPrecedes(right.deterministicBytes)
      ? rhs : lhs
  }

  /// Re-author a deterministic contender at a strict successor. Attribution is
  /// local, and the payload's embedded version is rewritten with the envelope
  /// version so row state, payload bytes, and ordering metadata cannot drift.
  public static func restamp(
    _ contender: SyncEnvelope, version: Hlc, deviceId: String
  ) throws -> SyncEnvelope {
    let payload = try normalizedPayload(
      contender.payload, operation: contender.operation,
      version: version.description,
      entityType: contender.entityType.asString, entityId: contender.entityId)
    return SyncEnvelope(
      entityType: contender.entityType, entityId: contender.entityId,
      operation: contender.operation, version: version,
      payloadSchemaVersion: contender.payloadSchemaVersion,
      payload: payload, deviceId: deviceId)
  }

  private static func normalizedPayload(
    _ raw: String, operation: SyncOperation, version: String,
    entityType: String, entityId: String
  ) throws -> String {
    let value: JSONValue
    switch operation {
    case .delete:
      value = .object(["version": .string(version)])
    case .upsert:
      guard let parsed = JSONValue.parse(raw), case .object(var object) = parsed else {
        throw SemanticError.payloadIsNotJSONObject(
          entityType: entityType, entityId: entityId)
      }
      object["version"] = .string(version)
      value = .object(object)
    }
    do {
      return try SyncCanonicalize.canonicalizeJSON(value)
    } catch {
      throw SemanticError.payloadCanonicalization("\(error)")
    }
  }
}
