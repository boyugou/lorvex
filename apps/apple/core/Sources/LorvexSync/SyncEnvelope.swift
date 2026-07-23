import Foundation
import LorvexDomain

/// Sync operation type. Unknown operation strings are rejected at the wire
/// boundary: pre-public sync has no compatibility contract for future
/// operation semantics, and accepting-then-skipping an unknown mutation would
/// let a transport checkpoint advance past data this build cannot interpret.
public enum SyncOperation: String, Sendable, Equatable, Codable {
  case upsert
  case delete

  /// Canonical string matching `OP_UPSERT` / `OP_DELETE`.
  public var asString: String {
    switch self {
    case .upsert: return SyncNaming.opUpsert
    case .delete: return SyncNaming.opDelete
    }
  }
}

/// Validation error produced by ``SyncEnvelope/validate()``.
public enum EnvelopeValidationError: Error, Equatable {
  case emptyField(field: String)
  case fieldTooLong(field: String, len: Int, max: Int)
  case unsafeEntityId(entityId: String, reason: String)
  /// Payload contracts are numbered from one; zero has never been a valid wire
  /// version and cannot be interpreted as a legacy schema.
  case payloadSchemaVersionUnsupported(version: UInt32)
  /// `payload_schema_version` is further ahead of the local build than
  /// ``SyncEnvelope/maxPayloadSchemaVersionAhead`` permits.
  case payloadSchemaVersionTooFarAhead(version: UInt32, localMax: UInt32)
  /// Payload JSON nesting reaches ``SyncEnvelope/maxJSONDepth`` (the same depth
  /// at which the canonicalize-emit gate errors).
  case payloadJsonTooDeep(depth: Int, max: Int)
  /// Payload is not syntactically valid JSON.
  case invalidPayloadJson
  /// The raw version is not an exact canonical fixed-width HLC. Typed
  /// envelopes cannot reach this case, but future/raw carriers can.
  case invalidVersion(value: String)

  public var message: String {
    switch self {
    case .emptyField(let field):
      return "sync envelope field \(field) must not be empty"
    case .fieldTooLong(let field, let len, let max):
      return "sync envelope field \(field) exceeds cap: \(len) > \(max)"
    case .unsafeEntityId(let entityId, let reason):
      return "sync envelope entity_id is unsafe (\(reason)): \(applyDebugQuoted(entityId))"
    case .payloadSchemaVersionUnsupported(let version):
      return "sync envelope payload_schema_version \(version) is unsupported; versions start at 1"
    case .payloadSchemaVersionTooFarAhead(let version, let localMax):
      return
        "sync envelope payload_schema_version \(version) exceeds local cap \(localMax) "
        + "(= PAYLOAD_SCHEMA_VERSION + MAX_PAYLOAD_SCHEMA_VERSION_AHEAD)"
    case .payloadJsonTooDeep(let depth, let max):
      return "sync envelope payload exceeds JSON nesting cap: depth \(depth) >= max \(max)"
    case .invalidPayloadJson:
      return "sync envelope payload must be valid JSON"
    case .invalidVersion(let value):
      return "sync envelope version is not a canonical HLC: \(applyDebugQuoted(value))"
    }
  }
}

/// Unified sync envelope — the wire format for all sync transport.
///
/// Wraps an entity payload with its identity, operation, HLC version, schema
/// generation, and source device. Serializes to / deserializes from the
/// canonical wire JSON: `entity_type` is the lowercase snake_case entity kind,
/// `operation` is `"upsert"`/`"delete"`, `version` is the canonical HLC string,
/// `payload` is the canonicalized JSON string. No unknown-field rejection: a
/// future additive envelope-level field (signature, compression hint, …) must
/// be deserializable by today's peers, so unknown top-level keys are accepted
/// and ignored. Unknown `entity_type` / `operation` values fail at the wire
/// boundary — the same place ``validate()`` rejects oversized / empty payloads.
public struct SyncEnvelope: Sendable, Equatable {
  /// Maximum canonicalized payload byte size inside a single envelope. Kept at
  /// the storage/canonicalization authority's 256-KiB cap so a payload plus the
  /// other encrypted wire fields and CloudKit metadata remains safely below
  /// CloudKit's 1-MiB whole-record limit.
  public static let maxEnvelopePayloadBytes = StorageSchema.maxPayloadBytes

  /// Maximum JSON nesting depth permitted in a payload. Shares
  /// `LorvexDomain.maxJSONDepth` with the canonicalize-emit gate so a payload
  /// that passes envelope validation also re-emits cleanly on the next enqueue.
  public static let maxJSONDepth = LorvexDomain.maxJSONDepth

