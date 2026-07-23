import Foundation
import LorvexDomain

/// The raw wire fields of a sync envelope that is not yet interpretable — a
/// future / unknown `entity_type` this build cannot model, or (with a known type)
/// a future / unknown `operation` on a forward-compat record.
///
/// A ``SyncEnvelope`` cannot carry such a record — its `entityType` and
/// `operation` are closed enums, so an unknown value of either fails to decode.
/// This carrier holds the verbatim wire strings instead, so the transport can
/// durably park a well-formed future record (rather than dropping it while the
/// change token advances past it) until a later build whose `EntityKind` /
/// operation set understands it drains and applies it. The transport has already
/// validated everything except the future field: `version` parses as an
/// ``LorvexDomain/Hlc`` (stored here in its canonical string form), `entityId` is
/// non-empty, and the raw carrier has passed the same bounded field, JSON, and
/// schema-headroom validation as a typed ``SyncEnvelope``. Both `entityType` and
/// `operation` may be future values when a schema-ahead record introduced them
/// together.
///
/// ``envelopeWireJSON()`` re-emits the canonical envelope JSON byte-shape that
/// ``SyncEnvelope``'s `Codable` consumes, so a parked row deserializes cleanly
/// the moment the type becomes known.
public struct RawEnvelopeFields: Sendable, Equatable {
  public var entityType: String
  public var entityId: String
  public var operation: String
  /// Canonical ``LorvexDomain/Hlc`` string (already validated by the transport).
  public var version: String
  public var payloadSchemaVersion: UInt32
  public var payload: String
  public var deviceId: String

  public init(
    entityType: String, entityId: String, operation: String, version: String,
    payloadSchemaVersion: UInt32, payload: String, deviceId: String
  ) {
    self.entityType = entityType
    self.entityId = entityId
    self.operation = operation
    self.version = version
    self.payloadSchemaVersion = payloadSchemaVersion
    self.payload = payload
    self.deviceId = deviceId
  }

  /// Apply the transport-level envelope contract without requiring a future
  /// `entity_type` or `operation` to fit today's closed enums. When the entity
  /// type is already known, its canonical entity-id grammar is enforced too.
  public func validate() -> Result<Void, EnvelopeValidationError> {
    validateEnvelopeWireFields(
      entityType: entityType,
      entityKind: EntityKind.parse(entityType),
      entityId: entityId,
      operation: operation,
      version: version,
      payloadSchemaVersion: payloadSchemaVersion,
      payload: payload,
      deviceId: deviceId)
  }

  /// Serialize to the canonical envelope wire JSON. The key set and value shapes
  /// match ``SyncEnvelope``'s `Codable` exactly (`version` as a string, the
  /// schema version as a number, `payload` as a string), so the parked row is
  /// decodable by `JSONDecoder().decode(SyncEnvelope.self, …)` once the type is
  /// understood.
  public func envelopeWireJSON() throws -> String {
    let data = try JSONEncoder().encode(self)
    return String(decoding: data, as: UTF8.self)
  }
}

extension RawEnvelopeFields: Codable {
  private enum CodingKeys: String, CodingKey {
    case entityType = "entity_type"
    case entityId = "entity_id"
    case operation
    case version
    case payloadSchemaVersion = "payload_schema_version"
    case payload
    case deviceId = "device_id"
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(entityType, forKey: .entityType)
    try c.encode(entityId, forKey: .entityId)
    try c.encode(operation, forKey: .operation)
    try c.encode(version, forKey: .version)
    try c.encode(payloadSchemaVersion, forKey: .payloadSchemaVersion)
    try c.encode(payload, forKey: .payload)
    try c.encode(deviceId, forKey: .deviceId)
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      entityType: try c.decode(String.self, forKey: .entityType),
      entityId: try c.decode(String.self, forKey: .entityId),
      operation: try c.decode(String.self, forKey: .operation),
      version: try c.decode(String.self, forKey: .version),
      payloadSchemaVersion: try c.decode(UInt32.self, forKey: .payloadSchemaVersion),
      payload: try c.decode(String.self, forKey: .payload),
      deviceId: try c.decode(String.self, forKey: .deviceId))
  }
}