  static let maxEnvelopeEntityTypeLen = 128
  static let maxEnvelopeEntityIdLen = 256
  static let maxEnvelopeOperationLen = 128
  static let maxEnvelopeVersionLen = 128
  /// Cap on the device_id string carried on the wire.
  public static let maxEnvelopeDeviceIdLen = 128
  /// Forward-compat headroom for `payload_schema_version`. Envelopes whose
  /// declared schema version is further ahead than
  /// `PAYLOAD_SCHEMA_VERSION + maxPayloadSchemaVersionAhead` are rejected.
  public static let maxPayloadSchemaVersionAhead: UInt32 = 100

  public var entityType: EntityKind
  public var entityId: String
  public var operation: SyncOperation
  public var version: Hlc
  public var payloadSchemaVersion: UInt32
  public var payload: String
  public var deviceId: String

  public init(
    entityType: EntityKind, entityId: String, operation: SyncOperation, version: Hlc,
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

  /// Validate per-field caps and non-empty invariants. The transport layer
  /// must call this on every incoming envelope before any further processing —
  /// a crafted oversized `payload` / `device_id` can otherwise stall the
  /// pipeline. Callers that accept in-process envelopes from their own enqueue
  /// path can skip validation since the shape is controlled locally.
  public func validate() -> Result<Void, EnvelopeValidationError> {
    validateEnvelopeWireFields(
      entityType: entityType.asString,
      entityKind: entityType,
      entityId: entityId,
      operation: operation.asString,
      version: version.description,
      payloadSchemaVersion: payloadSchemaVersion,
      payload: payload,
      deviceId: deviceId)
  }
}

extension SyncEnvelope: Codable {
  private enum CodingKeys: String, CodingKey {
    case entityType = "entity_type"
    case entityId = "entity_id"
    case operation
    case version
    case payloadSchemaVersion = "payload_schema_version"
    case payload
    case deviceId = "device_id"
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    // `entity_type` decodes via EntityKind's String-backed Codable — an unknown
    // variant fails here, the wire-boundary rejection of future entity kinds.
    self.entityType = try c.decode(EntityKind.self, forKey: .entityType)
    self.entityId = try c.decode(String.self, forKey: .entityId)
    // `operation` decodes via SyncOperation's String-backed Codable — an
    // unknown operation string fails closed at the boundary.
    self.operation = try c.decode(SyncOperation.self, forKey: .operation)
    // `version` decodes via Hlc's Codable (canonical string form).
    self.version = try c.decode(Hlc.self, forKey: .version)
    self.payloadSchemaVersion = try c.decode(UInt32.self, forKey: .payloadSchemaVersion)
    self.payload = try c.decode(String.self, forKey: .payload)
    self.deviceId = try c.decode(String.self, forKey: .deviceId)
    // Unknown top-level fields are ignored: a keyed container only reads the
    // keys it asks for, preserving envelope-level forward compatibility.
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
}

/// Shared bounded validation for typed and future/raw envelope carriers. A raw
/// future entity has no kind-specific identity grammar yet, but still receives
/// every transport-level cap, unsafe-identity rejection, JSON check, and schema
/// headroom check that a typed ``SyncEnvelope`` receives.
func validateEnvelopeWireFields(
  entityType: String,
  entityKind: EntityKind?,
  entityId: String,
  operation: String,
  version: String,
  payloadSchemaVersion: UInt32,
  payload: String,
  deviceId: String
) -> Result<Void, EnvelopeValidationError> {
  func cap(_ field: String, _ value: String, _ max: Int) -> EnvelopeValidationError? {
    if value.isEmpty {
      return .emptyField(field: field)
    }
    if value.utf8.count > max {
      return .fieldTooLong(field: field, len: value.utf8.count, max: max)
    }
    return nil
  }

  if let error = cap("entity_type", entityType, SyncEnvelope.maxEnvelopeEntityTypeLen) {
    return .failure(error)
  }
  if let error = cap("entity_id", entityId, SyncEnvelope.maxEnvelopeEntityIdLen) {
    return .failure(error)
  }
  if let error = rejectUnsafeEntityId(entityId) {
    return .failure(error)
  }
  if let entityKind, let error = rejectNoncanonicalEntityId(entityKind, entityId) {
    return .failure(error)
  }
  if let error = cap("operation", operation, SyncEnvelope.maxEnvelopeOperationLen) {
    return .failure(error)
  }
  if let error = cap("version", version, SyncEnvelope.maxEnvelopeVersionLen) {
    return .failure(error)
  }
  do {
    _ = try Hlc.parseCanonical(version)
  } catch {
    return .failure(.invalidVersion(value: version))
  }
  if let error = cap("device_id", deviceId, SyncEnvelope.maxEnvelopeDeviceIdLen) {
    return .failure(error)
  }
  if payload.utf8.count > SyncEnvelope.maxEnvelopePayloadBytes {
    return .failure(
      .fieldTooLong(
        field: "payload", len: payload.utf8.count, max: SyncEnvelope.maxEnvelopePayloadBytes))
  }
  if let error = scanMaxJSONDepth(payload, cap: SyncEnvelope.maxJSONDepth) {
    return .failure(error)
  }
  if !isValidJSONPayload(payload) {
    return .failure(.invalidPayloadJson)
  }
  if payloadSchemaVersion == 0 {
    return .failure(.payloadSchemaVersionUnsupported(version: payloadSchemaVersion))
  }
  let localMax =
    LorvexVersion.payloadSchemaVersion &+ SyncEnvelope.maxPayloadSchemaVersionAhead
  let safeLocalMax = localMax < LorvexVersion.payloadSchemaVersion ? UInt32.max : localMax
  if payloadSchemaVersion > safeLocalMax {
    return .failure(
      .payloadSchemaVersionTooFarAhead(version: payloadSchemaVersion, localMax: safeLocalMax))
  }
  return .success(())
}

private func isValidJSONPayload(_ payload: String) -> Bool {
  guard let data = payload.data(using: .utf8) else { return false }
  return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
}

/// Scan the payload string for JSON nesting depth without parsing into a value.
/// Counts `{` and `[` openers (skipping those inside string literals) and
/// tracks the maximum stack depth, returning the first
/// ``EnvelopeValidationError/payloadJsonTooDeep(depth:max:)`` when an opener
/// makes the running depth REACH `cap`. That matches
/// `LorvexDomain.writeCanonical`, which errors on any value at depth `cap` (the
/// leaf inside a `cap`-deep container): rejecting the container-that-would-hold
/// such a value keeps the scan's accepted set aligned with what re-canonicalizes
/// cleanly. Linear in `payload.utf8`, allocation-free.
private func scanMaxJSONDepth(_ payload: String, cap: Int) -> EnvelopeValidationError? {
  var depth = 0
  var inString = false
  var prevWasBackslash = false
  for byte in payload.utf8 {
    if inString {
      if prevWasBackslash {
        prevWasBackslash = false
      } else if byte == 0x5C {  // '\'
        prevWasBackslash = true
      } else if byte == 0x22 {  // '"'
        inString = false
      }
      continue
    }
    switch byte {
    case 0x22:  // '"'
      inString = true
    case 0x7B, 0x5B:  // '{' '['
      depth += 1
      if depth >= cap {
        return .payloadJsonTooDeep(depth: depth, max: cap)
      }
    case 0x7D, 0x5D:  // '}' ']'
      depth = depth > 0 ? depth - 1 : 0
    default:
      break
    }
  }
  return nil
}

/// Reject entity_ids carrying path-traversal sequences, path separators,
/// control bytes, or line/paragraph separators (U+2028/U+2029). Runs at the
/// envelope boundary for every transport-ingested envelope.
private func rejectUnsafeEntityId(_ entityId: String) -> EnvelopeValidationError? {
  if entityId.contains("..") {
    return .unsafeEntityId(
      entityId: entityId, reason: "contains path-traversal sequence '..'")
  }
  if entityId.contains("/") || entityId.contains("\\") {
    return .unsafeEntityId(entityId: entityId, reason: "contains path separator")
  }
  for scalar in entityId.unicodeScalars {
    if isUnicodeControl(scalar) {
      return .unsafeEntityId(entityId: entityId, reason: "contains control character")
    }
  }
  for scalar in entityId.unicodeScalars where scalar.value == 0x2028 || scalar.value == 0x2029 {
    return .unsafeEntityId(
      entityId: entityId, reason: "contains line/paragraph separator (U+2028/U+2029)")
  }
  return nil
}

/// Match Unicode general category `Cc` (control): C0 controls
/// `0x00...0x1F`, DEL `0x7F`, and C1 controls `0x80...0x9F`. Excludes U+2028 /
/// U+2029, which are rejected by their own explicit arm.
private func isUnicodeControl(_ scalar: Unicode.Scalar) -> Bool {
  let v = scalar.value
  return v <= 0x1F || v == 0x7F || (0x80...0x9F).contains(v)
}

/// Map the canonical entity_id validation failure into its static reason
/// string.
private func rejectNoncanonicalEntityId(
  _ kind: EntityKind, _ entityId: String
) -> EnvelopeValidationError? {
  switch SyncEntityId.validateForKind(kind, entityId) {
  case .success:
    return nil
  case .failure(let error):
    let reason: String
    switch error {
    case .invalidFormat(_, let expected, _):
      reason = expected
    case .empty:
      reason = "must not be empty"
    case .tooLong:
      reason = "exceeds canonical entity_id length"
    case .outOfRange, .message:
      reason = "failed canonical entity_id validation"
    }
    return .unsafeEntityId(entityId: entityId, reason: reason)
  }
}
